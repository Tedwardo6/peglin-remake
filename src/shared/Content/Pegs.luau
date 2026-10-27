--!strict
-- Peg types. Collision is always a circle; `shape` and `symbol` are visual
-- supplements so meaning never depends on colour alone (plan §10).
-- Every special peg's effect is explicit and visible; nothing is random.

export type PegKind = "ordinary" | "guard" | "relay" | "power" | "burst" | "spring" | "mend"

export type PegDef = {
	kind: PegKind,
	name: string,
	description: string,
	radius: number,
	restitution: number,
	-- Visual
	shape: "round" | "square" | "diamond" | "ring" | "spiky" | "pill" | "plus",
	color: Color3,
	litColor: Color3,
	symbol: string,
}

local Pegs: { [PegKind]: PegDef } = {
	ordinary = {
		kind = "ordinary",
		name = "Peg",
		description = "Deals your ball's damage.",
		radius = 0.9,
		restitution = 0.66,
		shape = "round",
		color = Color3.fromRGB(92, 116, 232),
		litColor = Color3.fromRGB(220, 246, 255),
		symbol = "",
	},
	guard = {
		kind = "guard",
		name = "Guard Peg",
		description = "Adds shield instead of damage. Shield absorbs the next threat.",
		radius = 1.05,
		restitution = 0.6,
		shape = "square",
		color = Color3.fromRGB(60, 200, 255),
		litColor = Color3.fromRGB(200, 244, 255),
		symbol = "SHIELD",
	},
	relay = {
		kind = "relay",
		name = "Relay Peg",
		description = "Sends a Relay Charge: +2 power on the recipient's next six damaging hits. One per shot.",
		radius = 1.15,
		restitution = 0.62,
		shape = "ring",
		color = Color3.fromRGB(196, 84, 255),
		litColor = Color3.fromRGB(244, 206, 255),
		symbol = "RELAY",
	},
	power = {
		kind = "power",
		name = "Power Peg",
		description = "Triple damage on this hit.",
		radius = 1.0,
		restitution = 0.66,
		shape = "diamond",
		color = Color3.fromRGB(255, 186, 38),
		litColor = Color3.fromRGB(255, 244, 196),
		symbol = "x3",
	},
	burst = {
		kind = "burst",
		name = "Burst Peg",
		description = "Explodes: also hits every peg inside its ring.",
		radius = 1.0,
		restitution = 0.66,
		shape = "spiky",
		color = Color3.fromRGB(255, 92, 72),
		litColor = Color3.fromRGB(255, 222, 200),
		symbol = "BURST",
	},
	spring = {
		kind = "spring",
		name = "Spring Peg",
		description = "Bounces the ball hard. Deals normal damage.",
		radius = 1.35,
		restitution = 1.12,
		shape = "pill",
		color = Color3.fromRGB(92, 232, 140),
		litColor = Color3.fromRGB(220, 255, 228),
		symbol = "",
	},
	mend = {
		kind = "mend",
		name = "Mend Peg",
		description = "Heals 3 health instead of dealing damage.",
		radius = 1.0,
		restitution = 0.62,
		shape = "plus",
		color = Color3.fromRGB(255, 120, 186),
		litColor = Color3.fromRGB(255, 220, 238),
		symbol = "+",
	},
}

-- Fixed iteration order (never iterate the map with pairs when order matters).
local ORDER: { PegKind } = { "ordinary", "guard", "relay", "power", "burst", "spring", "mend" }

local BURST_RADIUS = 7.5

return {
	Defs = Pegs,
	Order = ORDER,
	BURST_RADIUS = BURST_RADIUS,
}
