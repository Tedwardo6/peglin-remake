--!strict
-- Authoritative run state machine for a campaign: acts made of branching
-- maps (Sim/MapGen), a party vote at every fork, fights/elites/bosses,
-- treasure and campfire nodes, drafts after victories, joins at any
-- non-fight boundary, held seats, free restarts, and the developer test
-- conditions. Pure and time-driven like EncounterCore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Config = require(Shared.Config)
local Campaigns = require(Shared.Content.Campaigns)
local Kits = require(Shared.Content.Kits)
local Components = require(Shared.Content.Components)
local MapGen = require(Shared.Sim.MapGen)
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
	guarded: number,
	mended: number,
	blocked: number,
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
	admittedAt: number, -- node index at which they joined
	rerolls: number,
	rerollLeg: number,
	targetedLeg: number,
	offer: { Draft.Option }?,
	offerRerolls: number,
	picked: boolean,
	lastPick: string?,
	recipient: number?,
	vote: string?,
	restChoice: string?, -- "heal" | "train:<slot>"
	stats: Stats,
}

export type TestCondition = "solo" | "duo_self" | "duo_teammate"

export type Resume = {
	act: number,
	atNode: string?, -- last completed node in that act (nil = act start)
	index: number, -- nodes completed so far
}

export type Params = {
	id: string,
	seed: string,
	hostUid: number,
	now: number,
	campaign: string?,
	modifiers: { [string]: boolean },
	familyPool: { [string]: boolean },
	privacy: "open" | "friends" | "closed",
	mode: "normal" | "test",
	condition: TestCondition?,
	maxParty: number,
	firstIntro: boolean, -- play the long intro (first fight this session)
	resume: Resume?, -- personal continuation from a confirmed checkpoint
}

export type Preset = {
	rack: { string },
	components: { string },
	ballLevels: { [string]: number },
	hull: number,
	maxHull: number,
}

export type Founder = { uid: number, kit: string, preset: Preset? }

export type DraftKind = "fight" | "elite" | "boss" | "treasure"

local Run = {}
Run.__index = Run

Run.INTRO_FIRST = 4.0
Run.INTRO = 2.4
Run.BOSS_INTRO = 3.2
Run.RESULT_BEAT = 1.8
Run.DRAFT_FALLBACK_REPAIR = 8
Run.MAP_SINGLE_SECONDS = 4 -- a forced step still shows the map briefly

-- Test encounter: identical board, HP, threat, upgrade, and timing in every
-- condition (plan §12). Duo conditions use duo HP; solo uses solo HP.
Run.TEST_NODE = { id = "test", kind = "fight", enemy = "brute", board = "lanes" }
Run.TEST_SOLO_HP = 400
Run.TEST_UPGRADE = "whetstone"

export type CurrentNode = { id: string, kind: MapGen.NodeKind, enemy: string?, board: string? }

