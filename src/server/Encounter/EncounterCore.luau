--!strict
-- Authoritative state machine for one encounter (one monster, 1–4 personal
-- boards). Pure: time is passed in, nothing touches engine services, so the
-- whole fight can be driven headlessly in tests.
--
-- Rules implemented here (plan §2/§3):
--   * every accepted launch is simulated immediately from frozen inputs; its
--     hits are scheduled at launch time + step/60 and applied when earned
--     (shield, repair, charges); the shot's damage builds on the hero and is
--     dealt in one strike STRIKE_DELAY after the ball drains
--   * threats are announced with a countdown; shield absorbs first
--   * Relay Charge: one generated per shot, one held, consumed by the next
--     launch, never overwritten, returned to the sender if the recipient's
--     slot is full or they left, expires when the encounter ends
--   * enemy max HP = solo × (1 + 0.75 × (active − 1)); roster changes apply
--     after the hits due in the same tick, preserving the HP percentage
--   * defeated players observe; all defeated loses the fight (free restart)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared.Config)
local Enemies = require(Shared.Content.Enemies)
local Balls = require(Shared.Content.Balls)
local Boards = require(Shared.Content.Boards)
local Components = require(Shared.Content.Components)
local Aim = require(Shared.Sim.Aim)
local Shot = require(Shared.Sim.Shot)
local Scoring = require(Shared.Sim.Scoring)

local COMBAT = Config.Combat
local STEP_DT = 1 / Config.Sim.STEP_HZ

export type Charge = Scoring.Charge

export type PlayerSeed = {
	uid: number,
	hull: number,
	maxHull: number,
	rack: { string },
	components: { string },
	ballLevels: { [string]: number },
}

export type PlayerState = {
	uid: number,
	hull: number,
	maxHull: number,
	shield: number,
	defeated: boolean,
	present: boolean, -- still in the server (or inside the seat hold)
	active: boolean, -- counts toward HP scaling and threats
	rack: { string },
	components: { string },
	ballLevels: { [string]: number },
	cooldowns: { number },
	jam: number,
	charge: Charge?,
	recipient: number?, -- chosen recipient for 3–4 player parties
	seq: number,
	lastLaunchAt: number,
	lastActiveAt: number,
	idleWarned: boolean,
	inFlightUntil: number,
	-- Stats for results and logging
	damage: number,
	shots: number,
	biggestShot: number,
	chargesSent: number,
	chargesUsed: number,
	bonusDamage: number,
	usefulHits: number,
	guarded: number, -- shield gained (incl. from charges)
	mended: number, -- hull repaired
	blocked: number, -- threat damage absorbed by shield
}

export type LaunchRequest = {
	seq: number,
	slot: number,
	aim: number,
	boardRev: number,
}

export type ShotRecord = {
	id: string,
	uid: number,
	seq: number,
	slot: number,
	ballId: string,
	aim: number,
	boardId: string,
	boardRev: number,
	startAt: number,
	endAt: number,
	loadout: Scoring.Loadout,
	recipient: number,
	fingerprint: string,
	damage: number,
	hits: { Scoring.Hit },
}

type Pending = {
	t: number,
	order: number,
	kind: "hit" | "threatHit" | "shotEnd" | "strike",
	shot: ShotRecord?,
	hitIndex: number?,
	damage: number?,
	pierce: number?,
	label: string?,
}

export type OutEvent = { [string]: any }

export type Params = {
	id: string,
	enemyId: string,
	boardId: string,
	now: number,
	startAt: number, -- when the clock starts (after the intro beat)
	players: { PlayerSeed },
	modifiers: { [string]: boolean },
	relayMode: "auto" | "self",
	hpOverride: number?,
	hpMult: number?, -- elite nodes
	damageMult: number?, -- elite nodes: threat damage multiplier
}

local Encounter = {}
Encounter.__index = Encounter

