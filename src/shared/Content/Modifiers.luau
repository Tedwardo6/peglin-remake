--!strict
-- Optional difficulty modifiers. Each is a readable pattern or constraint,
-- never "more HP", and none changes the number of draft offers (plan §4).
-- Modifiers apply to the whole party; the run host chooses them.

export type ModifierDef = {
	id: string,
	name: string,
	description: string,
	icon: string,
}

local LIST: { ModifierDef } = {
	{ id = "blind", name = "No Guide", icon = "?", description = "The aim guide is hidden. Read the board yourself." },
	{ id = "slow_rack", name = "Slow Rack", icon = "+1", description = "Special balls need one extra shot to recharge." },
	{ id = "split_threats", name = "Split Threats", icon = "//", description = "Every threat lands as two half-hits, 2 s apart." },
	{ id = "thin_shields", name = "Thin Shields", icon = "15", description = "Shield caps at 15 instead of 30." },
}

local byId: { [string]: ModifierDef } = {}
local order: { string } = {}
for _, m in LIST do
	byId[m.id] = m
	table.insert(order, m.id)
end

return {
	ById = byId,
	Order = order,
}
