--!strict
-- Authoritative run state machine: nine encounters, drafts between them,
-- joins at drafts only, held seats, free restarts, and the developer test
-- conditions. Pure and time-driven like EncounterCore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared.Config)
local Route = require(Shared.Content.Route)
local Kits = require(Shared.Content.Kits)
local Components = require(Shared.Content.Components)
local Encounter = require(script.Parent.Parent.Encounter.EncounterCore)
local Draft = require(script.Parent.Draft)

local RUN = Config.Run
local COMBAT = Config.Combat

export type Stats = {
	damage: number,
	biggestShot: number,
	chargesSent: number,
	chargesUsed: number,
	bonusDamage: number,
	shots: number,
}

export type Member = {
	uid: number,
	kit: string,
	rack: { string },
	components: { string },
	ballLevels: { [string]: number },
	hull: number,
	maxHull: number,
	status: "active" | "waiting" | "disconnected",
	disconnectedAt: number?,
	admittedAt: number, -- encounter index at which they joined
	rerolls: number,
	rerollLeg: number,
	targetedLeg: number,
	offer: { Draft.Option }?,
	offerRerolls: number,
	picked: boolean,
	lastPick: string?,
	recipient: number?,
	stats: Stats,
}

export type TestCondition = "solo" | "duo_self" | "duo_teammate"

export type Params = {
	id: string,
	seed: string,
	hostUid: number,
	now: number,
	modifiers: { [string]: boolean },
	familyPool: { [string]: boolean },
	privacy: "open" | "friends" | "closed",
	mode: "normal" | "test",
	condition: TestCondition?,
	maxParty: number,
	firstIntro: boolean, -- play the long intro (first run this session)
	startIndex: number?, -- resume from a confirmed checkpoint (solo continuation)
}

export type Preset = {
	rack: { string },
	components: { string },
	ballLevels: { [string]: number },
	hull: number,
	maxHull: number,
}

export type Founder = { uid: number, kit: string, preset: Preset? }

local Run = {}
Run.__index = Run

Run.INTRO_FIRST = 4.0
Run.INTRO = 2.4
Run.BOSS_INTRO = 3.2
Run.LEG_BEAT = 2.6
Run.RESULT_BEAT = 1.8
Run.DRAFT_FALLBACK_REPAIR = 8

-- Test encounter: identical board, HP, threat, upgrade, and timing in every
-- condition (plan §12). Duo conditions use duo HP; solo uses solo HP.
Run.TEST_NODE = { enemy = "brute", board = "lanes", boss = false }
Run.TEST_SOLO_HP = 400
Run.TEST_UPGRADE = "whetstone"

export type Run = typeof(setmetatable(
	{} :: {
		id: string,
		seed: string,
		hostUid: number,
		mode: "normal" | "test",
		condition: TestCondition?,
		modifiers: { [string]: boolean },
		familyPool: { [string]: boolean },
		privacy: "open" | "friends" | "closed",
		maxParty: number,
		index: number,
		state: "fight" | "reward" | "draft" | "lost" | "finished" | "abandoned",
		stateAt: number,
		stateEndsAt: number,
		encounter: Encounter.Encounter?,
		members: { [number]: Member },
		order: { number },
		outbox: { { [string]: any } },
		restartSnapshot: { [number]: { [string]: any } },
		startedAt: number,
		firstIntro: boolean,
		introLength: number,
		restarts: number,
		lastOutcome: { [string]: any }?,
	},
	Run
))

local function emit(self: Run, ev: { [string]: any })
	table.insert(self.outbox, ev)
end

local function newStats(): Stats
	return { damage = 0, biggestShot = 0, chargesSent = 0, chargesUsed = 0, bonusDamage = 0, shots = 0 }
end

