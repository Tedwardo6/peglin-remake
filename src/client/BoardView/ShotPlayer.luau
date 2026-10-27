--!strict
-- Plays one simulated shot on the player's board in real time: moves the
-- ball along the solver's path, fires hit/wall callbacks at the exact step
-- they happened, supports short hit-stops, and drains the ball at the end.
-- The simulation itself is never altered by presentation.

local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Solver = require(Shared.Sim.Solver)
local Scoring = require(Shared.Sim.Scoring)

local Build = require(script.Parent.Parent.World.Build)
local Layout = require(script.Parent.Parent.World.Layout)

local STEP_HZ = Config.Sim.STEP_HZ

export type Callbacks = {
	onHit: (hit: Scoring.Hit, index: number) -> (),
	onWall: (pos: Vector3) -> (),
	onEnd: () -> (),
}

local ShotPlayer = {}
ShotPlayer.__index = ShotPlayer

export type ShotPlayer = typeof(setmetatable(
	{} :: {
		sim: Solver.SimResult,
		hits: { Scoring.Hit },
		walls: { Solver.SimEvent },
		cb: Callbacks,
		t: number,
		stop: number,
		nextHit: number,
		nextWall: number,
		ball: Model,
		core: BasePart,
		parts: { BasePart },
		radius: number,
		conn: RBXScriptConnection?,
		done: boolean,
		draining: number,
		lastPos: Vector3,
	},
	ShotPlayer
))

function ShotPlayer.new(parent: Instance, sim: Solver.SimResult, outcome: Scoring.Outcome, radius: number, color: Color3, accent: Color3, trailA: Color3, trailB: Color3, cb: Callbacks, startOffset: number?): ShotPlayer
	local self = setmetatable({}, ShotPlayer) :: any
	self.sim = sim
	self.hits = outcome.hits
	self.walls = {}
	for _, ev in sim.events do
		if ev.kind == "wall" then
			table.insert(self.walls, ev)
		end
	end
	self.cb = cb
	self.t = startOffset or 0
	self.stop = 0
	self.nextHit = 1
	self.nextWall = 1
	self.done = false
	self.draining = -1
	self.radius = radius

	local model = Build.model("Ball", parent)
	local R = radius * Layout.S * 1.04
	local start = Layout.boardToWorld(Config.Board.LAUNCH_X, Config.Board.LAUNCH_Y, Layout.BALL_Z)
	local outline = Build.ball(model, 2 * R + 0.16, start - Vector3.new(0, 0, 0.1), Build.INK)
	local core = Build.ball(model, 2 * R, start, color)
	local band = Build.ball(model, 2 * R * 0.62, start + Vector3.new(0, 0, R * 0.55), accent)
	local gloss = Build.ball(model, R * 0.55, start + Vector3.new(-R * 0.35, R * 0.35, R * 0.75), Color3.new(1, 1, 1), { transparency = 0.15 })
	self.parts = { outline, core, band, gloss }
	self.core = core
	self.ball = model
	self.lastPos = start

	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, R * 0.8, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -R * 0.8, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.28
	trail.MinLength = 0.02
	trail.FaceCamera = true
	trail.LightEmission = 0.6
	trail.Color = ColorSequence.new(trailA, trailB)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Parent = core

	self.conn = RunService.RenderStepped:Connect(function(dt)
		ShotPlayer._step(self, dt)
	end)
	return self
end

function ShotPlayer.hitStop(self: ShotPlayer, seconds: number)
	self.stop = math.max(self.stop, seconds)
end

local function place(self: ShotPlayer, pos: Vector3)
	local offs = {
		Vector3.new(0, 0, -0.1),
		Vector3.zero,
		Vector3.new(0, 0, self.radius * Layout.S * 0.55),
		Vector3.new(-self.radius * Layout.S * 0.36, self.radius * Layout.S * 0.36, self.radius * Layout.S * 0.78),
	}
	local cfs = table.create(4)
	for i = 1, 4 do
		cfs[i] = CFrame.new(pos + offs[i])
	end
	workspace:BulkMoveTo(self.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	self.lastPos = pos
end

function ShotPlayer.position(self: ShotPlayer): Vector3
	return self.lastPos
end

function ShotPlayer._step(self: ShotPlayer, dt: number)
	if self.done then
		return
	end
	if self.draining >= 0 then
		-- Drop out of the drain with a little fade.
		self.draining += dt
		local k = self.draining / 0.3
		place(self, self.lastPos + Vector3.new(0, -dt * 9, 0))
		for _, p in self.parts do
			p.Transparency = math.max(p.Transparency, math.min(1, k))
		end
		if k >= 1 then
			self.done = true
			ShotPlayer.destroy(self)
			self.cb.onEnd()
		end
		return
	end
	if self.stop > 0 then
		self.stop -= dt
		return
	end
	self.t += dt
	local sim = self.sim
	local fstep = self.t * STEP_HZ
	local s0 = math.floor(fstep)
	local frac = fstep - s0
	local last = sim.steps
	local x, y
	if s0 >= last then
		x, y = sim.xs[last], sim.ys[last]
	elseif s0 < 1 then
		local x0, y0 = Config.Board.LAUNCH_X, Config.Board.LAUNCH_Y
		x = x0 + (sim.xs[1] - x0) * fstep
		y = y0 + (sim.ys[1] - y0) * fstep
	else
		x = sim.xs[s0] + (sim.xs[s0 + 1] - sim.xs[s0]) * frac
		y = sim.ys[s0] + (sim.ys[s0 + 1] - sim.ys[s0]) * frac
	end
	place(self, Layout.boardToWorld(x, y, Layout.BALL_Z))

	-- Fire every event at or before the current step, in order.
	while self.nextWall <= #self.walls and self.walls[self.nextWall].step <= fstep do
		local w = self.walls[self.nextWall]
		self.nextWall += 1
		self.cb.onWall(Layout.boardToWorld(w.x, w.y, Layout.BALL_Z))
	end
	while self.nextHit <= #self.hits and self.hits[self.nextHit].step <= fstep do
		local i = self.nextHit
		self.nextHit += 1
		self.cb.onHit(self.hits[i], i)
		if self.stop > 0 then
			return
		end
	end
	if fstep >= last then
		-- Flush anything left (e.g. bursts on the final step), then drain.
		while self.nextHit <= #self.hits do
			local i = self.nextHit
			self.nextHit += 1
			self.cb.onHit(self.hits[i], i)
		end
		self.draining = 0
	end
end

function ShotPlayer.destroy(self: ShotPlayer)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	self.ball:Destroy()
end

return ShotPlayer
