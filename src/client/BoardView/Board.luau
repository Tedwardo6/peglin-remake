--!strict
-- Renders one authored board as chunky outlined pegs. Shapes and symbols
-- supplement colour (round · square guard · diamond power · ring relay ·
-- spiky burst with its visible ring · pill spring · plus mend).
-- Visual sizes follow the collision circles so what you see is what the
-- simulation uses.

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Pegs = require(Shared.Content.Pegs)
local Boards = require(Shared.Content.Boards)

local Build = require(script.Parent.Parent.World.Build)
local Layout = require(script.Parent.Parent.World.Layout)

type PegPart = { part: BasePart, offset: Vector3, size: Vector3, rot: CFrame, tint: boolean, cyl: boolean }

type PegView = {
	index: number,
	kind: Pegs.PegKind,
	center: Vector3,
	parts: { PegPart },
	base: Color3,
	lit: Color3,
	isLit: boolean,
	pop: number,
	flash: number,
	ring: BasePart?,
}

local Board = {}
Board.__index = Board

export type Board = typeof(setmetatable(
	{} :: {
		def: Boards.Board,
		model: Model,
		pegs: { PegView },
		active: { [number]: boolean },
		conn: RBXScriptConnection?,
		reducedMotion: boolean,
	},
	Board
))

local INK = Build.INK
local S = Layout.S
local VIS = 1.06 -- visual radius vs collision radius
local DEPTH = 0.26

local function addPart(view: PegView, p: BasePart, tint: boolean)
	local rel = p.CFrame.Position - view.center
	local rot = p.CFrame - p.CFrame.Position
	local cyl = p:IsA("Part") and (p :: Part).Shape == Enum.PartType.Cylinder
	table.insert(view.parts, { part = p, offset = rel, size = p.Size, rot = rot, tint = tint, cyl = cyl })
end

