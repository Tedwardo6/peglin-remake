--!strict
-- Binds the pure run/encounter rules to Roblox: remotes, players, profiles,
-- analytics, and the server clock. All consequences are decided by
-- RunCore/EncounterCore; this module only routes validated inputs to them
-- and broadcasts results.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Protocol = require(Shared.Net.Protocol)
local Kits = require(Shared.Content.Kits)
local Modifiers = require(Shared.Content.Modifiers)
local Cosmetics = require(Shared.Content.Cosmetics)
local Aim = require(Shared.Sim.Aim)

local RunCore = require(script.Parent.RunCore)
local Encounter = require(script.Parent.Parent.Encounter.EncounterCore)
local RateLimit = require(script.Parent.Parent.Validation.RateLimit)
local Schema = require(script.Parent.Parent.Persistence.Schema)
local ProfileStore = require(script.Parent.Parent.Persistence.ProfileStore)
local Funnels = require(script.Parent.Parent.Analytics.Funnels)

type Run = RunCore.Run

type PlayerInfo = {
	player: Player,
	uid: number,
	runId: string?,
	device: string,
	ready: boolean,
	firstRunDone: boolean,
	divergences: number,
	shotsPredicted: number,
	lastAimRelay: number,
	pendingKit: string,
	sessionLoaded: boolean,
}

local RunManager = {}

local net: Folder
local requestRemote: RemoteEvent
local pushRemote: RemoteEvent
local cosmeticRemote: UnreliableRemoteEvent
local cosmeticUp: UnreliableRemoteEvent

local runs: { [string]: Run } = {}
local infos: { [number]: PlayerInfo } = {}
local limiter = RateLimit.new(Config.Net.MAX_REQUESTS_PER_SECOND, Config.Net.MAX_REQUESTS_PER_SECOND)
local aimLimiter = RateLimit.new(6, 6)
local store: ProfileStore.Store
local funnels: Funnels.Funnels
local runCounter = 0
local lastSnapshotAt: { [string]: number } = {}
local dirty: { [string]: boolean } = {}
local testLog: { { [string]: any } } = {}
local backendLabel = "none"

local function now(): number
	return workspace:GetServerTimeNow()
end

local function log(msg: string)
	print("[Cabinet] " .. msg)
end

local function push(player: Player, kind: string, payload: any)
	pushRemote:FireClient(player, kind, payload)
end

local function pushRun(run: Run, kind: string, payload: any)
	for _, uid in run.order do
		local p = Players:GetPlayerByUserId(uid)
		if p then
			pushRemote:FireClient(p, kind, payload)
		end
	end
end

local function profileOf(uid: number): Schema.Profile?
	local s = ProfileStore.get(store, uid)
	return if s then s.profile else nil
end

local function sendProfile(info: PlayerInfo)
	local s = ProfileStore.get(store, info.uid)
	if s == nil then
		return
	end
	local p = s.profile
	push(info.player, "profile", {
		settings = p.settings,
		seen = p.seen,
		unlocked = p.unlocked,
		equippedTrail = p.equippedTrail,
		stats = p.stats,
		familyPool = p.familyPool,
		checkpoint = p.checkpoint,
		canSave = s.canSave,
		saveNote = if s.canSave then nil else "Progress won't save this session.",
		backend = backendLabel,
		devAllowed = RunManager.devAllowed(info.player),
	})
end

function RunManager.devAllowed(player: Player): boolean
	if RunService:IsStudio() then
		return true
	end
	return game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId
end

local function lobbyList(forUid: number): { any }
	local list = {}
	local t = now()
	for id, run in runs do
		if run.mode == "normal" and run.state ~= "finished" and run.state ~= "abandoned" and run.members[forUid] == nil then
			local host = Players:GetPlayerByUserId(run.hostUid)
			local lo, hi = RunCore.waitEstimate(run, t)
			table.insert(list, {
				id = id,
				host = run.hostUid,
				hostName = if host then host.DisplayName else "?",
				size = RunCore.partySize(run),
				maxParty = run.maxParty,
				privacy = run.privacy,
				state = run.state,
				index = run.index,
				waitLow = lo,
				waitHigh = hi,
			})
		end
	end
	return list
