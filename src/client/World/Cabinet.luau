--!strict
-- The rune altar around the player's board: a gothic stone frame with gold
-- trim, chasing rune lights along the arch, candles on the shoulders, a
-- starry backplate, and a floating orb launcher. Code-built and kept in one
-- module so a modelled altar can replace it later without touching
-- gameplay. The aiming surface never moves; recoil and shake go to the
-- frame and launcher only.
-- (Module name kept from the earlier "cabinet" so callers stay stable.)

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Build = require(script.Parent.Build)
local Layout = require(script.Parent.Layout)

export type Palette = { frame: Color3, trim: Color3, back: Color3, glow: Color3 }

local Cabinet = {}
Cabinet.__index = Cabinet

export type Cabinet = typeof(setmetatable(
	{} :: {
		model: Model,
		frame: Model,
		frameParts: { { part: BasePart, base: CFrame } },
		trimParts: { BasePart },
		backPart: BasePart,
		backGui: SurfaceGui,
		backGradient: UIGradient,
		stars: { Frame },
		bulbs: { BasePart },
		glowParts: { BasePart },
		orb: BasePart,
		orbRing: BasePart,
		orbCore: BasePart,
		barrel: BasePart,
		muzzle: Attachment,
		aimAngle: number,
		recoil: number,
		shake: number,
		chase: number,
		chaseSpeed: number,
		celebrate: number,
		t: number,
		conn: RBXScriptConnection?,
		palette: Palette,
		reducedMotion: boolean,
	},
	Cabinet
))

local W = Layout.BOARD_W
local H = Layout.BOARD_H
local SIDE = 1.4
local DEPTH = 2.0
local TOP = 2.2
local BOTTOM = 1.6

local STONE = Color3.fromRGB(34, 32, 64)
local STONE_DARK = Color3.fromRGB(18, 16, 40)
local GOLD = Color3.fromRGB(214, 160, 70)

function Cabinet.turretColor(trim: Color3): Color3
	return trim:Lerp(Color3.new(1, 1, 1), 0.35)
end