function Run.newMember(uid: number, kitId: string, completed: number): Member
	local kit = Kits.ById[kitId] or Kits.ById.ricochet
	local hull = COMBAT.START_HULL
	local comps = Draft.catchUp(kit.id, completed)
	local maxHull = hull
	for _, cid in comps do
		local c = Components.ById[cid]
		if c and c.maxHull then
			maxHull += c.maxHull
		end
	end
	return {
		uid = uid,
		kit = kit.id,
		rack = table.clone(kit.rack),
		components = comps,
		ballLevels = {},
		hull = maxHull,
		maxHull = maxHull,
		status = "active",
		disconnectedAt = nil,
		admittedAt = completed + 1,
		rerolls = RUN.REROLLS_PER_LEG,
		rerollLeg = 1,
		targetedLeg = 0,
		offer = nil,
		offerRerolls = 0,
		picked = false,
		lastPick = nil,
		recipient = nil,
		stats = newStats(),
	}
end

function Run.new(p: Params, founders: { Founder }): Run
	local self = setmetatable({}, Run) :: any
	self.id = p.id
	self.seed = p.seed
	self.hostUid = p.hostUid
	self.mode = p.mode
	self.condition = p.condition
	self.modifiers = p.modifiers
	self.familyPool = p.familyPool
	self.privacy = p.privacy
	self.maxParty = p.maxParty
	self.index = p.startIndex or 1
	self.state = "fight"
	self.stateAt = p.now
	self.stateEndsAt = math.huge
	self.encounter = nil
	self.members = {}
	self.order = {}
	self.outbox = {}
	self.restartSnapshot = {}
	self.startedAt = p.now
	self.firstIntro = p.firstIntro
	self.introLength = 0
	self.restarts = 0
	self.lastOutcome = nil
	for _, f in founders do
		local m = Run.newMember(f.uid, f.kit, 0)
		if f.preset then
			local pr = f.preset :: Preset
			m.rack = table.clone(pr.rack)
			m.components = table.clone(pr.components)
			m.ballLevels = table.clone(pr.ballLevels)
			m.hull = pr.hull
			m.maxHull = pr.maxHull
		end
		if p.mode == "test" then
			table.insert(m.components, Run.TEST_UPGRADE)
		end
		self.members[f.uid] = m
		table.insert(self.order, f.uid)
	end
	Run._startEncounter(self, p.now, false)
	return self
end

function Run.node(self: Run): Route.Node
	if self.mode == "test" then
		return Run.TEST_NODE
	end
	local _, _, node = Route.at(self.index)
	return node
end

function Run.legOf(self: Run, index: number): number
	if self.mode == "test" then
		return 1
	end
	local leg = Route.at(index)
	return leg
end

function Run.activeMembers(self: Run): { Member }
	local list = {}
	for _, uid in self.order do
		local m = self.members[uid]
		if m and m.status == "active" then
			table.insert(list, m)
		end
	end
	return list
end

function Run.partySize(self: Run): number
	local n = 0
	for _, uid in self.order do
		local m = self.members[uid]
		if m then
			n += 1
		end
	end
	return n
end

function Run._startEncounter(self: Run, now: number, legBeat: boolean)
	local node = Run.node(self)
	local intro = if self.firstIntro then Run.INTRO_FIRST elseif node.boss then Run.BOSS_INTRO else Run.INTRO
	if legBeat then
		intro += Run.LEG_BEAT
	end
	self.firstIntro = false
	self.introLength = intro
	local seeds = {}
	self.restartSnapshot = {}
	for _, m in Run.activeMembers(self) do
		table.insert(seeds, {
			uid = m.uid,
			hull = m.hull,
			maxHull = m.maxHull,
			rack = m.rack,
			components = m.components,
			ballLevels = m.ballLevels,
		})
		self.restartSnapshot[m.uid] = { hull = m.hull, maxHull = m.maxHull }
	end
	local hpOverride: number? = nil
	local relayMode: "auto" | "self" = "auto"
	if self.mode == "test" then
		hpOverride = Run.TEST_SOLO_HP
		if self.condition == "duo_self" then
			relayMode = "self"
		end
	end
	local enc = Encounter.new({
		id = `{self.id}/{self.index}.{self.restarts}`,
		enemyId = node.enemy,
		boardId = node.board,
		now = now,
		startAt = now + intro,
		players = seeds,
		modifiers = self.modifiers,
		relayMode = relayMode,
		hpOverride = hpOverride,
	})
	for _, m in Run.activeMembers(self) do
		if m.recipient then
			Encounter.setRecipient(enc, m.uid, m.recipient)
		end
	end
	self.encounter = enc
	self.state = "fight"
	self.stateAt = now
	self.stateEndsAt = math.huge
	emit(self, {
		type = "encounterStart",
		index = self.index,
		enemy = node.enemy,
		board = node.board,
		boss = node.boss,
		intro = intro,
		legBeat = legBeat,
		startAt = now + intro,
	})
