--!strict
-- World placement for the code-built scene. Everything the client builds
-- lives under one root far above the Studio baseplate, so the authored place
-- is never touched or overlapped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Shared.Config)

local Layout = {}

Layout.ROOT = Vector3.new(0, 400, 0)
Layout.S = 0.2 -- studs per board unit (board = 12 × 16 studs)
Layout.BOARD_W = Config.Board.WIDTH * Layout.S
Layout.BOARD_H = Config.Board.HEIGHT * Layout.S
Layout.BOARD_CENTER = Layout.ROOT + Vector3.new(0, 11, 0)
Layout.PEG_Z = 0.32 -- pegs sit in front of the backplate
Layout.BALL_Z = 0.55
Layout.MONSTER_BASE = Layout.BOARD_CENTER + Vector3.new(15.5, -6.5, -2.5)
Layout.FLOOR_Y = Layout.ROOT.Y - 1.2

-- Region the fight camera must show (cabinet, HUD margin, monster).
Layout.VIEW_MIN = Vector2.new(-11.5, -10.2)
Layout.VIEW_MAX = Vector2.new(24, 10.4)

function Layout.boardToWorld(x: number, y: number, z: number?): Vector3
	local c = Layout.BOARD_CENTER
	return Vector3.new(
		c.X + (x - Config.Board.WIDTH / 2) * Layout.S,
		c.Y + (Config.Board.HEIGHT / 2 - y) * Layout.S,
		c.Z + (z or Layout.PEG_Z)
	)
end

function Layout.worldToBoard(p: Vector3): (number, number)
	local c = Layout.BOARD_CENTER
	return (p.X - c.X) / Layout.S + Config.Board.WIDTH / 2, Config.Board.HEIGHT / 2 - (p.Y - c.Y) / Layout.S
end

-- Fight camera: steady, frames the whole region for the current aspect.
function Layout.fightCamera(viewport: Vector2, fovDeg: number): CFrame
	local aspect = viewport.X / math.max(1, viewport.Y)
	local tanV = math.tan(math.rad(fovDeg) / 2)
	local tanH = tanV * aspect
	local halfW = (Layout.VIEW_MAX.X - Layout.VIEW_MIN.X) / 2
	local halfH = (Layout.VIEW_MAX.Y - Layout.VIEW_MIN.Y) / 2
	local dist = math.max(halfH / tanV, halfW / tanH)
	local cx = (Layout.VIEW_MIN.X + Layout.VIEW_MAX.X) / 2
	local cy = (Layout.VIEW_MIN.Y + Layout.VIEW_MAX.Y) / 2
	local target = Layout.BOARD_CENTER + Vector3.new(cx, cy, 0)
	local eye = target + Vector3.new(0, 0, dist)
	return CFrame.lookAt(eye, target)
end

-- Wide workshop shot used by the intro and between runs.
function Layout.workshopCamera(): CFrame
	local target = Layout.BOARD_CENTER + Vector3.new(4, -2, 0)
	return CFrame.lookAt(target + Vector3.new(-26, 10, 52), target)
end

return Layout