export type Encounter = typeof(setmetatable(
	{} :: {
		id: string,
		def: Enemies.EnemyDef,
		boardId: string,
		boardRev: number,
		phase: "fight" | "won" | "lost",
		startAt: number,
		endAt: number?,
		soloHp: number,
		hp: number,
		maxHp: number,
		armor: number,
		bossPhase: number,
		cycle: { Enemies.ThreatDef },
		cadence: number,
		cycleIndex: number,
		growUses: number,
		nextThreatAt: number,
		players: { [number]: PlayerState },
		order: { number }, -- join order (stable iteration)
		modifiers: { [string]: boolean },
		relayMode: "auto" | "self",
		damageMult: number,
		queue: { Pending },
		queueOrder: number,
		shotCounter: number,
		chargeCounter: number,
		rosterDirty: boolean,
		outbox: { OutEvent },
		shots: { [string]: ShotRecord },
		longestFlight: number,
	},
	Encounter
))

local function emit(self: Encounter, ev: OutEvent)
	table.insert(self.outbox, ev)
end

local function shieldCap(self: Encounter): number
	return if self.modifiers.thin_shields then 15 else COMBAT.SHIELD_CAP
end

function Encounter.scaleFactor(active: number): number
	if active < 1 then
		active = 1
	end
	return 1 + COMBAT.HP_SCALE_PER_EXTRA * (active - 1)
end

function Encounter.new(p: Params): Encounter
	local def = Enemies.ById[p.enemyId]
	assert(def, "unknown enemy " .. p.enemyId)
	local board = Boards.ById[p.boardId]
	assert(board, "unknown board " .. p.boardId)
	local self = setmetatable({}, Encounter) :: any
	self.id = p.id
	self.def = def
	self.boardId = p.boardId
	self.boardRev = board.rev
	self.phase = "fight"
	self.startAt = p.startAt
	self.endAt = nil
	self.soloHp = math.floor((p.hpOverride or def.hp) * (p.hpMult or 1) + 0.5)
	self.damageMult = p.damageMult or 1
	self.armor = 0
	self.bossPhase = 0
	self.cycle = def.cycle
	self.cadence = def.cadence
	self.cycleIndex = 1
	self.growUses = 0
	self.nextThreatAt = p.startAt + def.firstDelay
	self.players = {}
	self.order = {}
	self.modifiers = p.modifiers
	self.relayMode = p.relayMode
	self.queue = {}
	self.queueOrder = 0
	self.shotCounter = 0
	self.chargeCounter = 0
	self.rosterDirty = false
	self.outbox = {}
	self.shots = {}
	self.longestFlight = 0
	for _, seed in p.players do
		Encounter._addPlayer(self, seed, p.now)
	end
	local active = Encounter.activeCount(self)
	self.maxHp = math.max(1, math.floor(self.soloHp * Encounter.scaleFactor(active) + 0.5))
	self.hp = self.maxHp
	return self
end

function Encounter._addPlayer(self: Encounter, seed: PlayerSeed, now: number)
	local cooldowns = {}
	for i = 1, #seed.rack do
		cooldowns[i] = 0
	end
	local ps: PlayerState = {
		uid = seed.uid,
		hull = seed.hull,
		maxHull = seed.maxHull,
		shield = 0,
		defeated = seed.hull <= 0,
		present = true,
		active = true,
		rack = table.clone(seed.rack),
		components = table.clone(seed.components),
		ballLevels = table.clone(seed.ballLevels),
		cooldowns = cooldowns,
		jam = 0,
		charge = nil,
		recipient = nil,
		seq = 0,
		lastLaunchAt = -math.huge,
		lastActiveAt = now,
		idleWarned = false,
		inFlightUntil = -math.huge,
		damage = 0,
		shots = 0,
		biggestShot = 0,
		chargesSent = 0,
		chargesUsed = 0,
		bonusDamage = 0,
		usefulHits = 0,
		guarded = 0,
		mended = 0,
		blocked = 0,
	}
	self.players[seed.uid] = ps
	table.insert(self.order, seed.uid)
end

function Encounter.activeCount(self: Encounter): number
	local n = 0
	for _, uid in self.order do
		local ps = self.players[uid]
		if ps.present and ps.active then
			n += 1
		end
	end
	return n
end