end

local function collectStats(self: Run)
	local enc = self.encounter
	if enc == nil then
		return
	end
	for uid, ps in enc.players do
		local m = self.members[uid]
		if m then
			m.stats.damage += ps.damage
			m.stats.biggestShot = math.max(m.stats.biggestShot, ps.biggestShot)
			m.stats.chargesSent += ps.chargesSent
			m.stats.chargesUsed += ps.chargesUsed
			m.stats.bonusDamage += ps.bonusDamage
			m.stats.shots += ps.shots
		end
	end
end

local function finishEncounter(self: Run, now: number, won: boolean)
	local enc = self.encounter :: Encounter.Encounter
	local node = Run.node(self)
	collectStats(self)
	-- Carry hull forward; defeated players return at half hull.
	for uid, ps in enc.players do
		local m = self.members[uid]
		if m and m.status == "active" then
			m.maxHull = ps.maxHull
			if ps.defeated then
				m.hull = math.max(1, math.floor(ps.maxHull * COMBAT.DEFEATED_RETURN_HULL_FRACTION))
			else
				m.hull = ps.hull
			end
		end
	end
	local perPlayer = {}
	for uid, ps in enc.players do
		perPlayer[uid] = {
			damage = ps.damage,
			biggestShot = ps.biggestShot,
			chargesSent = ps.chargesSent,
			chargesUsed = ps.chargesUsed,
			bonusDamage = ps.bonusDamage,
			shots = ps.shots,
		}
	end
	local duration = (enc.endAt or now) - enc.startAt
	self.lastOutcome = {
		index = self.index,
		won = won,
		boss = node.boss,
		duration = duration,
		perPlayer = perPlayer,
		condition = self.condition,
		longestFlight = enc.longestFlight,
	}
	emit(self, {
		type = if won then "encounterWon" else "encounterLost",
		index = self.index,
		boss = node.boss,
		duration = duration,
		perPlayer = perPlayer,
		condition = self.condition,
	})
	if not won then
		self.state = "lost"
		self.stateAt = now
		self.stateEndsAt = math.huge
		emit(self, { type = "rematchOffered", kind = "restart" })
		return
	end
	if self.mode == "test" then
		self.state = "finished"
		self.stateAt = now
		self.stateEndsAt = math.huge
		emit(self, { type = "rematchOffered", kind = "test" })
		return
	end
	if node.boss then
		local leg = Run.legOf(self, self.index)
		emit(self, { type = "bossDefeated", leg = leg })
	end
	if self.index >= Route.count() then
		self.state = "finished"
		self.stateAt = now
		self.stateEndsAt = math.huge
		emit(self, { type = "runFinished", duration = now - self.startedAt })
		emit(self, { type = "rematchOffered", kind = "run" })
		return
	end
	self.state = "reward"
	self.stateAt = now
	self.stateEndsAt = now + Run.RESULT_BEAT
end

