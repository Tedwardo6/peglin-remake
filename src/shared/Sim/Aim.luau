--!strict
-- Quantized aim. A shot's direction is one integer, so client and server
-- start every simulation from bit-identical inputs without trig.
--
-- The integer walks along a square path below the launcher:
--   |a| <= S        -> vector (a, S)              (within 45° of straight down)
--   S < |a| <= 2S   -> vector (±S, 2S − |a|)      (45° .. 90°)
-- then the vector is normalized with math.sqrt (IEEE correctly rounded).

local Config = require(script.Parent.Parent.Config)

local S = Config.Sim.AIM_STEPS
local MAX = Config.Sim.AIM_MAX

local Aim = {}

Aim.MAX = MAX

function Aim.isValid(a: any): boolean
	return type(a) == "number" and a == a and a % 1 == 0 and a >= -MAX and a <= MAX
end

function Aim.clamp(a: number): number
	if a ~= a then
		return 0
	end
	a = math.floor(a + 0.5)
	if a < -MAX then
		return -MAX
	elseif a > MAX then
		return MAX
	end
	return a
end

function Aim.vector(a: number): (number, number)
	local m = if a < 0 then -a else a
	local sx = if a < 0 then -1 else 1
	if m <= S then
		return a, S
	end
	return sx * S, 2 * S - m
end

function Aim.direction(a: number): (number, number)
	local vx, vy = Aim.vector(a)
	local len = math.sqrt(vx * vx + vy * vy)
	return vx / len, vy / len
end

-- Inverse: board-space direction (dy must point downward, > 0) to the
-- nearest aim integer. Used only by input code; never by the solver.
function Aim.fromDirection(dx: number, dy: number): number
	if dy <= 0 then
		dy = 1e-6
	end
	local ax = if dx < 0 then -dx else dx
	local a
	if ax <= dy then
		a = S * dx / dy
	else
		local m = 2 * S - S * dy / ax
		a = if dx < 0 then -m else m
	end
	return Aim.clamp(a)
end

return Aim