end

local function broadcastLobby()
	for uid, info in infos do
		if info.runId == nil then
			push(info.player, "lobby", lobbyList(uid))
		end
	end
end

local function sendSnapshots(run: Run, force: boolean)
	local t = now()
	if not force and not dirty[run.id] and t - (lastSnapshotAt[run.id] or 0) < 2 then
		return
	end
	if not force and t - (lastSnapshotAt[run.id] or 0) < Config.Net.STATE_BROADCAST_MIN_INTERVAL then
		return
	end
	dirty[run.id] = false
	lastSnapshotAt[run.id] = t
	local snap = RunCore.snapshot(run, t)
	local enc = if run.encounter and (run.state == "fight" or run.state == "reward" or run.state == "lost") then Encounter.snapshot(run.encounter) else nil
	pushRun(run, "state", { run = snap, enc = enc, serverTime = t })
	-- Personal draft offers.
	if run.state == "draft" then
		for _, m in RunCore.activeMembers(run) do
			local p = Players:GetPlayerByUserId(m.uid)
			if p and m.offer then
				push(p, "draft", { offer = m.offer, picked = m.picked, rerolls = m.rerolls, deadline = run.stateEndsAt, fallback = RunCore.DRAFT_FALLBACK_REPAIR })
			end
		end
	end
end

local function updateProfileFromRunEvent(run: Run, ev: { [string]: any })
	local t = ev.type
	if t == "encounterWon" then
		for uid, stats in ev.perPlayer do
			local p = profileOf(uid)
			if p then
				p.stats.encountersWon += 1
				p.stats.shots += stats.shots
				if stats.biggestShot > p.stats.biggestShot then
					p.stats.biggestShot = stats.biggestShot
				end
				p.stats.chargesSent += stats.chargesSent
				-- Checkpoint: last confirmed completed node (personal continuation).
				local m = run.members[uid]
				if m and run.mode == "normal" then
					local mods = {}
					for id, on in run.modifiers do
						if on then
							table.insert(mods, id)
						end
					end
					p.checkpoint = {
						runSeed = run.seed,
						kit = m.kit,
						completed = ev.index,
						rack = table.clone(m.rack),
						components = table.clone(m.components),
						ballLevels = table.clone(m.ballLevels),
						hull = m.hull,
						maxHull = m.maxHull,
						modifiers = mods,
						at = os.time(),
					}
				end
			end
		end
	elseif t == "bossDefeated" then
		for _, m in RunCore.activeMembers(run) do
			local p = profileOf(m.uid)
			if p then
				p.stats.bossesDefeated += 1
				if ev.leg == 1 then
					Schema.grantOnce(p, run.id .. ":boss1", function(pp)
						pp.milestones.boss1 = true
					end)
				end
			end
		end
	elseif t == "runFinished" then
		for _, m in RunCore.activeMembers(run) do
			local p = profileOf(m.uid)
			if p then
				Schema.grantOnce(p, run.id .. ":finish", function(pp)
					pp.stats.runsFinished += 1
					pp.milestones.run_complete = true
					pp.checkpoint = nil
				end)
			end
		end
	elseif t == "chargeUsed" and ev.from ~= ev.uid then
		local p = profileOf(ev.from)
		if p then
			p.stats.chargesUsedByOthers += 1
		end
	end
	-- Cosmetic unlocks from milestones/stats (earned only).
	for _, uid in run.order do
		local p = profileOf(uid)
		if p then
			for _, cid in Cosmetics.Order do
				local c = Cosmetics.ById[cid]
				if not p.unlocked[cid] then
					local earned = false
					if c.milestone and p.milestones[c.milestone] then
						earned = true
					elseif c.stat and c.threshold and ((p.stats :: any)[c.stat] or 0) >= c.threshold then
						earned = true
					end
					if earned then
						p.unlocked[cid] = true
						local pl = Players:GetPlayerByUserId(uid)
						if pl then
							push(pl, "unlock", { id = cid })
						end
					end
				end
			end
		end
	end
end

