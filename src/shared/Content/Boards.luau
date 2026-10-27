--!strict
-- Authored peg layouts. Each row is written as a pattern so layouts stay
-- readable and easy to tune:
--   on rows  (10 slots): x = 3, 9, 15, ... 57
--   off rows ( 9 slots): x = 6, 12, 18, ... 54
--   o ordinary · G guard · R relay · P power · B burst · S spring · M mend · . empty
-- Bump a board's `rev` whenever its geometry changes; shots record the
-- revision they were simulated against, and old replays stop matching.

local Pegs = require(script.Parent.Pegs)

type Row = { y: number, off: boolean, pattern: string }
type Wall = { x1: number, y1: number, x2: number, y2: number }

type BoardSpec = {
	id: string,
	rev: number,
	name: string,
	rows: { Row },
	walls: { Wall },
}

export type Board = {
	id: string,
	rev: number,
	name: string,
	pegs: { { x: number, y: number, kind: Pegs.PegKind } },
	walls: { Wall },
}

local KIND: { [string]: Pegs.PegKind } = {
	o = "ordinary",
	G = "guard",
	R = "relay",
	P = "power",
	B = "burst",
	S = "spring",
	M = "mend",
}

local function on(y: number, pattern: string): Row
	return { y = y, off = false, pattern = pattern }
end
local function off(y: number, pattern: string): Row
	return { y = y, off = true, pattern = pattern }
end

local SPECS: { BoardSpec } = {
	{
		id = "warmup",
		rev = 1,
		name = "Warm-Up",
		walls = {},
		rows = {
			off(14, "..ooooo.."),
			on(20, ".oooooooo."),
			off(26, "ooooPoooo"),
			on(32, "GooooooooG"),
			off(38, "ooRoooRoo"),
			on(44, "oooooooooo"),
			off(50, "ooooMoooo"),
			on(56, "ooGooooGoo"),
			off(62, ".ooo.ooo."),
			on(68, "S........S"),
		},
	},
	{
		id = "lanes",
		rev = 1,
		name = "Two Lanes",
		-- A divider splits the lower board: relay-rich left, power-rich right.
		walls = { { x1 = 30, y1 = 47, x2 = 30, y2 = 74 } },
		rows = {
			off(14, "...ooo..."),
			on(20, "..oooooo.."),
			off(26, ".ooooooo."),
			on(32, "oooo..oooo"),
			off(38, "ooRo.oPoo"),
			on(44, "oRoo..ooPo"),
			off(50, "oRoo.ooPo"),
			on(56, "ooGo..oGoo"),
			off(62, "oooo.oooo"),
			on(68, "S.oo..oo.S"),
		},
	},
	{
		id = "funnel",
		rev = 1,
		name = "Funnel",
		-- Rails catch wide shots and guide them toward the power core.
		walls = {
			{ x1 = 1, y1 = 12, x2 = 15, y2 = 22 },
			{ x1 = 59, y1 = 12, x2 = 45, y2 = 22 },
		},
		rows = {
			off(18, "...ooo..."),
			on(24, "...oPPo..."),
			off(30, "..ooBoo.."),
			on(36, ".oooooooo."),
			off(42, "GoooooooG"),
			on(48, "ooooRRoooo"),
			off(54, "ooooooooo"),
			on(60, "oMooooooMo"),
			off(66, "o.ooooo.o"),
			on(72, "S.o.oo.o.S"),
		},
	},
	{
		id = "bumpers",
		rev = 1,
		name = "Bumpers",
		walls = {},
		rows = {
			off(14, "...ooo..."),
			on(20, ".oo.oo.oo."),
			off(26, "ooSoooSoo"),
			on(32, "oooGooGooo"),
			off(38, "oPoooooPo"),
			on(44, "o..oSSo..o"),
			off(50, "oRoooooRo"),
			on(56, "oooBooBooo"),
			off(62, "oo.ooo.oo"),
			on(68, "MooooooooM"),
		},
	},
	{
		id = "zigzag",
		rev = 1,
		name = "Zigzag",
		-- Two shelves send the ball back across the board.
		walls = {
			{ x1 = 2, y1 = 40, x2 = 20, y2 = 46 },
			{ x1 = 58, y1 = 54, x2 = 40, y2 = 60 },
		},
		rows = {
			off(14, ".ooooooo."),
			on(20, "ooRoooRooo"),
			off(26, "ooooPoooo"),
			on(32, "oGoooooooo"),
			off(38, "....ooBoo"),
			on(44, "....oooooo"),
			off(50, "ooooooo.."),
			on(56, "oooPooo..."),
			off(62, "ooooooGoo"),
			on(68, "S.oooMoo.S"),
		},
	},
	{
		id = "fortress",
		rev = 1,
		name = "Fortress",
		-- Boss board: a guarded power core, relays on the outer ring.
		walls = {
			{ x1 = 20, y1 = 30, x2 = 26, y2 = 34 },
			{ x1 = 40, y1 = 30, x2 = 34, y2 = 34 },
		},
		rows = {
			off(14, ".ooooooo."),
			on(20, "oRoooooRoo"),
			off(26, "ooGoooGoo"),
			on(38, "ooooPPoooo"),
			off(44, "RoooBoooR"),
			on(50, "oGooooooGo"),
			off(56, "oooMoMooo"),
			on(62, "ooo.oo.ooo"),
			off(68, ".oo.o.oo."),
			on(74, "S........S"),
		},
	},
}

local function build(spec: BoardSpec): Board
	local pegs: { { x: number, y: number, kind: Pegs.PegKind } } = {}
	for _, row in spec.rows do
		local expected = if row.off then 9 else 10
		if #row.pattern ~= expected then
			error(`board {spec.id}: row y={row.y} must have {expected} slots, has {#row.pattern}`)
		end
		for i = 1, #row.pattern do
			local ch = string.sub(row.pattern, i, i)
			if ch ~= "." then
				local kind = KIND[ch]
				if kind == nil then
					error(`board {spec.id}: unknown peg symbol '{ch}'`)
				end
				local x = if row.off then 6 * i else 6 * i - 3
				local entry: { x: number, y: number, kind: Pegs.PegKind } = { x = x, y = row.y, kind = kind :: Pegs.PegKind }
				table.insert(pegs, entry)
			end
		end
	end
	return { id = spec.id, rev = spec.rev, name = spec.name, pegs = pegs, walls = spec.walls }
end

local byId: { [string]: Board } = {}
local order: { string } = {}
for _, spec in SPECS do
	byId[spec.id] = build(spec)
	table.insert(order, spec.id)
end

return {
	ById = byId,
	Order = order,
}
