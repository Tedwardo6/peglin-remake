--!strict
-- Turns a solver result into consequences: damage, shield, repair, and the
-- one Relay Charge a shot can generate. Pure and deterministic, so the
-- server's authoritative numbers and the client's predicted numbers agree.
-- All modifiers are read from the loadout frozen at launch.

local Balls = require(script.Parent.Parent.Content.Balls)
local Components = require(script.Parent.Parent.Content.Components)
local Pegs = require(script.Parent.Parent.Content.Pegs)
local Solver = require(script.Parent.Solver)

export type Charge = {
	id: string,
	from: number, -- sender user id
	power: number,
	hits: number,
}

export type Loadout = {
	ballId: string,
	components: { string },
	charge: Charge?, -- a received charge consumed by this launch
	enemyHpFrac: number, -- monster HP fraction when the shot launched
	ballBonus: number?, -- +damage per hit from draft upgrades to this ball
}

export type Hit = {
	step: number,
	peg: number?, -- nil for wall events
	kind: string, -- peg kind, or "wall"
	damage: number,
	shield: number,
	heal: number,
	charge: boolean, -- this hit generated the shot's Relay Charge
	burstFrom: number?, -- peg index of the burst that scored this peg
	combo: number, -- peg hits so far this shot, including this one
	bonus: number, -- extra damage this hit gained from a received charge
	big: boolean, -- a highlighted hit (multiplier or large number)
}

export type Totals = {
	damage: number,
	shield: number,
	heal: number,
	chargeStep: number?, -- step at which a charge was generated
	bonusDamage: number, -- realized damage from a received charge
	pegsHit: number,
	biggestHit: number,
	usefulStep: number?, -- first step with any effect
}

export type Outcome = {
	hits: { Hit },
	totals: Totals,
}

type Mods = {
	ordinaryBonus: number,
	powerMult: number,
	wallNextBonus: number,
	burstRadiusMul: number,
	springBonus: number,
	guardBonus: number,
	mendBonus: number,
	finisher: { threshold: number, bonus: number }?,
	opener: { hits: number, bonus: number }?,
	comboEvery: { n: number, bonus: number }?,
	allBonus: number,
}

local Scoring = {}

Scoring.GUARD_SHIELD = 5
Scoring.MEND_HEAL = 3
Scoring.POWER_MULT = 3

local function collectMods(componentIds: { string }): Mods
	local m: Mods = {
		ordinaryBonus = 0,
		powerMult = Scoring.POWER_MULT,
		wallNextBonus = 0,
		burstRadiusMul = 1,
		springBonus = 0,
		guardBonus = 0,
		mendBonus = 0,
		finisher = nil,
		opener = nil,
		comboEvery = nil,
		allBonus = 0,
	}
	for _, id in componentIds do
		local c = Components.ById[id]
		if c then
			m.ordinaryBonus += c.ordinaryBonus or 0
			if c.powerMult and c.powerMult > m.powerMult then
				m.powerMult = c.powerMult
			end
			m.wallNextBonus += c.wallNextBonus or 0
			if c.burstRadiusMul and c.burstRadiusMul > m.burstRadiusMul then
				m.burstRadiusMul = c.burstRadiusMul
			end
			m.springBonus += c.springBonus or 0
			m.guardBonus += c.guardBonus or 0
			m.mendBonus += c.mendBonus or 0
			m.finisher = c.finisher or m.finisher
			m.opener = c.opener or m.opener
			m.comboEvery = c.comboEvery or m.comboEvery
			m.allBonus += c.allBonus or 0
		end
	end
	return m
end

-- Physics parameters for a ball (no component changes physics today).
function Scoring.physicsFor(ballId: string): Solver.BallPhysics
	local b = Balls.ById[ballId]
	return {
		radius = b.radius,
		restitutionMul = b.restitutionMul,
		gravityMul = b.gravityMul,
		wallRestitution = b.wallRestitution,
	}
end