export type Run = typeof(setmetatable(
	{} :: {
		id: string,
		seed: string,
		hostUid: number,
		campaign: string,
		mode: "normal" | "test",
		condition: TestCondition?,
		modifiers: { [string]: boolean },
		familyPool: { [string]: boolean },
		privacy: "open" | "friends" | "closed",
		maxParty: number,
		index: number, -- nodes entered so far (1 = first node)
		act: number,
		map: MapGen.ActMap?,
		atNode: string?, -- last completed node in the current act
		current: CurrentNode?,
		path: { string }, -- node ids taken this act
		choices: { string },
		draftKind: DraftKind,
		state: "map" | "fight" | "reward" | "draft" | "rest" | "lost" | "finished" | "abandoned",
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
	return { damage = 0, biggestShot = 0, chargesSent = 0, chargesUsed = 0, bonusDamage = 0, shots = 0, guarded = 0, mended = 0, blocked = 0 }
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
		vote = nil,
		restChoice = nil,
		stats = newStats(),
	}
end

function Run.campaignDef(self: Run): Campaigns.Campaign
	return Campaigns.ById[self.campaign]
end

function Run.actCount(self: Run): number
	return #Run.campaignDef(self).acts
end

-- Kept for callers that think in legs (analytics milestones).
function Run.legOf(self: Run, _index: number?): number
	return self.act
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
		if self.members[uid] then
			n += 1
		end
	end
	return n
end

local openMap: (self: Run, now: number) -> ()

function Run.new(p: Params, founders: { Founder }): Run
	local self = setmetatable({}, Run) :: any
	self.id = p.id
	self.seed = p.seed
	self.hostUid = p.hostUid
	self.campaign = if p.campaign and Campaigns.ById[p.campaign] then p.campaign else Campaigns.DEFAULT
	self.mode = p.mode
	self.condition = p.condition
	self.modifiers = p.modifiers
	self.familyPool = p.familyPool
	self.privacy = p.privacy
	self.maxParty = p.maxParty
	self.index = 0
	self.act = 1
	self.map = nil
	self.atNode = nil
	self.current = nil
	self.path = {}
	self.choices = {}
	self.draftKind = "fight"
	self.state = "map"
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
	if p.mode == "test" then
		self.index = 1
		self.current = table.clone(Run.TEST_NODE) :: any
		Run._startEncounter(self, p.now)
		return self
	end
	if p.resume then
		local r = p.resume :: Resume
		self.act = math.clamp(r.act, 1, Run.actCount(self))
		self.index = r.index
		self.atNode = r.atNode
	end
	self.map = MapGen.generate(self.campaign, self.act, self.seed)
	openMap(self, p.now)
	return self
end

local function admitWaiting(self: Run)
	-- Waiting newcomers are admitted at every non-fight boundary.
	local completed = self.index
	for _, uid in self.order do
		local m = self.members[uid]
		if m and m.status == "waiting" then
			local fresh = Run.newMember(uid, m.kit, completed)
			-- A returning seat keeps its build; a newcomer gets the catch-up kit.
			if m.admittedAt > 0 and #m.components > 0 and m.disconnectedAt ~= nil then
				fresh.components = m.components
				fresh.rack = m.rack
				fresh.ballLevels = m.ballLevels
				fresh.maxHull = m.maxHull
				fresh.hull = math.max(1, m.hull)
				fresh.stats = m.stats
			end
			fresh.picked = true
			fresh.restChoice = "heal"
			self.members[uid] = fresh
			emit(self, { type = "admitted", uid = uid, catchUp = fresh.components, completed = completed })
		end
	end
end

openMap = function(self: Run, now: number)
	local map = self.map :: MapGen.ActMap
	admitWaiting(self)
	self.state = "map"
	self.stateAt = now
	local choices = MapGen.choices(map, self.atNode)
	self.choices = {}
	for _, n in choices do
		table.insert(self.choices, n.id)
	end
	for _, m in Run.activeMembers(self) do
		m.vote = nil
	end
	local seconds = if #self.choices <= 1 then Run.MAP_SINGLE_SECONDS else RUN.MAP_SECONDS
	self.stateEndsAt = now + seconds
	emit(self, { type = "mapOpen", act = self.act, choices = table.clone(self.choices), deadline = self.stateEndsAt })
end

-- Party vote: most votes wins; a tie goes to the host's pick when the host
-- voted for one of the tied nodes, otherwise to the leftmost tied node.
function Run.tallyVotes(self: Run): string
	local counts: { [string]: number } = {}
	for _, m in Run.activeMembers(self) do
		if m.vote and table.find(self.choices, m.vote) then
			counts[m.vote] = (counts[m.vote] or 0) + 1
		end
	end
	local best = 0
	local tied: { string } = {}
	for _, id in self.choices do
		local n = counts[id] or 0
		if n > best then
			best = n
			tied = { id }
		elseif n == best then
			table.insert(tied, id)
		end
	end
	if #tied == 1 then
		return tied[1]
	end
	local host = self.members[self.hostUid]
	if host and host.vote and table.find(tied, host.vote) then
		return host.vote :: string
	end
	return tied[1]
end

local function openRest(self: Run, now: number)
	self.state = "rest"
	self.stateAt = now
	self.stateEndsAt = now + RUN.REST_SECONDS
	for _, m in Run.activeMembers(self) do
		m.restChoice = nil
	end
	emit(self, { type = "restOpen", deadline = self.stateEndsAt })
end

local function openDraft(self: Run, now: number, kind: DraftKind)
	admitWaiting(self)
	self.draftKind = kind
	self.state = "draft"
	self.stateAt = now
	self.stateEndsAt = now + RUN.DRAFT_SECONDS
	-- After a boss the offers belong to the next act.
	local leg = if kind == "boss" then self.act + 1 else self.act
	for _, m in Run.activeMembers(self) do
		if m.picked and m.offer == nil and m.admittedAt > self.index then
			continue -- admitted at this boundary: they took the catch-up kit
		end
		if m.rerollLeg ~= leg then
			m.rerollLeg = leg
			m.rerolls = RUN.REROLLS_PER_LEG
		end
		m.picked = false
		m.offerRerolls = 0
		local targeted = m.targetedLeg ~= leg and kind ~= "treasure"
		m.offer = Draft.generate(m, {
			seed = `{self.seed}|{m.uid}|{self.index}|0`,
			targeted = targeted,
			familyPool = self.familyPool,
			treasure = kind == "treasure",
		})
		if targeted then
			m.targetedLeg = leg
		end
	end
	emit(self, { type = "draftOpen", deadline = self.stateEndsAt, kind = kind })
end

function Run._startEncounter(self: Run, now: number)
	local node = self.current :: CurrentNode
	local isBoss = node.kind == "boss"
	local intro = if self.firstIntro then Run.INTRO_FIRST elseif isBoss then Run.BOSS_INTRO else Run.INTRO
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
	local elite = node.kind == "elite"
	local enc = Encounter.new({
		id = `{self.id}/{self.index}.{self.restarts}`,
		enemyId = node.enemy :: string,
		boardId = node.board :: string,
		now = now,
		startAt = now + intro,
		players = seeds,
		modifiers = self.modifiers,
		relayMode = relayMode,
		hpOverride = hpOverride,
		hpMult = if elite then COMBAT.ELITE_HP_MULT else nil,
		damageMult = if elite then COMBAT.ELITE_DAMAGE_MULT else nil,
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
		act = self.act,
		nodeId = node.id,
		kind = node.kind,
		enemy = node.enemy,
		board = node.board,
		boss = isBoss,
		elite = elite,
		intro = intro,
		startAt = now + intro,
	})
end

local function enterNode(self: Run, now: number, nodeId: string)
	local map = self.map :: MapGen.ActMap
	local node = map.byId[nodeId]
	self.current = { id = node.id, kind = node.kind, enemy = node.enemy, board = node.board }
	self.index += 1
	table.insert(self.path, node.id)
	if node.kind == "fight" or node.kind == "elite" or node.kind == "boss" then
		Run._startEncounter(self, now)
	elseif node.kind == "treasure" then
		openDraft(self, now, "treasure")
	elseif node.kind == "rest" then
		openRest(self, now)
	end
end

local function closeMap(self: Run, now: number)
	local winner = Run.tallyVotes(self)
	local votes = {}
	for _, m in Run.activeMembers(self) do
		votes[tostring(m.uid)] = m.vote
	end
	local node = (self.map :: MapGen.ActMap).byId[winner]
	emit(self, { type = "pathChosen", nodeId = winner, kind = node.kind, votes = votes, act = self.act })
	enterNode(self, now, winner)
end

-- Leaves the current node and moves on: next fork, next act, or the end.
local function advance(self: Run, now: number)
	local cur = self.current :: CurrentNode
	if #Run.activeMembers(self) == 0 then
		self.state = "abandoned"
		emit(self, { type = "abandoned" })
		return
	end
	if cur.kind == "boss" then
		self.act += 1
		self.atNode = nil
		self.path = {}
		self.map = MapGen.generate(self.campaign, self.act, self.seed)
		emit(self, { type = "actStart", act = self.act })
	else
		self.atNode = cur.id
	end
	openMap(self, now)
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
			m.stats.guarded += ps.guarded
			m.stats.mended += ps.mended
			m.stats.blocked += ps.blocked
		end
	end
end

local function finishEncounter(self: Run, now: number, won: boolean)
	local enc = self.encounter :: Encounter.Encounter
	local node = self.current :: CurrentNode
	local isBoss = node.kind == "boss"
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
			guarded = ps.guarded,
			mended = ps.mended,
			blocked = ps.blocked,
		}
	end
	local duration = (enc.endAt or now) - enc.startAt
	self.lastOutcome = {
		index = self.index,
		won = won,
		boss = isBoss,
		elite = node.kind == "elite",
		enemy = node.enemy,
		duration = duration,
		perPlayer = perPlayer,
		condition = self.condition,
		longestFlight = enc.longestFlight,
	}
	emit(self, {
		type = if won then "encounterWon" else "encounterLost",
		index = self.index,
		act = self.act,
		nodeId = node.id,
		boss = isBoss,
		elite = node.kind == "elite",
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
	if node.kind == "elite" then
		for _, m in Run.activeMembers(self) do
			m.maxHull += COMBAT.ELITE_SPOILS_MAX_HULL
			m.hull += COMBAT.ELITE_SPOILS_MAX_HULL
		end
		emit(self, { type = "eliteSpoils", maxHull = COMBAT.ELITE_SPOILS_MAX_HULL })
	end
	if isBoss then
		emit(self, { type = "bossDefeated", leg = self.act, act = self.act })
		if self.act >= Run.actCount(self) then
			self.state = "finished"
			self.stateAt = now
			self.stateEndsAt = math.huge
			emit(self, { type = "runFinished", duration = now - self.startedAt })
			emit(self, { type = "rematchOffered", kind = "run" })
			return
		end
	end
	self.state = "reward"
	self.stateAt = now
	self.stateEndsAt = now + Run.RESULT_BEAT
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
	for _, m in Run.activeMembers(self) do
		if not m.picked then
			-- Previewed free fallback when the deadline passes.
			m.hull = math.min(m.maxHull, m.hull + Run.DRAFT_FALLBACK_REPAIR)
			m.picked = true
			m.lastPick = "fallback"
			emit(self, { type = "draftFallback", uid = m.uid })
		end
		if self.draftKind == "boss" then
			m.hull = math.min(m.maxHull, m.hull + math.floor(m.maxHull * COMBAT.BOSS_REPAIR_FRACTION + 0.5))
		end
		m.offer = nil
	end
	advance(self, now)
end

local function closeRest(self: Run, now: number)
	for _, m in Run.activeMembers(self) do
		local choice = m.restChoice or "heal"
		if string.sub(choice, 1, 6) == "train:" then
			local slot = tonumber(string.sub(choice, 7)) or 1
			local id = m.rack[math.clamp(slot, 1, #m.rack)]
			m.ballLevels[id] = (m.ballLevels[id] or 0) + 1
			emit(self, { type = "rested", uid = m.uid, choice = "train", ball = id })
		else
			local amount = math.floor(m.maxHull * COMBAT.REST_HEAL_FRACTION + 0.5)
			local before = m.hull
			m.hull = math.min(m.maxHull, m.hull + amount)
			emit(self, { type = "rested", uid = m.uid, choice = "heal", amount = m.hull - before })
		end
		m.restChoice = nil
	end
	advance(self, now)
end

export type Result = { ok: boolean, reason: string? }

function Run.vote(self: Run, uid: number, nodeId: string): Result
	local m = self.members[uid]
	if self.state ~= "map" or m == nil or m.status ~= "active" then
		return { ok = false, reason = "phase" }
	end
	if type(nodeId) ~= "string" or table.find(self.choices, nodeId) == nil then
		return { ok = false, reason = "choice" }
	end
	m.vote = nodeId
	emit(self, { type = "voted", uid = uid, nodeId = nodeId })
	return { ok = true }
end

function Run.chooseRest(self: Run, uid: number, choice: string, slot: number?): Result
	local m = self.members[uid]
	if self.state ~= "rest" or m == nil or m.status ~= "active" then
		return { ok = false, reason = "phase" }
	end
	if m.restChoice ~= nil then
		return { ok = false, reason = "already_chosen" }
	end
	if choice == "heal" then
		m.restChoice = "heal"
	elseif choice == "train" then
		if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > #m.rack then
			return { ok = false, reason = "slot" }
		end
		m.restChoice = `train:{slot}`
	else
		return { ok = false, reason = "choice" }
	end
	emit(self, { type = "restChosen", uid = uid, choice = choice })
	return { ok = true }
end

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
		treasure = self.draftKind == "treasure",
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
	Run._startEncounter(self, now)
	return { ok = true }
end

-- Newcomer asks to join. Admission happens at the next non-fight boundary.
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
	if self.state == "draft" or self.state == "map" or self.state == "rest" then
		admitWaiting(self)
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
	if self.state == "draft" or self.state == "map" or self.state == "rest" then
		admitWaiting(self)
	end
	return { ok = true }
end

local function everyoneDone(self: Run): boolean
	local any = false
	for _, m in Run.activeMembers(self) do
		any = true
		if self.state == "draft" and not m.picked then
			return false
		elseif self.state == "map" and m.vote == nil then
			return false
		elseif self.state == "rest" and m.restChoice == nil then
			return false
		end
	end
	return any
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
	if (self.state == "draft" or self.state == "map" or self.state == "rest") and everyoneDone(self) then
		self.stateEndsAt = math.min(self.stateEndsAt, now)
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
			local cur = self.current :: CurrentNode
			openDraft(self, now, if cur.kind == "boss" then "boss" elseif cur.kind == "elite" then "elite" else "fight")
		end
	elseif state == "draft" then
		if everyoneDone(self) or now >= self.stateEndsAt then
			closeDraft(self, now)
		end
	elseif state == "map" then
		if #Run.activeMembers(self) == 0 then
			return
		end
		-- A forced single step waits out its short preview.
		local forced = #self.choices <= 1
		if (not forced and everyoneDone(self)) or now >= self.stateEndsAt then
			closeMap(self, now)
		end
	elseif state == "rest" then
		if everyoneDone(self) or now >= self.stateEndsAt then
			closeRest(self, now)
		end
	end
end

function Run.drain(self: Run): { { [string]: any } }
	local out = self.outbox
	self.outbox = {}
	return out
end

-- Honest wait estimate for a newcomer: time until the next boundary where
-- they can be admitted, as a range. Nil when no estimate is possible yet.
function Run.waitEstimate(self: Run, now: number): (number?, number?)
	if self.state == "draft" or self.state == "map" or self.state == "rest" then
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
				vote = m.vote,
				restChoice = if m.restChoice then (if string.sub(m.restChoice, 1, 5) == "train" then "train" else "heal") else nil,
				stats = table.clone(m.stats),
			})
		end
	end
	local lo, hi = Run.waitEstimate(self, now)
	local camp = Run.campaignDef(self)
	local act = camp.acts[self.act]
	return {
		id = self.id,
		hostUid = self.hostUid,
		campaign = self.campaign,
		mode = self.mode,
		condition = self.condition,
		modifiers = self.modifiers,
		privacy = self.privacy,
		index = self.index,
		act = self.act,
		acts = #camp.acts,
		actName = if act then act.name else "",
		map = if self.map and self.mode ~= "test" then MapGen.view(self.map :: MapGen.ActMap) else nil,
		atNode = self.atNode,
		path = table.clone(self.path),
		choices = table.clone(self.choices),
		current = if self.current then table.clone(self.current :: any) else nil,
		draftKind = self.draftKind,
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
