--!strict
-- World placement for the code-built scenes. Everything the client builds
-- lives far above the Studio baseplate, so the authored place is never
-- touched or overlapped.
--
-- Fight view (camera looks along -Z):
--   left   the rune altar holding the board
--   right  the battlefield: party heroes near the altar, the monster beyond
--   behind act scenery, giant eyes, the vortex sky

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
Layout.FLOOR_Y = Layout.ROOT.Y - 1.2 -- ground the altar stands on
-- The battle ledge is raised so the party and the monster stand at the
-- board's mid-height: clear of the HUD along the bottom of the screen.
Layout.BATTLE_Y = Layout.BOARD_CENTER.Y - 6.6
Layout.LEDGE_X = Layout.BOARD_CENTER.X + 9 -- ledge starts right of the altar

-- Battlefield: heroes stand in a staggered line facing the monster.
Layout.HERO_ANCHOR = Vector3.new(Layout.BOARD_CENTER.X + 11.5, Layout.BATTLE_Y, Layout.BOARD_CENTER.Z - 3)
Layout.MONSTER_BASE = Vector3.new(Layout.BOARD_CENTER.X + 23.6, Layout.BATTLE_Y, Layout.BOARD_CENTER.Z - 6)
Layout.HERO_FACING = Vector3.new(1, 0, 0.55).Unit
Layout.MONSTER_FACING = Vector3.new(-1, 0, 0.75).Unit

-- Lobby hall (a separate set far behind the fight scene).
Layout.LOBBY = Vector3.new(0, 400, 600)

-- Region the fight camera must show (relative to BOARD_CENTER).
Layout.VIEW_MIN = Vector2.new(-9.5, -13.2)
Layout.VIEW_MAX = Vector2.new(35, 11.6)

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

-- Hero stand positions for seat 1..4 (front row nearest the monster).
function Layout.heroSpot(seat: number, count: number): Vector3
	local a = Layout.HERO_ANCHOR
	local spots = {
		Vector3.new(2.4, 0, 1.2),
		Vector3.new(0.4, 0, -1.6),
		Vector3.new(-0.6, 0, 2.2),
		Vector3.new(-2.0, 0, -0.6),
	}
	if count == 1 then
		return a + Vector3.new(1.4, 0, 0.4)
	end
	return a + spots[math.clamp(seat, 1, 4)]
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

-- Lobby camera: looks at the party on the dais with the hall behind.
function Layout.lobbyCamera(): CFrame
	local target = Layout.LOBBY + Vector3.new(0, 4.2, -2)
	return CFrame.lookAt(target + Vector3.new(4, 3.2, 21), target)
end

-- Kept for older callers: the "workshop" view is now the lobby hall.
function Layout.workshopCamera(): CFrame
	return Layout.lobbyCamera()
end

return Layout