local function openDraft(self: Run, now: number)
	self.state = "draft"
	self.stateAt = now
	self.stateEndsAt = now + RUN.DRAFT_SECONDS
	local nextLeg = Run.legOf(self, self.index + 1)
	for _, m in Run.activeMembers(self) do
		if m.rerollLeg ~= nextLeg then
			m.rerollLeg = nextLeg
			m.rerolls = RUN.REROLLS_PER_LEG
		end
		m.picked = false
		m.offerRerolls = 0
		local targeted = m.targetedLeg ~= nextLeg
		m.offer = Draft.generate(m, {
			seed = `{self.seed}|{m.uid}|{self.index}|0`,
			targeted = targeted,
			familyPool = self.familyPool,
		})
		if targeted then
			m.targetedLeg = nextLeg
		end
	end
	-- Waiting newcomers are admitted now (drafts are the only boundary).
	local completed = self.index
	for _, uid in self.order do
		local m = self.members[uid]
		if m and m.status == "waiting" then
			local fresh = Run.newMember(uid, m.kit, completed)
			-- A returning seat keeps its build; a newcomer gets the fixed kit.
			if m.admittedAt > 0 and #m.components > 0 and m.disconnectedAt ~= nil then
				fresh.components = m.components
				fresh.rack = m.rack
				fresh.ballLevels = m.ballLevels
				fresh.maxHull = m.maxHull
				fresh.hull = math.max(1, m.hull)
				fresh.stats = m.stats
			end
			fresh.picked = true
			self.members[uid] = fresh
			emit(self, { type = "admitted", uid = uid, catchUp = fresh.components, completed = completed })
		end
	end
	emit(self, { type = "draftOpen", deadline = self.stateEndsAt })
end

local function applyOption(m: Member, opt: Draft.Option, slot: number?)
	if opt.kind == "component" then
		table.insert(m.components, opt.id)
		local c = Components.ById[opt.id]
		if c.maxHull then
			m.maxHull += c.maxHull
			m.hull += c.maxHull
		end
	elseif opt.kind == "ball" then
		local s = slot or #m.rack
		if s < 2 or s > #m.rack then
			s = #m.rack
		end
		m.rack[s] = opt.id
	elseif opt.kind == "upgrade" then
		m.ballLevels[opt.id] = (m.ballLevels[opt.id] or 0) + 1
	end
	m.lastPick = opt.kind .. ":" .. opt.id
end

local function closeDraft(self: Run, now: number)
	local node = Run.node(self)
	for _, m in Run.activeMembers(self) do
		if not m.picked then
			-- Previewed free fallback when the 20 s deadline passes.
			m.hull = math.min(m.maxHull, m.hull + Run.DRAFT_FALLBACK_REPAIR)
			m.picked = true
			m.lastPick = "fallback"
			emit(self, { type = "draftFallback", uid = m.uid })
		end
		if node.boss then
			m.hull = math.min(m.maxHull, m.hull + math.floor(m.maxHull * COMBAT.BOSS_REPAIR_FRACTION + 0.5))
		end
		m.offer = nil
	end
	local prevLeg = Run.legOf(self, self.index)
	self.index += 1
	local newLeg = Run.legOf(self, self.index)
	if #Run.activeMembers(self) == 0 then
		self.state = "abandoned"
		emit(self, { type = "abandoned" })
		return
	end
	Run._startEncounter(self, now, newLeg ~= prevLeg)
end

export type Result = { ok: boolean, reason: string? }

function Run.pick(self: Run, uid: number, choice: number, slot: number?): Result
	local m = self.members[uid]
	if self.state ~= "draft" or m == nil or m.status ~= "active" then
		return { ok = false, reason = "phase" }
	end
	if m.picked or m.offer == nil then
		return { ok = false, reason = "already_picked" }
	end
	local offer = m.offer :: { Draft.Option }
	if type(choice) ~= "number" or choice % 1 ~= 0 or choice < 1 or choice > #offer then
		return { ok = false, reason = "choice" }
	end
	local opt = offer[choice]
	if opt.kind == "ball" then
		if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 2 or slot > #m.rack then
			return { ok = false, reason = "slot" }
		end
	end
	applyOption(m, opt, slot)
	m.picked = true
	emit(self, { type = "draftPicked", uid = uid, option = opt, slot = slot })
	return { ok = true }
end