local function schedule(self: Encounter, item: Pending)
	self.queueOrder += 1
	item.order = self.queueOrder
	-- Insertion keeps the queue sorted by (t, order); queues are short.
	local q = self.queue
	local i = #q
	while i >= 1 and (q[i].t > item.t or (q[i].t == item.t and q[i].order > item.order)) do
		i -= 1
	end
	table.insert(q, i + 1, item)
end

function Encounter.cooldownFor(self: Encounter, ps: PlayerState, ballId: string): number
	local def = Balls.ById[ballId]
	if def.cooldown <= 0 then
		return 0
	end
	local cd = def.cooldown
	for _, cid in ps.components do
		local c = Components.ById[cid]
		if c and c.cooldownReduce then
			cd -= c.cooldownReduce
		end
	end
	if cd < 1 then
		cd = 1
	end
	if self.modifiers.slow_rack then
		cd += 1
	end
	return cd
end

local function sendStats(ps: PlayerState): (number, number)
	local power = Config.Relay.BONUS_POWER
	local hits = Config.Relay.BONUS_HITS
	for _, cid in ps.components do
		local c = Components.ById[cid]
		if c then
			if c.sendPower and c.sendPower > power then
				power = c.sendPower
			end
			if c.sendHits and c.sendHits > hits then
				hits = c.sendHits
			end
		end
	end
	return power, hits
end

-- Who receives this player's next Relay Charge (frozen at launch).
function Encounter.resolveRecipient(self: Encounter, ps: PlayerState): number
	if self.relayMode == "self" then
		return ps.uid
	end
	local others = {}
	for _, uid in self.order do
		local o = self.players[uid]
		if uid ~= ps.uid and o.present and o.active and not o.defeated then
			table.insert(others, uid)
		end
	end
	if #others == 0 then
		return ps.uid
	end
	if #others == 1 then
		return others[1]
	end
	if ps.recipient then
		for _, uid in others do
			if uid == ps.recipient then
				return uid
			end
		end
	end
	return others[1]
end

export type LaunchResult = { ok: boolean, reason: string?, shot: ShotRecord? }

