--!strict
-- One complete shot: physics + scoring from frozen inputs. This is the
-- single function the server trusts and the client predicts with.

local Solver = require(script.Parent.Solver)
local Scoring = require(script.Parent.Scoring)
local Boards = require(script.Parent.Parent.Content.Boards)
local Balls = require(script.Parent.Parent.Content.Balls)

export type Input = {
	boardId: string,
	boardRev: number,
	aim: number,
	loadout: Scoring.Loadout,
}

export type Result = {
	sim: Solver.SimResult,
	outcome: Scoring.Outcome,
	fingerprint: string,
}

local Shot = {}

function Shot.resolve(input: Input): Result
	local board = Boards.ById[input.boardId]
	assert(board, "unknown board " .. input.boardId)
	assert(board.rev == input.boardRev, "board revision mismatch")
	assert(Balls.ById[input.loadout.ballId], "unknown ball " .. input.loadout.ballId)
	local sim = Solver.simulate(board, Scoring.physicsFor(input.loadout.ballId), input.aim)
	local outcome = Scoring.score(board, sim, input.loadout)
	local fp = Solver.fingerprint(sim) .. ":" .. tostring(outcome.totals.damage) .. ":" .. tostring(outcome.totals.shield) .. ":" .. tostring(outcome.totals.heal)
	return { sim = sim, outcome = outcome, fingerprint = fp }
end

return Shot