local function buildPeg(model: Instance, index: number, x: number, y: number, kind: Pegs.PegKind): PegView
	local def = Pegs.Defs[kind]
	local R = def.radius * S * VIS
	local center = Layout.boardToWorld(x, y)
	local view: PegView = {
		index = index,
		kind = kind,
		center = center,
		parts = {},
		base = def.color,
		lit = def.litColor,
		isLit = false,
		pop = 0,
		flash = 0,
		ring = nil,
	}
	local back = center + Vector3.new(0, 0, -0.12)
	local front = center
	local o = 0.075 -- outline width (studs)
	local shape = def.shape
	if shape == "round" then
		addPart(view, Build.disc(model, 2 * R + 2 * o, DEPTH, back, INK), false)
		addPart(view, Build.disc(model, 2 * R, DEPTH, front, def.color), true)
	elseif shape == "square" then
		local s = 2 * R * 0.9
		addPart(view, Build.block(model, Vector3.new(s + 2 * o, s + 2 * o, DEPTH), CFrame.new(back), INK), false)
		addPart(view, Build.block(model, Vector3.new(s, s, DEPTH), CFrame.new(front), def.color), true)
		-- Shield emblem: a lighter inner block with a notch.
		addPart(view, Build.block(model, Vector3.new(s * 0.5, s * 0.55, DEPTH), CFrame.new(front + Vector3.new(0, 0.02, 0.06)), Color3.fromRGB(210, 232, 255)), false)
		addPart(view, Build.block(model, Vector3.new(s * 0.36, s * 0.36, DEPTH), CFrame.new(front + Vector3.new(0, -s * 0.18, 0.06)) * CFrame.Angles(0, 0, math.rad(45)), Color3.fromRGB(210, 232, 255)), false)
	elseif shape == "diamond" then
		local s = 2 * R * 0.78
		local rot = CFrame.Angles(0, 0, math.rad(45))
		addPart(view, Build.block(model, Vector3.new(s + 2 * o, s + 2 * o, DEPTH), CFrame.new(back) * rot, INK), false)
		addPart(view, Build.block(model, Vector3.new(s, s, DEPTH), CFrame.new(front) * rot, def.color), true)
		addPart(view, Build.block(model, Vector3.new(s * 0.4, s * 0.4, DEPTH), CFrame.new(front + Vector3.new(0, 0, 0.06)) * rot, Color3.fromRGB(255, 250, 220)), false)
	elseif shape == "ring" then
		addPart(view, Build.disc(model, 2 * R + 2 * o, DEPTH, back, INK), false)
		addPart(view, Build.disc(model, 2 * R, DEPTH, front, def.color), true)
		addPart(view, Build.disc(model, R * 1.05, DEPTH, front + Vector3.new(0, 0, 0.05), INK), false)
		addPart(view, Build.disc(model, R * 0.5, DEPTH, front + Vector3.new(0, 0, 0.09), def.litColor), true)
	elseif shape == "spiky" then
		addPart(view, Build.disc(model, 2 * R + 2 * o, DEPTH, back, INK), false)
		for k = 0, 3 do
			local a = math.rad(45 + 90 * k)
			local pos = back + Vector3.new(math.cos(a) * R * 0.95, math.sin(a) * R * 0.95, 0)
			addPart(view, Build.block(model, Vector3.new(R * 0.75, R * 0.75, DEPTH), CFrame.new(pos) * CFrame.Angles(0, 0, a + math.rad(45)), INK), false)
			addPart(view, Build.block(model, Vector3.new(R * 0.55, R * 0.55, DEPTH), CFrame.new(pos + Vector3.new(0, 0, 0.04)) * CFrame.Angles(0, 0, a + math.rad(45)), def.color), true)
		end
		addPart(view, Build.disc(model, 2 * R, DEPTH, front, def.color), true)
		addPart(view, Build.disc(model, R * 0.7, DEPTH, front + Vector3.new(0, 0, 0.05), Color3.fromRGB(255, 236, 200)), false)
		-- Visible blast ring: what a burst will reach.
		local ringR = Pegs.BURST_RADIUS * S
		local ring = Build.disc(model, ringR * 2, 0.05, center + Vector3.new(0, 0, -0.22), def.color, { transparency = 0.86 })
		view.ring = ring
	elseif shape == "pill" then
		local r2 = R * 0.62
		addPart(view, Build.disc(model, 2 * r2 + 2 * o, DEPTH, back + Vector3.new(-R * 0.42, 0, 0), INK), false)
		addPart(view, Build.disc(model, 2 * r2 + 2 * o, DEPTH, back + Vector3.new(R * 0.42, 0, 0), INK), false)
		addPart(view, Build.block(model, Vector3.new(R * 0.84, 2 * r2 + 2 * o, DEPTH), CFrame.new(back), INK), false)
		addPart(view, Build.disc(model, 2 * r2, DEPTH, front + Vector3.new(-R * 0.42, 0, 0), def.color), true)
		addPart(view, Build.disc(model, 2 * r2, DEPTH, front + Vector3.new(R * 0.42, 0, 0), def.color), true)
		addPart(view, Build.block(model, Vector3.new(R * 0.84, 2 * r2, DEPTH), CFrame.new(front), def.color), true)
		addPart(view, Build.block(model, Vector3.new(R * 1.1, r2 * 0.45, DEPTH), CFrame.new(front + Vector3.new(0, r2 * 0.3, 0.05)), Color3.fromRGB(220, 255, 230)), false)
	elseif shape == "plus" then
		local l = 2 * R
		local t = R * 0.72
		addPart(view, Build.block(model, Vector3.new(l + 2 * o, t + 2 * o, DEPTH), CFrame.new(back), INK), false)
		addPart(view, Build.block(model, Vector3.new(t + 2 * o, l + 2 * o, DEPTH), CFrame.new(back), INK), false)
		addPart(view, Build.block(model, Vector3.new(l, t, DEPTH), CFrame.new(front), def.color), true)
		addPart(view, Build.block(model, Vector3.new(t, l, DEPTH), CFrame.new(front), def.color), true)
	end
	-- Gloss dot gives every peg a toy-like sheen.
	addPart(view, Build.disc(model, R * 0.42, DEPTH, front + Vector3.new(-R * 0.32, R * 0.32, 0.08), Color3.new(1, 1, 1), { transparency = 0.25 }), false)
	return view
