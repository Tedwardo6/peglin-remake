--!strict
-- Earned-only cosmetic trails (plan §7/§8: appearance, never power; no sales).

export type CosmeticDef = {
	id: string,
	name: string,
	description: string, -- how it is earned
	colorA: Color3,
	colorB: Color3,
	stat: string?, -- profile stat that unlocks it
	threshold: number?,
	milestone: string?, -- or a one-off milestone flag
}

local LIST: { CosmeticDef } = {
	{
		id = "default",
		name = "Plain Trail",
		description = "Always available.",
		colorA = Color3.fromRGB(255, 255, 255),
		colorB = Color3.fromRGB(150, 180, 255),
	},
	{
		id = "spark",
		name = "Spark Trail",
		description = "Defeat the first boss.",
		colorA = Color3.fromRGB(255, 240, 120),
		colorB = Color3.fromRGB(255, 120, 40),
		milestone = "boss1",
	},
	{
		id = "comet",
		name = "Comet Trail",
		description = "Finish a full run.",
		colorA = Color3.fromRGB(140, 255, 250),
		colorB = Color3.fromRGB(60, 90, 255),
		milestone = "run_complete",
	},
	{
		id = "ribbon",
		name = "Relay Ribbon",
		description = "Have 10 of your Relay Charges used by teammates.",
		colorA = Color3.fromRGB(240, 160, 255),
		colorB = Color3.fromRGB(140, 50, 240),
		stat = "chargesUsedByOthers",
		threshold = 10,
	},
}

local byId: { [string]: CosmeticDef } = {}
local order: { string } = {}
for _, m in LIST do
	byId[m.id] = m
	table.insert(order, m.id)
end

return {
	ById = byId,
	Order = order,
}
