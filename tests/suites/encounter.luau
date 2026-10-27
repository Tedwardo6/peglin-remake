--!nocheck
-- Encounter rules: validation, scheduling, threats, relay, scaling, roster.

local function seed(uid, opts)
	opts = opts or {}
	return {
		uid = uid,
		hull = opts.hull or 40,
		maxHull = 40,
		rack = opts.rack or { "basic", "rebound", "zip" },
		components = opts.components or {},
		ballLevels = {},
	}
end

local function newEnc(T, players, opts)
	opts = opts or {}
	local E = T.Loader.server("Encounter.EncounterCore")
	return E.new({
		id = "t",
		enemyId = opts.enemy or "brute",
		boardId = opts.board or "lanes",
		now = 0,
		startAt = 0,
		players = players,
		modifiers = opts.modifiers or {},
		relayMode = opts.relayMode or "auto",
		hpOverride = opts.hp,
	}), E
end

-- Finds an aim on a board whose shot generates a charge (or not).
local function findAim(T, boardId, wantCharge, ballId)
	local Shot = T.Loader.shared("Sim.Shot")
	local Boards = T.Loader.shared("Content.Boards")
	local b = Boards.ById[boardId]
	for a = -1880, 1880, 10 do
		local r = Shot.resolve({ boardId = boardId, boardRev = b.rev, aim = a, loadout = { ballId = ballId or "basic", components = {}, enemyHpFrac = 1 } })
		local has = r.outcome.totals.chargeStep ~= nil
		if has == wantCharge and r.outcome.totals.damage > 0 then
			return a, r
		end
	end
	error("no aim found")
end

local function eventsOf(enc, E, typ)
	local out = {}
	for _, ev in E.drain(enc) do
		if typ == nil or ev.type == typ then
			table.insert(out, ev)
		end
	end
	return out
end