function Cabinet.new(parent: Instance, palette: Palette): Cabinet
	local self = setmetatable({}, Cabinet) :: any
	self.palette = palette
	self.model = Build.model("Altar", parent)
	self.frame = Build.model("Frame", self.model)
	self.frameParts = {}
	self.trimParts = {}
	self.bulbs = {}
	self.glowParts = {}
	self.stars = {}
	self.aimAngle = 0
	self.recoil = 0
	self.shake = 0
	self.chase = 0
	self.chaseSpeed = 3
	self.celebrate = 0
	self.t = 0
	self.reducedMotion = false

	local c = Layout.BOARD_CENTER
	local frame = self.frame
	local function framePart(p: BasePart)
		table.insert(self.frameParts, { part = p, base = p.CFrame })
	end
	local function stone(size: Vector3, cf: CFrame, col: Color3?): BasePart
		local p = Build.block(frame, size, cf, col or STONE, { material = Enum.Material.Slate })
		framePart(p)
		return p
	end

	-- Backplate: deep night with a soft vertical gradient and star specks.
	local back = Build.block(self.model, Vector3.new(W + 0.4, H + 0.4, 0.4), CFrame.new(c + Vector3.new(0, 0, -0.2)), palette.back, { name = "Backplate" })
	self.backPart = back
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0.15
	gui.Parent = back
	self.backGui = gui
	local grad = Instance.new("Frame")
	grad.Size = UDim2.fromScale(1, 1)
	grad.BackgroundColor3 = Color3.new(1, 1, 1)
	grad.BorderSizePixel = 0
	grad.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Parent = grad
	self.backGradient = g
	local rng = Random.new(7)
	for _ = 1, 46 do
		local s = rng:NextInteger(2, 5)
		local star = Instance.new("Frame")
		star.Size = UDim2.fromOffset(s, s)
		star.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
		star.BackgroundColor3 = Color3.new(1, 1, 1)
		star.BackgroundTransparency = rng:NextNumber(0.35, 0.8)
		star.BorderSizePixel = 0
		local cr = Instance.new("UICorner")
		cr.CornerRadius = UDim.new(1, 0)
		cr.Parent = star
		star.Parent = grad
		table.insert(self.stars, star)
	end
	-- Faint vertical rune lines.
	for i = 1, 5 do
		local line = Instance.new("Frame")
		line.BackgroundColor3 = Color3.fromRGB(150, 170, 255)
		line.BackgroundTransparency = 0.93
		line.BorderSizePixel = 0
		line.Size = UDim2.new(0, 2, 1, 0)
		line.Position = UDim2.fromScale(i / 6, 0)
		line.Parent = grad
	end
	-- Drain: a glowing rune channel along the bottom.
	local drain = Build.block(self.model, Vector3.new(W, 0.3, 0.6), CFrame.new(c + Vector3.new(0, -H / 2 - 0.05, 0.1)), palette.glow, { material = Enum.Material.Neon, name = "Drain" })
	table.insert(self.glowParts, drain)

	-- Frame: stone pillars, arch header, plinth.
	stone(Vector3.new(SIDE, H + 0.6, DEPTH), CFrame.new(c + Vector3.new(-W / 2 - SIDE / 2, 0, 0.3)))
	stone(Vector3.new(SIDE, H + 0.6, DEPTH), CFrame.new(c + Vector3.new(W / 2 + SIDE / 2, 0, 0.3)))
	stone(Vector3.new(W + SIDE * 2, TOP, DEPTH + 0.3), CFrame.new(c + Vector3.new(0, H / 2 + TOP / 2, 0.35)))
	stone(Vector3.new(W + SIDE * 2 + 0.8, BOTTOM, DEPTH + 0.8), CFrame.new(c + Vector3.new(0, -H / 2 - BOTTOM / 2, 0.45)), STONE_DARK)
	-- Pointed arch: two wedges meeting above the header.
	for _, sx in { -1, 1 } do
		local w = Build.wedge(frame, Vector3.new(DEPTH, 2.4, W / 2 + SIDE), CFrame.new(c + Vector3.new(sx * (W / 4 + SIDE / 2), H / 2 + TOP + 1.2, 0.35)) * CFrame.Angles(0, math.rad(sx * -90), 0), STONE, { material = Enum.Material.Slate })
		framePart(w)
	end
	-- Pillar capitals and bases.
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local y = if sy > 0 then H / 2 + 0.1 else -H / 2 - 0.1
			stone(Vector3.new(SIDE + 0.6, 0.7, DEPTH + 0.5), CFrame.new(c + Vector3.new(sx * (W / 2 + SIDE / 2), y, 0.35)), STONE_DARK)
		end
	end
	-- Gold trim around the opening.
	local trims = {
		Build.block(frame, Vector3.new(0.22, H + 0.3, 0.25), CFrame.new(c + Vector3.new(-W / 2 - 0.12, 0, 1.35)), GOLD, { material = Enum.Material.Metal }),
		Build.block(frame, Vector3.new(0.22, H + 0.3, 0.25), CFrame.new(c + Vector3.new(W / 2 + 0.12, 0, 1.35)), GOLD, { material = Enum.Material.Metal }),
		Build.block(frame, Vector3.new(W + 0.5, 0.22, 0.25), CFrame.new(c + Vector3.new(0, H / 2 + 0.12, 1.45)), GOLD, { material = Enum.Material.Metal }),
		Build.block(frame, Vector3.new(W + SIDE * 2, 0.25, 0.25), CFrame.new(c + Vector3.new(0, -H / 2 - BOTTOM + 0.3, 1.9)), GOLD, { material = Enum.Material.Metal }),
	}
	for _, t in trims do
		table.insert(self.trimParts, t)
		framePart(t)
	end
	-- Rune lights along the header (chasing).
	local count = 13
	for i = 1, count do
		local x = -W / 2 + 0.4 + (i - 0.5) * ((W - 0.8) / count)
		local rune = Build.block(frame, Vector3.new(0.34, 0.34, 0.2), CFrame.new(c + Vector3.new(x, H / 2 + TOP / 2 + 0.05, 1.55)) * CFrame.Angles(0, 0, math.rad(45)), palette.glow, { material = Enum.Material.Neon })
		table.insert(self.bulbs, rune)
		framePart(rune)
	end
	-- Rune strips down the pillars.
	for _, sx in { -1, 1 } do
		local strip = Build.block(frame, Vector3.new(0.18, H - 1, 0.1), CFrame.new(c + Vector3.new(sx * (W / 2 + SIDE / 2), 0, 1.33)), palette.glow, { material = Enum.Material.Neon, transparency = 0.25 })
		table.insert(self.glowParts, strip)
		framePart(strip)
	end
	-- Candles on the shoulders.
	for _, sx in { -1, 1 } do
		for k = 0, 1 do
			local x = sx * (W / 2 + SIDE / 2 + (k - 0.5) * 0.5)
			local h = 0.9 - k * 0.35
			local candle = Build.cylinder(frame, h, 0.32, CFrame.new(c + Vector3.new(x, H / 2 + TOP + h / 2, 0.6 + k * 0.3)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(230, 214, 190))
			framePart(candle)
			local flame = Build.ball(frame, 0.22, c + Vector3.new(x, H / 2 + TOP + h + 0.15, 0.6 + k * 0.3), Color3.fromRGB(255, 170, 80), { material = Enum.Material.Neon })
			framePart(flame)
			if k == 0 then
				local fire = Instance.new("Fire")
				fire.Size = 1.2
				fire.Heat = 4
				fire.Color = Color3.fromRGB(255, 140, 60)
				fire.SecondaryColor = Color3.fromRGB(255, 220, 140)
				fire.Parent = flame
			end
		end
	end
	-- Plinth steps down to the floor.
	local stepTop = c.Y - H / 2 - BOTTOM
	local stepH = stepTop - Layout.FLOOR_Y
	if stepH > 0.2 then
		stone(Vector3.new(W + SIDE * 2 + 1.6, stepH, DEPTH + 2), CFrame.new(Vector3.new(c.X, Layout.FLOOR_Y + stepH / 2, c.Z + 0.6)), STONE_DARK)
	end

	-- Orb launcher: a floating crystal orb with a gold ring, pointing along the aim.
	local launchPos = Layout.boardToWorld(30, 3, 0.9)
	self.orb = Build.ball(self.model, 1.7, launchPos + Vector3.new(0, 0.5, 0.2), Color3.fromRGB(30, 26, 80), { material = Enum.Material.Glass, transparency = 0.15, name = "Orb" })
	self.orbCore = Build.ball(self.model, 0.9, launchPos + Vector3.new(0, 0.5, 0.2), palette.glow, { material = Enum.Material.Neon, name = "OrbCore" })
	self.orbRing = Build.cylinder(self.model, 0.12, 2.3, CFrame.new(launchPos), GOLD, { material = Enum.Material.Metal, name = "OrbRing" })
	self.barrel = Build.cylinder(self.model, 1.5, 0.55, CFrame.new(launchPos), Color3.fromRGB(230, 220, 255), { material = Enum.Material.Neon, transparency = 0.2, name = "Barrel" })
	local att = Instance.new("Attachment")
	att.Parent = self.barrel
	att.Position = Vector3.new(-0.8, 0, 0)
	self.muzzle = att
	local pl = Instance.new("PointLight")
	pl.Color = palette.glow
	pl.Brightness = 0.8
	pl.Range = 6
	pl.Parent = self.orbCore

	Cabinet.setPalette(self, palette, false)
	self.conn = RunService.RenderStepped:Connect(function(dt)
		Cabinet._step(self, dt)
	end)
	return self
end

function Cabinet.setPalette(self: Cabinet, palette: Palette, animate: boolean?)
	self.palette = palette
	local t = if animate then 0.8 else 0
	local function to(p: BasePart, col: Color3)
		if t > 0 then
			TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad), { Color = col }):Play()
		else
			p.Color = col
		end
	end
	for _, b in self.bulbs do
		to(b, palette.glow)
	end
	for _, gp in self.glowParts do
		to(gp, palette.glow)
	end
	to(self.backPart, palette.back)
	to(self.orbCore, palette.glow)
	local light = self.orbCore:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = palette.glow
	end
	self.backGradient.Color = ColorSequence.new(palette.back:Lerp(palette.glow, 0.18), palette.back:Lerp(Color3.new(0, 0, 0), 0.45))