function Encounter.launch(self: Encounter, uid: number, req: LaunchRequest, now: number): LaunchResult
	local ps = self.players[uid]
	if ps == nil then
		return { ok = false, reason = "not_member" }
	end
	if self.phase ~= "fight" then
		return { ok = false, reason = "phase" }
	end
	if now < self.startAt then
		return { ok = false, reason = "not_started" }
	end
	if not ps.present or not ps.active then
		return { ok = false, reason = "observer" }
	end
	if ps.defeated then
		return { ok = false, reason = "defeated" }
	end
	if type(req.seq) ~= "number" or req.seq ~= ps.seq + 1 then
		return { ok = false, reason = "sequence" }
	end
	if req.boardRev ~= self.boardRev then
		return { ok = false, reason = "board_revision" }
	end
	if type(req.slot) ~= "number" or req.slot % 1 ~= 0 or req.slot < 1 or req.slot > #ps.rack then
		return { ok = false, reason = "slot" }
	end
	if not Aim.isValid(req.aim) then
		return { ok = false, reason = "aim" }
	end
	if now < ps.inFlightUntil then
		return { ok = false, reason = "in_flight" }
	end
	if now - ps.lastLaunchAt < COMBAT.MIN_LAUNCH_INTERVAL then
		return { ok = false, reason = "frequency" }
	end
	local ballId = ps.rack[req.slot]
	if ps.cooldowns[req.slot] > 0 then
		return { ok = false, reason = "cooldown" }
	end

	-- Accepted: freeze everything this shot depends on.
	ps.seq = req.seq
	ps.lastLaunchAt = now
	ps.lastActiveAt = now
	ps.idleWarned = false
	local charge = ps.charge
	ps.charge = nil
	local loadout: Scoring.Loadout = {
		ballId = ballId,
		components = table.clone(ps.components),
		charge = charge,
		enemyHpFrac = self.hp / self.maxHp,
		ballBonus = ps.ballLevels[ballId] or 0,
	}
	local recipient = Encounter.resolveRecipient(self, ps)
	local result = Shot.resolve({ boardId = self.boardId, boardRev = self.boardRev, aim = req.aim, loadout = loadout })

	self.shotCounter += 1
	local shotId = self.id .. ":" .. tostring(self.shotCounter)
	local flight = result.sim.steps * STEP_DT
	if flight > self.longestFlight then
		self.longestFlight = flight
	end
	local shot: ShotRecord = {
		id = shotId,
		uid = uid,
		seq = req.seq,
		slot = req.slot,
		ballId = ballId,
		aim = req.aim,
		boardId = self.boardId,
		boardRev = self.boardRev,
		startAt = now,
		endAt = now + flight,
		loadout = loadout,
		recipient = recipient,
		fingerprint = result.fingerprint,
		damage = result.outcome.totals.damage,
		hits = result.outcome.hits,
	}
	self.shots[shotId] = shot
	ps.inFlightUntil = shot.endAt
	ps.shots += 1

	-- Cooldowns are counted in shots: every launch ticks the others down.
	for i = 1, #ps.cooldowns do
		if ps.cooldowns[i] > 0 then
			ps.cooldowns[i] -= 1
		end
	end
	ps.cooldowns[req.slot] = Encounter.cooldownFor(self, ps, ballId)
	if ps.jam > 0 then
		for i = 2, #ps.cooldowns do
			ps.cooldowns[i] += ps.jam
		end
		ps.jam = 0
	end

	if charge then
		ps.chargesUsed += 1
		for _, cid in ps.components do
			local c = Components.ById[cid]
			if c and c.consumeShield then
				ps.shield = math.min(shieldCap(self), ps.shield + c.consumeShield)
			end
		end
		emit(self, { type = "chargeUsed", uid = uid, from = charge.from, chargeId = charge.id, shotId = shotId })
	end

	for i, h in shot.hits do
		schedule(self, { t = now + h.step * STEP_DT, order = 0, kind = "hit", shot = shot, hitIndex = i })
	end
	schedule(self, { t = shot.endAt, order = 0, kind = "shotEnd", shot = shot })
	schedule(self, { t = shot.endAt + COMBAT.STRIKE_DELAY, order = 0, kind = "strike", shot = shot })

	emit(self, {
		type = "shotStarted",
		shotId = shotId,
		uid = uid,
		seq = req.seq,
		slot = req.slot,
		ballId = ballId,
		aim = req.aim,
		boardId = self.boardId,
		boardRev = self.boardRev,
		startAt = now,
		loadout = loadout,
		recipient = recipient,
		fingerprint = result.fingerprint,
	})
	return { ok = true, shot = shot }
end

local function damageEnemy(self: Encounter, amount: number, t: number, source: number?)
	if amount <= 0 or self.phase ~= "fight" then
		return
	end
	local absorbed = 0
	if self.armor > 0 then
		absorbed = math.min(self.armor, amount)
		self.armor -= absorbed
		amount -= absorbed
	end
	self.hp -= amount
	if source then
		local ps = self.players[source]
		if ps then
			ps.damage += amount + absorbed
		end
	end
	-- Boss phase changes at HP thresholds.
	local phases = self.def.phases
	if phases then
		local nextPhase = phases[self.bossPhase + 1]
		if nextPhase and self.hp > 0 and self.hp / self.maxHp <= nextPhase.at then
			self.bossPhase += 1
			self.cycle = nextPhase.cycle
			self.cadence = nextPhase.cadence
			self.cycleIndex = 1
			emit(self, { type = "bossPhase", phase = self.bossPhase, label = nextPhase.label, t = t })
		end
	end
	if self.hp <= 0 then
		self.hp = 0
		self.phase = "won"
		self.endAt = t
		emit(self, { type = "won", t = t })
	end
end

