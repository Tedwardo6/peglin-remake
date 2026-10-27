--!strict
-- Monsters and their telegraphed threats. Every threat is announced with a
-- countdown (≥ 12 s) and a plain description of what it will do.
-- Six ordinary behaviours and three bosses. HP values are solo HP; the
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
	body: Color3,
	belly: Color3,
	horn: "none" | "horns" | "antenna" | "spikes" | "crown" | "shell",
	eyes: number,
	scale: number,
	mouth: "grin" | "fangs" | "flat",
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
		name = "Small Monster",
		hp = 100,
		boss = false,
		cadence = 20,
		firstDelay = 24,
		cycle = { slam(5) },
		look = { body = c(120, 214, 110), belly = c(220, 255, 190), horn = "antenna", eyes = 2, scale = 0.85, mouth = "grin" },
		blurb = "Slow and forgiving. Slams every 20 s.",
	},
	{
		id = "brute",
		name = "Brute Monster",
		hp = 360,
		boss = false,
		cadence = 18,
		firstDelay = 18,
		cycle = { slam(8) },
		look = { body = c(240, 120, 70), belly = c(255, 214, 170), horn = "horns", eyes = 2, scale = 1.0, mouth = "fangs" },
		blurb = "Big single slams.",
	},
	{
		id = "twin",
		name = "Twin-Strike Monster",
		hp = 360,
		boss = false,
		cadence = 18,
		firstDelay = 18,
		cycle = { double(5) },
		look = { body = c(90, 200, 230), belly = c(210, 245, 255), horn = "antenna", eyes = 3, scale = 0.95, mouth = "grin" },
		blurb = "Strikes twice in a row.",
	},
	{
		id = "jammer",
		name = "Jammer Monster",
		hp = 440,
		boss = false,
		cadence = 18,
		firstDelay = 18,
		cycle = { jam(5), slam(9) },
		look = { body = c(200, 110, 230), belly = c(240, 210, 255), horn = "spikes", eyes = 1, scale = 1.0, mouth = "flat" },
		blurb = "Jams your special balls for a shot, then slams.",
	},
	{
		id = "grower",
		name = "Growing Monster",
		hp = 540,
		boss = false,
		cadence = 17,
		firstDelay = 17,
		cycle = { grow(5, 2) },
		look = { body = c(250, 200, 60), belly = c(255, 245, 200), horn = "horns", eyes = 2, scale = 1.05, mouth = "fangs" },
		blurb = "Every slam hits 2 harder than the last.",
	},
	{
		id = "shell",
		name = "Shell Monster",
		hp = 480,
		boss = false,
		cadence = 18,
		firstDelay = 18,
		cycle = { armor(18), slam(10) },
		look = { body = c(110, 140, 190), belly = c(200, 215, 240), horn = "shell", eyes = 2, scale = 1.05, mouth = "flat" },
		blurb = "Grows armor that soaks damage, then slams.",
	},
	{
		id = "piercer",
		name = "Piercer Monster",
		hp = 580,
		boss = false,
		cadence = 17,
		firstDelay = 17,
		cycle = { pierce(11) },
		look = { body = c(230, 70, 110), belly = c(255, 200, 215), horn = "spikes", eyes = 2, scale = 1.0, mouth = "fangs" },
		blurb = "Half of each hit ignores shield.",
	},
	{
		id = "boss_crusher",
		name = "Crusher Boss",
		hp = 880,
		boss = true,
		cadence = 18,
		firstDelay = 20,
		cycle = { slam(9), double(6) },
		phases = {
			{ at = 0.5, cycle = { slam(11), double(7) }, cadence = 16, label = "Enraged: faster threats" },
		},
		look = { body = c(255, 110, 60), belly = c(255, 220, 160), horn = "crown", eyes = 2, scale = 1.35, mouth = "fangs" },
		blurb = "Alternates slams and double strikes. Speeds up at half health.",
	},
	{
		id = "boss_warden",
		name = "Warden Boss",
		hp = 1100,
		boss = true,
		cadence = 18,
		firstDelay = 18,
		cycle = { armor(30), slam(12), pierce(10) },
		phases = {
			{ at = 0.4, cycle = { pierce(12), slam(13) }, cadence = 17, label = "Armor broken: piercing attacks" },
		},
		look = { body = c(80, 120, 200), belly = c(190, 210, 255), horn = "shell", eyes = 3, scale = 1.4, mouth = "flat" },
		blurb = "Armors up, then breaks through shields.",
	},
	{
		id = "boss_overseer",
		name = "Overseer Boss",
		hp = 1300,
		boss = true,
		cadence = 17,
		firstDelay = 18,
		cycle = { grow(8, 2), jam(8), double(8) },
		phases = {
			{ at = 0.5, cycle = { armor(40), pierce(13), grow(12, 3) }, cadence = 16, label = "Final form: armor and pierce" },
		},
		look = { body = c(150, 70, 220), belly = c(230, 200, 255), horn = "crown", eyes = 1, scale = 1.5, mouth = "fangs" },
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
