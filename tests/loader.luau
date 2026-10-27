--!nocheck
-- Headless module loader for Lune. Emulates just enough of Roblox's
-- instance-based `require(script.Parent.X)` to run the pure game modules
-- (simulation, scoring, rules, encounter/run state machines) outside Studio.
-- Modules that touch engine services are not loaded here.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Loader = {}

local cache: { [string]: any } = {}
-- Pre-scanned file system (fs calls yield, and lookups happen inside
-- __index metamethods, which cannot yield).
local isFile: { [string]: boolean } = {}
local isDir: { [string]: boolean } = {}
local sources: { [string]: string } = {}

local function scan(dir: string)
	isDir[dir] = true
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			scan(path)
		else
			isFile[path] = true
			if string.sub(name, -5) == ".luau" then
				sources[path] = fs.readFile(path)
			end
		end
	end
end
local loading: { [string]: boolean } = {}

local Node = {}
Node.__index = function(self, key)
	local raw = rawget(Node, key)
	if raw ~= nil then
		return raw
	end
	if key == "Parent" then
		return rawget(self, "_parent")
	end
	if key == "Name" then
		return rawget(self, "_name")
	end
	local child = Node.FindFirstChild(self, key)
	if child == nil then
		error(`{rawget(self, "_name")} has no child named {key}`, 2)
	end
	return child
end

local function newNode(name: string, path: string, parent: any?, kind: string)
	return setmetatable({ _name = name, _path = path, _parent = parent, _kind = kind, _children = {} }, Node)
end

function Node.FindFirstChild(self, name: string)
	local children = rawget(self, "_children")
	if children[name] then
		return children[name]
	end
	local overrides = rawget(self, "_virtual")
	if overrides and overrides[name] then
		return overrides[name]
	end
	if rawget(self, "_kind") ~= "dir" then
		-- A module folder (dir with init.luau) still has children.
		if rawget(self, "_kind") ~= "moduledir" then
			return nil
		end
	end
	local dir = rawget(self, "_path")
	local file = `{dir}/{name}.luau`
	local child
	if isFile[file] then
		child = newNode(name, file, self, "module")
	elseif isDir[`{dir}/{name}`] then
		local sub = `{dir}/{name}`
		if isFile[`{sub}/init.luau`] then
			child = newNode(name, sub, self, "moduledir")
		else
			child = newNode(name, sub, self, "dir")
		end
	end
	if child then
		children[name] = child
	end
	return child
end

function Node.WaitForChild(self, name: string)
	return Node.__index(self, name)
end

function Node.GetFullName(self)
	return rawget(self, "_path")
end

local root = "."

local services = {}

local function makeEnv(scriptNode)
	local env = {}
	env.script = scriptNode
	env.require = Loader.requireNode
	env.game = Loader.game
	env.Color3 = roblox.Color3
	env.Vector2 = roblox.Vector2
	env.Vector3 = roblox.Vector3
	env.CFrame = roblox.CFrame
	env.NumberSequence = roblox.NumberSequence
	env.ColorSequence = roblox.ColorSequence
	env.UDim2 = roblox.UDim2
	env.UDim = roblox.UDim
	env.Enum = roblox.Enum
	env.warn = function(...)
		print("[warn]", ...)
	end
	return env
end

function Loader.requireNode(node)
	if type(node) ~= "table" or getmetatable(node) ~= Node then
		error("headless require only supports module nodes, got " .. tostring(node), 2)
	end
	local kind = rawget(node, "_kind")
	local path = rawget(node, "_path")
	local file = if kind == "moduledir" then `{path}/init.luau` else path
	if kind ~= "module" and kind ~= "moduledir" then
		error(`{path} is not a module`, 2)
	end
	if cache[file] ~= nil then
		return cache[file]
	end
	if loading[file] then
		error(`circular require: {file}`, 2)
	end
	loading[file] = true
	local source = sources[file]
	local chunk = luau.load(source, { debugName = file, environment = makeEnv(node) })
	local result = chunk()
	loading[file] = nil
	cache[file] = result
	return result
end

function Loader.init(repoRoot: string)
	root = repoRoot
	scan(root .. "/src")
	local rs = newNode("ReplicatedStorage", root .. "/src", nil, "dir")
	rawset(rs, "_virtual", { Shared = newNode("Shared", root .. "/src/shared", rs, "dir") })
	local sss = newNode("ServerScriptService", root .. "/src", nil, "dir")
	rawset(sss, "_virtual", { Server = newNode("Server", root .. "/src/server", sss, "dir") })
	local client = newNode("Client", root .. "/src/client", nil, "dir")
	services.ReplicatedStorage = rs
	services.ServerScriptService = sss
	services.Client = client
	Loader.game = {
		GetService = function(_, name)
			local s = services[name]
			if not s then
				error(`service {name} is not available headless`, 2)
			end
			return s
		end,
	}
	Loader.game.ReplicatedStorage = rs
end

function Loader.shared(path: string)
	local node = services.ReplicatedStorage.Shared
	for part in string.gmatch(path, "[^%.]+") do
		node = node[part]
	end
	return Loader.requireNode(node)
end

function Loader.server(path: string)
	local node = services.ServerScriptService.Server
	for part in string.gmatch(path, "[^%.]+") do
		node = node[part]
	end
	return Loader.requireNode(node)
end

function Loader.client(path: string)
	local node = services.Client
	for part in string.gmatch(path, "[^%.]+") do
		node = node[part]
	end
	return Loader.requireNode(node)
end

return Loader
