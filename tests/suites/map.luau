--!nocheck
-- Act maps, party votes, campfires, treasure, elites, and resume.

local function newRun(T, founders, extra)
	local Run = T.Loader.server("Run.RunCore")
	local p = { id = "r", seed = "map-seed", hostUid = 1, now = 0, modifiers = {}, familyPool = {}, privacy = "open", mode = "normal", maxParty = 4, firstIntro = false, campaign = "abyss" }
	for k, v in extra or {} do
		p[k] = v
	end
	return Run.new(p, founders), Run
end

local function winFight(Run, run, t)
	run.encounter.hp = 0
	run.encounter.phase = "won"
	Run.tick(run, t)
	Run.tick(run, t + Run.RESULT_BEAT + 0.01)
end

return {
	{
		name = "maps are deterministic, linked, and always offer a campfire before the boss",
		run = function(T)
			local MapGen = T.Loader.shared("Sim.MapGen")
			local Campaigns = T.Loader.shared("Content.Campaigns")
			local camp = Campaigns.ById.abyss
			for seedN = 1, 40 do
				for act = 1, #camp.acts do
					local seed = "s" .. seedN
					local a = MapGen.generate("abyss", act, seed)
					local b = MapGen.generate("abyss", act, seed)
					T.eq(#a.rows, MapGen.ROWS, "rows")
					local hasRest = false
					for r, row in a.rows do
						T.eq(#row, #b.rows[r], "same shape for the same seed")
						for i, n in row do
							T.eq(n.kind, b.rows[r][i].kind, "same kinds for the same seed")
							T.check(#n.next >= 1, "no dead ends")
							for _, id in n.next do
								T.check(a.byId[id] ~= nil and a.byId[id].row == r + 1, "links go to the next row")
							end
							if n.kind == "fight" or n.kind == "elite" then
								T.check(n.enemy ~= nil and n.board ~= nil, "fights have an enemy and board")
								local inPool = table.find(camp.acts[act].pool, n.enemy) ~= nil or n.enemy == camp.acts[act].opener
								T.check(inPool, "enemy from this act's pool")
							end
							if n.kind == "rest" then
								hasRest = true
								T.eq(r, MapGen.ROWS, "campfire sits before the boss")
							end
						end
					end
					T.check(hasRest, "a campfire is always on the map")
					-- Every next-row node is reachable from some node.
					for r = 2, MapGen.ROWS do
						for _, n in a.rows[r] do
							local reached = false
							for _, p in a.rows[r - 1] do
								if table.find(p.next, n.id) then
									reached = true
								end
							end
							T.check(reached, "every node is reachable")
						end
					end
					if act == 1 then
						T.eq(#a.rows[1], 1, "act I opens with one gentle fight")
						T.eq(a.rows[1][1].enemy, camp.acts[1].opener, "the opener")
					end
				end
			end
		end,
	},
	{
		name = "votes: majority wins, host breaks ties, no votes takes the first choice",
		run = function(T)
			local run, Run = newRun(T, { { uid = 1, kit = "relay" }, { uid = 2, kit = "guard" }, { uid = 3, kit = "ricochet" } })
			Run.tick(run, Run.MAP_SINGLE_SECONDS + 0.01)
			winFight(Run, run, 5)
			for _, uid in { 1, 2, 3 } do
				Run.pick(run, uid, 1, 2)
			end
			Run.tick(run, 8)
			T.eq(run.state, "map", "fork")
			local c = run.choices
			T.check(#c >= 2, "at least two options")
			T.eq(Run.vote(run, 1, "nope").reason, "choice", "unknown node rejected")
			Run.vote(run, 1, c[1])
			Run.vote(run, 2, c[2])
			Run.vote(run, 3, c[2])
			T.eq(Run.tallyVotes(run), c[2], "majority")
			Run.vote(run, 3, c[1])
			T.eq(Run.tallyVotes(run), c[1], "2-1 the other way")
			-- Tie: host (1) picks c[2], 2 picks c[1], 3 has not voted.
			run.members[3].vote = nil
			Run.vote(run, 1, c[2])
			Run.vote(run, 2, c[1])
			T.eq(Run.tallyVotes(run), c[2], "host breaks the tie")
			run.members[1].vote = nil
			run.members[2].vote = nil
			T.eq(Run.tallyVotes(run), c[1], "no votes: first choice")
		end,
	},
	{
		name = "campfire: heal or train, defaults to heal",
		run = function(T)
			local run, Run = newRun(T, { { uid = 1, kit = "relay" }, { uid = 2, kit = "guard" } })
			local MapGen = T.Loader.shared("Sim.MapGen")
			-- Jump straight to the campfire node of row 3.
			local rest
			for _, n in run.map.rows[MapGen.ROWS] do
				if n.kind == "rest" then
					rest = n
				end
			end
			run.members[1].hull = 10
			run.members[2].hull = 10
			run.choices = { rest.id }
			Run.vote(run, 1, rest.id)
			run.stateEndsAt = 0
			Run.tick(run, 1)
			T.eq(run.state, "rest", "campfire")
			T.check(Run.chooseRest(run, 1, "train", 2).ok, "train a ball")
			T.eq(Run.chooseRest(run, 1, "heal").reason, "already_chosen", "one choice")
			T.eq(Run.chooseRest(run, 2, "train", 9).reason, "slot", "bad slot rejected")
			local ball = run.members[1].rack[2]
			Run.tick(run, 1 + 20.1)
			T.eq(run.members[1].ballLevels[ball], 1, "trained ball levelled up")
			T.check(run.members[2].hull > 10, "unchosen defaults to heal")
			T.eq(run.state, "map", "on to the boss vote")
			T.eq(#run.choices, 1, "only the boss remains")
			T.eq(run.map.byId[run.choices[1]].kind, "boss", "boss next")
		end,
	},
	{
		name = "treasure offers relics only; elite wins grant spoils",
		run = function(T)
			local run, Run = newRun(T, { { uid = 1, kit = "ricochet" } })
			local MapGen = T.Loader.shared("Sim.MapGen")
			local treasure, elite
			for _, n in run.map.rows[2] do
				if n.kind == "treasure" then
					treasure = n
				elseif n.kind == "elite" then
					elite = n
				end
			end
			run.choices = { treasure.id }
			Run.vote(run, 1, treasure.id)
			run.stateEndsAt = 0
			Run.tick(run, 1)
			T.eq(run.state, "draft", "treasure opens a draft")
			T.eq(run.draftKind, "treasure", "treasure kind")
			for _, o in run.members[1].offer do
				T.eq(o.kind ~= "ball", true, "no balls in treasure")
			end
			-- Elite: tougher monster, spoils after the win.
			local run2, Run2 = newRun(T, { { uid = 1, kit = "ricochet" } }, { seed = "map-seed" })
			run2.choices = { elite.id }
			Run2.vote(run2, 1, elite.id)
			run2.stateEndsAt = 0
			Run2.tick(run2, 1)
			T.eq(run2.state, "fight", "elite fight")
			local Enemies = T.Loader.shared("Content.Enemies")
			local Config = T.Loader.shared("Config")
			local base = Enemies.ById[elite.enemy].hp
			T.eq(run2.encounter.maxHp, math.floor(base * Config.Combat.ELITE_HP_MULT + 0.5), "elite HP multiplier")
			local before = run2.members[1].maxHull
			winFight(Run2, run2, 5)
			T.eq(run2.members[1].maxHull, before + Config.Combat.ELITE_SPOILS_MAX_HULL, "elite spoils")
			T.eq(run2.draftKind, "elite", "elite draft")
		end,
	},
	{
		name = "resume rebuilds the same map and continues from the saved node",
		run = function(T)
			local MapGen = T.Loader.shared("Sim.MapGen")
			local m = MapGen.generate("abyss", 2, "resume-seed")
			local at = m.rows[1][1].id
			local run, Run = newRun(T, { { uid = 1, kit = "guard" } }, { seed = "resume-seed", resume = { act = 2, atNode = at, index = 4 } })
			T.eq(run.act, 2, "act restored")
			T.eq(run.state, "map", "starts at the fork")
			local expected = MapGen.choices(m, at)
			T.eq(#run.choices, #expected, "same choices as before")
			for i, n in expected do
				T.eq(run.choices[i], n.id, "same node ids")
			end
		end,
	},
}
