--!strict
-- The act map: rows of choices from the act's start to its boss, drawn like
-- a star chart over the dimmed battlefield. Nodes you can take now glow;
-- each party member's vote shows as their portrait on the node they chose.
-- Most votes wins when everyone has voted or time runs out; the party
-- leader breaks ties. A single forced step just previews briefly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enemies = require(Shared.Content.Enemies)
local Campaigns = require(Shared.Content.Campaigns)
local Config = require(Shared.Config)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Hud = require(script.Parent.Hud)
local Audio = require(script.Parent.Parent.Juice.Audio)

local C = Theme.Color
local myUid = Players.LocalPlayer.UserId

local MapScreen = {}

export type View = {
	frame: Frame,
	update: (run: { [string]: any }, now: number) -> (),
	close: () -> (),
}

local KIND = {
	fight = { glyph = "⚔", name = "Battle", color = Color3.fromRGB(150, 170, 255) },
	elite = { glyph = "☠", name = "Elite", color = Color3.fromRGB(255, 96, 120) },
	rest = { glyph = "🔥", name = "Campfire", color = Color3.fromRGB(255, 160, 70) },
	treasure = { glyph = "◆", name = "Treasure", color = Color3.fromRGB(255, 210, 90) },
	boss = { glyph = "👑", name = "Boss", color = Color3.fromRGB(255, 70, 90) },
}

local function describe(node: { [string]: any }): string
	local k = node.kind
	if k == "fight" or k == "elite" or k == "boss" then
		local e = Enemies.ById[node.enemy]
		local name = if e then e.name else "?"
		if k == "elite" then
			return `ELITE · {name}\nTougher ({math.floor(Config.Combat.ELITE_HP_MULT * 100)}% HP, harder hits). Win: +{Config.Combat.ELITE_SPOILS_MAX_HULL} max hull for everyone.`
		elseif k == "boss" then
			return `BOSS · {name}\n{if e then e.blurb else ""}`
		end
		return `BATTLE · {name}\n{if e then e.blurb else ""}`
	elseif k == "rest" then
		return `CAMPFIRE\nEach hero chooses: repair {math.floor(Config.Combat.REST_HEAL_FRACTION * 100)}% hull, or train a ball (+1 level).`
	elseif k == "treasure" then
		return "TREASURE\nA relic for each hero, no fight."
	end
	return ""
end

local function line(parent: Instance, a: Vector2, b: Vector2, color: Color3, thickness: number, transparency: number, z: number): Frame
	local d = b - a
	local f = Kit.new("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(d.Magnitude, thickness),
		Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		ZIndex = z,
		Parent = parent,
	})
	return f
end