local function deliverCharge(self: Encounter, shot: ShotRecord, t: number)
	local sender = self.players[shot.uid]
	if sender == nil then
		return
	end
	local power, hits = sendStats(sender)
	self.chargeCounter += 1
	local charge: Charge = { id = self.id .. "#c" .. tostring(self.chargeCounter), from = shot.uid, power = power, hits = hits }
	sender.chargesSent += 1
	local target = self.players[shot.recipient]
	local targetOk = target ~= nil and target.present and target.active and not target.defeated
	if targetOk and (target :: PlayerState).charge == nil then
		(target :: PlayerState).charge = charge
		emit(self, { type = "chargeSent", from = shot.uid, to = shot.recipient, chargeId = charge.id, shotId = shot.id, t = t })
		return
	end
	if sender.charge == nil and sender.present and not sender.defeated then
		sender.charge = charge
		emit(self, {
			type = "chargeReturned",
			from = shot.uid,
			intended = shot.recipient,
			chargeId = charge.id,
			reason = if targetOk then "full" else "left",
			t = t,
		})
		return
	end
	emit(self, { type = "chargeDropped", from = shot.uid, intended = shot.recipient, chargeId = charge.id, t = t })
end

local function applyHit(self: Encounter, shot: ShotRecord, index: number, t: number)
	if self.phase ~= "fight" then
		return
	end
	local h = shot.hits[index]
	local ps = self.players[shot.uid]
	if ps and (h.damage > 0 or h.shield > 0 or h.heal > 0 or h.charge) then
		ps.usefulHits += 1
		if ps.usefulHits == 1 then
			emit(self, { type = "firstUseful", uid = shot.uid, t = t })
		end
	end
	if h.shield > 0 and ps and not ps.defeated then
		local before = ps.shield
		ps.shield = math.min(shieldCap(self), ps.shield + h.shield)
		ps.guarded += ps.shield - before
	end
	if h.heal > 0 and ps and not ps.defeated then
		local before = ps.hull
		ps.hull = math.min(ps.maxHull, ps.hull + h.heal)
		ps.mended += ps.hull - before
	end
	if h.bonus > 0 and ps then
		ps.bonusDamage += h.bonus
	end
	if h.charge then
		deliverCharge(self, shot, t)
	end
	-- Damage is banked on the hero and dealt by the strike (see tick).
end

local function threatDamage(self: Encounter, threat: Enemies.ThreatDef): number
	local d = threat.damage
	if threat.kind == "grow" then
		d += (threat.growBy or 0) * self.growUses
	end
	if self.damageMult ~= 1 then
		d = math.ceil(d * self.damageMult)
	end
	return d
end

-- The threat that will land next (for the HUD telegraph).
function Encounter.nextThreat(self: Encounter): (Enemies.ThreatDef, number)
	local threat = self.cycle[self.cycleIndex]
	return threat, threatDamage(self, threat)
end

local function hitPlayers(self: Encounter, amount: number, pierce: number, t: number, label: string)
	local results = {}
	local allDown = true
	local anyPresent = false
	for _, uid in self.order do
		local ps = self.players[uid]
		if ps.present and ps.active and not ps.defeated then
			local pierced = math.floor(amount * pierce)
			local rest = amount - pierced
			local blocked = math.min(ps.shield, rest)
			ps.shield -= blocked
			ps.blocked += blocked
			local toHull = rest - blocked + pierced
			ps.hull -= toHull
			-- Shield Spikes: blocked damage hits the monster back.
			local spikes = 0
			for _, cid in ps.components do
				local c = Components.ById[cid]
				if c and c.spikesMul then
					spikes = blocked * c.spikesMul
				end
			end
			if ps.hull <= 0 then
				ps.hull = 0
				ps.defeated = true
				emit(self, { type = "defeated", uid = uid, t = t })
			end
			table.insert(results, { uid = uid, blocked = blocked, hull = toHull, spikes = spikes })
			if spikes > 0 then
				damageEnemy(self, spikes, t, uid)
			end
		end
	end
	emit(self, { type = "threatHit", t = t, label = label, amount = amount, results = results })
	for _, uid in self.order do
		local ps = self.players[uid]
		if ps.present and ps.active then
			anyPresent = true
			if not ps.defeated then
				allDown = false
			end
		end
	end
	if anyPresent and allDown and self.phase == "fight" then
		self.phase = "lost"
		self.endAt = t
		emit(self, { type = "lost", t = t })
	end
end

