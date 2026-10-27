--!strict
-- Small deterministic 2D circle/wall solver shared by server and client.
--
-- The server runs it for every accepted launch (authority); the client runs
-- the identical code for instant prediction and for re-creating teammates'
-- shots from their inputs. Determinism rules (plan §9):
--   * inputs are quantized integers (see Sim/Aim) — no trig in the solver
--   * fixed stepping (Config.Sim.STEP_HZ × SUBSTEPS), no frame-time input
--   * bounded speed, so travel per substep stays below a peg radius
--   * collisions resolved in a fixed order (grid cell order, then peg index)
--   * versioned boards; a shot records the board revision it used
-- Do not add `--!native` to this file: keep one code path on every device.

local Config = require(script.Parent.Parent.Config)
local Pegs = require(script.Parent.Parent.Content.Pegs)
local Aim = require(script.Parent.Aim)

local SIM = Config.Sim
local W = Config.Board.WIDTH
local H = Config.Board.HEIGHT

export type PegData = { x: number, y: number, kind: Pegs.PegKind }
export type WallData = { x1: number, y1: number, x2: number, y2: number }

export type Board = {
	id: string,
	rev: number,
	name: string,
	pegs: { PegData },
	walls: { WallData },
}

export type BallPhysics = {
	radius: number,
	restitutionMul: number,
	gravityMul: number,
	wallRestitution: number,
}

export type SimEvent = {
	step: number, -- 1-based fixed step at which the contact happened
	kind: "peg" | "wall",
	peg: number?, -- peg index for "peg" events (first contact only)
	x: number,
	y: number,
}

export type SimResult = {
	steps: number,
	endReason: "drain" | "timeout",
	xs: { number }, -- ball centre after each step (index = step)
	ys: { number },
	events: { SimEvent },
	pegFirstHit: { [number]: number }, -- peg index -> step
}

export type Options = {
	maxContacts: number?, -- stop after this many contacts (guide line)
	maxSteps: number?,
}

local CELL = 3.0
local COLS = math.ceil(W / CELL) + 1
local ROWS = math.ceil((H + 8) / CELL) + 1

type Grid = { [number]: { number } }

local gridCache: { [string]: Grid } = {}

local function cellIndex(cx: number, cy: number): number
	return cy * COLS + cx
end

local function buildGrid(board: Board): Grid
	local key = board.id .. "#" .. tostring(board.rev)
	local cached = gridCache[key]
	if cached then
		return cached
	end
	local grid: Grid = {}
	for i, peg in board.pegs do
		local cx = math.floor(peg.x / CELL)
		local cy = math.floor(peg.y / CELL)
		local idx = cellIndex(cx, cy)
		local list = grid[idx]
		if list == nil then
			list = {}
			grid[idx] = list
		end
		table.insert(list, i)
	end
	gridCache[key] = grid
	return grid
end

local Solver = {}

Solver.STEP_DT = 1 / SIM.STEP_HZ

function Solver.defaultPhysics(): BallPhysics
	return { radius = 1.0, restitutionMul = 1.0, gravityMul = 1.0, wallRestitution = SIM.WALL_RESTITUTION }
end

