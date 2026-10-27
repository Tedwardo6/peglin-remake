--!strict
-- Run structure: three legs × (two ordinary fights + one boss) = nine
-- encounters (plan §2). One modular setting; each leg gets its own palette.

export type Node = { enemy: string, board: string, boss: boolean }
export type Leg = { name: string, nodes: { Node }, palette: { frame: Color3, trim: Color3, back: Color3, glow: Color3 } }

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local LEGS: { Leg } = {
	{
		name = "Leg 1",
		palette = { frame = c(38, 170, 196), trim = c(255, 214, 64), back = c(22, 44, 92), glow = c(120, 240, 255) },
		nodes = {
			{ enemy = "brute_intro", board = "warmup", boss = false },
			{ enemy = "twin", board = "lanes", boss = false },
			{ enemy = "boss_crusher", board = "fortress", boss = true },
		},
	},
	{
		name = "Leg 2",
		palette = { frame = c(236, 128, 48), trim = c(120, 230, 255), back = c(54, 30, 70), glow = c(255, 190, 110) },
		nodes = {
			{ enemy = "jammer", board = "funnel", boss = false },
			{ enemy = "grower", board = "bumpers", boss = false },
			{ enemy = "boss_warden", board = "zigzag", boss = true },
		},
	},
	{
		name = "Leg 3",
		palette = { frame = c(150, 80, 230), trim = c(255, 120, 200), back = c(26, 20, 60), glow = c(220, 160, 255) },
		nodes = {
			{ enemy = "shell", board = "lanes", boss = false },
			{ enemy = "piercer", board = "bumpers", boss = false },
			{ enemy = "boss_overseer", board = "fortress", boss = true },
		},
	},
}

local Route = {}

Route.Legs = LEGS

function Route.count(): number
	local n = 0
	for _, leg in LEGS do
		n += #leg.nodes
	end
	return n
end

-- 1-based encounter index -> leg index, node index within leg, node
function Route.at(index: number): (number, number, Node)
	local i = index
	for li, leg in LEGS do
		if i <= #leg.nodes then
			return li, i, leg.nodes[i]
		end
		i -= #leg.nodes
	end
	error("encounter index out of range: " .. tostring(index))
end

return Route