local function analyticsFromRunEvent(run: Run, ev: { [string]: any })
	local t = ev.type
	local tn = now()
	if t == "shotStarted" then
		funnels:mark(ev.uid, "first_launch", tn)
		funnels:mark(ev.uid, "independent_repeat", tn)
		local enc = run.encounter
		if enc and Encounter.activeCount(enc) >= 2 and run.condition ~= "duo_self" then
			funnels:mark(ev.uid, "assist_opportunity", tn)
		end
	elseif t == "firstUseful" then
		funnels:mark(ev.uid, "first_useful_hit", tn)
	elseif t == "chargeSent" then
		if ev.from ~= ev.to then
			funnels:mark(ev.from, "assist_sent", tn)
		else
			funnels:mark(ev.from, "self_charge_sent", tn)
		end
	elseif t == "chargeUsed" then
		if ev.from ~= ev.uid then
			funnels:mark(ev.uid, "assist_used", tn)
		else
			funnels:mark(ev.uid, "self_charge_used", tn)
		end
	elseif t == "encounterWon" then
		for uid in ev.perPlayer do
			funnels:mark(uid, "first_reward", tn)
		end
	elseif t == "draftPicked" then
		funnels:mark(ev.uid, "first_upgrade", tn)
	elseif t == "bossDefeated" then
		for _, m in RunCore.activeMembers(run) do
			funnels:mark(m.uid, "boss_" .. tostring(ev.leg), tn)
			funnels:mark(m.uid, "leg_" .. tostring(ev.leg), tn)
		end
	elseif t == "runFinished" then
		for _, m in RunCore.activeMembers(run) do
			funnels:mark(m.uid, "run_complete", tn)
		end
	elseif t == "rematchOffered" then
		for _, m in RunCore.activeMembers(run) do
			funnels:mark(m.uid, "rematch_offered", tn)
		end
	end
end