local function landThreat(self: Encounter, t: number)
	local threat = self.cycle[self.cycleIndex]
	local amount = threatDamage(self, threat)
	emit(self, { type = "threatLanding", t = t, kind = threat.kind, label = threat.label })
	if threat.kind == "armor" then
		self.armor += threat.armor or 0
		emit(self, { type = "armorUp", t = t, armor = self.armor })
	else
		local hits = threat.hits or 1
		local gap = threat.gap or 1.2
		if self.modifiers.split_threats then
			-- Every hit lands as two halves, 2 s apart.
			local parts = {}
			for _ = 1, hits do
				table.insert(parts, math.ceil(amount / 2))
				table.insert(parts, math.floor(amount / 2))
			end
			for i, part in parts do
				schedule(self, { t = t + (i - 1) * 2, order = 0, kind = "threatHit", damage = part, pierce = threat.pierce or 0, label = threat.label })
			end
		else
			for i = 1, hits do
				schedule(self, { t = t + (i - 1) * gap, order = 0, kind = "threatHit", damage = amount, pierce = threat.pierce or 0, label = threat.label })
			end
		end
		if threat.kind == "jam" then
			for _, uid in self.order do
				local ps = self.players[uid]
				if ps.present and ps.active and not ps.defeated then
					ps.jam += threat.jam or 1
				end
			end
		end
	end
	if threat.kind == "grow" then
		self.growUses += 1
	end
	self.cycleIndex = (self.cycleIndex % #self.cycle) + 1
	self.nextThreatAt = t + self.cadence
end

-- Marks a player gone (left the server). Their accepted shot finishes.
function Encounter.removePlayer(self: Encounter, uid: number, now: number)
	local ps = self.players[uid]
	if ps and ps.present then
		ps.present = false
		self.rosterDirty = true
		-- A charge waiting for them returns to its sender if possible.
		if ps.charge then
			local ch = ps.charge :: Charge
			ps.charge = nil
			local sender = self.players[ch.from]
			if sender and sender.uid ~= uid and sender.present and sender.charge == nil then
				sender.charge = ch
				emit(self, { type = "chargeReturned", from = ch.from, intended = uid, chargeId = ch.id, reason = "left", t = now })
			end
		end
		emit(self, { type = "left", uid = uid, t = now })
	end
end

function Encounter.setObserver(self: Encounter, uid: number, now: number)
	local ps = self.players[uid]
	if ps and ps.active then
		ps.active = false
		self.rosterDirty = true
		emit(self, { type = "observer", uid = uid, t = now })
	end
end

function Encounter.touch(self: Encounter, uid: number, now: number)
	local ps = self.players[uid]
	if ps then
		ps.lastActiveAt = now
		if ps.idleWarned then
			ps.idleWarned = false
			emit(self, { type = "idleCleared", uid = uid })
		end
	end
end

function Encounter.setRecipient(self: Encounter, uid: number, target: number): boolean
	local ps = self.players[uid]
	local t = self.players[target]
	if ps == nil or t == nil or target == uid then
		return false
	end
	ps.recipient = target
	return true
end

local function applyRoster(self: Encounter)
	if not self.rosterDirty then
		return
	end
	self.rosterDirty = false
	local active = Encounter.activeCount(self)
	if active == 0 then
		return
	end
	local newMax = math.max(1, math.floor(self.soloHp * Encounter.scaleFactor(active) + 0.5))
	if newMax ~= self.maxHp and self.phase == "fight" then
		local frac = self.hp / self.maxHp
		self.maxHp = newMax
		-- Preserve the HP percentage; rescaling alone never defeats the monster.
		self.hp = math.max(1, math.floor(frac * newMax + 0.5))
		emit(self, { type = "rescaled", maxHp = newMax, hp = self.hp, active = active })
	end
end

-- Advances the encounter to `now`. Order inside a tick: due hits and threat
-- hits (time order), then roster changes, then idle checks.
function Encounter.tick(self: Encounter, now: number)
	local q = self.queue
	-- Process everything due, strictly in time order. A queued item and a
	-- threat landing at the same instant: the queued item (e.g. a Guard hit)
	-- goes first, so defence earned right at the deadline counts.
	while true do
		local qt = if #q > 0 then q[1].t else math.huge
		local tt = if self.phase == "fight" then self.nextThreatAt else math.huge
		if qt > now and tt > now then
			break
		end
		if qt <= tt then
			local item = table.remove(q, 1) :: Pending
			if item.kind == "hit" then
				applyHit(self, item.shot :: ShotRecord, item.hitIndex :: number, item.t)
			elseif item.kind == "threatHit" then
				if self.phase == "fight" then
					hitPlayers(self, item.damage :: number, item.pierce or 0, item.t, item.label or "")
				end
			elseif item.kind == "shotEnd" then
				local shot = item.shot :: ShotRecord
				local ps = self.players[shot.uid]
				if ps and shot.damage > ps.biggestShot then
					ps.biggestShot = shot.damage
				end
				emit(self, { type = "shotEnded", shotId = shot.id, uid = shot.uid, damage = shot.damage })
			elseif item.kind == "strike" then
				local shot = item.shot :: ShotRecord
				if self.phase == "fight" and shot.damage > 0 then
					emit(self, { type = "strike", shotId = shot.id, uid = shot.uid, damage = shot.damage, t = item.t })
					damageEnemy(self, shot.damage, item.t, shot.uid)
				end
			end
		else
			landThreat(self, self.nextThreatAt)
		end
	end
	applyRoster(self)

	-- Idle: warn after 45 s without meaningful input, observer 15 s later.
	if self.phase == "fight" then
		local P = Config.Party
		for _, uid in self.order do
			local ps = self.players[uid]
			if ps.present and ps.active and not ps.defeated and now >= self.startAt then
				local idle = now - math.max(ps.lastActiveAt, self.startAt)
				if idle >= P.IDLE_WARN_SECONDS + P.IDLE_OBSERVER_AFTER_WARN then
					Encounter.setObserver(self, uid, now)
				elseif idle >= P.IDLE_WARN_SECONDS and not ps.idleWarned then
					ps.idleWarned = true
					emit(self, { type = "idleWarn", uid = uid, t = now })
				end
			end
		end
		applyRoster(self)
	end
end

function Encounter.drain(self: Encounter): { OutEvent }
	local out = self.outbox
	self.outbox = {}
	return out
end

function Encounter.threatTelegraph(self: Encounter): { [string]: any }
	local threat, amount = Encounter.nextThreat(self)
	return {
		kind = threat.kind,
		label = threat.label,
		amount = amount,
		hits = threat.hits or 1,
		armor = threat.armor,
		pierce = threat.pierce,
		landsAt = self.nextThreatAt,
		warnAt = self.nextThreatAt - COMBAT.THREAT_WARNING,
	}
end

-- Compact replicated snapshot (sent on change, not per frame).
function Encounter.snapshot(self: Encounter): { [string]: any }
	local players = {}
	for _, uid in self.order do
		local ps = self.players[uid]
		table.insert(players, {
			uid = uid,
			hull = ps.hull,
			maxHull = ps.maxHull,
			shield = ps.shield,
			defeated = ps.defeated,
			present = ps.present,
			active = ps.active,
			cooldowns = table.clone(ps.cooldowns),
			jam = ps.jam,
			rack = table.clone(ps.rack),
			seq = ps.seq,
			charge = if ps.charge then { id = ps.charge.id, from = ps.charge.from, power = ps.charge.power, hits = ps.charge.hits } else nil,
			recipient = ps.recipient,
			idleWarned = ps.idleWarned,
			damage = ps.damage,
			shots = ps.shots,
			biggestShot = ps.biggestShot,
			chargesSent = ps.chargesSent,
			bonusDamage = ps.bonusDamage,
			guarded = ps.guarded,
			mended = ps.mended,
			blocked = ps.blocked,
		})
	end
	return {
		id = self.id,
		enemyId = self.def.id,
		boardId = self.boardId,
		boardRev = self.boardRev,
		phase = self.phase,
		hp = self.hp,
		maxHp = self.maxHp,
		armor = self.armor,
		bossPhase = self.bossPhase,
		startAt = self.startAt,
		threat = Encounter.threatTelegraph(self),
		players = players,
	}
end

return Encounter
