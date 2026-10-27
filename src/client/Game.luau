--!strict
-- Client orchestration: turns server state and events into the scene, HUD,
-- predicted shots, and feedback. Consequences always come from the server;
-- the client predicts its own shot with the shared simulation so the first
-- frame after LAUNCH already shows the ball moving.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Boards = require(Shared.Content.Boards)
local Balls = require(Shared.Content.Balls)
local Enemies = require(Shared.Content.Enemies)
local Campaigns = require(Shared.Content.Campaigns)
local Cosmetics = require(Shared.Content.Cosmetics)
local Pegs = require(Shared.Content.Pegs)
local Shot = require(Shared.Sim.Shot)
local Scoring = require(Shared.Sim.Scoring)
local Components = require(Shared.Content.Components)
local AimMath = require(Shared.Sim.Aim)

local Net = require(script.Parent.State.Net)
local Layout = require(script.Parent.World.Layout)
local LobbyHall = require(script.Parent.World.LobbyHall)
local Scenery = require(script.Parent.World.Scenery)
local Cabinet = require(script.Parent.World.Cabinet)
local Monster = require(script.Parent.World.Monster)
local Hero = require(script.Parent.World.Hero)
local Gallery = require(script.Parent.World.Gallery)
local Board = require(script.Parent.BoardView.Board)
local ShotPlayer = require(script.Parent.BoardView.ShotPlayer)
local Guide = require(script.Parent.BoardView.Guide)
local AimInput = require(script.Parent.Input.AimInput)
local Audio = require(script.Parent.Juice.Audio)
local Fx = require(script.Parent.Juice.Fx)
local Theme = require(script.Parent.UI.Theme)
local Kit = require(script.Parent.UI.Kit)
local Hud = require(script.Parent.UI.Hud)
local Screens = require(script.Parent.UI.Screens)
local Teammates = require(script.Parent.UI.Teammates)
local LobbyMenu = require(script.Parent.UI.LobbyMenu)
local MapScreen = require(script.Parent.UI.MapScreen)
local Director = require(script.Parent.Cutscenes.Director)

local C = Theme.Color
local me = Players.LocalPlayer
local myUid = me.UserId

local Game = {}

-- Scene objects
local worldRoot: Folder
local cabinet: Cabinet.Cabinet
local board: Board.Board? = nil
local boardId = ""
local monster: Monster.Monster? = nil
local monsterEncId = ""
local guide: Guide.Guide
local hud: Hud.Hud
local teammates: Teammates.Teammates
local menu: LobbyMenu.Menu
local hall: LobbyHall.Handles
local heroes: { [number]: Hero.Hero } = {}
local lobbyHeroes: { [number]: Hero.Hero } = {}
local heroFolder: Folder
local mapView: MapScreen.View? = nil
local restModal: Screens.Rest? = nil
local restOpenFor = ""
local bank: { [number]: number } = {}

-- Replicated state
local profile: { [string]: any } = {}
local runSnap: { [string]: any }? = nil
local encSnap: { [string]: any }? = nil
local snapTime = 0
local lastRunState = ""
local lastEncId = ""
local lobby: { [string]: any } = {}

-- Local play state
local selectedSlot = 1
local localSeq = 0
local shotPlayer: ShotPlayer.ShotPlayer? = nil
local practice = false
local pendingShots: { [number]: { fingerprint: string, startAt: number } } = {}
local visualHits: { { t: number, dmg: number } } = {}
local optimisticCooldowns: { [number]: number }? = nil
local draftModal: Screens.Draft? = nil
local draftOpenFor = ""
local endModal: Screens.Modal? = nil
local waiting: Screens.Waiting? = nil
local cutsceneUntil = 0
local lowShots = 0
local lastAimSent = 0
local tipsShown: { [string]: boolean } = {}
local pendingIntro: { [string]: any }? = nil
local settingsState = { reducedMotion = false, music = 0.6, sfx = 0.9, skipSeen = false }

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function myEncPlayer(): { [string]: any }?
	if encSnap == nil then
		return nil
	end
	for _, p in (encSnap :: any).players do
		if p.uid == myUid then
			return p
		end
	end
	return nil
end

local function myMember(): { [string]: any }?
	if runSnap == nil then
		return nil
	end
	for _, m in (runSnap :: any).members do
		if m.uid == myUid then
			return m
		end
	end
	return nil
end

local function playerName(uid: number): string
	local p = Players:GetPlayerByUserId(uid)
	return if p then p.DisplayName else "Teammate"
end

local function seen(id: string): boolean
	return tipsShown[id] == true or (profile.seen ~= nil and profile.seen[id] == true)
end

local function markSeen(id: string)
	tipsShown[id] = true
	Net.send("seenCutscene", { id = id })
end

