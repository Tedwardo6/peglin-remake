--!strict
-- The 18 components (passive upgrades). Each has one explicit effect that
-- helps on its own; its tag says which kit it suits.

export type Tag = "ricochet" | "relay" | "guard" | "flex" | "wild"

export type ComponentDef = {
	id: string,
	name: string,
	tag: Tag,
	description: string,
	icon: string, -- short glyph shown on the card
	-- Effects (nil = absent). Interpreted by Sim/Scoring and the encounter.
	ordinaryBonus: number?,
	powerMult: number?,
	wallNextBonus: number?,
	burstRadiusMul: number?,
	springBonus: number?,
	guardBonus: number?,
	maxHull: number?,
	mendBonus: number?,
	sendPower: number?,
	sendHits: number?,
	consumeShield: number?,
	cooldownReduce: number?,
	finisher: { threshold: number, bonus: number }?,
	opener: { hits: number, bonus: number }?,
	guideContacts: number?,
	spikesMul: number?,
	comboEvery: { n: number, bonus: number }?,
	allBonus: number?,
}

local LIST: { ComponentDef } = {
	{ id = "whetstone", name = "Whetstone", tag = "flex", icon = "+1", description = "+1 damage on ordinary pegs.", ordinaryBonus = 1 },
	{ id = "power_coil", name = "Power Coil", tag = "wild", icon = "x4", description = "Power pegs deal ×4 instead of ×3.", powerMult = 4 },
	{ id = "wall_studs", name = "Wall Studs", tag = "ricochet", icon = "|+", description = "After each wall bounce, your next hit deals +3.", wallNextBonus = 3 },
	{ id = "long_fuse", name = "Long Fuse", tag = "wild", icon = "((o))", description = "Burst rings are 50% wider.", burstRadiusMul = 1.5 },
	{ id = "spring_tune", name = "Spring Tune", tag = "ricochet", icon = "~+", description = "Spring pegs deal +4 damage.", springBonus = 4 },
	{ id = "plating", name = "Plating", tag = "guard", icon = "[+]", description = "Guard pegs give +2 shield.", guardBonus = 2 },
	{ id = "hull_plates", name = "Hull Plates", tag = "guard", icon = "HP", description = "+12 max hull, repaired now.", maxHull = 12 },
	{ id = "patch_kit", name = "Patch Kit", tag = "guard", icon = "++", description = "Mend pegs repair 2 more.", mendBonus = 2 },
	{ id = "relay_booster", name = "Relay Booster", tag = "relay", icon = ">>", description = "Charges you send give +3 power instead of +2.", sendPower = 3 },
	{ id = "long_relay", name = "Long Relay", tag = "relay", icon = ">9", description = "Charges you send cover 9 hits instead of 6.", sendHits = 9 },
	{ id = "return_coil", name = "Return Coil", tag = "relay", icon = "<@", description = "Using a charge gives you 4 shield.", consumeShield = 4 },
	{ id = "fast_rack", name = "Fast Rack", tag = "flex", icon = "-1", description = "Special balls recharge 1 shot faster (minimum 1).", cooldownReduce = 1 },
	{ id = "finisher", name = "Finisher", tag = "wild", icon = "!", description = "+2 damage per hit while the monster is under 35% HP.", finisher = { threshold = 0.35, bonus = 2 } },
	{ id = "opener", name = "Opening Volley", tag = "flex", icon = "123", description = "Your first 3 damaging hits each shot deal +2.", opener = { hits = 3, bonus = 2 } },
	{ id = "steady_hand", name = "Steady Hand", tag = "flex", icon = "-->", description = "The aim guide also shows the second bounce.", guideContacts = 2 },
	{ id = "spikes", name = "Shield Spikes", tag = "guard", icon = "^^", description = "Shield that blocks a threat hits the monster back for double.", spikesMul = 2 },
	{ id = "combo_engine", name = "Combo Engine", tag = "ricochet", icon = "x8", description = "Every 8th peg hit in a shot deals +6.", comboEvery = { n = 8, bonus = 6 } },
	{ id = "lead_core", name = "Lead Core", tag = "flex", icon = "+1!", description = "+1 damage on every damaging hit.", allBonus = 1 },
}

local byId: { [string]: ComponentDef } = {}
local order: { string } = {}
for _, comp in LIST do
	byId[comp.id] = comp
	table.insert(order, comp.id)
end

return {
	ById = byId,
	Order = order,
}
