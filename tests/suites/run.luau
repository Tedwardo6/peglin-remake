--!nocheck
-- Run flow and pacing estimates driven by bots.
local Bot = require("../bot")

local function playRun(T, style, players, opts)
	opts = opts or {}
	local Run = T.Loader.server("Run.RunCore")
	local E = T.Loader.server("Encounter.EncounterCore")
	local founders = {}
	for i = 1, players do
		table.insert(founders, { uid = i, kit = ({ "ricochet", "relay", "guard", "ricochet" })[i] })
	end
	local run = Run.new({
		id = "r", seed = opts.seed or "seed-1", hostUid = 1, now = 0,
		modifiers = opts.modifiers or {}, familyPool = {}, privacy = "open",
		mode = opts.mode or "normal", condition = opts.condition, maxParty = 4, firstIntro = true,
		campaign = "abyss",
	}, founders)
	local rng = Bot.lcg(opts.rngSeed or 7)
	local now = 0
	local THINK = opts.think or 3
	local nextAction = {}
	local fights = {}
	local fightStart = 0
	local losses = 0
	local events = {}
	while now < (opts.limit or 3600) do
		now += 0.1
		Run.tick(run, now)
		for _, ev in Run.drain(run) do
			events[ev.type] = (events[ev.type] or 0) + 1
			if ev.type == "encounterWon" then
				table.insert(fights, { index = ev.index, boss = ev.boss, elite = ev.elite, duration = ev.duration })
			elseif ev.type == "encounterLost" then
				losses += 1
			end
		end
		if run.state == "finished" or run.state == "abandoned" then
			break
		elseif run.state == "lost" then
			if losses > (opts.maxLosses or 3) then
				break
			end
			Run.restart(run, 1, now)
		elseif run.state == "map" then
			for _, m in Run.activeMembers(run) do
				if m.vote == nil then
					local pickIdx = (rng() % #run.choices) + 1
					-- Low hull: head for the campfire when one is offered.
					if m.hull < m.maxHull * 0.5 then
						for i, id in run.choices do
							if run.map.byId[id].kind == "rest" then
								pickIdx = i
							end
						end
					end
					Run.vote(run, m.uid, run.choices[pickIdx])
				end
			end
		elseif run.state == "rest" then
			for _, m in Run.activeMembers(run) do
				if m.restChoice == nil then
					if m.hull < m.maxHull * 0.8 then
						Run.chooseRest(run, m.uid, "heal")
					else
						Run.chooseRest(run, m.uid, "train", 2)
					end
				end
			end
		elseif run.state == "draft" then
			for _, m in Run.activeMembers(run) do
				if not m.picked then
					local slot = nil
					if m.offer[1].kind == "ball" then
						slot = 3
					end
					Run.pick(run, m.uid, 1, slot)
				end
			end
		elseif run.state == "fight" then
			local enc = run.encounter
			if now >= enc.startAt then
				for uid, ps in enc.players do
					if ps.active and ps.present and not ps.defeated and now >= ps.inFlightUntil + THINK and now >= (nextAction[uid] or 0) then
						local soon = enc.nextThreatAt - now < 10
						local aim, slot = Bot.chooseAim(T, enc, ps, style, rng, soon)
						local res = E.launch(enc, uid, { seq = ps.seq + 1, slot = slot, aim = aim, boardRev = enc.boardRev }, now)
						if not res.ok then
							nextAction[uid] = now + 1
						end
					end
				end
			end
		end
	end
	return run, fights, now, losses, events
end

return {
	{
		name = "solo sharp bot completes a run; record pacing",
		run = function(T)
			local run, fights, now, losses, events = playRun(T, "sharp", 1)
			T.eq(run.state, "finished", "run finishes")
			T.check(#fights >= 7 and #fights <= 12, "between 7 and 12 fights won (path-dependent): " .. #fights)
			local parts = {}
			for _, f in fights do
				table.insert(parts, string.format("%d%s:%.0fs", f.index, if f.boss then "B" elseif f.elite then "E" else "", f.duration))
			end
			T.note(string.format("solo sharp: total %.1f min, losses %d | %s", now / 60, losses, table.concat(parts, " ")))
			T.check((events.draftOpen or 0) >= #fights - 1, "a draft after every won fight except the last boss")
			T.check((events.bossDefeated or 0) == 3, "three bosses")
			T.eq(events.actStart or 0, 2, "two act transitions")
			T.eq(events.pathChosen or 0, 12, "twelve nodes chosen (4 per act)")
		end,
	},
	{
		name = "solo casual bot pacing (random aim)",
		run = function(T)
			local run, fights, now, losses = playRun(T, "casual", 1, { maxLosses = 30 })
			local parts = {}
			for _, f in fights do
				table.insert(parts, string.format("%d%s:%.0fs", f.index, if f.boss then "B" elseif f.elite then "E" else "", f.duration))
			end
			T.note(string.format("solo casual: state %s, %.1f min, losses %d | %s", run.state, now / 60, losses, table.concat(parts, " ")))
			T.check(true, "recorded")
		end,
	},
	{
		name = "duo sharp bots complete a run; record pacing and relay use",
		run = function(T)
			local run, fights, now, losses, events = playRun(T, "sharp", 2)
			T.eq(run.state, "finished", "duo run finishes")
			local parts = {}
			for _, f in fights do
				table.insert(parts, string.format("%d%s:%.0fs", f.index, if f.boss then "B" elseif f.elite then "E" else "", f.duration))
			end
			T.note(string.format("duo sharp: total %.1f min, losses %d, charges sent %d used %d | %s", now / 60, losses, events.chargeSent or 0, events.chargeUsed or 0, table.concat(parts, " ")))
		end,
	},
	{
		name = "four sharp bots complete a run (4-player party behind the phone gate)",
		run = function(T)
			local run, fights, now, losses, events = playRun(T, "sharp", 4)
			T.eq(run.state, "finished", "quad run finishes")
			T.eq(#T.Loader.server("Run.RunCore").activeMembers(run), 4, "all four still seated")
			local parts = {}
			for _, f in fights do
				table.insert(parts, string.format("%d%s:%.0fs", f.index, if f.boss then "B" elseif f.elite then "E" else "", f.duration))
			end
			T.note(string.format("quad sharp: total %.1f min, losses %d, charges sent %d used %d | %s", now / 60, losses, events.chargeSent or 0, events.chargeUsed or 0, table.concat(parts, " ")))
		end,
	},
	{
		name = "test mode: identical setup across conditions, finishes with rematch offer",
		run = function(T)
			for _, cond in { "solo", "duo_self", "duo_teammate" } do
				local players = if cond == "solo" then 1 else 2
				local run, fights, now, _, events = playRun(T, "sharp", players, { mode = "test", condition = cond })
				T.eq(run.state, "finished", cond .. " finishes")
				T.eq((events.rematchOffered or 0), 1, cond .. " offers a free rematch")
				local o = run.lastOutcome
				local bonus = 0
				for _, p in o.perPlayer do
					bonus += p.bonusDamage
				end
				T.note(string.format("test %-12s duration %.0fs bonus damage %d", cond, o.duration, bonus))
				T.eq(run.encounter.boardId, "lanes", cond .. " uses the test board")
			end
		end,
	},
	{
		name = "newcomer waits during a fight, is admitted at the draft with a fixed catch-up kit",
		run = function(T)
			local Run = T.Loader.server("Run.RunCore")
			local run = Run.new({ id = "r", seed = "s", hostUid = 1, now = 0, modifiers = {}, familyPool = {}, privacy = "open", mode = "normal", maxParty = 2, firstIntro = false }, { { uid = 1, kit = "ricochet" } })
			Run.tick(run, Run.MAP_SINGLE_SECONDS + 0.01)
			T.eq(run.state, "fight", "the forced first node starts a fight")
			T.check(Run.requestJoin(run, 2, "guard", 1).ok, "join request accepted")
			T.eq(run.members[2].status, "waiting", "waits during the fight")
			T.check(run.encounter.players[2] == nil, "not in the running fight")
			T.eq(Run.requestJoin(run, 3, "relay", 1).reason, "full", "party cap enforced")
			run.encounter.hp = 0
			run.encounter.phase = "won"
			Run.tick(run, 2)
			Run.tick(run, 2 + Run.RESULT_BEAT + 0.01)
			T.eq(run.state, "draft", "draft open")
			T.eq(run.members[2].status, "active", "admitted at the draft")
			local kit1 = table.concat(run.members[2].components, ",")
			T.check(#run.members[2].components == 2, "catch-up: starter + one kit component after one fight")
			Run.pick(run, 1, 2)
			Run.tick(run, 4)
			T.eq(run.state, "map", "path vote opens after the draft")
			T.check(#run.choices >= 2, "a real fork: " .. #run.choices)
			local fightId
			for _, id in run.choices do
				local k = run.map.byId[id].kind
				if k == "fight" or k == "elite" then
					fightId = id
				end
			end
			T.check(Run.vote(run, 1, fightId).ok and Run.vote(run, 2, fightId).ok, "both vote")
			Run.tick(run, 5)
			T.eq(run.state, "fight", "next fight starts")
			T.check(run.encounter.players[2] ~= nil, "newcomer fights")
			local Draft = T.Loader.server("Run.Draft")
			T.eq(table.concat(Draft.catchUp("guard", 1), ","), kit1, "catch-up kit is fixed")
		end,
	},
	{
		name = "draft: three distinct options, kit/flex/wild, reroll once per leg, fallback on deadline",
		run = function(T)
			local Run = T.Loader.server("Run.RunCore")
			local run = Run.new({ id = "r", seed = "s", hostUid = 1, now = 0, modifiers = {}, familyPool = {}, privacy = "open", mode = "normal", maxParty = 2, firstIntro = false }, { { uid = 1, kit = "relay" } })
			Run.tick(run, Run.MAP_SINGLE_SECONDS + 0.01)
			run.encounter.hp = 0
			run.encounter.phase = "won"
			Run.tick(run, 1)
			Run.tick(run, 1 + Run.RESULT_BEAT + 0.01)
			local offer = run.members[1].offer
			T.eq(#offer, 3, "three options")
			T.eq(offer[1].badge, "targeted", "first draft of the leg carries the kit pick")
			T.eq(offer[2].badge, "flex", "flexible option")
			T.eq(offer[3].badge, "wild", "wildcard option")
			T.check(offer[1].id ~= offer[2].id and offer[2].id ~= offer[3].id, "distinct")
			T.check(Run.reroll(run, 1).ok, "free reroll")
			T.eq(Run.reroll(run, 1).reason, "no_rerolls", "only one reroll per leg")
			local hullBefore = run.members[1].hull
			Run.tick(run, 1 + Run.RESULT_BEAT + 20.1)
			T.eq(run.members[1].lastPick, "fallback", "deadline applies the free fallback")
			T.check(run.members[1].hull >= hullBefore, "fallback repairs")
			T.eq(run.state, "map", "path vote next")
		end,
	},
	{
		name = "disconnect holds the seat 60 s and HP rescales immediately",
		run = function(T)
			local Run = T.Loader.server("Run.RunCore")
			local run = Run.new({ id = "r", seed = "s", hostUid = 1, now = 0, modifiers = {}, familyPool = {}, privacy = "open", mode = "normal", maxParty = 2, firstIntro = false }, { { uid = 1, kit = "relay" }, { uid = 2, kit = "guard" } })
			Run.tick(run, Run.MAP_SINGLE_SECONDS + 0.01)
			local enc = run.encounter
			local before = enc.maxHp
			Run.leave(run, 2, 5, true)
			Run.tick(run, 5)
			T.check(enc.maxHp < before, "monster HP rescaled after the departure")
			T.eq(run.members[2].status, "disconnected", "seat held")
			T.check(Run.rejoin(run, 2, 30).ok, "rejoin within 60 s")
			T.eq(run.members[2].status, "waiting", "returns at the next boundary")
		end,
	},
}
