--!strict
-- Monsters and their telegraphed threats. Every threat is announced with a
-- countdown (≥ 12 s) and a plain description of what it will do.
-- Six ordinary behaviours and three bosses (names are placeholders). HP
-- values are solo HP; the
-- encounter scales them by party size (Config.Combat.HP_SCALE_PER_EXTRA).

export type ThreatKind = "slam" | "double" | "jam" | "grow" | "armor" | "pierce"

export type ThreatDef = {
	kind: ThreatKind,
	label: string,
	damage: number, -- per hit, before growth
	hits: number?, -- "double": number of hits
	gap: number?, -- seconds between multi-hits
	growBy: number?, -- "grow": added each use
	armor: number?, -- "armor": monster armor gained
	pierce: number?, -- "pierce": fraction that ignores shield
	jam: number?, -- "jam": special cooldowns increased by this
}

export type Look = {
	model: string, -- key in Content/MonsterModels
	height: number, -- standing height on the battlefield, in studs
	glow: Color3, -- psychedelic rim/aura colour
	float: boolean?, -- hovers instead of standing
}

export type Phase = { at: number, cycle: { ThreatDef }, cadence: number, label: string }

export type EnemyDef = {
	id: string,
	name: string,
	hp: number,
	boss: boolean,
	cadence: number, -- seconds between threats (16–20)
	firstDelay: number, -- seconds before the first threat lands
	cycle: { ThreatDef },
	phases: { Phase }?,
	look: Look,
	blurb: string,
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function slam(d: number): ThreatDef
	return { kind = "slam", label = "Slam", damage = d }
end
local function double(d: number): ThreatDef
	return { kind = "double", label = "Double Strike", damage = d, hits = 2, gap = 1.2 }
end
local function jam(d: number): ThreatDef
	return { kind = "jam", label = "Jam", damage = d, jam = 1 }
end
local function grow(d: number, by: number): ThreatDef
	return { kind = "grow", label = "Rising Slam", damage = d, growBy = by }
end
local function armor(a: number): ThreatDef
	return { kind = "armor", label = "Armor Up", damage = 0, armor = a }
end
local function pierce(d: number): ThreatDef
	return { kind = "pierce", label = "Pierce", damage = d, pierce = 0.5 }
end

local LIST: { EnemyDef } = {
	{
		id = "brute_intro",
		name = "Mire Imp",
		hp = 100,
		boss = false,
		cadence = 20,
		firstDelay = 24,
		cycle = { slam(5) },
		look = { model = "imp", height = 4.2, glow = c(90, 200, 255) },
		blurb = "Slow and forgiving. Slams every 20 s.",
	},
	{
		id = "brute",
		name = "Gloom Brute",
		hp = 360,
		boss = false,
		cadence = 18,
		firstDelay = 18,
		cycle = { slam(8) },
		look = { model = "brute", height = 6.6, glow = c(170, 90, 255) },
		blurb = "Big single slams.",
	},
	{
		id = "twin",
		name = "Twinfang Hound",
		hp = 360,
		boss = false,
		cadence = 18,
		firstDelay = 18,
		cycle = { double(5) },
		look = { model = "hound", height = 5.4, glow = c(80, 160, 255) },
		blurb = "Strikes twice in a row.",
	},
	{
		id = "jammer",
		name = "Hex Weaver",
		hp = 440,
		boss = false,
		cadence = 18,
		firstDelay = 18,
		cycle = { jam(5), slam(9) },
		look = { model = "hex", height = 7.0, glow = c(120, 110, 255), float = true },
		blurb = "Jams your special balls for a shot, then slams.",
	},
	{
		id = "grower",
		name = "Spore Colossus",
		hp = 540,
		boss = false,
		cadence = 17,
		firstDelay = 17,
		cycle = { grow(5, 2) },
		look = { model = "fungal", height = 7.6, glow = c(255, 90, 220) },
		blurb = "Every slam hits 2 harder than the last.",
	},
	{
		id = "shell",
		name = "Carapace Golem",
		hp = 480,
		boss = false,
		cadence = 18,
		firstDelay = 18,
		cycle = { armor(18), slam(10) },
		look = { model = "golem", height = 7.2, glow = c(90, 200, 255) },
		blurb = "Grows armor that soaks damage, then slams.",
	},
	{
		id = "piercer",
		name = "Thorn Wraith",
		hp = 580,
		boss = false,
		cadence = 17,
		firstDelay = 17,
		cycle = { pierce(11) },
		look = { model = "wraith", height = 7.4, glow = c(255, 70, 200), float = true },
		blurb = "Half of each hit ignores shield.",
	},
	{
		id = "boss_crusher",
		name = "The Drowned King",
		hp = 880,
		boss = true,
		cadence = 18,
		firstDelay = 20,
		cycle = { slam(9), double(6) },
		phases = {
			{ at = 0.5, cycle = { slam(11), double(7) }, cadence = 16, label = "Enraged: faster threats" },
		},
		look = { model = "king", height = 12.5, glow = c(70, 140, 255) },
		blurb = "Alternates slams and double strikes. Speeds up at half health.",
	},
	{
		id = "boss_warden",
		name = "The Eye Warden",
		hp = 1100,
		boss = true,
		cadence = 18,
		firstDelay = 18,
		cycle = { armor(30), slam(12), pierce(10) },
		phases = {
			{ at = 0.4, cycle = { pierce(12), slam(13) }, cadence = 17, label = "Armor broken: piercing attacks" },
		},
		look = { model = "eyetree", height = 10.5, glow = c(255, 130, 60) },
		blurb = "Armors up, then breaks through shields.",
	},
	{
		id = "boss_overseer",
		name = "The Vortex Eye",
		hp = 1300,
		boss = true,
		cadence = 17,
		firstDelay = 18,
		cycle = { grow(8, 2), jam(8), double(8) },
		phases = {
			{ at = 0.5, cycle = { armor(40), pierce(13), grow(12, 3) }, cadence = 16, label = "Final form: armor and pierce" },
		},
		look = { model = "overseer", height = 12.5, glow = c(120, 200, 255), float = true },
		blurb = "Everything at once. Gains armor at half health.",
	},
}

local byId: { [string]: EnemyDef } = {}
local order: { string } = {}
for _, e in LIST do
	byId[e.id] = e
	table.insert(order, e.id)
end

return {
	ById = byId,
	Order = order,
}