local function logTestOutcome(run: Run, ev: { [string]: any })
	if run.mode ~= "test" then
		return
	end
	local entry = {
		condition = run.condition,
		won = ev.type == "encounterWon",
		duration = ev.duration,
		players = {},
		at = os.time(),
	}
	local totalBonus = 0
	for uid, st in ev.perPlayer do
		table.insert(entry.players, { uid = uid, bonusDamage = st.bonusDamage, damage = st.damage, shots = st.shots, chargesSent = st.chargesSent, chargesUsed = st.chargesUsed })
		totalBonus += st.bonusDamage
		funnels:event(uid, "test_bonus_damage", st.bonusDamage)
		funnels:event(uid, "test_duration", math.floor(ev.duration * 10 + 0.5) / 10)
	end
	table.insert(testLog, entry)
	print(string.format("[testlog] condition=%s won=%s duration=%.1fs bonusDamage=%d players=%d", tostring(run.condition), tostring(entry.won), ev.duration, totalBonus, #entry.players))
	pushRun(run, "testResult", { entry = entry, history = testLog })
end

local function processRunEvents(run: Run)
	local events = RunCore.drain(run)
	if #events == 0 then
		return
	end
	dirty[run.id] = true
	local forClients = {}
	for _, ev in events do
		analyticsFromRunEvent(run, ev)
		updateProfileFromRunEvent(run, ev)
		if ev.type == "encounterWon" or ev.type == "encounterLost" then
			logTestOutcome(run, ev)
		end
		if ev.type == "shotStarted" then
			-- Shots go out immediately so teammates re-simulate them in sync.
			pushRun(run, "shot", ev)
		else
			table.insert(forClients, ev)
		end
	end
	if #forClients > 0 then
		pushRun(run, "events", forClients)
	end
	-- Send fresh state right after meaningful events.
	sendSnapshots(run, true)
	if run.state == "finished" or run.state == "abandoned" then
		broadcastLobby()
	end
end

local function newRunId(): string
	runCounter += 1
	return string.format("run%d_%s", runCounter, string.sub(HttpService:GenerateGUID(false), 1, 6))
end

local function startRunFor(founders: { RunCore.Founder }, opts: {
	modifiers: { [string]: boolean },
	familyPool: { [string]: boolean },
	privacy: "open" | "friends" | "closed",
	mode: "normal" | "test",
	condition: RunCore.TestCondition?,
	startIndex: number?,
	seed: string?,
}): Run
	local id = newRunId()
	local hostInfo = infos[founders[1].uid]
	local firstIntro = hostInfo ~= nil and not hostInfo.firstRunDone
	local run = RunCore.new({
		id = id,
		seed = opts.seed or HttpService:GenerateGUID(false),
		hostUid = founders[1].uid,
		now = now(),
		modifiers = opts.modifiers,
		familyPool = opts.familyPool,
		privacy = opts.privacy,
		mode = opts.mode,
		condition = opts.condition,
		maxParty = if opts.mode == "test" then Config.Party.MAX_PARTY_TESTING else Config.Party.MAX_PARTY,
		firstIntro = firstIntro,
		startIndex = opts.startIndex,
	}, founders)
	runs[id] = run
	for _, f in founders do
		local info = infos[f.uid]
		if info then
			info.runId = id
			info.firstRunDone = true
		end
		local p = profileOf(f.uid)
		if p then
			p.stats.runsStarted += 1
		end
	end
	log(`run {id} started ({opts.mode}{if opts.condition then " " .. opts.condition else ""}) with {#founders} player(s)`)
	processRunEvents(run)
	sendSnapshots(run, true)
	broadcastLobby()
	return run
end

local function leaveCurrentRun(info: PlayerInfo, hold: boolean)
	local id = info.runId
	if id == nil then
		return
	end
	local run = runs[id]
	info.runId = nil
	if run then
		RunCore.leave(run, info.uid, now(), hold)
		processRunEvents(run)
		dirty[run.id] = true
		sendSnapshots(run, true)
	end
end

local function sanitizeModifiers(list: { string }?): { [string]: boolean }
	local out = {}
	local l: { string } = list or {}
	for _, id in l do
		if Modifiers.ById[id] then
			out[id] = true
		end
	end
	return out
end

local FAMILIES = { "ricochet", "relay", "guard", "wild" }

local function sanitizeFamilies(list: { string }?): { [string]: boolean }
	-- Bounded family pool: at least two families stay enabled.
	local chosen = {}
	local count = 0
	local l: { string } = list or {}
	for _, f in l do
		if table.find(FAMILIES, f) and not chosen[f] then
			chosen[f] = true
			count += 1
		end
	end
	if count < 2 then
		return { ricochet = true, relay = true, guard = true, wild = true }
	end
	local out = {}
	for _, f in FAMILIES do
		out[f] = chosen[f] == true
	end
	return out
end

-- Request handlers --------------------------------------------------------

local handlers: { [string]: (info: PlayerInfo, msg: { [string]: any }) -> () } = {}

handlers.ready = function(info, msg)
	local device = msg.device
	if device ~= "touch" and device ~= "keyboard" and device ~= "gamepad" then
		device = "unknown"
	end
	info.device = device
	funnels:setDevice(info.uid, device)
	if not info.ready then
		info.ready = true
		funnels:mark(info.uid, "ready_to_act", now())
	end
	-- New players start equipped at the board: no lobby walk, no menu.
	local p = profileOf(info.uid)
	local returning = p ~= nil and p.stats.runsStarted > 0
	if info.runId == nil and not returning then
		startRunFor({ { uid = info.uid, kit = "ricochet" } }, {
			modifiers = {},
			familyPool = if p then p.familyPool else {},
			privacy = "friends",
			mode = "normal",
		})
	else
		push(info.player, "lobby", lobbyList(info.uid))
	end
end

handlers.startRun = function(info, msg)
	if info.runId then
		return
	end
	local kit = if Kits.ById[msg.kit] then msg.kit else "ricochet"
	local privacy = msg.privacy
	if privacy ~= "open" and privacy ~= "friends" and privacy ~= "closed" then
		privacy = "friends"
	end
	local p = profileOf(info.uid)
	local families = sanitizeFamilies(msg.families)
	if p then
		p.familyPool = families
	end
	startRunFor({ { uid = info.uid, kit = kit } }, {
		modifiers = sanitizeModifiers(msg.modifiers),
		familyPool = families,
		privacy = privacy,
		mode = "normal",
	})
end

handlers.continueRun = function(info, _msg)
	if info.runId then
		return
	end
	local p = profileOf(info.uid)
	local cp = if p then p.checkpoint else nil
	if p == nil or cp == nil or cp.completed >= 9 then
		push(info.player, "notice", { text = "No run to continue." })
		return
	end
	-- Personal continuation from the last confirmed completed node.
	startRunFor({ {
		uid = info.uid,
		kit = cp.kit,
		preset = { rack = cp.rack, components = cp.components, ballLevels = cp.ballLevels, hull = cp.hull, maxHull = cp.maxHull },
	} }, {
		modifiers = sanitizeModifiers(cp.modifiers),
		familyPool = p.familyPool,
		privacy = "friends",
		mode = "normal",
		startIndex = cp.completed + 1,
		seed = cp.runSeed,
	})
end

handlers.launch = function(info, msg)
	local run = if info.runId then runs[info.runId] else nil
	if run == nil or run.state ~= "fight" or run.encounter == nil then
		push(info.player, "reject", { seq = msg.seq, reason = "phase" })
		return
	end
	local enc = run.encounter :: Encounter.Encounter
	local res = Encounter.launch(enc, info.uid, { seq = msg.seq, slot = msg.slot, aim = msg.aim, boardRev = msg.boardRev }, now())
	if not res.ok then
		push(info.player, "reject", { seq = msg.seq, reason = res.reason })
		dirty[run.id] = true
		sendSnapshots(run, true) -- resync the client's sequence/cooldowns
		return
	end
	local shot = res.shot :: Encounter.ShotRecord
	info.shotsPredicted += 1
	if type(msg.predicted) == "string" and msg.predicted ~= "" and msg.predicted ~= shot.fingerprint then
		info.divergences += 1
		log(`divergence uid={info.uid} shot={shot.id} client={msg.predicted} server={shot.fingerprint}`)
		funnels:event(info.uid, "sim_divergence", info.divergences)
	end
	-- Encounter emitted shotStarted; move it into the run outbox now.
	for _, ev in Encounter.drain(enc) do
		ev.encounter = true
		table.insert(run.outbox, ev)
	end
	processRunEvents(run)
end

handlers.activity = function(info, _msg)
	local run = if info.runId then runs[info.runId] else nil
	if run and run.encounter then
		Encounter.touch(run.encounter, info.uid, now())
		for _, ev in Encounter.drain(run.encounter) do
			table.insert(run.outbox, ev)
		end
		processRunEvents(run)
	end
end

handlers.pick = function(info, msg)
	local run = if info.runId then runs[info.runId] else nil
	if run == nil then
		return
	end
	local res = RunCore.pick(run, info.uid, msg.choice, msg.slot)
	if not res.ok then
		push(info.player, "notice", { text = "That choice isn't available.", reason = res.reason })
	end
	processRunEvents(run)
	dirty[run.id] = true
	sendSnapshots(run, true)
end

handlers.reroll = function(info, _msg)
	local run = if info.runId then runs[info.runId] else nil
	if run == nil then
		return
	end
	RunCore.reroll(run, info.uid)
	processRunEvents(run)
	dirty[run.id] = true
	sendSnapshots(run, true)
end

handlers.restart = function(info, _msg)
	local run = if info.runId then runs[info.runId] else nil
	if run == nil then
		return
	end
	local res = RunCore.restart(run, info.uid, now())
	if res.ok then
		for _, m in RunCore.activeMembers(run) do
			funnels:mark(m.uid, "rematch_started", now())
		end
	end
	processRunEvents(run)
end

handlers.rematch = function(info, _msg)
	local run = if info.runId then runs[info.runId] else nil
	if run == nil or run.state ~= "finished" then
		return
	end
	local founders: { RunCore.Founder } = {}
	for _, m in RunCore.activeMembers(run) do
		if Players:GetPlayerByUserId(m.uid) then
			table.insert(founders, { uid = m.uid, kit = m.kit })
		end
	end
	-- The requester leads the new run.
	table.sort(founders, function(a, b)
		return a.uid == info.uid and b.uid ~= info.uid
	end)
	for _, f in founders do
		local fi = infos[f.uid]
		if fi then
			fi.runId = nil
		end
		funnels:mark(f.uid, "rematch_started", now())
		if run.mode == "test" then
			-- Each repeated condition is a new session/condition ID.
			local prior = true
			local fi2 = infos[f.uid]
			funnels:start(f.uid, now(), "test_" .. tostring(run.condition), prior, if fi2 then fi2.device else "unknown")
		end
	end
	runs[run.id] = nil
	if #founders == 0 then
		return
	end
	startRunFor(founders, {
		modifiers = run.modifiers,
		familyPool = run.familyPool,
		privacy = run.privacy,
		mode = run.mode,
		condition = run.condition,
	})
end

handlers.leaveRun = function(info, _msg)
	leaveCurrentRun(info, false)
	push(info.player, "lobby", lobbyList(info.uid))
	sendProfile(info)
end

handlers.joinRun = function(info, msg)
	if info.runId then
		return
	end
	local run = runs[msg.runId]
	if not run then
		push(info.player, "notice", { text = "That run has ended." })
		return
	end
	if run.privacy == "closed" then
		push(info.player, "notice", { text = "That run is closed." })
		return
	end
	if run.privacy == "friends" then
		local host = Players:GetPlayerByUserId(run.hostUid)
		local ok, isFriend = pcall(function()
			return host ~= nil and info.player:IsFriendsWithAsync(run.hostUid)
		end)
		if not (ok and isFriend) then
			push(info.player, "notice", { text = "That run is friends-only." })
			return
		end
	end
	local kit = if Kits.ById[msg.kit] then msg.kit else "ricochet"
	local res = RunCore.requestJoin(run, info.uid, kit, now())
	if not res.ok then
		push(info.player, "notice", { text = if res.reason == "full" then "That party is full." else "Can't join right now." })
		return
	end
	info.runId = run.id
	processRunEvents(run)
	dirty[run.id] = true
	sendSnapshots(run, true)
	broadcastLobby()
end

handlers.setRecipient = function(info, msg)
	local run = if info.runId then runs[info.runId] else nil
	if run then
		RunCore.setRecipient(run, info.uid, msg.uid)
		dirty[run.id] = true
		sendSnapshots(run, true)
	end
end

handlers.settings = function(info, msg)
	local p = profileOf(info.uid)
	if p == nil then
		return
	end
	if msg.reducedMotion ~= nil then
		p.settings.reducedMotion = msg.reducedMotion
	end
	if msg.music ~= nil then
		p.settings.music = math.clamp(msg.music, 0, 1)
	end
	if msg.sfx ~= nil then
		p.settings.sfx = math.clamp(msg.sfx, 0, 1)
	end
	if msg.skipSeen ~= nil then
		p.settings.skipSeen = msg.skipSeen
	end
end

handlers.equipTrail = function(info, msg)
	local p = profileOf(info.uid)
	if p and Cosmetics.ById[msg.id] and p.unlocked[msg.id] then
		p.equippedTrail = msg.id
		sendProfile(info)
	end
end

handlers.seenCutscene = function(info, msg)
	local p = profileOf(info.uid)
	if p and type(msg.id) == "string" and #msg.id <= 32 then
		p.seen[msg.id] = true
	end
end

handlers.devTest = function(info, msg)
	if not RunManager.devAllowed(info.player) then
		return
	end
	local cond = msg.condition
	if cond ~= "solo" and cond ~= "duo_self" and cond ~= "duo_teammate" then
		return
	end
	local founders: { RunCore.Founder } = { { uid = info.uid, kit = "ricochet" } }
	if cond ~= "solo" then
		local partner: PlayerInfo? = nil
		for uid, other in infos do
			if uid ~= info.uid and other.sessionLoaded then
				partner = other
				break
			end
		end
		if partner == nil then
			push(info.player, "notice", { text = "Duo conditions need a second player (Test → Clients and Servers, 2 players)." })
			return
		end
		table.insert(founders, { uid = (partner :: PlayerInfo).uid, kit = "ricochet" })
	end
	for _, f in founders do
		local fi = infos[f.uid]
		if fi then
			leaveCurrentRun(fi, false)
			funnels:start(f.uid, now(), "test_" .. cond, true, fi.device)
		end
	end
	startRunFor(founders, { modifiers = {}, familyPool = {}, privacy = "closed", mode = "test", condition = cond, seed = "test-fixed" })
end

local function onRequest(player: Player, kind: any, payload: any)
	local info = infos[player.UserId]
	if info == nil or not info.sessionLoaded then
		return
	end
	if not RateLimit.allow(limiter, info.uid, os.clock()) then
		return
	end
	local msg, reason = Protocol.validate(kind, payload)
	if msg == nil then
		log(`rejected {tostring(kind)} from {info.uid}: {reason}`)
		return
	end
	local handler = handlers[kind]
	if handler then
		local ok, err = pcall(function()
			handler(info, msg :: { [string]: any })
		end)
		if not ok then
			warn(`[Cabinet] handler {kind} failed: {err}`)
		end
	end
end

-- Teammate aim previews: cosmetic, unreliable, rate-limited, validated.
local function onAim(player: Player, aim: any)
	local info = infos[player.UserId]
	if info == nil or info.runId == nil or not Aim.isValid(aim) then
		return
	end
	if not RateLimit.allow(aimLimiter, info.uid, os.clock()) then
		return
	end
	local run = runs[info.runId :: string]
	if not run then
		return
	end
	for _, uid in run.order do
		if uid ~= info.uid then
			local p = Players:GetPlayerByUserId(uid)
			if p then
				cosmeticRemote:FireClient(p, info.uid, aim)
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	local uid = player.UserId
	local info: PlayerInfo = {
		player = player,
		uid = uid,
		runId = nil,
		device = "unknown",
		ready = false,
		firstRunDone = false,
		divergences = 0,
		shotsPredicted = 0,
		lastAimRelay = 0,
		pendingKit = "ricochet",
		sessionLoaded = false,
	}
	infos[uid] = info
	-- Join is recorded at once so early exits stay in the denominator; the
	-- prior-exposure field is filled from the profile when it loads.
	funnels:start(uid, now(), "normal", false, "unknown")
	local session = ProfileStore.load(store, uid)
	if player.Parent == nil then
		ProfileStore.save(store, uid, true)
		ProfileStore.forget(store, uid)
		return
	end
	local fs = funnels:session(uid)
	if fs then
		fs.prior = if session.profile.stats.runsStarted > 0 then "returning" else "new"
	end
	if session.status ~= "loaded" then
		log(`profile for {uid} not loaded ({session.reason}); playing without saving`)
	end
	info.sessionLoaded = true
	sendProfile(info)
	-- A held seat from a recent disconnect is reclaimed automatically.
	for id, run in runs do
		local m = run.members[uid]
		if m and m.status == "disconnected" then
			local res = RunCore.rejoin(run, uid, now())
			if res.ok then
				info.runId = id
				processRunEvents(run)
				dirty[id] = true
				sendSnapshots(run, true)
			end
		end
	end
	push(player, "hello", { serverTime = now(), runId = info.runId })
end

local function onPlayerRemoving(player: Player)
	local uid = player.UserId
	local info = infos[uid]
	if info then
		leaveCurrentRun(info, true)
	end
	infos[uid] = nil
	RateLimit.forget(limiter, uid)
	RateLimit.forget(aimLimiter, uid)
	funnels:finish(uid)
	task.spawn(function()
		ProfileStore.save(store, uid, true)
		ProfileStore.forget(store, uid)
	end)
	broadcastLobby()
end

local function makeStore(): ProfileStore.Store
	local DataStoreService = game:GetService("DataStoreService")
	local backend: any
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(Config.Persistence.STORE_NAME, ProfileStore.SCOPE)
	end)
	if ok and ds then
		backend = ProfileStore.dataStoreBackend(ds)
		backendLabel = "datastore:" .. ProfileStore.SCOPE
	else
		backend = ProfileStore.memoryBackend()
		backendLabel = "memory"
		log("DataStores unavailable here; profiles are kept in memory for this session only")
	end
	local rng = Random.new()
	return ProfileStore.new({
		backend = backend,
		jobId = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false),
		clock = os.time,
		wait = function(s)
			task.wait(s)
		end,
		jitter = function()
			return rng:NextNumber()
		end,
		log = log,
	})