-- Runs one complete shot. Pure: same inputs always give the same result.
function Solver.simulate(board: Board, phys: BallPhysics, aim: number, opts: Options?): SimResult
	local grid = buildGrid(board)
	local pegs = board.pegs
	local walls = board.walls
	local pegDefs = Pegs.Defs

	local maxSteps = SIM.MAX_FLIGHT_STEPS
	local maxContacts: number? = nil
	if opts then
		maxSteps = opts.maxSteps or maxSteps
		maxContacts = opts.maxContacts
	end

	local dx, dy = Aim.direction(aim)
	local x = Config.Board.LAUNCH_X
	local y = Config.Board.LAUNCH_Y
	local vx = dx * SIM.LAUNCH_SPEED
	local vy = dy * SIM.LAUNCH_SPEED

	local r = phys.radius
	local g = SIM.GRAVITY * phys.gravityMul
	local h = 1 / (SIM.STEP_HZ * SIM.SUBSTEPS)
	local maxSpeed = SIM.MAX_SPEED
	local maxSpeed2 = maxSpeed * maxSpeed
	local wallE = phys.wallRestitution
	local keep = SIM.TANGENT_KEEP

	local xs: { number } = {}
	local ys: { number } = {}
	local events: { SimEvent } = {}
	local firstHit: { [number]: number } = {}
	local contacts = 0
	local stallSteps = 0
	local endReason: "drain" | "timeout" = "timeout"
	local steps = 0

	for step = 1, maxSteps do
		steps = step
		local drained = false
		for _ = 1, SIM.SUBSTEPS do
			vy += g * h
			local sp2 = vx * vx + vy * vy
			if sp2 > maxSpeed2 then
				local k = maxSpeed / math.sqrt(sp2)
				vx *= k
				vy *= k
			end
			x += vx * h
			y += vy * h

			-- Side walls and ceiling (planes).
			if x < r then
				x = r
				if vx < 0 then
					if -vx > 3 then
						table.insert(events, { step = step, kind = "wall", x = x, y = y })
						contacts += 1
					end
					vx = -vx * wallE
				end
			elseif x > W - r then
				x = W - r
				if vx > 0 then
					if vx > 3 then
						table.insert(events, { step = step, kind = "wall", x = x, y = y })
						contacts += 1
					end
					vx = -vx * wallE
				end
			end
			if y < r then
				y = r
				if vy < 0 then
					vy = -vy * wallE
				end
			end

			-- Board-specific wall segments, in board order.
			for _, w in walls do
				local ex = w.x2 - w.x1
				local ey = w.y2 - w.y1
				local len2 = ex * ex + ey * ey
				local t = ((x - w.x1) * ex + (y - w.y1) * ey) / len2
				if t < 0 then
					t = 0
				elseif t > 1 then
					t = 1
				end
				local px = w.x1 + ex * t
				local py = w.y1 + ey * t
				local ox = x - px
				local oy = y - py
				local d2 = ox * ox + oy * oy
				if d2 < r * r and d2 > 1e-12 then
					local d = math.sqrt(d2)
					local nx = ox / d
					local ny = oy / d
					x += nx * (r - d)
					y += ny * (r - d)
					local vn = vx * nx + vy * ny
					if vn < 0 then
						if -vn > 3 then
							table.insert(events, { step = step, kind = "wall", x = x, y = y })
							contacts += 1
						end
						local tx = vx - vn * nx
						local ty = vy - vn * ny
						-- Tangential friction only on real impacts, so rolling along
						-- a rail or peg crest does not grind the ball to a halt.
						local kt = if vn < -2 then keep else 1
						vx = tx * kt - vn * wallE * nx
						vy = ty * kt - vn * wallE * ny
					end
				end
			end

			-- Pegs: 3×3 grid neighbourhood in fixed row-major order.
			local cx = math.floor(x / CELL)
			local cy = math.floor(y / CELL)
			for oyc = -1, 1 do
				local row = cy + oyc
				if row >= 0 and row < ROWS then
					for oxc = -1, 1 do
						local col = cx + oxc
						if col >= 0 and col < COLS then
							local list = grid[cellIndex(col, row)]
							if list then
								for _, pi in list do
									local peg = pegs[pi]
									local def = pegDefs[peg.kind]
									local rr = r + def.radius
									local ox = x - peg.x
									local oy = y - peg.y
									local d2 = ox * ox + oy * oy
									if d2 < rr * rr then
										local d = math.sqrt(d2)
										local nx, ny
										if d > 1e-9 then
											nx = ox / d
											ny = oy / d
										else
											nx = 0
											ny = -1
										end
										x = peg.x + nx * rr
										y = peg.y + ny * rr
										local vn = vx * nx + vy * ny
										if vn < 0 then
											local e = def.restitution * phys.restitutionMul
											local tx = vx - vn * nx
											local ty = vy - vn * ny
											local outN = -vn * e
											-- A spring kicks only on its first contact each shot;
											-- later contacts are ordinary, so it cannot loop forever.
											if peg.kind == "spring" then
												if firstHit[pi] == nil then
													if outN < 26 then
														outN = 26
													end
												else
													outN = -vn * 0.7
												end
											end
											local kt = if vn < -2 then keep else 1
											vx = tx * kt + outN * nx
											vy = ty * kt + outN * ny
										end
										if firstHit[pi] == nil then
											firstHit[pi] = step
											table.insert(events, { step = step, kind = "peg", peg = pi, x = peg.x, y = peg.y })
											contacts += 1
										end
									end
								end
							end
						end
					end
				end
			end

			if y > H + r then
				drained = true
				break
			end
		end

		xs[step] = x
		ys[step] = y

		if drained then
			endReason = "drain"
			break
		end
		if maxContacts and contacts >= maxContacts then
			break
		end

		-- Deterministic stall nudge: a ball resting on a peg crest gets a
		-- small sideways push, alternating direction by step parity.
		if vx * vx + vy * vy < SIM.STALL_SPEED * SIM.STALL_SPEED then
			stallSteps += 1
			if stallSteps >= SIM.STALL_STEPS then
				vx += if step % 2 == 0 then 6 else -6
				stallSteps = 0
			end
		else
			stallSteps = 0
		end
	end

	return {
		steps = steps,
		endReason = endReason,
		xs = xs,
		ys = ys,
		events = events,
		pegFirstHit = firstHit,
	}
end

-- Order-sensitive fingerprint of a result, used for replay tests and for
-- logging client/server disagreement. Quantized to 1e-4 board units.
function Solver.fingerprint(res: SimResult): string
	local acc = 2166136261
	-- FNV-1a with the 32-bit multiply split so every intermediate stays an
	-- exact integer below 2^53 (16777619 = 2^24 + 403).
	local function mix(n: number)
		local a = bit32.bxor(acc, n % 4294967296)
		acc = ((a % 256) * 16777216 + a * 403) % 4294967296
	end
	mix(res.steps)
	for _, ev in res.events do
		mix(ev.step)
		mix(ev.peg or 0)
	end
	local last = res.steps
	if last > 0 then
		mix(math.floor(res.xs[last] * 10000 + 0.5))
		mix(math.floor(res.ys[last] * 10000 + 0.5))
	end
	return string.format("%08x:%d:%d", acc, res.steps, #res.events)
end

return Solver
