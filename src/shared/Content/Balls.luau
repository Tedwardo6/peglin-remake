--!strict
-- The 12 balls. Every ball has a useful standalone effect; components and
-- kits make it better, never rescue it (plan §4/§5). All effects are
-- deterministic and printed on the card — no hidden rolls.

export type Family = "core" | "ricochet" | "relay" | "guard" | "wild"

export type BallDef = {
	id: string,
	name: string,
	family: Family,
	description: string,
	cooldown: number, -- shots before it can launch again (0 = always ready)
	damage: number, -- damage per damaging peg hit
	radius: number,
	restitutionMul: number,
	gravityMul: number,
	wallRestitution: number,
	color: Color3,
	accent: Color3,
	-- Effects (nil = absent)
	wallBonus: number?, -- each wall bounce adds this to later hits this shot
	everyNth: { n: number, mult: number }?, -- every Nth damaging hit is multiplied
	relayDamage: number?, -- Relay pegs also deal this damage
	relayShield: number?, -- Relay pegs also give this shield
	chargeHitsWhenUsed: number?, -- a received charge covers this many hits instead
	guardMul: number?, -- Guard peg shield multiplier
	shieldPerHit: number?, -- every damaging hit also gives shield
	mendMul: number?, -- Mend peg repair multiplier
	burstFirst: boolean?, -- the first peg this ball hits bursts
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local LIST: { BallDef } = {
	{
		id = "basic",
		name = "Basic Ball",
		family = "core",
		description = "2 damage per peg. Always ready.",
		cooldown = 0,
		damage = 2,
		radius = 1.0,
		restitutionMul = 1.0,
		gravityMul = 1.0,
		wallRestitution = 0.72,
		color = c(245, 245, 255),
		accent = c(150, 170, 255),
	},
	{
		id = "rebound",
		name = "Rebound Ball",
		family = "ricochet",
		description = "Each wall bounce adds +1 damage to every later hit this shot.",
		cooldown = 2,
		damage = 2,
		radius = 1.0,
		restitutionMul = 1.05,
		gravityMul = 1.0,
		wallRestitution = 0.9,
		color = c(255, 214, 64),
		accent = c(255, 140, 30),
		wallBonus = 1,
	},
	{
		id = "zip",
		name = "Zip Ball",
		family = "ricochet",
		description = "Small and lively. Every 4th damaging hit deals triple.",
		cooldown = 2,
		damage = 2,
		radius = 0.78,
		restitutionMul = 1.12,
		gravityMul = 0.95,
		wallRestitution = 0.85,
		color = c(120, 255, 236),
		accent = c(20, 190, 200),
		everyNth = { n = 4, mult = 3 },
	},
	{
		id = "combo",
		name = "Combo Ball",
		family = "ricochet",
		description = "Every 5th damaging hit deals 5×.",
		cooldown = 3,
		damage = 2,
		radius = 1.0,
		restitutionMul = 1.0,
		gravityMul = 1.0,
		wallRestitution = 0.72,
		color = c(255, 120, 220),
		accent = c(200, 40, 160),
		everyNth = { n = 5, mult = 5 },
	},
	{
		id = "signal",
		name = "Signal Ball",
		family = "relay",
		description = "Relay pegs also give you 4 shield.",
		cooldown = 1,
		damage = 2,
		radius = 1.0,
		restitutionMul = 1.0,
		gravityMul = 1.0,
		wallRestitution = 0.72,
		color = c(206, 140, 255),
		accent = c(130, 60, 230),
		relayShield = 4,
	},
	{
		id = "beacon",
		name = "Beacon Ball",
		family = "relay",
		description = "Relay pegs also deal 6 damage.",
		cooldown = 2,
		damage = 2,
		radius = 1.05,
		restitutionMul = 1.0,
		gravityMul = 1.0,
		wallRestitution = 0.72,
		color = c(255, 160, 255),
		accent = c(170, 70, 220),
		relayDamage = 6,
	},
	{
		id = "echo",
		name = "Echo Ball",
		family = "relay",
		description = "A Relay Charge used on this ball powers 10 hits instead of 6.",
		cooldown = 2,
		damage = 2,
		radius = 1.0,
		restitutionMul = 1.0,
		gravityMul = 1.0,
		wallRestitution = 0.72,
		color = c(170, 190, 255),
		accent = c(90, 90, 230),
		chargeHitsWhenUsed = 10,
	},
	{
		id = "bulwark",
		name = "Bulwark Ball",
		family = "guard",
		description = "Guard pegs give double shield.",
		cooldown = 1,
		damage = 2,
		radius = 1.0,
		restitutionMul = 0.95,
		gravityMul = 1.0,
		wallRestitution = 0.72,
		color = c(110, 170, 255),
		accent = c(30, 80, 220),
		guardMul = 2,
	},
	{
		id = "anchor",
		name = "Anchor Ball",
		family = "guard",
		description = "Every damaging hit also gives 1 shield.",
		cooldown = 2,
		damage = 2,
		radius = 1.0,
		restitutionMul = 0.9,
		gravityMul = 1.05,
		wallRestitution = 0.7,
		color = c(150, 220, 255),
		accent = c(40, 120, 200),
		shieldPerHit = 1,
	},
	{
		id = "patch",
		name = "Patch Ball",
		family = "guard",
		description = "Mend pegs repair triple.",
		cooldown = 2,
		damage = 2,
		radius = 1.0,
		restitutionMul = 1.0,
		gravityMul = 1.0,
		wallRestitution = 0.72,
		color = c(255, 170, 200),
		accent = c(230, 80, 140),
		mendMul = 3,
	},
	{
		id = "heavy",
		name = "Heavy Ball",
		family = "wild",
		description = "4 damage per peg, but sinks fast.",
		cooldown = 2,
		damage = 4,
		radius = 1.1,
		restitutionMul = 0.78,
		gravityMul = 1.2,
		wallRestitution = 0.6,
		color = c(150, 150, 170),
		accent = c(70, 70, 90),
	},
	{
		id = "blast",
		name = "Blast Ball",
		family = "wild",
		description = "The first peg it hits bursts, hitting every peg in its ring.",
		cooldown = 3,
		damage = 2,
		radius = 1.0,
		restitutionMul = 1.0,
		gravityMul = 1.0,
		wallRestitution = 0.72,
		color = c(255, 120, 80),
		accent = c(220, 50, 30),
		burstFirst = true,
	},
	{
		id = "giant",
		name = "Giant Ball",
		family = "wild",
		description = "Huge. Touches far more pegs.",
		cooldown = 2,
		damage = 2,
		radius = 1.65,
		restitutionMul = 0.92,
		gravityMul = 1.0,
		wallRestitution = 0.68,
		color = c(255, 236, 150),
		accent = c(230, 170, 40),
	},
}

local byId: { [string]: BallDef } = {}
local order: { string } = {}
for _, b in LIST do
	byId[b.id] = b
	table.insert(order, b.id)
end

return {
	ById = byId,
	Order = order,
}
