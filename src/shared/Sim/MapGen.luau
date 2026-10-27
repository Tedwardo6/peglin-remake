--!strict
-- Deterministic act maps: a few rows of branching choices, then the boss.
-- The same seed always produces the same map, so the server and every
-- client agree without sending the whole graph, and a resumed run rebuilds
-- the exact map it left.
--
-- Shape per act (rows left to right, boss last):
--   row 1: the opener (act I: one gentle fight; later acts: two fights)
--   row 2: three nodes drawn from fight / elite / treasure
--   row 3: two nodes, one of them always a campfire rest
--   boss
-- Every node in a row links to one or two nodes in the next row, so the
-- party always has a real choice and no node is a dead end.

local Campaigns = require(script.Parent.Parent.Content.Campaigns)
local Rng = require(script.Parent.Rng)

export type NodeKind = "fight" | "elite" | "rest" | "treasure" | "boss"

export type MapNode = {
	id: string,
	row: number, -- 1..ROWS, boss is ROWS + 1
	col: number,
	x: number, -- 0..1 vertical placement inside its row (for drawing)
	kind: NodeKind,
	enemy: string?,
	board: string?,
	next: { string },
}

export type ActMap = {
	act: number,
	rows: { { MapNode } },
	boss: MapNode,
	byId: { [string]: MapNode },
}

local MapGen = {}

MapGen.ROWS = 3

local function shuffleStr(rng: Rng.Rng, list: { string }): { string }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = Rng.pick(rng, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function shuffle(rng: Rng.Rng, list: { NodeKind }): { NodeKind }
	local out = table.clone(list)
	for i = #out, 2, -1 do
		local j = Rng.pick(rng, i)
		out[i], out[j] = out[j], out[i]
	end
	return out
end

local function placeX(count: number, col: number): number
	if count == 1 then
		return 0.5
	end
	return 0.18 + (col - 1) * (0.64 / (count - 1))
end

function MapGen.generate(campaignId: string, actIndex: number, seed: string): ActMap
	local camp = Campaigns.ById[campaignId]
	assert(camp, "unknown campaign " .. campaignId)
	local act = camp.acts[actIndex]
	assert(act, "act out of range")
	local rng = Rng.new(`{seed}|map|{campaignId}|{actIndex}`)

	local enemyBag: { string } = {}
	local function nextEnemy(): string
		if #enemyBag == 0 then
			enemyBag = shuffleStr(rng, act.pool)
		end
		return table.remove(enemyBag) :: string
	end
	local boardBag: { string } = {}
	local function nextBoard(): string
		if #boardBag == 0 then
			boardBag = shuffleStr(rng, act.boards)
		end
		return table.remove(boardBag) :: string
	end

	local kinds: { { NodeKind } } = {}
	local FIGHT: NodeKind = "fight"
	local ELITE: NodeKind = "elite"
	local TREASURE: NodeKind = "treasure"
	local REST: NodeKind = "rest"
	if act.opener then
		kinds[1] = { FIGHT }
	else
		kinds[1] = { FIGHT, FIGHT }
	end
	kinds[2] = shuffle(rng, { FIGHT, ELITE, TREASURE })
	local partners: { NodeKind } = { FIGHT, TREASURE, ELITE }
	local partner: NodeKind = partners[Rng.pick(rng, 3)]
	local last: { NodeKind } = { REST, partner }
	kinds[3] = shuffle(rng, last)

	local map: ActMap = { act = actIndex, rows = {}, boss = nil :: any, byId = {} }
	for r = 1, MapGen.ROWS do
		local row: { MapNode } = {}
		for col, kind: NodeKind in kinds[r] do
			local node: MapNode = {
				id = `a{actIndex}r{r}c{col}`,
				row = r,
				col = col,
				x = placeX(#kinds[r], col),
				kind = kind,
				enemy = nil,
				board = nil,
				next = {},
			}
			if kind == "fight" or kind == "elite" then
				node.enemy = if r == 1 and act.opener then act.opener else nextEnemy()
				node.board = nextBoard()
			end
			table.insert(row, node)
			map.byId[node.id] = node
		end
		map.rows[r] = row
	end
	local boss: MapNode = {
		id = `a{actIndex}boss`,
		row = MapGen.ROWS + 1,
		col = 1,
		x = 0.5,
		kind = "boss",
		enemy = act.boss,
		board = act.bossBoard,
		next = {},
	}
	map.boss = boss
	map.byId[boss.id] = boss

	-- Links: each node reaches the nearest one or two nodes of the next row.
	for r = 1, MapGen.ROWS do
		local row = map.rows[r]
		local nextRow: { MapNode } = if r < MapGen.ROWS then map.rows[r + 1] else { boss }
		for _, node in row do
			if #nextRow == 1 then
				node.next = { nextRow[1].id }
			else
				-- Map this column onto the next row's span and take the
				-- neighbours on either side of that point.
				local pos = if #row == 1 then (#nextRow + 1) / 2 else 1 + (node.col - 1) * (#nextRow - 1) / (#row - 1)
				local lo = math.floor(pos)
				local hi = math.ceil(pos)
				if #row == 1 then
					for _, n in nextRow do
						table.insert(node.next, n.id)
					end
				elseif lo == hi then
					-- Exactly on a node: also reach the inward neighbour.
					local inward = if node.col <= (#row + 1) / 2 then lo + 1 else lo - 1
					inward = math.clamp(inward, 1, #nextRow)
					table.insert(node.next, nextRow[lo].id)
					if inward ~= lo and #nextRow > #row then
						table.insert(node.next, nextRow[inward].id)
					end
				else
					table.insert(node.next, nextRow[lo].id)
					table.insert(node.next, nextRow[hi].id)
				end
			end
		end
	end
	return map
end

-- Nodes the party may vote for, given the node they just finished
-- (nil = start of the act).
function MapGen.choices(map: ActMap, fromId: string?): { MapNode }
	if fromId == nil then
		return table.clone(map.rows[1])
	end
	local from = map.byId[fromId]
	if from == nil then
		return {}
	end
	local out = {}
	for _, id in from.next do
		table.insert(out, map.byId[id])
	end
	return out
end

-- Compact form for snapshots and the client's map screen.
function MapGen.view(map: ActMap): { [string]: any }
	local rows = {}
	for r, row in map.rows do
		local list = {}
		for _, n in row do
			table.insert(list, { id = n.id, row = n.row, col = n.col, x = n.x, kind = n.kind, enemy = n.enemy, next = table.clone(n.next) })
		end
		rows[r] = list
	end
	return {
		act = map.act,
		rows = rows,
		boss = { id = map.boss.id, row = map.boss.row, col = 1, x = 0.5, kind = "boss", enemy = map.boss.enemy, next = {} },
	}
end

return MapGen