end

-- Direction in board space (dy > 0 is down the board).
function Cabinet.setAim(self: Cabinet, dx: number, dy: number)
	self.aimAngle = math.atan2(dx, dy)
end

function Cabinet.kick(self: Cabinet, amount: number)
	self.recoil = math.max(self.recoil, amount)
end

function Cabinet.shakeFrame(self: Cabinet, amount: number)
	if self.reducedMotion then
		return
	end
	self.shake = math.min(0.6, math.max(self.shake, amount))
end

function Cabinet.cheer(self: Cabinet, seconds: number)
	self.celebrate = seconds
end

function Cabinet._step(self: Cabinet, dt: number)
	self.t += dt
	local launchPos = Layout.boardToWorld(30, 3, 0.9)
	self.recoil = math.max(0, self.recoil - dt * 3.5)
	local dir = Vector3.new(math.sin(self.aimAngle), -math.cos(self.aimAngle), 0)
	local back = dir * (-self.recoil * 0.5)
	local bob = if self.reducedMotion then 0 else math.sin(self.t * 2) * 0.08
	local orbPos = launchPos + Vector3.new(0, 0.45 + bob, 0.2) + back
	self.orb.CFrame = CFrame.new(orbPos)
	self.orbCore.CFrame = CFrame.new(orbPos)
	self.orbRing.CFrame = CFrame.lookAt(orbPos, orbPos + dir) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(self.t * 1.5, 0, 0)
	self.barrel.CFrame = CFrame.lookAt(orbPos + dir * 1.1, orbPos + dir * 3) * CFrame.Angles(0, math.rad(90), 0)
	self.barrel.Transparency = 0.2 + 0.25 * (0.5 + 0.5 * math.sin(self.t * 5))

	-- Frame shake (never the board or camera).
	self.shake = math.max(0, self.shake - dt * 2.2)
	if self.shake > 0.001 then
		local s = self.shake
		local off = Vector3.new((math.random() - 0.5) * s, (math.random() - 0.5) * s, 0)
		local parts = table.create(#self.frameParts)
		local cfs = table.create(#self.frameParts)
		for i, fp in self.frameParts do
			parts[i] = fp.part
			cfs[i] = fp.base + off
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	elseif self.shake == 0 and self.frameParts[1].part.CFrame ~= self.frameParts[1].base then
		local parts = table.create(#self.frameParts)
		local cfs = table.create(#self.frameParts)
		for i, fp in self.frameParts do
			parts[i] = fp.part
			cfs[i] = fp.base
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- Rune chase; faster and brighter while celebrating.
	self.celebrate = math.max(0, self.celebrate - dt)
	local speed = if self.celebrate > 0 then 14 else self.chaseSpeed
	self.chase += dt * speed
	for i, b in self.bulbs do
		local phase = (self.chase - i * 0.5) % 3
		b.Transparency = if phase < 1.0 then 0 else 0.6
	end
	-- Stars twinkle.
	if not self.reducedMotion then
		local n = #self.stars
		local idx = (math.floor(self.t * 12) % n) + 1
		local star = self.stars[idx]
		star.BackgroundTransparency = 0.1 + 0.7 * math.abs(math.sin(self.t + idx))
	end
end

function Cabinet.destroy(self: Cabinet)
	if self.conn then
		self.conn:Disconnect()
	end
	self.model:Destroy()
end

return Cabinet
