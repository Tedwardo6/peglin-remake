--!nocheck
-- Playthrough bots for balance estimates (not player-behaviour evidence).
--   "sharp": scans aims and takes the best damage/shield shot
--   "casual": takes a random aim
-- Both wait THINK seconds between shots, like a person aiming.
local Bot = {}

function Bot.chooseAim(T, enc, ps, style, rng, threatSoon)
	local Shot = T.Loader.shared("Sim.Shot")
	local slot = 1
	for i = #ps.rack, 2, -1 do
		if ps.cooldowns[i] == 0 then
			slot = i
			break
		end
	end
	if style == "casual" then
		return (rng() % 3761) - 1880, slot
	end
	local best, bestScore = 0, -1
	for a = -1880, 1880, 47 do
		local r = Shot.resolve({
			boardId = enc.boardId,
			boardRev = enc.boardRev,
			aim = a,
			loadout = { ballId = ps.rack[slot], components = ps.components, charge = ps.charge, enemyHpFrac = enc.hp / enc.maxHp, ballBonus = ps.ballLevels[ps.rack[slot]] or 0 },
		})
		local t = r.outcome.totals
		local score = t.damage + t.shield * (if threatSoon then 2 else 0.5) + t.heal + (if t.chargeStep then 6 else 0)
		if score > bestScore then
			best, bestScore = a, score
		end
	end
	return best, slot
end

function Bot.lcg(seed)
	local s = seed
	return function()
		s = (s * 1103515245 + 12345) % 2147483648
		return s
	end
end

return Bot