local function actOf(run: { [string]: any }?): Campaigns.Act
	local camp = Campaigns.ById[if run then run.campaign or Campaigns.DEFAULT else Campaigns.DEFAULT] or Campaigns.ById[Campaigns.DEFAULT]
	local idx = if run then math.clamp(run.act or 1, 1, #camp.acts) else 1
	return camp.acts[idx]
end

local function legPalette(_index: number?): Cabinet.Palette
	local p = actOf(runSnap).palette
	return { frame = p.deep, trim = Color3.fromRGB(214, 160, 70), back = p.deep, glow = p.glow }
end

-- Seat (1-based) of a player in the run, for their colour.
local function seatOf(uid: number): number
	local run = runSnap
	if run then
		for i, m in (run :: any).members do
			if m.uid == uid then
				return i
			end
		end
	end
	return 1
end

local function heroOf(uid: number): Hero.Hero?
	return heroes[uid]
end

local function trailColors(): (Color3, Color3)
	local def = Cosmetics.ById[profile.equippedTrail or "default"] or Cosmetics.ById.default
	return def.colorA, def.colorB
end

-- Board and monster -------------------------------------------------------

local function setBoard(id: string, trim: Color3)
	if id == boardId and board then
		return
	end
	if board then
		(board :: Board.Board):destroy()
	end
	board = Board.new(worldRoot, id, trim);
	(board :: Board.Board).reducedMotion = settingsState.reducedMotion
	boardId = id
end

local function setMonster(enemyId: string?, encId: string)
	if monster and monsterEncId ~= encId then
		local old = monster :: Monster.Monster
		if not old.dead then
			old:destroy()
		end
		monster = nil
	end
	if enemyId and not monster then
		local m = Monster.new(worldRoot, enemyId, Layout.MONSTER_BASE)
		m.reducedMotion = settingsState.reducedMotion
		m:hide()
		monster = m
		monsterEncId = encId
		local def = Enemies.ById[enemyId]
		if hud and def then
			hud:setEnemyPortrait(def.look.model)
		end
	end
end

-- Prediction display: monster HP = server HP minus strikes that have landed
-- on screen but are not yet in the latest server snapshot.
local function displayedEnemyHp(): (number, number)
	if encSnap == nil then
		return 0, 0
	end
	local hp = (encSnap :: any).hp
	local armor = (encSnap :: any).armor
	local pending = 0
	local now = serverNow()
	for _, v in visualHits do
		if v.t > snapTime and v.t <= now then
			pending += v.dmg
		end
	end
	local soak = math.min(armor, pending)
	return math.max(0, hp - (pending - soak)), math.max(0, armor - soak)
end

-- Feedback for one scoring hit on a board we render in 3D.
local function onBoardHit(hit: Scoring.Hit, sp: ShotPlayer.ShotPlayer?, isMine: boolean, serverT: number)
	local b = board
	if b == nil or hit.peg == nil then
		return
	end
	local pos = b:position(hit.peg :: number)
	b:hit(hit.peg :: number, if hit.big then 1 else 0)
	local kind = hit.kind
	local def = Pegs.Defs[kind :: Pegs.PegKind]
	Fx.sparks(pos, def.litColor, if hit.big then 18 else 8)
	-- Sound: rising pitch across the combo; special pegs have their own voice.
	local pitch = Audio.comboPitch(hit.combo)
	if kind == "guard" then
		Audio.play("pegGuard", { pitch = 0.9 + math.min(hit.combo, 20) * 0.01 })
	elseif kind == "relay" then
		Audio.play("pegRelay")
	elseif kind == "power" then
		Audio.play("pegPower", { pitch = pitch * 0.9 })
	elseif kind == "mend" then
		Audio.play("pegMend")
	elseif kind == "burst" then
		Audio.play("burst")
		Fx.ring(pos + Vector3.new(0, 0, 0.6), def.color, Pegs.BURST_RADIUS * Layout.S, 0.3)
	elseif kind == "spring" then
		Audio.play("spring")
	end
	Audio.play("peg", { pitch = pitch })
	if hit.damage > 0 then
		local color = if hit.bonus > 0 then C.purple elseif hit.big then C.gold else C.text
		Fx.number(pos + Vector3.new(0, 0.6, 1.2), tostring(hit.damage), color, hit.damage * 0.8)
		-- Damage gathers on your hero; it strikes when the ball drains.
		if isMine then
			bank[myUid] = (bank[myUid] or 0) + hit.damage
			local h = heroOf(myUid)
			if h then
				h:bank(bank[myUid])
			end
		end
		local _ = serverT
		if hit.big then
			Audio.play("bigHit", { pitch = 1 + math.min(hit.damage, 40) / 80 })
			cabinet:shakeFrame(math.min(0.45, 0.12 + hit.damage / 80))
			if sp and not settingsState.reducedMotion then
				sp:hitStop(if hit.damage >= 20 then Fx.HIT_STOP_BIG else Fx.HIT_STOP_SMALL)
			end
		else
			Audio.play("flinch", { pitch = 1 + math.random() * 0.2, volume = 0.6 })
		end
	end
	if hit.shield > 0 then
		Fx.number(pos + Vector3.new(0, 0.6, 1.2), `+{hit.shield} 🛡`, C.shield, 8)
	end
	if hit.heal > 0 then
		Fx.number(pos + Vector3.new(0, 0.6, 1.2), `+{hit.heal} ♥`, C.green, 8)
	end
	if hit.charge and isMine then
		-- Predict the recipient the server froze at launch: yourself when solo
		-- or in the self-charge control, else your chosen (or only) teammate.
		local to = myUid
		local enc = encSnap
		if enc and not (runSnap and (runSnap :: any).condition == "duo_self") then
			local mm = myMember()
			local first: number? = nil
			for _, tp in (enc :: any).players do
				if tp.uid ~= myUid and tp.present and tp.active and not tp.defeated then
					first = first or tp.uid
					if mm and mm.recipient == tp.uid then
						first = tp.uid
					end
				end
			end
			if first then
				to = first
			end
		end
		Fx.callout(if to == myUid then "EMPOWERED!" else `EMPOWER → {string.upper(playerName(to))}!`, C.purple, 1)
		Audio.play("chargeSend")
		local mine = heroOf(myUid)
		if mine then
mine:castSupport()
		end
		local toHero = heroOf(to)
		local target = if to == myUid then hud:chargeSlotScreenPos() elseif toHero then Fx.toScreen(toHero:headPosition()) else (teammates:screenPos(to) or hud:chargeSlotScreenPos())
		Fx.arc(Fx.toScreen(pos), target, C.purple, 0.55, function()
			Audio.play("chargeArrive")
		end)
	end
	if isMine and (hit.combo == 5 or hit.combo == 10 or hit.combo == 15 or hit.combo == 20 or hit.combo == 30 or hit.combo == 40) then
		Fx.callout(`{hit.combo} PEG COMBO!`, if hit.combo >= 20 then C.pink elseif hit.combo >= 10 then C.gold else C.cyan, 0.9 + math.min(hit.combo, 30) / 60)
	end
end

-- Hero strikes: the shot's damage leaves the hero's weapon as a bolt and
-- lands on the monster at the moment the server applies it.
local function scheduleStrike(uid: number, total: number, impactT: number)
	if total <= 0 then
		return
	end
	table.insert(visualHits, { t = impactT, dmg = total })
	local delayTime = impactT - serverNow()
	local travel = 0.18
	local wind = 0.26
	task.delay(math.max(0, delayTime - travel - wind), function()
		local h = heroOf(uid)
		local color = Theme.slot(seatOf(uid))
		local function launchBolt()
			bank[uid] = 0
			local m = monster
			if m == nil or m.dead then
				return
			end
			local from = if h then h:weaponPosition() else Layout.HERO_ANCHOR + Vector3.new(0, 3, 0)
			local to = m:centerPosition()
			Audio.play("whoosh", { pitch = 1.3 })
			Fx.bolt(from, to, color, travel, function()
				local mm = monster
				if mm == nil or mm.dead then
					return
				end
				local big = total >= 30
				mm:hit(total, big)
				Fx.number(to + Vector3.new((math.random() - 0.5) * 2, 1 + math.random(), 2.5), tostring(total), color, total * 1.6)
				Fx.sparks(to, color, if big then 20 else 10)
				Audio.play("bigHit", { pitch = 1.25 - math.min(total, 80) / 160 })
				Scenery.pulse(math.min(1.5, total / 40))
				if big then
					cabinet:shakeFrame(math.min(0.4, total / 120))
				end
			end)
		end
		if h then
			h:strike(wind, launchBolt)
		else
			task.delay(wind, launchBolt)
		end
	end)
end

-- HUD refresh -------------------------------------------------------------

local function threatText(t: { [string]: any }): (string, string)
	local k = t.kind
	if k == "slam" then
		return `SLAM {t.amount}`, `{t.amount} damage to everyone. Guard pegs build shield.`
	elseif k == "double" then
		return `DOUBLE {t.amount}×2`, `Two hits of {t.amount}. Shield blocks both.`
	elseif k == "jam" then
		return `JAM {t.amount}`, `{t.amount} damage and special balls need +1 shot.`
	elseif k == "grow" then
		return `RISING {t.amount}`, `{t.amount} damage, more each time.`
	elseif k == "armor" then
		return "ARMOR UP", `Monster gains {t.armor or 0} armor. Break it with damage.`
	elseif k == "pierce" then
		return `PIERCE {t.amount}`, `{t.amount} damage; half ignores shield.`
	end
	return string.upper(t.label or "THREAT"), ""
end

local function canLaunch(): boolean
	if practice then
		return not shotPlayer
	end
	local enc = encSnap
	local run = runSnap
	if enc == nil or run == nil or (run :: any).state ~= "fight" or (enc :: any).phase ~= "fight" then
		return false
	end
	if serverNow() < (enc :: any).startAt or os.clock() < cutsceneUntil then
		return false
	end
	local p = myEncPlayer()
	if p == nil or p.defeated or not p.active or not p.present then
		return false
	end
	if shotPlayer then
		return false
	end
	local cds = optimisticCooldowns or p.cooldowns
	local cd = (cds :: any)[selectedSlot] or 0
	if selectedSlot > 1 then
		cd += p.jam or 0
	end
	return cd <= 0
end

-- Party heroes on the battlefield follow the encounter's roster.
local function syncHeroes()
	local enc = encSnap
	local run = runSnap
	local want: { [number]: { [string]: any } } = {}
	local count = 0
	if enc and run and not practice then
		for _, tp in (enc :: any).players do
			if tp.present then
				want[tp.uid] = tp
				count += 1
			end
		end
	elseif run and not practice and (run :: any).state ~= "finished" then
		-- Between fights the party still stands on the field.
		for _, m in (run :: any).members do
			if m.status == "active" then
				want[m.uid] = { uid = m.uid, hull = m.hull, maxHull = m.maxHull, shield = 0, defeated = false, active = true, present = true }
				count += 1
			end
		end
	end
	for uid, h in heroes do
		if want[uid] == nil then
			h:destroy()
			heroes[uid] = nil
		end
	end
	if count == 0 then
		return
	end
	-- Seats in run order, so colours match the party list everywhere.
	local seatIdx = 0
	for _, m in (run :: any).members do
		local tp = want[m.uid]
		if tp then
			seatIdx += 1
			local seat = seatOf(m.uid)
			local spot = Layout.heroSpot(seatIdx, count)
			local existing: Hero.Hero? = heroes[m.uid]
			local h: Hero.Hero
			if existing == nil then
				h = Hero.new(heroFolder, m.uid, m.kit, Theme.slot(seat), spot, Layout.HERO_FACING)
				h.reducedMotion = settingsState.reducedMotion
				heroes[m.uid] = h
			else
				h = existing
				h:setSpot(spot, Layout.HERO_FACING)
			end
			h:setVitals(tp.hull, tp.maxHull, tp.shield, tp.defeated, not tp.active)
		end
	end
end

local function clearHeroes(set: { [number]: Hero.Hero })
	for uid, h in set do
		h:destroy()
		set[uid] = nil
	end
end

-- Lobby: you (and your party) stand on the dais.
local function syncLobbyHeroes()
	local party = lobby.party
	local list: { { uid: number, kit: string } } = {}
	if party then
		for _, m in party.members do
			table.insert(list, { uid = m.uid, kit = m.kit or "ricochet" })
		end
	else
		table.insert(list, { uid = myUid, kit = menu.choices.kit })
	end
	local keep: { [number]: boolean } = {}
	for i, e in list do
		keep[e.uid] = true
		local h: Hero.Hero? = lobbyHeroes[e.uid]
		if h and h.kit ~= e.kit then
			h:destroy()
			lobbyHeroes[e.uid] = nil
			h = nil
		end
		local spot = hall.spots[math.clamp(i, 1, #hall.spots)]
		if h == nil then
			local nh = Hero.new(heroFolder, e.uid, e.kit, Theme.slot(i), spot, hall.facing)
			nh.reducedMotion = settingsState.reducedMotion
			lobbyHeroes[e.uid] = nh
		else
			h:setSpot(spot, hall.facing)
		end
	end
	for uid, h in lobbyHeroes do
		if not keep[uid] then
			h:destroy()
			lobbyHeroes[uid] = nil
		end
	end
end

local function nodeStep(run: { [string]: any }): (number, number)
	local cur = run.current
	if cur == nil then
		return 1, 4
	end
	if cur.kind == "boss" then
		return 4, 4
	end
	local row = tonumber(string.match(cur.id or "", "r(%d+)")) or 1
	return row, 4
end

local function refreshHud()
	local run = runSnap
	local enc = encSnap
	if run == nil then
		return
	end
	local act = actOf(run)
	local step, steps = nodeStep(run :: any)
	if (run :: any).mode == "test" then
		hud:setProgress(1, 1, "Developer test")
	else
		hud:setProgress(step, steps, `{act.subtitle} · {act.name}`)
	end
	syncHeroes()
	local mm = myMember()
	local p = myEncPlayer()
	if enc and p then
		local def = Enemies.ById[(enc :: any).enemyId]
		local hp, armor = displayedEnemyHp()
		local cur = (run :: any).current
		local elite = cur and cur.kind == "elite"
		local phaseLabel = if (enc :: any).bossPhase > 0 and def.phases then def.phases[(enc :: any).bossPhase].label else (if def.boss then "BOSS" elseif elite then "ELITE" else "")
		hud:setEnemy(def.name, hp, (enc :: any).maxHp, armor, phaseLabel)
		local contrib: { Hud.Contribution } = {}
		for _, tp in (enc :: any).players do
			if tp.present then
				table.insert(contrib, { uid = tp.uid, name = if tp.uid == myUid then "You" else playerName(tp.uid), seat = seatOf(tp.uid), damage = tp.damage or 0 })
			end
		end
		hud:setContribution(contrib, hp, (enc :: any).maxHp)
		local status = ""
		if p.defeated then
			status = "Knocked out — watching until this fight ends."
		elseif not p.active then
			status = "Watching (idle). You'll rejoin next fight."
		elseif serverNow() < (enc :: any).startAt then
			status = `Get ready… {math.max(1, math.ceil((enc :: any).startAt - serverNow()))}`
		end
		hud:setPlayer(p.hull, p.maxHull, p.shield, status)
		hud:setCharge(p.charge, if p.charge then playerName(p.charge.from) else nil)
		local rack = p.rack
		local cds = optimisticCooldowns or p.cooldowns
		hud:setRack(rack, cds, p.jam or 0, selectedSlot, canLaunch())
		local m = monster
		if m then
			m:setArmor(armor > 0)
		end
	elseif practice then
		hud:setEnemy("Practice", 1, 1, 0, "")
		hud:setPlayer(Config.Combat.START_HULL, Config.Combat.START_HULL, 0, "Practice board: shots here don't count.")
		hud:setCharge(nil, nil)
		hud:setRack({ "basic" }, { 0 }, 0, 1, canLaunch())
	end
	-- Teammates.
	if enc then
		local list = {}
		local count = 0
		for _, tp in (enc :: any).players do
			if tp.present then
				count += 1
			end
			if tp.uid ~= myUid and tp.present then
				table.insert(list, {
					uid = tp.uid,
					hull = tp.hull,
					maxHull = tp.maxHull,
					shield = tp.shield,
					charge = tp.charge ~= nil,
					status = if tp.defeated then "Knocked out" elseif not tp.active then "Watching" elseif tp.charge then `Holding +{tp.charge.power} from {if tp.charge.from == myUid then "you" else playerName(tp.charge.from)}` else "",
				})
			end
		end
		teammates:set(list, (enc :: any).boardId, if mm then mm.recipient else nil, count >= 3)
	else
		teammates:set({}, "", nil, false)
	end
end

-- Shots -------------------------------------------------------------------

local function finishShot()
	shotPlayer = nil
	local b = board
	if b then
		b:refresh(true)
	end
	Audio.play("drain")
	optimisticCooldowns = nil
	refreshHud()
end

local function startLocalShot(aim: number, slot: number, loadout: Scoring.Loadout, serverStart: number, isPractice: boolean): string
	local enc = encSnap
	local bId = if isPractice then boardId else (enc :: any).boardId
	local bdef = Boards.ById[bId]
	local result = Shot.resolve({ boardId = bId, boardRev = bdef.rev, aim = aim, loadout = loadout })
	local ball = Balls.ById[loadout.ballId]
	local ta, tb = trailColors()
	local sp: ShotPlayer.ShotPlayer
	sp = ShotPlayer.new(worldRoot, result.sim, result.outcome, ball.radius, ball.color, ball.accent, ta, tb, {
		onHit = function(hit, _i)
			onBoardHit(hit, sp, not isPractice, serverStart + hit.step / Config.Sim.STEP_HZ)
		end,
		onWall = function(pos)
			Audio.play("wall", { pitch = 0.9 + math.random() * 0.2 })
			Fx.sparks(pos, Color3.new(1, 1, 1), 4)
			cabinet:shakeFrame(0.05)
		end,
		onEnd = function()
			local total = result.outcome.totals
			if total.damage > 0 then
				Fx.callout(`STRIKE {total.damage}`, if total.damage >= 60 then C.gold else C.text, 0.85)
			end
			if total.pegsHit <= 4 then
				lowShots += 1
			else
				lowShots = 0
			end
			finishShot()
		end,
	})
	shotPlayer = sp
	if not isPractice then
bank[myUid] = 0
scheduleStrike(myUid, result.outcome.totals.damage, serverStart + result.sim.steps / Config.Sim.STEP_HZ + Config.Combat.STRIKE_DELAY)
	end
	-- Launch feel: barrel recoil, muzzle sparks, frame kick.
	cabinet:kick(1)
	cabinet:shakeFrame(0.08)
	Fx.sparks(cabinet.muzzle.WorldPosition, ball.color, 12)
	Audio.play("launch", { pitch = 1 + (slot - 1) * 0.06 })
	return result.fingerprint
end

local function tryLaunch()
	if not canLaunch() then
		Audio.play("reject")
		return
	end
	Screens.clearTip()
	local aim = AimInput.get()
	if practice then
		startLocalShot(aim, 1, { ballId = "basic", components = {}, enemyHpFrac = 1 }, serverNow(), true)
		return
	end
	local enc = encSnap :: any
	local p = myEncPlayer() :: any
	local mm = myMember() :: any
	local ballId = p.rack[selectedSlot]
	local loadout: Scoring.Loadout = {
		ballId = ballId,
		components = table.clone(mm.components),
		charge = p.charge,
		enemyHpFrac = enc.hp / enc.maxHp,
		ballBonus = (mm.ballLevels or {})[ballId] or 0,
	}
	localSeq = math.max(localSeq, p.seq) + 1
	local seq = localSeq
	local est = serverNow() + 0.06
	local fp = startLocalShot(aim, selectedSlot, loadout, est, false)
	pendingShots[seq] = { fingerprint = fp, startAt = est }
	Net.send("launch", { seq = seq, slot = selectedSlot, aim = aim, boardRev = Boards.ById[enc.boardId].rev, predicted = fp })
	-- Optimistic cooldown display until the server's state arrives.
	local cds = table.clone(p.cooldowns)
	for i = 1, #cds do
		if cds[i] > 0 then
			cds[i] -= 1
		end
	end
	local def = Balls.ById[ballId]
	if def.cooldown > 0 then
		local cd = def.cooldown
		for _, cid in mm.components do
			local c = Components.ById[cid]
			if c and c.cooldownReduce then
				cd -= c.cooldownReduce
			end
		end
		cds[selectedSlot] = math.max(1, cd) + (if enc.modifiers and enc.modifiers.slow_rack then 1 else 0)
	end
	optimisticCooldowns = cds
	if p.charge then
		local from = p.charge.from
		Audio.play("chargeUse")
		Fx.callout(if from == myUid then "RELAY BOOST!" else `BOOST FROM {string.upper(playerName(from))}!`, C.purple, 1.05)
		Fx.arc(hud:chargeSlotScreenPos(), Fx.toScreen(cabinet.muzzle.WorldPosition), C.purple, 0.35, nil)
	end
	-- Back to the basic ball after a special so the next shot is never blocked.
	if selectedSlot > 1 then
		selectedSlot = 1
	end
	refreshHud()
end

local function selectSlot(slot: number)
	local p = myEncPlayer()
	local rackSize = if p then #p.rack else 1
	if slot == -1 then
		slot = ((selectedSlot - 2) % rackSize) + 1
	elseif slot == -2 then
		slot = (selectedSlot % rackSize) + 1
	end
	if slot < 1 or slot > rackSize then
		return
	end
	selectedSlot = slot
	Audio.play("click", { pitch = 1 + slot * 0.08 })
	refreshHud()
end

-- Teammate shot: re-simulate from its inputs on their mini board, and show
-- its hits on the shared monster at the right moments.
local function teammateShot(ev: { [string]: any })
	local bdef = Boards.ById[ev.boardId]
	if bdef == nil or bdef.rev ~= ev.boardRev then
		return
	end
	local result = Shot.resolve({ boardId = ev.boardId, boardRev = ev.boardRev, aim = ev.aim, loadout = ev.loadout })
	local offset = math.max(0, serverNow() - ev.startAt)
	teammates:play(ev.uid, result.sim, result.outcome.hits, offset)
	local uid = ev.uid
	bank[uid] = 0
	-- Their damage gathers over their hero as their ball earns it.
	for _, h in result.outcome.hits do
		local t = ev.startAt + h.step / Config.Sim.STEP_HZ
		local delayTime = t - serverNow()
		if delayTime >= -0.05 and h.damage > 0 then
			task.delay(math.max(0, delayTime), function()
				bank[uid] = (bank[uid] or 0) + h.damage
				local hero = heroOf(uid)
				if hero then
					hero:bank(bank[uid])
				end
			end)
		end
		if h.charge then
			task.delay(math.max(0, delayTime), function()
				local hero = heroOf(uid)
				if hero then
					hero:castSupport()
				end
			end)
		end
	end
	scheduleStrike(uid, result.outcome.totals.damage, ev.startAt + result.sim.steps / Config.Sim.STEP_HZ + Config.Combat.STRIKE_DELAY)
end

-- Encounters, cutscenes, and run flow ---------------------------------------

local function enterFightView()
	clearHeroes(lobbyHeroes)
	Director.toFight()
	menu.show(false)
	hud:setVisible(true)
	AimInput.setEnabled(true)
	guide:setVisible(not (runSnap and (runSnap :: any).modifiers and (runSnap :: any).modifiers.blind))
end

local function closeWaiting()
	if waiting then
		(waiting :: Screens.Waiting).close()
		waiting = nil
	end
	practice = false
end

local function setupEncounter(run: { [string]: any }, enc: { [string]: any }, introEvent: { [string]: any }?)
	closeWaiting()
	if endModal then
		(endModal :: Screens.Modal).close()
		endModal = nil
	end
	local pal = legPalette(run.index)
	local act = actOf(run)
	Scenery.setScene(act.scene, act.palette)
	cabinet:setPalette(pal, false)
	setBoard(enc.boardId, act.palette.glow)
	setMonster(enc.enemyId, enc.id)
	visualHits = {}
	pendingShots = {}
	localSeq = 0
	optimisticCooldowns = nil
	selectedSlot = 1
	lowShots = 0
	enterFightView()
	local def = Enemies.ById[enc.enemyId]
	local remaining = enc.startAt - serverNow()
	local kind: "intro" | "fight" | "boss" | "leg" = if introEvent and introEvent.intro >= 3.9 and not def.boss and run.index <= 1 then "intro" elseif def.boss then "boss" else "fight"
	local elite = introEvent ~= nil and introEvent.elite == true
	local cutId = "cut_" .. kind
	local skippable = seen(cutId)
	if remaining > 0.6 then
		cutsceneUntil = os.clock() + remaining
		Director.play({
			kind = kind,
			duration = math.min(5, remaining),
			skippable = skippable,
			autoSkip = skippable and settingsState.skipSeen,
			title = (if elite then "ELITE · " else "") .. string.upper(def.name),
			sub = def.blurb,
			color = if def.boss or elite then C.red else C.gold,
			monsterReveal = function(seconds)
				local m = monster
				if m then
					m:revealIn(seconds)
				end
			end,
			monsterHead = function()
				local m = monster
				return if m then m:headPosition() else Layout.MONSTER_BASE
			end,
			legTitle = nil,
			onLegShift = function()
				cabinet:cheer(1.5)
			end,
			onDone = function()
				cutsceneUntil = 0
				markSeen(cutId)
				Director.toFight()
				refreshHud()
				-- First-session teaching, introduced when useful.
				if not seen("tip_aim") then
					markSeen("tip_aim")
					local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
					Screens.tip(if touch then "Drag on the board to aim. Every peg your ball hits powers your hero's strike." else "Aim with the mouse. Every peg your ball hits powers your hero's strike.", UDim2.fromScale(0.52, 0.36))
				end
			end,
		})
	else
		Director.toFight()
		local m = monster
		if m then
			m:revealIn(0.4)
		end
	end
	lastEncId = enc.id
	refreshHud()
end

local function closeMap()
	if mapView then
		(mapView :: MapScreen.View).close()
		mapView = nil
	end
end

local function closeRest()
	if restModal then
		(restModal :: Screens.Rest).modal.close()
		restModal = nil
		restOpenFor = ""
	end
end

local function backToWorkshop()
	if draftModal then
		(draftModal :: Screens.Draft).modal.close()
		draftModal = nil
	end
	closeMap()
	closeRest()
	closeWaiting()
	setMonster(nil, "")
	clearHeroes(heroes)
	hud:setVisible(false)
	AimInput.setEnabled(false)
	guide:setVisible(false)
	teammates:clear()
	runSnap = nil
	encSnap = nil
	lastRunState = ""
	lastEncId = ""
	Scenery.applyLighting(actOf(nil).palette, "lobby")
	Director.toWorkshop()
	menu.show(true)
	menu.setProfile(profile)
	menu.setLobby(lobby)
	syncLobbyHeroes()
end

local function showRunResults(run: { [string]: any })
	local rows = {}
	local squad = 0
	for i, m in run.members do
		table.insert(rows, {
			name = if m.uid == myUid then "You" else playerName(m.uid),
			seat = i,
			damage = m.stats.damage,
			biggest = m.stats.biggestShot,
			sent = m.stats.chargesSent,
			used = m.stats.chargesUsed,
			guarded = m.stats.guarded,
			mended = m.stats.mended,
			blocked = m.stats.blocked,
		})
		squad += m.stats.damage
	end
	local minutes = (serverNow() - run.startedAt) / 60
	if run.mode == "test" then
		local o = run.lastOutcome or {}
		endModal = Screens.results(
			string.format("TEST · %s · %s", string.upper(tostring(run.condition)), if o.won then "WON" else "LOST"),
			rows,
			squad,
			(o.duration or 0) / 60,
			"RUN AGAIN",
			function()
				Net.send("rematch")
			end,
			function()
				Net.send("leaveRun")
			end
		)
		return
	end
	endModal = Screens.results("THE ABYSS IS CONQUERED", rows, squad, minutes, "DESCEND AGAIN", function()
		Net.send("rematch")
	end, function()
		Net.send("leaveRun")
	end)
	cabinet:cheer(4)
end

local function onDraft(payload: { [string]: any })
	local run = runSnap
	if run == nil then
		return
	end
	local key = `{(run :: any).id}:{(run :: any).index}`
	local mm = myMember()
	local rack = if mm then mm.rack else { "basic" }
	if draftModal and draftOpenFor == key then
		local d = draftModal :: Screens.Draft
		d.setDeadline(payload.deadline, serverNow())
		d.setPicked(payload.picked)
		d.update(payload.offer, payload.rerolls)
		return
	end
	if draftModal then
		(draftModal :: Screens.Draft).modal.close()
	end
	draftOpenFor = key
	AimInput.setEnabled(false)
	local dk = (run :: any).draftKind
	local title = if dk == "treasure" then "A relic cache: take one" elseif dk == "elite" then `Elite spoils: +{Config.Combat.ELITE_SPOILS_MAX_HULL} max health for everyone` elseif dk == "boss" then "The boss falls. Choose, then the next act begins." else "Victory: choose a reward"
	draftModal = Screens.draft(payload.offer, rack, payload.rerolls, payload.fallback, title, function(choice, slot)
		Net.send("pick", { choice = choice, slot = slot })
		if draftModal then
			(draftModal :: Screens.Draft).setPicked(true)
		end
	end, function()
		Net.send("reroll")
	end)
	local d = draftModal :: Screens.Draft
	d.setDeadline(payload.deadline, serverNow())
	d.setPicked(payload.picked)
end

local function updateMapAndRest(run: { [string]: any })
	local st = run.state
	if st == "map" then
		if mapView == nil then
			AimInput.setEnabled(false)
			guide:setVisible(false)
			enterFightView()
			AimInput.setEnabled(false)
			Scenery.setScene(actOf(run).scene, actOf(run).palette)
			cabinet:setPalette(legPalette(), false)
			mapView = MapScreen.open(hud.root.Parent :: Instance, function(nodeId)
				Net.send("vote", { nodeId = nodeId })
			end)
		end
		(mapView :: MapScreen.View).update(run, serverNow())
	elseif mapView then
		closeMap()
	end
	if st == "rest" then
		local key = `{run.id}:{run.index}`
		local mm = myMember()
		if restModal == nil or restOpenFor ~= key then
			closeRest()
			restOpenFor = key
			AimInput.setEnabled(false)
			local heal = if mm then math.floor(mm.maxHull * Config.Combat.REST_HEAL_FRACTION + 0.5) else 0
			if mm then
				heal = math.min(heal, mm.maxHull - mm.hull)
			end
			restModal = Screens.rest(if mm then mm.rack else { "basic" }, heal, function()
				Net.send("rest", { choice = "heal" })
			end, function(slot)
				Net.send("rest", { choice = "train", slot = slot })
			end)
		end
		local rm = restModal :: Screens.Rest
		rm.setDeadline(run.stateEndsAt, serverNow())
		local waitingOn = {}
		for _, m in run.members do
			if m.status == "active" and m.restChoice == nil then
				table.insert(waitingOn, if m.uid == myUid then "you" else playerName(m.uid))
			end
			if m.uid == myUid then
				rm.setChosen(m.restChoice ~= nil)
			end
		end
		rm.setStatus(if #waitingOn > 0 then "Waiting for " .. table.concat(waitingOn, ", ") else "Everyone has chosen.")
	elseif restModal then
		closeRest()
	end
end

local function onRunStateChanged(run: { [string]: any }, prev: string)
	local st = run.state
	if st ~= "draft" and draftModal then
		(draftModal :: Screens.Draft).modal.close()
		draftModal = nil
		draftOpenFor = ""
	end
	if st == "fight" and practice == false then
		AimInput.setEnabled(true)
	end
	if st == "finished" then
		AimInput.setEnabled(false)
		task.delay(1.2, function()
			if runSnap and (runSnap :: any).state == "finished" and endModal == nil then
				showRunResults(runSnap :: any)
			end
		end)
	elseif st == "lost" and prev ~= "lost" then
		AimInput.setEnabled(false)
		task.delay(0.8, function()
			if runSnap and (runSnap :: any).state == "lost" then
				endModal = Screens.defeat(function()
					Net.send("restart")
				end, function()
					Net.send("leaveRun")
				end)
			end
		end)
	end
end

local function onState(payload: { [string]: any })
	local run = payload.run
	local enc = payload.enc
	runSnap = run
	snapTime = payload.serverTime
	local prevEnc = encSnap
	encSnap = enc
	-- Prune predicted hits the server has already counted.
	local kept = {}
	for _, v in visualHits do
		if v.t > snapTime - 0.5 then
			table.insert(kept, v)
		end
	end
	visualHits = kept
	optimisticCooldowns = nil
	local mm = myMember()
	if mm and mm.status == "waiting" then
		-- Newcomer: practise while the party finishes its fight.
		if waiting == nil then
			waiting = Screens.waiting(function()
				Net.send("leaveRun")
				task.delay(0.3, function()
					Net.send("startRun", { kit = menu.choices.kit, modifiers = {}, families = {}, privacy = "friends", campaign = menu.choices.campaign })
				end)
			end)
			practice = true
			menu.show(false)
			hud:setVisible(true)
			setBoard("warmup", legPalette(1).trim)
			Director.toFight()
			AimInput.setEnabled(true)
			guide:setVisible(true)
		end
		local host = playerName(run.hostUid);
		(waiting :: Screens.Waiting).set(host, run.waitLow, run.waitHigh)
		refreshHud()
		return
	end
	if enc and enc.id ~= lastEncId and run.state == "fight" then
		-- Events arrive before state, so the encounterStart details wait here.
		local intro = pendingIntro
		pendingIntro = nil
		setupEncounter(run, enc, intro)
	end
	if run.state ~= lastRunState then
		local prev = lastRunState
		lastRunState = run.state
		onRunStateChanged(run, prev)
	end
	updateMapAndRest(run)
	-- Defeat → a quiet banner (watching).
	local p = myEncPlayer()
	if p and prevEnc then
		for _, op in (prevEnc :: any).players do
			if op.uid == myUid and not op.defeated and p.defeated then
				hud:showBanner("KNOCKED OUT", "Watching until this fight ends", C.red, 2)
			end
		end
	end
	refreshHud()
end

local function onEvents(list: { { [string]: any } })
	for _, ev in list do
		local t = ev.type
		if t == "encounterStart" then
			pendingIntro = ev
		elseif t == "threatLanding" then
			local m = monster
			if m then
				m:attack()
			end
			Audio.play("telegraph", { pitch = 1.1 })
		elseif t == "threatHit" then
			local m = monster
			for _, r in ev.results do
				local h = heroOf(r.uid)
				if h then
					if r.hull > 0 then
						h:hit()
					end
					if m and not m.dead then
						Fx.bolt(m:centerPosition(), h:headPosition() - Vector3.new(0, 1.5, 0), if r.hull > 0 then C.threat else C.shield, 0.2, nil)
					end
				end
				if r.uid == myUid then
					if r.blocked > 0 then
						Audio.play("shieldBlock")
						Fx.flash(C.shield, 0.25)
						Fx.callout(`BLOCKED {r.blocked}!`, C.shield, 1)
					end
					if r.hull > 0 then
						Audio.play("threatHit")
						Fx.flash(C.red, 0.35)
						cabinet:shakeFrame(0.5)
						Kit.bounce(hud.playerPanel, 0.1)
					end
					if r.spikes > 0 then
						Fx.callout(`SPIKES {r.spikes}!`, C.gold, 0.9)
					end
				else
					teammates:flashCard(r.uid, if r.hull > 0 then C.red else C.shield)
				end
			end
		elseif t == "armorUp" then
			Audio.play("armorUp")
			local m = monster
			if m then
				m:setArmor(true)
			end
			hud:showBanner("ARMOR UP", "Damage breaks armor first", C.armor, 1.4)
		elseif t == "bossPhase" then
			hud:showBanner("PHASE " .. tostring(ev.phase + 1), ev.label, C.red, 2)
			Audio.play("telegraph", { pitch = 0.7 })
			cabinet:shakeFrame(0.3)
		elseif t == "won" then
			local m = monster
			if m then
				Fx.confetti(m:centerPosition(), { C.gold, C.pink, C.cyan, C.purple })
				Fx.ring(m:centerPosition(), C.purple, 10, 0.6)
				Scenery.pulse(2)
				m:die()
				monster = nil
			end
			Audio.play("monsterDeath")
			task.delay(0.25, function()
				Audio.play("victory")
			end)
			cabinet:cheer(2.5)
		elseif t == "encounterWon" then
			-- Victory line names everyone's share of the damage.
			local parts = {}
			local total = 0
			for _, st in ev.perPlayer or {} do
				total += st.damage
			end
			local count = 0
			for uid, st in ev.perPlayer or {} do
				count += 1
				local pct = if total > 0 then math.floor(st.damage / total * 100 + 0.5) else 0
				table.insert(parts, `{if uid == myUid then "You" else playerName(uid)} {pct}%`)
			end
			local mine = ev.perPlayer and ev.perPlayer[myUid]
			local sub = if count > 1 then table.concat(parts, " · ") elseif mine then `Your best strike: {mine.biggestShot}` else nil
			hud:showBanner(if ev.boss then "THE BOSS FALLS" elseif ev.elite then "ELITE SLAIN" else "VICTORY", sub, C.gold, 1.8)
		elseif t == "lost" then
			Audio.play("defeat")
		elseif t == "chargeSent" then
			if ev.to == myUid and ev.from ~= myUid then
				-- A teammate powered us: arc from their card into our slot.
				local from = teammates:screenPos(ev.from)
				if from then
					Fx.arc(from, hud:chargeSlotScreenPos(), C.purple, 0.6, function()
						Audio.play("chargeArrive")
						Fx.callout(`+2 FROM {string.upper(playerName(ev.from))}`, C.purple, 0.9)
					end)
				end
				if not seen("tip_receive") then
					markSeen("tip_receive")
					Screens.tip(`{playerName(ev.from)} sent you a Relay Charge! Your next shot's first hits deal +2.`, UDim2.fromScale(0.26, 0.72), 5)
				end
			end
		elseif t == "chargeReturned" then
			if ev.from == myUid then
				Screens.notice(if ev.reason == "full" then "Their relay slot was full — the charge came back to you." else "They left — the charge came back to you.", C.purpleDeep)
			end
		elseif t == "chargeDropped" then
			if ev.from == myUid then
				Screens.notice("Both relay slots were full, so that charge couldn't be stored.", C.panelLight)
			end
		elseif t == "chargeUsed" then
			if ev.from == myUid and ev.uid ~= myUid then
				teammates:flashCard(ev.uid, C.purple)
				Fx.callout(`{string.upper(playerName(ev.uid))} USED YOUR RELAY!`, C.purple, 0.9)
			end
		elseif t == "idleWarn" and ev.uid == myUid then
			Screens.idleWarning(true)
		elseif t == "idleCleared" and ev.uid == myUid then
			Screens.idleWarning(false)
		elseif t == "observer" and ev.uid == myUid then
			Screens.idleWarning(false)
			hud:showBanner("WATCHING", "You'll rejoin at the next fight", C.textDim, 2)
		elseif t == "rescaled" then
			Screens.notice(`Monster HP adjusted for {ev.active} player{if ev.active == 1 then "" else "s"}.`)
		elseif t == "seatHeld" and ev.uid ~= myUid then
			Screens.notice(`{playerName(ev.uid)} disconnected — their seat is held for 60 s.`)
		elseif t == "admitted" and ev.uid == myUid then
			closeWaiting()
			Screens.notice("You're in! You join the party at this break.", C.greenDeep)
		elseif t == "admitted" then
			Screens.notice(`{playerName(ev.uid)} joined the party!`, C.greenDeep)
		elseif t == "draftFallback" and ev.uid == myUid then
			Screens.notice(`Time ran out, so you repaired 8 health instead.`)
		elseif t == "eliteSpoils" then
			Screens.notice(`Elite spoils: +{ev.maxHull} max health for every hero!`, C.goldDeep)
		elseif t == "actStart" then
			local camp = Campaigns.ById[if runSnap then (runSnap :: any).campaign else Campaigns.DEFAULT]
			local act = if camp then camp.acts[ev.act] else nil
			if act then
				hud:showBanner(string.upper(act.name), act.subtitle, act.palette.accent, 2.4)
			end
		elseif t == "rested" and ev.uid == myUid then
			if ev.choice == "train" then
				Screens.notice("Trained: +1 damage per hit for that ball.", C.goldDeep)
			else
				Screens.notice(`Rested: +{ev.amount} health.`, C.greenDeep)
			end
		elseif t == "pathChosen" then
			Audio.play("whoosh", { pitch = 0.8 })
		end
	end
	refreshHud()
end

local function onShot(ev: { [string]: any })
	if ev.uid == myUid then
		local pending = pendingShots[ev.seq]
		if pending then
			pendingShots[ev.seq] = nil
			-- Re-time our predicted hits to the server's exact start.
			local shift = ev.startAt - pending.startAt
			for _, v in visualHits do
				if math.abs(v.t - pending.startAt) < 9 then
					v.t += shift
				end
			end
			if ev.fingerprint ~= pending.fingerprint then
				warn(`[Cabinet] prediction differed from the server for shot {ev.shotId}`)
			end
		end
		localSeq = math.max(localSeq, ev.seq)
	else
		teammateShot(ev)
	end
end

local function onReject(payload: { [string]: any })
	pendingShots[payload.seq] = nil
	localSeq = 0
	optimisticCooldowns = nil
	local sp = shotPlayer
	if sp then
		sp:destroy()
		shotPlayer = nil
	end
	visualHits = {}
	local b = board
	if b then
		b:refresh(false)
	end
	Audio.play("reject")
	if payload.reason ~= "phase" and payload.reason ~= "not_started" then
		Screens.notice("That shot didn't go through — try again.")
	end
	refreshHud()
end

local function applySettings(s: { [string]: any })
	settingsState.reducedMotion = s.reducedMotion == true
	settingsState.music = s.music or 0.6
	settingsState.sfx = s.sfx or 0.9
	settingsState.skipSeen = s.skipSeen == true
	Kit.Settings.reducedMotion = settingsState.reducedMotion
	Fx.setReducedMotion(settingsState.reducedMotion)
	cabinet.reducedMotion = settingsState.reducedMotion
	local b = board
	if b then
		b.reducedMotion = settingsState.reducedMotion
	end
	local m = monster
	if m then
		m.reducedMotion = settingsState.reducedMotion
	end
	Audio.setVolumes(settingsState.sfx, settingsState.music)
end

-- Avatar copies arrive from the server a moment after joining: swap any
-- stand-in hero for the real avatar once it exists.
local lastHeroCheck = 0
local function upgradeHeroes()
	if os.clock() - lastHeroCheck < 0.5 then
		return
	end
	lastHeroCheck = os.clock()
	local folder = game:GetService("ReplicatedStorage"):FindFirstChild("HeroModels")
	if folder == nil then
		return
	end
	for _, set in { heroes, lobbyHeroes } do
		for uid, h in set do
			if h.fallback and folder:FindFirstChild(tostring(uid)) then
				local nh = Hero.new(heroFolder, uid, h.kit, h.color, h.spot, h.facing)
				nh.reducedMotion = h.reducedMotion
				h:destroy()
				set[uid] = nh
			end
		end
	end
end

-- Per-frame upkeep: aim guide, threat telegraph, HP display.
local function step(_dt: number)
	upgradeHeroes()
	local enc = encSnap
	local now = serverNow()
	local fighting = (enc ~= nil and runSnap ~= nil and (runSnap :: any).state == "fight") or practice
	-- Aim guide follows the chosen ball's physics.
	if fighting and board and not shotPlayer then
		local p = myEncPlayer()
		local ballId = if p and p.rack then p.rack[selectedSlot] or "basic" else "basic"
		local contacts = 1
		local mm = myMember()
		if mm then
			for _, cid in mm.components do
				local c = Components.ById[cid]
				if c and c.guideContacts then
					contacts = math.max(contacts, c.guideContacts)
				end
			end
		end
		guide:update(boardId, Scoring.physicsFor(ballId), AimInput.get(), contacts)
		local dx, dy = AimMath.direction(AimInput.get())
		cabinet:setAim(dx, dy)
	elseif shotPlayer then
		guide:setVisible(false)
	end
	if not shotPlayer and fighting and not (runSnap and (runSnap :: any).modifiers and (runSnap :: any).modifiers.blind) then
		guide:setVisible(true)
	end
	if enc and not practice then
		local tel = (enc :: any).threat
		if tel and (enc :: any).phase == "fight" then
			local secs = tel.landsAt - now
			local armed = now >= tel.warnAt
			local title, detail = threatText(tel)
			hud:setThreat(title, detail, secs, armed)
			local m = monster
			if m then
				m:setTelegraph(if armed then 1 - math.clamp(secs / Config.Combat.THREAT_WARNING, 0, 1) else 0, armed and secs < 3)
			end
			if armed and secs < 9 and tel.kind ~= "armor" and not seen("tip_guard") and not shotPlayer and os.clock() > cutsceneUntil then
				markSeen("tip_guard")
				Screens.tip("The monster is winding up! Hit cyan square GUARD pegs to raise a shield before it lands.", UDim2.fromScale(0.36, 0.3), 6)
			end
		end
		local hp, armor = displayedEnemyHp()
		local def = Enemies.ById[(enc :: any).enemyId]
		hud:setEnemy(def.name, hp, (enc :: any).maxHp, armor, hud.phaseLabel.Text)
		hud.launch.setEnabled(canLaunch())
		-- Relay tip for duos: point out the cross-board choice once.
		local others = 0
		for _, tp in (enc :: any).players do
			if tp.uid ~= myUid and tp.present then
				others += 1
			end
		end
		if others > 0 and not seen("tip_relay") and os.clock() > cutsceneUntil and not shotPlayer and seen("tip_aim") then
			markSeen("tip_relay")
			Screens.tip("Purple RELAY rings empower your ally's next strike. Hit hard now, or set them up?", UDim2.fromScale(0.36, 0.62), 7)
		end
		-- Optional guidance after repeated low-impact shots (no physics change).
		if lowShots >= 2 and not seen("tip_dense") and not shotPlayer then
			markSeen("tip_dense")
			Screens.tip("Tip: aim for crowded areas — gold diamond POWER pegs deal triple.", UDim2.fromScale(0.36, 0.5), 6)
		end
		-- Cosmetic aim sharing for teammate previews (≤ 5 Hz).
		if os.clock() - lastAimSent > 0.2 and not shotPlayer and others > 0 then
			lastAimSent = os.clock()
			Net.sendAim(AimInput.get())
		end
	end
end

-- Boot ----------------------------------------------------------------------

function Game.start(gui: ScreenGui, root: Frame)
	worldRoot = Instance.new("Folder")
	worldRoot.Name = "CabinetWorld"
	worldRoot.Parent = workspace

	Audio.init()
	Fx.init(worldRoot, gui)
	Screens.init(gui, root)
	Director.init(root)

	Scenery.init(worldRoot)
	local firstAct = actOf(nil)
	Scenery.setScene(firstAct.scene, firstAct.palette)
	Scenery.applyLighting(firstAct.palette, "lobby")
	hall = LobbyHall.build(worldRoot)
	heroFolder = Instance.new("Folder")
	heroFolder.Name = "Heroes"
	heroFolder.Parent = worldRoot
	cabinet = Cabinet.new(worldRoot, legPalette())
	setBoard("warmup", firstAct.palette.glow)
	guide = Guide.new(worldRoot)
	guide:setVisible(false)

	hud = Hud.new(root, selectSlot, tryLaunch, function()
		local inRun = runSnap ~= nil
		Screens.settings(settingsState, function(s)
			applySettings(s)
			Net.send("settings", { reducedMotion = s.reducedMotion, music = s.music, sfx = s.sfx, skipSeen = s.skipSeen })
		end, if inRun then function()
			Net.send("leaveRun")
		end else nil)
	end, function()
		Screens.pegKey()
	end)
	hud:setVisible(false)
	teammates = Teammates.new(root, function(uid)
		Net.send("setRecipient", { uid = uid })
		Audio.play("click")
	end)
	local function lists(ch: LobbyMenu.Choices): ({ string }, { string })
		local mods = {}
		for id, on in ch.modifiers do
			if on then
				table.insert(mods, id)
			end
		end
		local fams = {}
		for id, on in ch.families do
			if on then
				table.insert(fams, id)
			end
		end
		return mods, fams
	end
	local function openSettings()
		local inRun = runSnap ~= nil
		Screens.settings(settingsState, function(s)
			applySettings(s)
			Net.send("settings", { reducedMotion = s.reducedMotion, music = s.music, sfx = s.sfx, skipSeen = s.skipSeen })
		end, if inRun then function()
			Net.send("leaveRun")
		end else nil)
	end
	menu = LobbyMenu.new(root, {
		onSolo = function(ch)
			local mods, fams = lists(ch)
			Net.send("startRun", { kit = ch.kit, modifiers = mods, families = fams, privacy = ch.privacy, campaign = ch.campaign })
		end,
		onCreateParty = function(ch)
			Net.send("createParty", { kit = ch.kit, campaign = ch.campaign, privacy = ch.privacy })
		end,
		onJoinParty = function(partyId, kit)
			Net.send("joinParty", { partyId = partyId, kit = kit })
		end,
		onLeaveParty = function()
			Net.send("leaveParty")
		end,
		onReady = function(ready)
			Net.send("partyReady", { ready = ready })
		end,
		onStartParty = function(ch)
			local mods, fams = lists(ch)
			Net.send("startParty", { modifiers = mods, families = fams })
		end,
		onPartyKit = function(kit)
			Net.send("partyKit", { kit = kit })
		end,
		onPartyCampaign = function(campaign)
			Net.send("partyCampaign", { campaign = campaign })
		end,
		onContinue = function()
			Net.send("continueRun")
		end,
		onJoinRun = function(runId, kit)
			Net.send("joinRun", { runId = runId, kit = kit })
		end,
		onTrail = function(id)
			Net.send("equipTrail", { id = id })
		end,
		onDevTest = function(condition)
			Net.send("devTest", { condition = condition })
		end,
		onGallery = function()
			menu.show(false)
			clearHeroes(lobbyHeroes)
			Director.toFight()
			Gallery.start(worldRoot, root, function()
				backToWorkshop()
			end)
		end,
		onSettings = openSettings,
		onClassPreview = function(_kitId)
			Audio.play("click")
			if runSnap == nil then
				syncLobbyHeroes()
			end
		end,
	})

	AimInput.init({
		onAim = function(_a)
			if seen("tip_aim") and not seen("tip_launch") and not shotPlayer then
				markSeen("tip_launch")
				local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
				Screens.tip(if touch then "Tap LAUNCH to fire." else "Click or press Space to fire.", UDim2.new(1, -230, 1, -230))
			end
		end,
		onLaunch = tryLaunch,
		onSlot = selectSlot,
		onActivity = function()
			Net.send("activity")
		end,
	})

	Net.init()
	Net.on("profile", function(p)
		profile = p
		applySettings(p.settings or {})
		if p.saveNote then
			Screens.notice(p.saveNote, C.panelLight)
		end
		menu.setProfile(p)
	end)
	Net.on("lobby", function(payload)
		lobby = payload
		menu.setLobby(payload)
		if runSnap == nil and not Gallery.active() then
			backToWorkshop()
		end
	end)
	Net.on("state", onState)
	Net.on("events", onEvents)
	Net.on("shot", onShot)
	Net.on("reject", onReject)
	Net.on("draft", onDraft)
	Net.on("notice", function(p)
		Screens.notice(p.text)
	end)
	Net.on("unlock", function(p)
		local def = Cosmetics.ById[p.id]
		if def then
			Screens.notice(`New trail unlocked: {def.name}!`, C.greenDeep)
		end
	end)
	Net.on("testResult", function(p)
		menu.setTestLog(p.history)
	end)
	Net.onAim(function(uid, aim)
		teammates:aim(uid, aim)
	end)

	RunService.RenderStepped:Connect(step)

	-- Controls are ready: the scene, board, and inputs exist. The server
	-- starts a new player's first run immediately on this message.
	Net.send("ready", { device = AimInput.device(), reducedMotion = false })
end

return Game