function Run.reroll(self: Run, uid: number): Result
	local m = self.members[uid]
	if self.state ~= "draft" or m == nil or m.status ~= "active" or m.picked then
		return { ok = false, reason = "phase" }
	end
	if m.rerolls <= 0 then
		return { ok = false, reason = "no_rerolls" }
	end
	m.rerolls -= 1
	m.offerRerolls += 1
	m.offer = Draft.generate(m, {
		seed = `{self.seed}|{m.uid}|{self.index}|{m.offerRerolls}`,
		targeted = false,
		familyPool = self.familyPool,
	})
	emit(self, { type = "draftRerolled", uid = uid })
	return { ok = true }
end

function Run.restart(self: Run, uid: number, now: number): Result
	local m = self.members[uid]
	if self.state ~= "lost" or m == nil or m.status ~= "active" then
		return { ok = false, reason = "phase" }
	end
	-- Free immediate restart: everyone returns to their state at fight start.
	for muid, snap in self.restartSnapshot do
		local mm = self.members[muid]
		if mm then
			mm.hull = snap.hull
			mm.maxHull = snap.maxHull
		end
	end
	self.restarts += 1
	emit(self, { type = "rematchStarted", uid = uid, kind = "restart" })
	Run._startEncounter(self, now, false)
	return { ok = true }
end

-- Newcomer asks to join. Admission happens only at a draft.
function Run.requestJoin(self: Run, uid: number, kitId: string, now: number): Result
	if self.members[uid] then
		local m = self.members[uid]
		if m.status == "disconnected" then
			return Run.rejoin(self, uid, now)
		end
		return { ok = false, reason = "already_member" }
	end
	if self.mode == "test" then
		return { ok = false, reason = "test_run" }
	end
	if self.state == "finished" or self.state == "abandoned" then
		return { ok = false, reason = "closed" }
	end
	if Run.partySize(self) >= self.maxParty then
		return { ok = false, reason = "full" }
	end
	local m = Run.newMember(uid, kitId, 0)
	m.status = "waiting"
	m.admittedAt = 0
	m.components = {}
	self.members[uid] = m
	table.insert(self.order, uid)
	emit(self, { type = "waiting", uid = uid })
	if self.state == "draft" then
		local fresh = Run.newMember(uid, kitId, self.index)
		fresh.picked = true
		self.members[uid] = fresh
		emit(self, { type = "admitted", uid = uid, catchUp = fresh.components, completed = self.index })
	end
	return { ok = true }
end

function Run.rejoin(self: Run, uid: number, now: number): Result
	local m = self.members[uid]
	if m == nil or m.status ~= "disconnected" then
		return { ok = false, reason = "no_seat" }
	end
	if now - (m.disconnectedAt or now) > Config.Party.SEAT_HOLD_SECONDS then
		return { ok = false, reason = "seat_expired" }
	end
	m.status = "waiting"
	emit(self, { type = "waiting", uid = uid, returning = true })
	return { ok = true }
end

function Run.leave(self: Run, uid: number, now: number, hold: boolean)
	local m = self.members[uid]
	if m == nil then
		return
	end
	if self.encounter then
		Encounter.removePlayer(self.encounter :: Encounter.Encounter, uid, now)
	end
	if hold and m.status == "active" then
		m.status = "disconnected"
		m.disconnectedAt = now
		emit(self, { type = "seatHeld", uid = uid, untilT = now + Config.Party.SEAT_HOLD_SECONDS })
	else
		self.members[uid] = nil
		local idx = table.find(self.order, uid)
		if idx then
			table.remove(self.order, idx)
		end
		emit(self, { type = "memberLeft", uid = uid })
	end
	if self.state == "draft" then
		local allPicked = true
		for _, am in Run.activeMembers(self) do
			if not am.picked then
				allPicked = false
			end
		end
		if allPicked and #Run.activeMembers(self) > 0 then
			self.stateEndsAt = now
		end
	end
end

function Run.setRecipient(self: Run, uid: number, target: number): Result
	local m = self.members[uid]
	if m == nil or self.members[target] == nil or target == uid then
		return { ok = false, reason = "target" }
	end
	m.recipient = target
	if self.encounter then
		Encounter.setRecipient(self.encounter :: Encounter.Encounter, uid, target)
	end
	return { ok = true }
end

