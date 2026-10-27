--!nocheck
-- Solver determinism, bounds, and board sanity.
return {
	{
		name = "boards load with 50-80 pegs and pegs stay inside the board",
		run = function(T)
			local Boards = T.Loader.shared("Content.Boards")
			local Config = T.Loader.shared("Config")
			for _, id in Boards.Order do
				local b = Boards.ById[id]
				T.check(#b.pegs >= 50 and #b.pegs <= 80, `{id} has {#b.pegs} pegs (want 50-80)`)
				for _, p in b.pegs do
					T.check(p.x > 1 and p.x < Config.Board.WIDTH - 1 and p.y > 8 and p.y < Config.Board.HEIGHT, `{id} peg in bounds`)
				end
			end
		end,
	},
	{
		name = "aim quantization round-trips and stays below horizontal",
		run = function(T)
			local Aim = T.Loader.shared("Sim.Aim")
			for a = -Aim.MAX, Aim.MAX, 37 do
				local dx, dy = Aim.direction(a)
				T.check(dy > 0.05, `aim {a} points down`)
				local back = Aim.fromDirection(dx, dy)
				T.check(math.abs(back - a) <= 1, `aim {a} round-trips (got {back})`)
			end
			T.check(Aim.isValid(0) and not Aim.isValid(0.5) and not Aim.isValid(0 / 0) and not Aim.isValid(Aim.MAX + 1), "aim validation")
		end,
	},
	{
		name = "same input gives identical results (replay)",
		run = function(T)
			local Boards = T.Loader.shared("Content.Boards")
			local Solver = T.Loader.shared("Sim.Solver")
			for _, id in Boards.Order do
				local b = Boards.ById[id]
				for a = -1800, 1800, 300 do
					local r1 = Solver.simulate(b, Solver.defaultPhysics(), a)
					local r2 = Solver.simulate(b, Solver.defaultPhysics(), a)
					T.eq(Solver.fingerprint(r1), Solver.fingerprint(r2), `{id} aim {a} replay`)
				end
			end
		end,
	},
	{
		name = "flight is bounded and most shots drain; record longest flight",
		run = function(T)
			local Boards = T.Loader.shared("Content.Boards")
			local Solver = T.Loader.shared("Sim.Solver")
			local Config = T.Loader.shared("Config")
			local worstAll = 0
			for _, id in Boards.Order do
				local b = Boards.ById[id]
				local worst, total, timeouts, hits, n = 0, 0, 0, 0, 0
				for a = -1880, 1880, 20 do
					local r = Solver.simulate(b, Solver.defaultPhysics(), a)
					worst = math.max(worst, r.steps)
					total += r.steps
					n += 1
					if r.endReason == "timeout" then
						timeouts += 1
					end
					local c = 0
					for _ in r.pegFirstHit do
						c += 1
					end
					hits += c
					for s = 1, r.steps do
						local x, y = r.xs[s], r.ys[s]
						if x < 0 or x > Config.Board.WIDTH or y < 0 then
							T.check(false, `{id} aim {a} left the board at step {s}`)
							break
						end
					end
				end
				worstAll = math.max(worstAll, worst)
				T.note(string.format("%-9s pegs=%d avg %.2fs, longest %.2fs, timeouts %d/%d, avg pegs hit %.1f", id, #b.pegs, total / n / 60, worst / 60, timeouts, n, hits / n))
				T.check(timeouts / n < 0.06, `{id}: under 6% of shots should hit the 8 s cap ({timeouts}/{n})`)
			end
			T.check(worstAll <= Config.Sim.MAX_FLIGHT_STEPS, "flight never exceeds the 8 s cap")
		end,
	},
}