function Scoring.score(board: Solver.Board, sim: Solver.SimResult, loadout: Loadout): Outcome
	local ball = Balls.ById[loadout.ballId]
	local m = collectMods(loadout.components)
	local pegs = board.pegs

	local hits: { Hit } = {}
	local totals: Totals = {
		damage = 0,
		shield = 0,
		heal = 0,
		chargeStep = nil,
		bonusDamage = 0,
		pegsHit = 0,
		biggestHit = 0,
		usefulStep = nil,
	}

	local scored: { [number]: boolean } = {}
	local walls = 0
	local pendingWall = 0
	local damagingHits = 0
	local combo = 0
	local charge = loadout.charge
	local chargeLeft = 0
	local chargePower = 0
	if charge then
		chargeLeft = charge.hits
		chargePower = charge.power
		if ball.chargeHitsWhenUsed and ball.chargeHitsWhenUsed > chargeLeft then
			chargeLeft = ball.chargeHitsWhenUsed
		end
	end
	local finisherOn = m.finisher ~= nil and loadout.enemyHpFrac < (m.finisher :: any).threshold
	local firstPegDone = false

	local function scorePeg(step: number, pi: number, burstFrom: number?)
		scored[pi] = true
		combo += 1
		totals.pegsHit += 1
		local kind = pegs[pi].kind
		local base = ball.damage + m.allBonus + (loadout.ballBonus or 0)
		local dmg = 0
		local shield = 0
		local heal = 0
		local makesCharge = false
		local big = false

		if kind == "ordinary" then
			dmg = base + m.ordinaryBonus
		elseif kind == "power" then
			dmg = base * m.powerMult
			big = true
		elseif kind == "spring" then
			dmg = base + m.springBonus
		elseif kind == "burst" then
			dmg = base
			big = true
		elseif kind == "relay" then
			dmg = ball.relayDamage or 0
			shield += ball.relayShield or 0
			if totals.chargeStep == nil then
				makesCharge = true
				totals.chargeStep = step
			end
		elseif kind == "guard" then
			shield += (Scoring.GUARD_SHIELD + m.guardBonus) * (ball.guardMul or 1)
		elseif kind == "mend" then
			heal += (Scoring.MEND_HEAL + m.mendBonus) * (ball.mendMul or 1)
		end

		local bonus = 0
		if dmg > 0 then
			damagingHits += 1
			local add = 0
			if ball.wallBonus then
				add += ball.wallBonus * walls
			end
			if pendingWall > 0 then
				add += pendingWall
				pendingWall = 0
			end
			if m.opener and damagingHits <= m.opener.hits then
				add += m.opener.bonus
			end
			if finisherOn then
				add += (m.finisher :: any).bonus
			end
			local withoutCharge = dmg + add
			local withCharge = withoutCharge
			if chargeLeft > 0 then
				withCharge += chargePower
				chargeLeft -= 1
			end
			if ball.everyNth and damagingHits % ball.everyNth.n == 0 then
				withoutCharge *= ball.everyNth.mult
				withCharge *= ball.everyNth.mult
				big = true
			end
			dmg = withCharge
			bonus = withCharge - withoutCharge
			if ball.shieldPerHit then
				shield += ball.shieldPerHit
			end
		end
		if m.comboEvery and combo % m.comboEvery.n == 0 then
			dmg += m.comboEvery.bonus
			big = true
		end
		if dmg >= 12 then
			big = true
		end

		totals.damage += dmg
		totals.shield += shield
		totals.heal += heal
		totals.bonusDamage += bonus
		if dmg > totals.biggestHit then
			totals.biggestHit = dmg
		end
		if totals.usefulStep == nil and (dmg > 0 or shield > 0 or heal > 0 or makesCharge) then
			totals.usefulStep = step
		end
		table.insert(hits, {
			step = step,
			peg = pi,
			kind = kind,
			damage = dmg,
			shield = shield,
			heal = heal,
			charge = makesCharge,
			burstFrom = burstFrom,
			combo = combo,
			bonus = bonus,
			big = big,
		})
	end

	-- Burst: score every unscored peg inside the ring, nearest-index order,
	-- chaining through other burst pegs breadth-first.
	local function burst(step: number, origin: number)
		local queue = { origin }
		local qi = 1
		local radius = Pegs.BURST_RADIUS * m.burstRadiusMul
		local r2 = radius * radius
		while qi <= #queue do
			local center = pegs[queue[qi]]
			qi += 1
			for pi, p in pegs do
				if not scored[pi] then
					local dx = p.x - center.x
					local dy = p.y - center.y
					if dx * dx + dy * dy <= r2 then
						scorePeg(step, pi, queue[qi - 1])
						if p.kind == "burst" then
							table.insert(queue, pi)
						end
					end
				end
			end
		end
	end

	for _, ev in sim.events do
		if ev.kind == "wall" then
			walls += 1
			pendingWall += m.wallNextBonus
		else
			local pi = ev.peg :: number
			if not scored[pi] then
				scorePeg(ev.step, pi, nil)
				local isBurst = pegs[pi].kind == "burst"
				if (not firstPegDone) and ball.burstFirst then
					isBurst = true
				end
				firstPegDone = true
				if isBurst then
					burst(ev.step, pi)
				end
			end
		end
	end

	return { hits = hits, totals = totals }
end

return Scoring
