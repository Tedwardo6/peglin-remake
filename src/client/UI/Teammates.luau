--!strict
-- Simplified teammate previews (left column): portrait, hull, held charge,
-- and a mini board that replays each teammate's shot from its inputs, plus
-- their live aim. In 3–4 player parties, tapping a portrait chooses who
-- receives your next Relay Charge (no chat needed).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Boards = require(Shared.Content.Boards)
local Pegs = require(Shared.Content.Pegs)
local Aim = require(Shared.Sim.Aim)
local Solver = require(Shared.Sim.Solver)
local Scoring = require(Shared.Sim.Scoring)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Hud = require(script.Parent.Hud)

local C = Theme.Color
local MINI_W = 96
local MINI_H = 128

type Card = {
	uid: number,
	frame: Frame,
	portrait: ImageLabel,
	name: TextLabel,
	hull: Kit.Bar,
	charge: Frame,
	board: Frame,
	boardId: string,
	dots: { Frame },
	ball: Frame,
	aimDots: { Frame },
	target: UIStroke,
	status: TextLabel,
	playing: { sim: Solver.SimResult, hits: { Scoring.Hit }, start: number, nextHit: number }?,
}

local Teammates = {}
Teammates.__index = Teammates

export type Teammates = typeof(setmetatable(
	{} :: {
		root: Frame,
		cards: { [number]: Card },
		order: { number },
		onPick: (uid: number) -> (),
		conn: RBXScriptConnection,
	},
	Teammates
))

local function toMini(x: number, y: number): UDim2
	return UDim2.fromOffset(x / Config.Board.WIDTH * MINI_W, y / Config.Board.HEIGHT * MINI_H)
end

function Teammates.new(parent: Instance, onPick: (number) -> ()): Teammates
	local self = setmetatable({}, Teammates) :: any
	self.root = Kit.new("Frame", {
		Name = "Teammates",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(200, 520),
		Position = UDim2.fromOffset(16, 84),
		Parent = parent,
	})
	Kit.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self.root })
	self.cards = {}
	self.order = {}
	self.onPick = onPick
	self.conn = RunService.RenderStepped:Connect(function(dt)
		Teammates._step(self, dt)
	end)
	return self
end

local function buildBoard(card: Card, boardId: string)
	for _, d in card.dots do
		d:Destroy()
	end
	card.dots = {}
	card.boardId = boardId
	local board = Boards.ById[boardId]
	if board == nil then
		return
	end
	for i, p in board.pegs do
		local def = Pegs.Defs[p.kind]
		local d = Kit.new("Frame", {
			Size = UDim2.fromOffset(if p.kind == "ordinary" then 4 else 6, if p.kind == "ordinary" then 4 else 6),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = toMini(p.x, p.y),
			BackgroundColor3 = def.color,
			BorderSizePixel = 0,
			Parent = card.board,
		})
		Kit.corner(3).Parent = d
		card.dots[i] = d
	end
end

function Teammates._card(self: Teammates, uid: number): Card
	local existing = self.cards[uid]
	if existing then
		return existing
	end
	local frame = Kit.panel({ Size = UDim2.fromOffset(196, 150), Color = C.panel, Parent = self.root })
	local portrait = Kit.new("ImageLabel", {
		Size = UDim2.fromOffset(44, 44),
		Position = UDim2.fromOffset(8, 8),
		BackgroundColor3 = C.panelLight,
		Image = Hud.portrait(uid),
		Parent = frame,
	})
	Kit.corner(22).Parent = portrait
	Kit.stroke(2.5).Parent = portrait
	local player = Players:GetPlayerByUserId(uid)
	local name = Kit.label({ Text = if player then player.DisplayName else "Player", TextSize = 15, Size = UDim2.fromOffset(84, 18), Position = UDim2.fromOffset(6, 56), TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local hull = Kit.bar({ Size = UDim2.fromOffset(84, 16), Position = UDim2.fromOffset(6, 78), Color = C.hull, OverlayColor = C.shield, TextSize = 11, Radius = 7, Parent = frame })
	local charge = Kit.new("Frame", { Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(58, 18), BackgroundColor3 = C.purple, Visible = false, Parent = frame })
	Kit.corner(12).Parent = charge
	Kit.stroke(2).Parent = charge
	Kit.label({ Text = "+", TextSize = 16, Size = UDim2.fromScale(1, 1), Parent = charge })
	local status = Kit.label({ Text = "", TextSize = 12, TextColor3 = C.textDim, Size = UDim2.fromOffset(86, 34), Position = UDim2.fromOffset(6, 98), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Parent = frame })
	local board = Kit.new("Frame", {
		Size = UDim2.fromOffset(MINI_W, MINI_H),
		Position = UDim2.new(1, -8, 0, 11),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = C.ink,
		ClipsDescendants = true,
		Parent = frame,
	})
	Kit.corner(8).Parent = board
	Kit.stroke(2, C.panelEdge).Parent = board
	local ball = Kit.new("Frame", { Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 3, Parent = board })
	Kit.corner(4).Parent = ball
	local aimDots = {}
	for i = 1, 6 do
		local a = Kit.new("Frame", { Size = UDim2.fromOffset(3, 3), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.3, Visible = false, ZIndex = 2, Parent = board })
		Kit.corner(2).Parent = a
		aimDots[i] = a
	end
	local target = Kit.stroke(0, C.purple)
	target.Parent = frame
	local pick = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = frame })
	pick.Activated:Connect(function()
		self.onPick(uid)
	end)
	local card: Card = {
		uid = uid,
		frame = frame,
		portrait = portrait,
		name = name,
		hull = hull,
		charge = charge,
		board = board,
		boardId = "",
		dots = {},
		ball = ball,
		aimDots = aimDots,
		target = target,
		status = status,
		playing = nil,
	}
	self.cards[uid] = card
	Kit.popIn(frame)
	return card
