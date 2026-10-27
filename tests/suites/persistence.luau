--!nocheck
-- Profiles: session lock, failed-load protection, migrations, repeat-safe grants.

local function deps(T, backend, job, clockRef)
	local logs = {}
	return {
		backend = backend,
		jobId = job,
		clock = function()
			return clockRef.t
		end,
		wait = function(s)
			clockRef.t += s
		end,
		jitter = function()
			return 0.5
		end,
		log = function(m)
			table.insert(logs, m)
		end,
	}, logs
end

return {
	{
		name = "fresh profile loads, saves, and releases",
		run = function(T)
			local PS = T.Loader.server("Persistence.ProfileStore")
			local backend = PS.memoryBackend()
			local clock = { t = 1000 }
			local store = PS.new(deps(T, backend, "jobA", clock))
			local s = PS.load(store, 7)
			T.eq(s.status, "loaded", "loaded")
			T.check(s.canSave, "can save")
			s.profile.stats.shots = 12
			T.check(PS.save(store, 7, true), "release save")
			T.eq(backend.store.u_7.data.stats.shots, 12, "data stored")
			T.eq(backend.store.u_7.lock, nil, "lock released")
		end,
	},
	{
		name = "a second server cannot take a live lock; takes over after it goes stale",
		run = function(T)
			local PS = T.Loader.server("Persistence.ProfileStore")
			local backend = PS.memoryBackend()
			local clock = { t = 1000 }
			local a = PS.new(deps(T, backend, "jobA", clock))
			PS.load(a, 7)
			a.sessions[7].profile.stats.shots = 5
			PS.save(a, 7)
			local b = PS.new(deps(T, backend, "jobB", clock))
			local sb = PS.load(b, 7)
			T.eq(sb.status, "failed", "live lock blocks the second server")
			T.check(not sb.canSave, "failed session never saves")
			T.eq(backend.store.u_7.data.stats.shots, 5, "existing progress untouched")
			clock.t += 400
			local sb2 = PS.load(b, 7)
			T.eq(sb2.status, "loaded", "stale lock is taken over")
			T.eq(sb2.profile.stats.shots, 5, "progress carried over")
			T.check(not PS.save(a, 7), "the old server cannot save after losing the lock")
			T.eq(a.sessions[7].status, "lost", "old session marked lost")
		end,
	},
	{
		name = "failed load never overwrites stored progress",
		run = function(T)
			local PS = T.Loader.server("Persistence.ProfileStore")
			local backend = PS.memoryBackend()
			backend.store.u_9 = { data = { version = 2, stats = { shots = 99 } }, lock = nil }
			backend.failNext = 10
			local clock = { t = 0 }
			local store = PS.new(deps(T, backend, "jobA", clock))
			local s = PS.load(store, 9)
			T.eq(s.status, "failed", "load failed after retries")
			T.eq(s.profile.stats.shots, 0, "session plays on defaults")
			backend.failNext = 0
			T.check(not PS.save(store, 9, true), "no save from a failed session")
			T.eq(backend.store.u_9.data.stats.shots, 99, "stored progress intact")
			T.check(clock.t > 0, "retries backed off")
		end,
	},
	{
		name = "newer stored version is refused, not downgraded",
		run = function(T)
			local PS = T.Loader.server("Persistence.ProfileStore")
			local backend = PS.memoryBackend()
			backend.store.u_3 = { data = { version = 99, stats = { shots = 1 } } }
			local store = PS.new(deps(T, backend, "jobA", { t = 0 }))
			local s = PS.load(store, 3)
			T.eq(s.status, "failed", "refused")
			T.eq(backend.store.u_3.data.version, 99, "untouched")
		end,
	},
	{
		name = "v1 data migrates to v2 and keeps progress",
		run = function(T)
			local Schema = T.Loader.server("Persistence.Schema")
			local data = { trail = "spark", stats = { shots = 40, runsFinished = 2 }, unlocked = { default = true, spark = true } }
			local p = Schema.migrate(data, 0)
			T.eq(p.version, 2, "version bumped")
			T.eq(p.equippedTrail, "spark", "trail moved to new field")
			T.eq(p.stats.shots, 40, "stats kept")
			T.eq(p.stats.biggestShot, 0, "new stat defaulted")
			T.check(p.familyPool.relay == true, "new field defaulted")
			local again = Schema.migrate(p, 0)
			T.eq(again.version, 2, "migration is repeatable")
		end,
	},
	{
		name = "rewards are granted once per id",
		run = function(T)
			local Schema = T.Loader.server("Persistence.Schema")
			local p = Schema.default(0)
			local n = 0
			Schema.grantOnce(p, "run:abc:boss1", function()
				n += 1
			end)
			Schema.grantOnce(p, "run:abc:boss1", function()
				n += 1
			end)
			T.eq(n, 1, "second grant ignored")
		end,
	},
	{
		name = "protocol rejects malformed requests",
		run = function(T)
			local P = T.Loader.shared("Net.Protocol")
			T.check(P.validate("launch", { seq = 1, slot = 1, aim = 0, boardRev = 1, predicted = "x" }) ~= nil, "valid launch")
			local _, r1 = P.validate("launch", { seq = 1, slot = 1, aim = 0.5, boardRev = 1 })
			T.eq(r1, "bad_aim", "fractional aim")
			local _, r2 = P.validate("launch", { seq = 1, slot = 1, aim = 0, boardRev = 1, damage = 999 })
			T.eq(r2, "unknown_field", "client damage field rejected")
			local _, r3 = P.validate("nuke", {})
			T.eq(r3, "unknown_kind", "unknown kind")
			local _, r4 = P.validate("launch", "x")
			T.eq(r4, "payload", "non-table payload")
			local _, r5 = P.validate("startRun", { kit = string.rep("a", 200) })
			T.eq(r5, "bad_kit", "oversized string")
			local _, r6 = P.validate("launch", { slot = 1, aim = 0, boardRev = 1 })
			T.eq(r6, "missing_seq", "missing sequence")
			local RL = T.Loader.server("Validation.RateLimit")
			local rl = RL.new(12, 12)
			local allowed = 0
			for _ = 1, 30 do
				if RL.allow(rl, 1, 0) then
					allowed += 1
				end
			end
			T.eq(allowed, 12, "burst limited to 12")
			T.check(RL.allow(rl, 1, 1), "refills over time")
		end,
	},
}