function Run.tick(self: Run, now: number)
	-- Expire held seats.
	for _, uid in table.clone(self.order) do
		local m = self.members[uid]
		if m and m.status == "disconnected" and now - (m.disconnectedAt or now) > Config.Party.SEAT_HOLD_SECONDS then
			self.members[uid] = nil
			table.remove(self.order, table.find(self.order, uid) :: number)
			emit(self, { type = "seatExpired", uid = uid })
		end
	end
	local anyone = false
	for _, uid in self.order do
		local m = self.members[uid]
		if m and (m.status == "active" or m.status == "disconnected" or m.status == "waiting") then
			anyone = true
		end
	end
	if not anyone then
		if self.state ~= "abandoned" then
			self.state = "abandoned"
			emit(self, { type = "abandoned" })
		end
		return
	end
	local state: string = self.state

	if state == "fight" then
		local enc = self.encounter :: Encounter.Encounter
		Encounter.tick(enc, now)
		for _, ev in Encounter.drain(enc) do
			ev.encounter = true
			emit(self, ev)
		end
		if enc.phase == "won" then
			finishEncounter(self, now, true)
		elseif enc.phase == "lost" then
			finishEncounter(self, now, false)
		end
	elseif state == "reward" then
		-- Let accepted shots finish their visuals; no further consequences.
		if self.encounter then
			Encounter.tick(self.encounter :: Encounter.Encounter, now)
			Encounter.drain(self.encounter :: Encounter.Encounter)
		end
		if now >= self.stateEndsAt then
			openDraft(self, now)
		end
	elseif state == "draft" then
		local allPicked = true
		for _, m in Run.activeMembers(self) do
			if not m.picked then
				allPicked = false
			end
		end
		if allPicked or now >= self.stateEndsAt then
			closeDraft(self, now)
		end
	end
end

function Run.drain(self: Run): { { [string]: any } }
	local out = self.outbox
	self.outbox = {}
	return out
end

-- Honest wait estimate for a newcomer: time until the current fight is
-- likely to end, from the monster's remaining HP and the party's observed
-- damage rate, as a range. Nil when no estimate is possible yet.
function Run.waitEstimate(self: Run, now: number): (number?, number?)
	if self.state == "draft" then
		return 0, 0
	end
	if self.state == "reward" then
		return 0, math.ceil(self.stateEndsAt - now)
	end
	local enc = self.encounter
	if self.state ~= "fight" or enc == nil then
		return nil, nil
	end
	local elapsed = now - enc.startAt
	local dealt = enc.maxHp - enc.hp
	if elapsed < 8 or dealt <= 0 then
		return nil, nil
	end
	local rate = dealt / elapsed
	local remaining = (enc.hp + enc.armor) / rate
	return math.floor(remaining * 0.7), math.ceil(remaining * 1.4) + 4
end

-- Replicated summary for each client (sent on change).
function Run.snapshot(self: Run, now: number): { [string]: any }
	local members = {}
	for _, uid in self.order do
		local m = self.members[uid]
		if m then
			table.insert(members, {
				uid = uid,
				kit = m.kit,
				rack = table.clone(m.rack),
				components = table.clone(m.components),
				ballLevels = table.clone(m.ballLevels),
				hull = m.hull,
				maxHull = m.maxHull,
				status = m.status,
				picked = m.picked,
				rerolls = m.rerolls,
				recipient = m.recipient,
				stats = table.clone(m.stats),
			})
		end
	end
	local lo, hi = Run.waitEstimate(self, now)
	return {
		id = self.id,
		hostUid = self.hostUid,
		mode = self.mode,
		condition = self.condition,
		modifiers = self.modifiers,
		privacy = self.privacy,
		index = self.index,
		total = if self.mode == "test" then 1 else Route.count(),
		leg = Run.legOf(self, self.index),
		state = self.state,
		stateEndsAt = self.stateEndsAt,
		introLength = self.introLength,
		members = members,
		maxParty = self.maxParty,
		waitLow = lo,
		waitHigh = hi,
		lastOutcome = self.lastOutcome,
		startedAt = self.startedAt,
	}
end

return Run
