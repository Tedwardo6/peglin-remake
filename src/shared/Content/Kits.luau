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
		name = "Ricochet Kit",
		tag = "ricochet",
		description = "Wall bounces and long combos.",
		rack = { "basic", "rebound", "zip" },
		starter = "wall_studs",
		color = Color3.fromRGB(255, 196, 46),
		families = { "ricochet" },
	},
	{
		id = "relay",
		name = "Relay Kit",
		tag = "relay",
		description = "Power up a friend's next shot.",
		rack = { "basic", "signal", "beacon" },
		starter = "return_coil",
		color = Color3.fromRGB(190, 92, 255),
		families = { "relay" },
	},
	{
		id = "guard",
		name = "Guard Kit",
		tag = "guard",
		description = "Shields, repairs, and steady damage.",
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
