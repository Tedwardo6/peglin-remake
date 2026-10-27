--!strict
-- First-collision aim guide. It runs the real solver from the launcher to
-- the first contact (second with Steady Hand), so the line is honest: it is
-- exactly where the ball will go. A few faint dots hint the bounce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Solver = require(Shared.Sim.Solver)
local Boards = require(Shared.Content.Boards)

local Build = require(script.Parent.Parent.World.Build)
local Layout = require(script.Parent.Parent.World.Layout)

local SOLID = 30
local HINT = 6

local Guide = {}
Guide.__index = Guide

export type Guide = typeof(setmetatable(
	{} :: {
		model: Model,
		fronts: { BasePart },
		backs: { BasePart },
		ring: BasePart,
		ringBack: BasePart,
		visible: boolean,
		lastKey: string,
	},
	Guide
))

function Guide.new(parent: Instance): Guide
	local self = setmetatable({}, Guide) :: any
	self.model = Build.model("AimGuide", parent)
	self.fronts = {}
	self.backs = {}
	for i = 1, SOLID + HINT do
		local d = if i <= SOLID then 0.28 else 0.18
		table.insert(self.backs, Build.disc(self.model, d + 0.1, 0.05, Vector3.zero, Build.INK))
		table.insert(self.fronts, Build.disc(self.model, d, 0.05, Vector3.zero, Color3.new(1, 1, 1)))
	end
	self.ringBack = Build.disc(self.model, 0.95, 0.04, Vector3.zero, Build.INK, { transparency = 0.2 })
	self.ring = Build.disc(self.model, 0.8, 0.04, Vector3.zero, Color3.fromRGB(255, 240, 120), { transparency = 0.1 })
	self.visible = true
	self.lastKey = ""
	return self
end

function Guide.setVisible(self: Guide, on: boolean)
	if on == self.visible then
		return
	end
	self.visible = on
	self.lastKey = ""
	if not on then
		for i, p in self.fronts do
			p.Transparency = 1
			self.backs[i].Transparency = 1
		end
		self.ring.Transparency = 1
		self.ringBack.Transparency = 1
	end
end

function Guide.update(self: Guide, boardId: string, phys: Solver.BallPhysics, aim: number, contacts: number)
	if not self.visible then
		return
	end
	local key = `{boardId}|{aim}|{phys.radius}|{contacts}`
	if key == self.lastKey then
		return
	end
	self.lastKey = key
	local board = Boards.ById[boardId]
	local sim = Solver.simulate(board, phys, aim, { maxContacts = contacts + 1, maxSteps = 200 })
	-- Step of the Nth contact (or the end of the computed path).
	local contactStep = sim.steps
	local count = 0
	for _, ev in sim.events do
		count += 1
		if count == contacts then
			contactStep = ev.step
			break
		end
	end
	local hintEnd = math.min(sim.steps, contactStep + 9)
	local function at(stepF: number): Vector3
		local s = math.clamp(stepF, 1, sim.steps)
		local s0 = math.floor(s)
		local f = s - s0
		local s1 = math.min(sim.steps, s0 + 1)
		local x = sim.xs[s0] + (sim.xs[s1] - sim.xs[s0]) * f
		local y = sim.ys[s0] + (sim.ys[s1] - sim.ys[s0]) * f
		return Layout.boardToWorld(x, y, Layout.BALL_Z + 0.1)
	end
	local parts = {}
	local cfs = {}
	for i = 1, SOLID do
		local s = 1 + (contactStep - 1) * (i / SOLID)
		local pos = at(s)
		table.insert(parts, self.backs[i])
		table.insert(cfs, CFrame.new(pos - Vector3.new(0, 0, 0.03)) * CFrame.Angles(0, math.rad(90), 0))
		table.insert(parts, self.fronts[i])
		table.insert(cfs, CFrame.new(pos) * CFrame.Angles(0, math.rad(90), 0))
		local fade = 0.05 + 0.45 * (i / SOLID)
		self.fronts[i].Transparency = fade
		self.backs[i].Transparency = fade
	end
	for j = 1, HINT do
		local i = SOLID + j
		local s = contactStep + (hintEnd - contactStep) * (j / HINT)
		local pos = at(s)
		table.insert(parts, self.backs[i])
		table.insert(cfs, CFrame.new(pos - Vector3.new(0, 0, 0.03)) * CFrame.Angles(0, math.rad(90), 0))
		table.insert(parts, self.fronts[i])
		table.insert(cfs, CFrame.new(pos) * CFrame.Angles(0, math.rad(90), 0))
		local fade = if hintEnd > contactStep then 0.55 + 0.35 * (j / HINT) else 1
		self.fronts[i].Transparency = fade
		self.backs[i].Transparency = math.min(1, fade + 0.2)
	end
	local hitPos = at(contactStep)
	table.insert(parts, self.ringBack)
	table.insert(cfs, CFrame.new(hitPos - Vector3.new(0, 0, 0.05)) * CFrame.Angles(0, math.rad(90), 0))
	table.insert(parts, self.ring)
	table.insert(cfs, CFrame.new(hitPos - Vector3.new(0, 0, 0.02)) * CFrame.Angles(0, math.rad(90), 0))
	self.ring.Transparency = if count >= contacts then 0.35 else 1
	self.ringBack.Transparency = if count >= contacts then 0.5 else 1
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function Guide.destroy(self: Guide)
	self.model:Destroy()
end

return Guide
