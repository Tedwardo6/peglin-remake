--!strict
-- Small deterministic PRNG (xorshift32) for draft offers. Seeded per run,
-- player, and encounter so offers are reproducible and a rejoin cannot reroll.

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.hashString(s: string): number
	local h = 2166136261
	for i = 1, #s do
		local a = bit32.bxor(h, string.byte(s, i))
		h = ((a % 256) * 16777216 + a * 403) % 4294967296
	end
	if h == 0 then
		h = 0x9E3779B9
	end
	return h
end

function Rng.new(seed: string): Rng
	return setmetatable({ state = Rng.hashString(seed) }, Rng)
end

function Rng.nextU32(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x
end

-- Integer in [1, n].
function Rng.pick(self: Rng, n: number): number
	return (Rng.nextU32(self) % n) + 1
end

return Rng