end

local function makeFunnels(): Funnels.Funnels
	local AnalyticsService = game:GetService("AnalyticsService")
	local function fieldMap(f: { string }): { [string]: string }
		return {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = f[1],
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = f[2],
			[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = f[3],
		}
	end
	local verbose = RunService:IsStudio()
	return Funnels.new({
		funnelStep = function(uid, funnel, sessionId, step, name, f)
			local p = Players:GetPlayerByUserId(uid)
			if p then
				local ok, err = pcall(function()
					AnalyticsService:LogFunnelStepEvent(p, funnel, sessionId, step, name, fieldMap(f))
				end)
				if not ok and verbose then
					log(`funnel event not sent ({err})`)
				end
			end
			if verbose then
				print(string.format("[funnel] %s/%d %s uid=%d session=%s", funnel, step, name, uid, string.sub(sessionId, 1, 8)))
			end
		end,
		custom = function(uid, name, value, f)
			local p = Players:GetPlayerByUserId(uid)
			if p then
				pcall(function()
					AnalyticsService:LogCustomEvent(p, name, value, fieldMap(f))
				end)
			end
			if verbose and string.sub(name, 1, 2) ~= "t_" then
				print(string.format("[event] %s=%s uid=%d", name, tostring(value), uid))
			end
		end,
	}, function()
		return HttpService:GenerateGUID(false)
	end)
end

function RunManager.start()
	Players.CharacterAutoLoads = false

	net = Instance.new("Folder")
	net.Name = Protocol.FOLDER
	requestRemote = Instance.new("RemoteEvent")
	requestRemote.Name = Protocol.REQUEST
	requestRemote.Parent = net
	pushRemote = Instance.new("RemoteEvent")
	pushRemote.Name = Protocol.PUSH
	pushRemote.Parent = net
	cosmeticRemote = Instance.new("UnreliableRemoteEvent")
	cosmeticRemote.Name = Protocol.COSMETIC
	cosmeticRemote.Parent = net
	cosmeticUp = Instance.new("UnreliableRemoteEvent")
	cosmeticUp.Name = Protocol.COSMETIC_UP
	cosmeticUp.Parent = net
	net.Parent = ReplicatedStorage

	store = makeStore()
	funnels = makeFunnels()

	requestRemote.OnServerEvent:Connect(onRequest)
	cosmeticUp.OnServerEvent:Connect(onAim)
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayerAdded, p)
	end

	local tickTimes: { number } = {}
	RunService.Heartbeat:Connect(function()
		local t0 = os.clock()
		local t = now()
		for id, run in runs do
			RunCore.tick(run, t)
			processRunEvents(run)
			sendSnapshots(run, false)
			if run.state == "abandoned" then
				runs[id] = nil
				log(`run {id} closed`)
			end
		end
		-- Server game-work timing (budget: p95 < 4 ms/frame at the 8-player cap).
		table.insert(tickTimes, (os.clock() - t0) * 1000)
		if #tickTimes >= 600 then
			table.sort(tickTimes)
			local p95 = tickTimes[math.floor(#tickTimes * 0.95)]
			local maxv = tickTimes[#tickTimes]
			if RunService:IsStudio() then
				print(string.format("[perf] server game work over 600 frames: p95 %.3f ms, max %.3f ms, players %d, runs %d", p95, maxv, #Players:GetPlayers(), (function()
					local n = 0
					for _ in runs do
						n += 1
					end
					return n
				end)()))
			end
			table.clear(tickTimes)
		end
	end)

	-- Autosave.
	task.spawn(function()
		while true do
			task.wait(Config.Persistence.AUTOSAVE_SECONDS)
			for uid in infos do
				task.spawn(ProfileStore.save, store, uid)
			end
		end
	end)

	game:BindToClose(function()
		for uid in infos do
			ProfileStore.save(store, uid, true)
		end
	end)

	log(`server ready (build {Config.BUILD_VERSION}, event map v{Config.EVENT_MAP_VERSION}, profiles: {backendLabel})`)
end

return RunManager
