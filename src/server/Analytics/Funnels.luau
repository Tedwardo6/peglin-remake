--!strict
-- Onboarding/progression event map (plan §6), event-map version in Config.
--
-- Scope: repeatable experiment funnel. Each join (and each developer test
-- condition) gets a unique session/condition ID; every milestone is recorded
-- once per ID. Events are emitted by the server only after validation.
-- Time origin is server join; readiness-to-action timing is also kept.
--
--   Onboarding funnel: 1 join · 2 ready_to_act · 3 first_launch ·
--     4 first_useful_hit · 5 first_reward · 6 first_upgrade · 7 independent_repeat
--   Assist funnel (eligible duo sessions): 1 assist_opportunity · 2 assist_sent · 3 assist_used
--   Rematch funnel: 1 rematch_offered · 2 rematch_started
--   Milestone custom events: boss_1..3, leg_1..3, run_complete,
--     alt_kit_run, modifier_run, self_charge_sent, self_charge_used
-- Fields (Roblox allows three): build/event-map · device · condition|prior.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

export type Sink = {
	funnelStep: (uid: number, funnel: string, sessionId: string, step: number, name: string, fields: { string }) -> (),
	custom: (uid: number, name: string, value: number, fields: { string }) -> (),
}

export type Session = {
	id: string,
	uid: number,
	joinAt: number,
	readyAt: number?,
	device: string,
	condition: string,
	prior: string,
	done: { [string]: boolean },
	upgraded: boolean,
}

local STEPS: { [string]: { funnel: string, step: number } } = {
	join = { funnel = "Onboarding", step = 1 },
	ready_to_act = { funnel = "Onboarding", step = 2 },
	first_launch = { funnel = "Onboarding", step = 3 },
	first_useful_hit = { funnel = "Onboarding", step = 4 },
	first_reward = { funnel = "Onboarding", step = 5 },
	first_upgrade = { funnel = "Onboarding", step = 6 },
	independent_repeat = { funnel = "Onboarding", step = 7 },
	assist_opportunity = { funnel = "Assist", step = 1 },
	assist_sent = { funnel = "Assist", step = 2 },
	assist_used = { funnel = "Assist", step = 3 },
	rematch_offered = { funnel = "Rematch", step = 1 },
	rematch_started = { funnel = "Rematch", step = 2 },
}

local Funnels = {}
Funnels.__index = Funnels
Funnels.STEPS = STEPS

export type Funnels = typeof(setmetatable(
	{} :: {
		sink: Sink,
		sessions: { [number]: Session },
		log: { string },
		makeId: () -> string,
	},
	Funnels
))

function Funnels.new(sink: Sink, makeId: () -> string): Funnels
	return setmetatable({ sink = sink, sessions = {}, log = {}, makeId = makeId }, Funnels)
end

local function fields(s: Session): { string }
	return {
		`b{Config.BUILD_VERSION}|m{Config.EVENT_MAP_VERSION}`,
		s.device,
		`{s.condition}|{s.prior}`,
	}
end

local function record(self: Funnels, line: string)
	table.insert(self.log, line)
	if #self.log > 300 then
		table.remove(self.log, 1)
	end
end

-- Starts a new session/condition ID. Join is recorded immediately so early
-- exits stay in the denominator.
function Funnels.start(self: Funnels, uid: number, now: number, condition: string, prior: boolean, device: string?): Session
	local s: Session = {
		id = self.makeId(),
		uid = uid,
		joinAt = now,
		readyAt = nil,
		device = device or "unknown",
		condition = condition,
		prior = if prior then "returning" else "new",
		done = {},
		upgraded = false,
	}
	self.sessions[uid] = s
	Funnels.mark(self, uid, "join", now)
	return s
end

function Funnels.setDevice(self: Funnels, uid: number, device: string)
	local s = self.sessions[uid]
	if s then
		s.device = device
	end
end

-- Records a milestone once per session. Returns true when newly recorded.
function Funnels.mark(self: Funnels, uid: number, name: string, now: number): boolean
	local s = self.sessions[uid]
	if s == nil or s.done[name] then
		return false
	end
	if name == "independent_repeat" and not s.upgraded then
		return false
	end
	s.done[name] = true
	if name == "first_upgrade" then
		s.upgraded = true
	end
	if name == "ready_to_act" then
		s.readyAt = now
	end
	local elapsed = now - s.joinAt
	local f = fields(s)
	local def = STEPS[name]
	if def then
		self.sink.funnelStep(uid, def.funnel, s.id, def.step, name, f)
	end
	self.sink.custom(uid, "t_" .. name, math.floor(elapsed * 10 + 0.5) / 10, f)
	if name == "first_launch" and s.readyAt then
		self.sink.custom(uid, "t_ready_to_first_launch", math.floor((now - s.readyAt) * 10 + 0.5) / 10, f)
	end
	record(self, string.format("[funnel] %s uid=%d session=%s %s +%.1fs", name, uid, string.sub(s.id, 1, 8), table.concat(f, " "), elapsed))
	return true
end

-- Custom events that are not once-per-session (e.g. divergence counts).
function Funnels.event(self: Funnels, uid: number, name: string, value: number)
	local s = self.sessions[uid]
	if s == nil then
		return
	end
	self.sink.custom(uid, name, value, fields(s))
	record(self, string.format("[event] %s uid=%d value=%s", name, uid, tostring(value)))
end

function Funnels.session(self: Funnels, uid: number): Session?
	return self.sessions[uid]
end

function Funnels.finish(self: Funnels, uid: number)
	self.sessions[uid] = nil
end

return Funnels
