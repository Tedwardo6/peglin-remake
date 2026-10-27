--!strict
-- Starter kits set a direction, not a party role. Each kit can deal damage
-- and defend on its own (every board has Guard pegs; every rack has Basic).

export type KitDef = {
	id: string,
	name: string,
	tag: "ricochet" | "relay" | "guard",
	description: string,
	rack: { string }, -- 3 ball ids; slot 1 is always the Basic Ball
	starter: string, -- starting component id
	color: Color3,
	families: { string }, -- ball families this kit's compatible offers draw from
}

local LIST: { KitDef } = {
	{
		id = "ricochet",
		name = "Duelist",
		tag = "ricochet",
		description = "Ricochets and long combos. Twin daggers strike hard.",
		rack = { "basic", "rebound", "zip" },
		starter = "wall_studs",
		color = Color3.fromRGB(255, 196, 46),
		families = { "ricochet" },
	},
	{
		id = "relay",
		name = "Mystic",
		tag = "relay",
		description = "Support caster: Relay pegs empower an ally's next strike.",
		rack = { "basic", "signal", "beacon" },
		starter = "return_coil",
		color = Color3.fromRGB(190, 92, 255),
		families = { "relay" },
	},
	{
		id = "guard",
		name = "Warden",
		tag = "guard",
		description = "Shield and blade: guards the party and mends wounds.",
		rack = { "basic", "bulwark", "anchor" },
		starter = "plating",
		color = Color3.fromRGB(64, 150, 255),
		families = { "guard" },
	},
}

local byId: { [string]: KitDef } = {}
local order: { string } = {}
for _, k in LIST do
	byId[k.id] = k
	table.insert(order, k.id)
end

return {
	ById = byId,
	Order = order,
}