end

export type MemberView = {
	uid: number,
	hull: number,
	maxHull: number,
	shield: number,
	charge: boolean,
	status: string,
}

function Teammates.set(self: Teammates, members: { MemberView }, boardId: string, recipient: number?, selectable: boolean)
	local seen = {}
	for i, m in members do
		local card = Teammates._card(self, m.uid)
		seen[m.uid] = true
		card.frame.LayoutOrder = i
		if card.boardId ~= boardId then
			buildBoard(card, boardId)
		end
		card.hull.set(m.hull, m.maxHull)
		card.hull.setOverlay(math.min(m.shield, m.maxHull), m.maxHull)
		card.charge.Visible = m.charge
		card.status.Text = m.status
		local isTarget = selectable and recipient == m.uid
		Kit.tween(card.target, 0.15, { Thickness = if isTarget then 5 else 0 })
	end
	for uid, card in self.cards do
		if not seen[uid] then
			card.frame:Destroy()
			self.cards[uid] = nil
		end
	end
end

function Teammates.play(self: Teammates, uid: number, sim: Solver.SimResult, hits: { Scoring.Hit }, offset: number)
	local card = self.cards[uid]
	if card == nil then
		return
	end
	for _, d in card.dots do
		d.BackgroundTransparency = 0
		d.Size = UDim2.fromOffset(d.Size.X.Offset, d.Size.Y.Offset)
	end
	local board = Boards.ById[card.boardId]
	if board then
		for i, p in board.pegs do
			card.dots[i].BackgroundColor3 = Pegs.Defs[p.kind].color
		end
	end
	card.playing = { sim = sim, hits = hits, start = os.clock() - offset, nextHit = 1 }
	card.ball.Visible = true
	for _, a in card.aimDots do
		a.Visible = false
	end
end

function Teammates.aim(self: Teammates, uid: number, aim: number)
	local card = self.cards[uid]
	if card == nil or card.playing then
		return
	end
	local dx, dy = Aim.direction(aim)
	for i, a in card.aimDots do
		local d = i * 3.2
		a.Position = toMini(Config.Board.LAUNCH_X + dx * d, Config.Board.LAUNCH_Y + dy * d)
		a.Visible = true
	end
end

function Teammates.screenPos(self: Teammates, uid: number): Vector2?
	local card = self.cards[uid]
	if card == nil then
		return nil
	end
	return card.portrait.AbsolutePosition + card.portrait.AbsoluteSize / 2
end

function Teammates.flashCard(self: Teammates, uid: number, color: Color3)
	local card = self.cards[uid]
	if card then
		card.frame.BackgroundColor3 = color
		Kit.tween(card.frame, 0.5, { BackgroundColor3 = C.panel })
		Kit.bounce(card.frame, 0.08)
	end
end

function Teammates._step(self: Teammates, _dt: number)
	for _, card in self.cards do
		local pl = card.playing
		if pl then
			local step = (os.clock() - pl.start) * Config.Sim.STEP_HZ
			local s = math.clamp(math.floor(step), 1, pl.sim.steps)
			card.ball.Position = toMini(pl.sim.xs[s], pl.sim.ys[s])
			while pl.nextHit <= #pl.hits and pl.hits[pl.nextHit].step <= step do
				local h = pl.hits[pl.nextHit]
				pl.nextHit += 1
				if h.peg then
					local d = card.dots[h.peg]
					if d then
						d.BackgroundColor3 = Color3.new(1, 1, 1)
					end
				end
			end
			if step >= pl.sim.steps then
				card.playing = nil
				card.ball.Visible = false
				local board = Boards.ById[card.boardId]
				if board then
					for i, p in board.pegs do
						Kit.tween(card.dots[i], 0.4, { BackgroundColor3 = Pegs.Defs[p.kind].color })
					end
				end
			end
		end
	end
end

function Teammates.clear(self: Teammates)
	for uid, card in self.cards do
		card.frame:Destroy()
		self.cards[uid] = nil
	end
end

return Teammates