return {
	{
		name = "HP scales 1 / 1.75 / 2.5 / 3.25 with active players",
		run = function(T)
			local E = T.Loader.server("Encounter.EncounterCore")
			T.eq(E.scaleFactor(1), 1, "solo")
			T.eq(E.scaleFactor(2), 1.75, "duo")
			T.eq(E.scaleFactor(3), 2.5, "trio")
			T.eq(E.scaleFactor(4), 3.25, "quad")
			local enc = newEnc(T, { seed(1), seed(2) }, { hp = 100 })
			T.eq(enc.maxHp, 175, "duo encounter max HP")
		end,
	},
	{
		name = "launch validation rejects malformed and repeated requests",
		run = function(T)
			local enc, E = newEnc(T, { seed(1) })
			local rev = enc.boardRev
			T.eq(E.launch(enc, 99, { seq = 1, slot = 1, aim = 0, boardRev = rev }, 1).reason, "not_member", "stranger")
			T.eq(E.launch(enc, 1, { seq = 2, slot = 1, aim = 0, boardRev = rev }, 1).reason, "sequence", "skipped seq")
			T.eq(E.launch(enc, 1, { seq = 1, slot = 1, aim = 0 / 0, boardRev = rev }, 1).reason, "aim", "NaN aim")
			T.eq(E.launch(enc, 1, { seq = 1, slot = 1, aim = 0.5, boardRev = rev }, 1).reason, "aim", "fractional aim")
			T.eq(E.launch(enc, 1, { seq = 1, slot = 1, aim = 99999, boardRev = rev }, 1).reason, "aim", "huge aim")
			T.eq(E.launch(enc, 1, { seq = 1, slot = 4, aim = 0, boardRev = rev }, 1).reason, "slot", "bad slot")
			T.eq(E.launch(enc, 1, { seq = 1, slot = 1, aim = 0, boardRev = rev + 1 }, 1).reason, "board_revision", "stale board")
			local ok = E.launch(enc, 1, { seq = 1, slot = 2, aim = 0, boardRev = rev }, 1)
			T.check(ok.ok, "valid launch accepted")
			T.eq(E.launch(enc, 1, { seq = 1, slot = 1, aim = 0, boardRev = rev }, 2).reason, "sequence", "replayed seq")
			T.eq(E.launch(enc, 1, { seq = 2, slot = 1, aim = 0, boardRev = rev }, 1.1).reason, "in_flight", "one ball at a time")
			E.tick(enc, ok.shot.endAt + 0.01)
			T.eq(E.launch(enc, 1, { seq = 2, slot = 2, aim = 0, boardRev = rev }, ok.shot.endAt + 0.5).reason, "cooldown", "special on cooldown")
			T.check(E.launch(enc, 1, { seq = 2, slot = 1, aim = 0, boardRev = rev }, ok.shot.endAt + 0.5).ok, "basic always ready")
		end,
	},
	{
		name = "damage applies when earned and matches the client's prediction",
		run = function(T)
			local Shot = T.Loader.shared("Sim.Shot")
			local enc, E = newEnc(T, { seed(1) }, { hp = 5000 })
			local res = E.launch(enc, 1, { seq = 1, slot = 1, aim = 120, boardRev = enc.boardRev }, 10)
			T.check(res.ok, "accepted")
			-- Client prediction from the same frozen inputs.
			local predicted = Shot.resolve({ boardId = enc.boardId, boardRev = enc.boardRev, aim = 120, loadout = res.shot.loadout })
			T.eq(predicted.fingerprint, res.shot.fingerprint, "server and client agree")
			local half = res.shot.startAt + (res.shot.endAt - res.shot.startAt) / 2
			E.tick(enc, half)
			local mid = enc.hp
			T.check(mid < 5000 and mid > 5000 - res.shot.damage or res.shot.damage == 0, "partial damage mid-flight")
			E.tick(enc, res.shot.endAt + 0.01)
			T.eq(enc.hp, 5000 - res.shot.damage, "full damage after the ball drains")
		end,
	},
	{
		name = "relay charge: send, consume with bonus, never overwrite, return, drop",
		run = function(T)
			local aimCharge = findAim(T, "lanes", true)
			local aimPlain = findAim(T, "lanes", false)
			local enc, E = newEnc(T, { seed(1), seed(2) }, { hp = 100000 })
			local rev = enc.boardRev
			local s1 = E.launch(enc, 1, { seq = 1, slot = 1, aim = aimCharge, boardRev = rev }, 1)
			T.eq(s1.shot.recipient, 2, "duo recipient is the teammate")
			E.tick(enc, s1.shot.endAt + 0.01)
			local sent = eventsOf(enc, E, "chargeSent")
			T.eq(#sent, 1, "one charge per shot")
			T.check(enc.players[2].charge ~= nil and enc.players[2].charge.from == 1, "recipient holds a named charge")
			-- Second charge from player 1 while 2 is full -> returns to 1.
			local s2 = E.launch(enc, 1, { seq = 2, slot = 1, aim = aimCharge, boardRev = rev }, s1.shot.endAt + 1)
			E.tick(enc, s2.shot.endAt + 0.01)
			T.eq(#eventsOf(enc, E, "chargeReturned"), 1, "full queue returns the charge to the sender")
			T.check(enc.players[2].charge.from == 1 and enc.players[1].charge ~= nil, "original charge kept; sender holds the returned one")
			-- Third: both full -> dropped, nothing overwritten.
			local held2 = enc.players[2].charge.id
			local s3 = E.launch(enc, 1, { seq = 3, slot = 1, aim = aimCharge, boardRev = rev }, s2.shot.endAt + 1)
			T.check(s3.shot.loadout.charge ~= nil, "player 1's own held charge is consumed by its next launch")
			E.tick(enc, s3.shot.endAt + 0.01)
			T.eq(enc.players[2].charge.id, held2, "never overwritten")
			-- Player 2 consumes: bonus realized on the first six damaging hits.
			local s4 = E.launch(enc, 2, { seq = 1, slot = 1, aim = aimPlain, boardRev = rev }, s3.shot.endAt + 1)
			T.check(s4.shot.loadout.charge ~= nil, "charge consumed on next launch")
			T.check(enc.players[2].charge == nil, "slot cleared")
			local bonus = 0
			local bonusHits = 0
			for _, h in s4.shot.hits do
				bonus += h.bonus
				if h.bonus > 0 then
					bonusHits += 1
				end
			end
			T.check(bonusHits <= 6 and bonusHits > 0, `bonus on at most six hits (got {bonusHits})`)
			T.eq(bonus, bonusHits * 2, "+2 power per boosted hit")
			T.eq(#eventsOf(enc, E, "chargeUsed"), 2, "chargeUsed emitted for both consumptions (returned charge, then teammate charge)")
		end,
	},
	{
		name = "solo and self-mode charges go to the shooter",
		run = function(T)
			local aimCharge = findAim(T, "lanes", true)
			local enc, E = newEnc(T, { seed(1) }, { hp = 100000 })
			local s = E.launch(enc, 1, { seq = 1, slot = 1, aim = aimCharge, boardRev = enc.boardRev }, 1)
			T.eq(s.shot.recipient, 1, "solo self-charge")
			local enc2, E2 = newEnc(T, { seed(1), seed(2) }, { hp = 100000, relayMode = "self" })
			local s2 = E2.launch(enc2, 1, { seq = 1, slot = 1, aim = aimCharge, boardRev = enc2.boardRev }, 1)
			T.eq(s2.shot.recipient, 1, "duo self-charge control condition")
		end,
	},
	{
		name = "recipient leaving returns a pending charge to the sender",
		run = function(T)
			local aimCharge = findAim(T, "lanes", true)
			local enc, E = newEnc(T, { seed(1), seed(2) }, { hp = 100000 })
			local s = E.launch(enc, 1, { seq = 1, slot = 1, aim = aimCharge, boardRev = enc.boardRev }, 1)
			E.removePlayer(enc, 2, 1.01)
			E.tick(enc, s.shot.endAt + 0.01)
			T.check(enc.players[1].charge ~= nil, "charge returned to sender after recipient left")
		end,
	},
	{
		name = "roster change preserves HP percentage after due hits",
		run = function(T)
			local enc, E = newEnc(T, { seed(1), seed(2) }, { hp = 100 })
			T.eq(enc.maxHp, 175, "duo HP")
			enc.hp = 87 -- just under half
			E.removePlayer(enc, 2, 5)
			E.tick(enc, 5)
			T.eq(enc.maxHp, 100, "solo HP after departure")
			T.eq(enc.hp, 50, "HP percentage preserved (87/175 -> 50/100)")
		end,
	},
	{
		name = "threats: telegraph >= 12 s, shield absorbs, defeat, all defeated loses",
		run = function(T)
			local Config = T.Loader.shared("Config")
			local enc, E = newEnc(T, { seed(1, { hull = 10 }), seed(2, { hull = 40 }) }, { enemy = "brute", hp = 100000 })
			local tel = E.threatTelegraph(enc)
			T.check(tel.landsAt - tel.warnAt >= 12, "warning window is at least 12 s")
			T.check(tel.landsAt >= 12, "first threat lands after the warning window")
			enc.players[2].shield = 5
			E.tick(enc, tel.landsAt + 0.01)
			T.eq(enc.players[1].hull, 2, "8 damage to the unshielded player")
			T.eq(enc.players[2].shield, 0, "shield absorbs first")
			T.eq(enc.players[2].hull, 37, "remainder hits hull")
			E.tick(enc, tel.landsAt + 18.01)
			T.check(enc.players[1].defeated, "second slam defeats the low-hull player")
			T.eq(enc.phase, "fight", "fight continues while one player stands")
			enc.players[2].hull = 3
			E.tick(enc, tel.landsAt + 36.01)
			T.eq(enc.phase, "lost", "all defeated loses the encounter")
			local _ = Config
		end,
	},
	{
		name = "idle: warn at 45 s, observer at 60 s, roster rescales",
		run = function(T)
			local enc, E = newEnc(T, { seed(1), seed(2) }, { enemy = "brute", hp = 100 })
			E.tick(enc, 44)
			T.check(not enc.players[2].idleWarned, "not warned yet")
			E.touch(enc, 1, 44)
			E.tick(enc, 45.5)
			T.check(enc.players[2].idleWarned, "warned at 45 s")
			T.check(not enc.players[1].idleWarned, "active player not warned")
			E.touch(enc, 1, 59)
			E.tick(enc, 60.5)
			T.check(not enc.players[2].active, "observer after 15 more seconds")
			T.eq(enc.maxHp, 100, "HP rescaled to one active player")
		end,
	},
	{
		name = "threat warning covers the longest flight plus aim time",
		run = function(T)
			local Config = T.Loader.shared("Config")
			local maxFlight = Config.Sim.MAX_FLIGHT_STEPS / Config.Sim.STEP_HZ
			T.check(Config.Combat.THREAT_WARNING - maxFlight >= 4, "12 s warning leaves >= 4 s to aim after an 8 s flight")
			local Enemies = T.Loader.shared("Content.Enemies")
			for _, id in Enemies.Order do
				local e = Enemies.ById[id]
				T.check(e.cadence >= 16 and e.cadence <= 20, `{id} cadence in 16-20 s`)
				T.check(e.firstDelay >= 12, `{id} first threat at least 12 s in`)
				for _, ph in e.phases or {} do
					T.check(ph.cadence >= 16 and ph.cadence <= 20, `{id} phase cadence in 16-20 s`)
				end
			end
		end,
	},
	{
		name = "armor soaks damage and boss phases trigger",
		run = function(T)
			local enc, E = newEnc(T, { seed(1) }, { enemy = "boss_crusher", hp = 100 })
			enc.armor = 5
			local shot = E.launch(enc, 1, { seq = 1, slot = 1, aim = 0, boardRev = enc.boardRev }, 1)
			E.tick(enc, shot.shot.endAt + 0.01)
			local dealt = math.min(shot.shot.damage, 105)
			T.check(enc.armor == 0 or shot.shot.damage < 5, "armor used up first")
			local phases = eventsOf(enc, E, "bossPhase")
			if 100 - math.max(0, dealt - 5) <= 50 and enc.phase == "fight" then
				T.eq(#phases, 1, "phase change at 50%")
			end
		end,
	},
}