end

function Board.new(parent: Instance, boardId: string, trim: Color3): Board
	local self = setmetatable({}, Board) :: any
	self.def = Boards.ById[boardId]
	self.model = Build.model("Board_" .. boardId, parent)
	self.pegs = {}
	self.active = {}
	self.reducedMotion = false
	for i, p in self.def.pegs do
		self.pegs[i] = buildPeg(self.model, i, p.x, p.y, p.kind)
	end
	-- Rails/dividers drawn as thick outlined bars.
	for _, w in self.def.walls do
		local a = Layout.boardToWorld(w.x1, w.y1)
		local b = Layout.boardToWorld(w.x2, w.y2)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		local cf = CFrame.new(mid) * CFrame.Angles(0, 0, math.atan2(b.Y - a.Y, b.X - a.X))
		Build.block(self.model, Vector3.new(len + 0.32, 0.5, DEPTH), cf * CFrame.new(0, 0, 0.12), INK)
		Build.block(self.model, Vector3.new(len + 0.18, 0.34, DEPTH), cf * CFrame.new(0, 0, 0.2), trim)
		Build.block(self.model, Vector3.new(len, 0.08, DEPTH), cf * CFrame.new(0, 0.08, 0.26), Color3.new(1, 1, 1), { transparency = 0.4 })
	end
	self.conn = RunService.RenderStepped:Connect(function(dt)
		Board._step(self, dt)
	end)
	return self
end

function Board.position(self: Board, index: number): Vector3
	return self.pegs[index].center
end

local function applyPose(view: PegView)
	local scale = 1 + 0.55 * view.pop
	for _, pp in view.parts do
		local s = pp.size
		pp.part.Size = if pp.cyl then Vector3.new(s.X, s.Y * scale, s.Z * scale) else Vector3.new(s.X * scale, s.Y * scale, s.Z)
		pp.part.CFrame = CFrame.new(view.center + pp.offset * scale) * pp.rot
	end
end

local function tint(view: PegView, color: Color3, neon: boolean)
	for _, pp in view.parts do
		if pp.tint then
			pp.part.Color = color
			pp.part.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

-- A peg is hit: flash, pop, then stay lit until the board refreshes.
function Board.hit(self: Board, index: number, strength: number?)
	local view = self.pegs[index]
	if view == nil then
		return
	end
	view.isLit = true
	view.flash = 0.16
	view.pop = if self.reducedMotion then 0.15 else math.min(1, 0.7 + (strength or 0) * 0.3)
	tint(view, view.lit, true)
	self.active[index] = true
	if view.ring then
		(view.ring :: BasePart).Transparency = 0.55
	end
end

-- Pegs refresh before each launch (plan §5): a quick wave from the bottom.
function Board.refresh(self: Board, animated: boolean)
	for _, view in self.pegs do
		if view.isLit then
			view.isLit = false
			local _, by = Layout.worldToBoard(view.center)
			local delayTime = if animated and not self.reducedMotion then (80 - by) / 80 * 0.35 else 0
			task.delay(delayTime, function()
				if not view.isLit then
					tint(view, view.base, false)
					view.pop = if animated and not self.reducedMotion then 0.3 else 0
					self.active[view.index] = true
				end
			end)
		end
		if view.ring then
			(view.ring :: BasePart).Transparency = 0.86
		end
	end
end

function Board._step(self: Board, dt: number)
	for index in self.active do
		local view = self.pegs[index]
		if view.flash > 0 then
			view.flash -= dt
			if view.flash <= 0 then
				tint(view, if view.isLit then view.lit:Lerp(view.base, 0.25) else view.base, false)
			end
		end
		view.pop = math.max(0, view.pop - dt * 5)
		applyPose(view)
		if view.pop <= 0 and view.flash <= 0 then
			self.active[index] = nil
		end
	end
end

function Board.destroy(self: Board)
	if self.conn then
		self.conn:Disconnect()
	end
	self.model:Destroy()
end

return Board