function MapScreen.open(parent: Instance, onVote: (nodeId: string) -> ()): View
	local frame: Frame = Kit.new("Frame", { Name = "MapScreen", BackgroundColor3 = Color3.fromRGB(2, 2, 12), BackgroundTransparency = 0.25, Size = UDim2.fromScale(1, 1), ZIndex = 20, Parent = parent })
	-- Swirling backdrop.
	local swirl = Kit.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, Size = UDim2.fromOffset(900, 900), Position = UDim2.fromScale(0.5, 0.55), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 20, Parent = frame })
	Kit.corner(450).Parent = swirl
	Kit.shimmer(swirl, 8)
	local chart = Kit.panel({ Size = UDim2.fromOffset(940, 420), Position = UDim2.new(0.5, 0, 0.5, 18), AnchorPoint = Vector2.new(0.5, 0.5), Color = Color3.fromRGB(8, 8, 28), Transparency = 0.15, ZIndex = 21, Parent = frame })
	local title = Kit.label({ Text = "", Title = true, Bold = true, TextSize = 44, TextColor3 = C.gold, Size = UDim2.fromOffset(900, 48), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 22, Parent = frame })
	local sub = Kit.label({ Text = "", TextSize = 16, TextColor3 = C.textDim, Size = UDim2.fromOffset(900, 22), Position = UDim2.new(0.5, 0, 0, 56), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 22, Parent = frame })
	local timer = Kit.bar({ Size = UDim2.fromOffset(420, 16), Position = UDim2.new(0.5, 0, 1, -54), AnchorPoint = Vector2.new(0.5, 0), Color = C.gold, TextSize = 12, ZIndex = 22, Parent = frame })
	local info = Kit.label({ Text = "Pick a glowing node to vote for it. Hover to read what waits there.", TextSize = 15, TextColor3 = C.text, TextWrapped = true, Size = UDim2.fromOffset(760, 40), Position = UDim2.new(0.5, 0, 1, -100), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 22, Parent = frame })
	local lines: Frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 22, Parent = chart })
	local nodesHolder: Frame = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 23, Parent = chart })
	Kit.popIn(chart)
	Audio.play("open")

	local builtFor = ""
	local nodeButtons: { [string]: { button: TextButton, ring: UIStroke, votes: Frame, pos: Vector2, color: Color3 } } = {}
	local myVote: string? = nil

	local function nodePos(node: { [string]: any }, rows: number): Vector2
		-- Columns left→right by row, vertical spread by x (0..1).
		local w, h = 940, 420
		local x = 70 + (node.row - 1) * ((w - 140) / rows)
		local y = 40 + node.x * (h - 80)
		return Vector2.new(x, y)
	end

	local function build(run: { [string]: any })
		for _, ch in lines:GetChildren() do
			ch:Destroy()
		end
		for _, ch in nodesHolder:GetChildren() do
			ch:Destroy()
		end
		nodeButtons = {}
		local map = run.map
		if map == nil then
			return
		end
		local camp = Campaigns.ById[run.campaign]
		local act = if camp then camp.acts[run.act] else nil
		local accent = if act then act.palette.glow else C.blue
		local rows = #map.rows + 1
		local all = {}
		for _, row in map.rows do
			for _, n in row do
				table.insert(all, n)
			end
		end
		table.insert(all, map.boss)
		local byId = {}
		for _, n in all do
			byId[n.id] = n
		end
		-- Start marker and links.
		local startPos = Vector2.new(24, 210)
		for _, n in map.rows[1] do
			line(lines, startPos, nodePos(n, rows), accent, 3, 0.5, 22)
		end
		for _, n in all do
			for _, id in n.next do
				local m = byId[id]
				if m then
					line(lines, nodePos(n, rows), nodePos(m, rows), accent, 3, 0.55, 22)
				end
			end
			if #n.next == 0 and n.kind ~= "boss" then
				line(lines, nodePos(n, rows), nodePos(map.boss, rows), accent, 3, 0.55, 22)
			end
		end
		local dot = Kit.new("Frame", { BackgroundColor3 = accent, Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(startPos.X, startPos.Y), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 24, Parent = nodesHolder })
		Kit.corner(7).Parent = dot
		for _, n in all do
			local def = KIND[n.kind] or KIND.fight
			local size = if n.kind == "boss" then 86 else 64
			local pos = nodePos(n, rows)
			local b: TextButton = Kit.new("TextButton", {
				Text = "",
				AutoButtonColor = false,
				BackgroundColor3 = Color3.fromRGB(16, 14, 44),
				Size = UDim2.fromOffset(size, size),
				Position = UDim2.fromOffset(pos.X, pos.Y),
				AnchorPoint = Vector2.new(0.5, 0.5),
				ZIndex = 24,
				Parent = nodesHolder,
			})
			Kit.corner(size // 2).Parent = b
			local ring = Kit.stroke(3, def.color, 0.2)
			ring.Parent = b
			Kit.label({ Text = def.glyph, TextSize = if n.kind == "boss" then 42 else 30, Size = UDim2.fromScale(1, 1), TextColor3 = def.color, ZIndex = 25, Parent = b })
			local e = if n.enemy then Enemies.ById[n.enemy] else nil
			Kit.label({ Text = if e then e.name else def.name, TextSize = 12, TextColor3 = C.textDim, Size = UDim2.fromOffset(130, 16), Position = UDim2.new(0.5, 0, 1, 4), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 25, Parent = b })
			local votes = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(120, 26), Position = UDim2.new(0.5, 0, 0, -30), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 26, Parent = b })
			Kit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 2), Parent = votes })
			nodeButtons[n.id] = { button = b, ring = ring, votes = votes, pos = pos, color = def.color }
			b.MouseEnter:Connect(function()
				info.Text = describe(n)
			end)
			b.Activated:Connect(function()
				local choices = (b:GetAttribute("Choosable") :: boolean?) == true
				info.Text = describe(n)
				if not choices then
					Audio.play("reject")
					return
				end
				myVote = n.id
				Audio.play("click", { pitch = 1.15 })
				onVote(n.id)
			end)
		end
	end

	local view: View
	view = {
		frame = frame,
		update = function(run: { [string]: any }, now: number)
			local key = `{run.id}:{run.act}`
			if key ~= builtFor then
				builtFor = key
				build(run)
				myVote = nil
			end
			local camp = Campaigns.ById[run.campaign]
			local act = if camp then camp.acts[run.act] else nil
			title.Text = if act then `{act.subtitle} · {act.name}` else "THE PATH"
			local forced = #run.choices <= 1
			sub.Text = if forced then "The path leads on…" else "Choose the path. Most votes wins; the leader breaks ties."
			local remaining = math.max(0, run.stateEndsAt - now)
			local total = if forced then 4 else Config.Run.MAP_SECONDS
			timer.set(remaining, total)
			timer.setText(`{math.ceil(remaining)}s`)
			-- Visited path, choosable nodes, votes.
			local visited = {}
			for _, id in run.path or {} do
				visited[id] = true
			end
			local tally: { [string]: { number } } = {}
			for i, m in run.members do
				if m.vote then
					tally[m.vote] = tally[m.vote] or {}
					table.insert(tally[m.vote], i)
				end
				if m.uid == myUid then
					myVote = m.vote
				end
			end
			for id, nb in nodeButtons do
				local choosable = table.find(run.choices, id) ~= nil
				nb.button:SetAttribute("Choosable", choosable)
				local done = visited[id] == true
				nb.button.BackgroundColor3 = if done then Color3.fromRGB(44, 40, 90) elseif choosable then Color3.fromRGB(30, 26, 80) else Color3.fromRGB(12, 10, 32)
				nb.ring.Transparency = if choosable then 0 elseif done then 0.4 else 0.75
				nb.ring.Thickness = if myVote == id then 6 elseif choosable then 3.5 else 2
				nb.ring.Color = if myVote == id then C.gold else nb.color
				for _, ch in nb.votes:GetChildren() do
					if ch:IsA("ImageLabel") then
						ch:Destroy()
					end
				end
				local voters: { number } = tally[id] or {}
				for _, idx in voters do
					local m = run.members[idx]
					local img = Kit.new("ImageLabel", { Size = UDim2.fromOffset(24, 24), BackgroundColor3 = C.inkSoft, Image = Hud.portrait(m.uid), ZIndex = 27, Parent = nb.votes })
					Kit.corner(12).Parent = img
					Kit.stroke(2, Theme.slot(idx)).Parent = img
				end
			end
		end,
		close = function()
			Kit.tween(frame, 0.2, { BackgroundTransparency = 1 })
			task.delay(0.05, function()
				frame:Destroy()
			end)
		end,
	}
	return view
end

return MapScreen
