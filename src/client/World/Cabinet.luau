--!strict
-- The toy-machine cabinet around the player's board: chunky frame, marquee
-- with chasing bulbs, launcher turret, drain glow. Code-built and kept in
-- one module so a modelled cabinet can replace it later without touching
-- gameplay. The aiming surface never moves; recoil and shake go to the
-- frame and launcher only (plan §10).

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
		bulbs: { BasePart },
		glowParts: { BasePart },
		turretBase: BasePart,
		barrel: BasePart,
		barrelCap: BasePart,
		muzzle: Attachment,
		aimAngle: number,
		recoil: number,
		shake: number,
		chase: number,
		chaseSpeed: number,
		celebrate: number,
		conn: RBXScriptConnection?,
		palette: Palette,
		reducedMotion: boolean,
	},
	Cabinet
))

local W = Layout.BOARD_W
local H = Layout.BOARD_H
local SIDE = 1.5
local DEPTH = 2.2
local TOP = 2.6
local BOTTOM = 1.7

function Cabinet.new(parent: Instance, palette: Palette): Cabinet
	local self = setmetatable({}, Cabinet) :: any
	self.palette = palette
	self.model = Build.model("Cabinet", parent)
	self.frame = Build.model("Frame", self.model)
	self.frameParts = {}
	self.trimParts = {}
	self.bulbs = {}
	self.glowParts = {}
	self.aimAngle = 0
	self.recoil = 0
	self.shake = 0
	self.chase = 0
	self.chaseSpeed = 4
	self.celebrate = 0
	self.reducedMotion = false

	local c = Layout.BOARD_CENTER
	local frame = self.frame
	local function framePart(p: BasePart)
		table.insert(self.frameParts, { part = p, base = p.CFrame })
	end

	-- Backplate with a soft vertical gradient and faint guide lines.
	local back = Build.block(self.model, Vector3.new(W + 0.4, H + 0.4, 0.4), CFrame.new(c + Vector3.new(0, 0, -0.2)), palette.back, { name = "Backplate" })
	self.backPart = back
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0.4
	gui.Parent = back
	self.backGui = gui
	local grad = Instance.new("Frame")
	grad.Size = UDim2.fromScale(1, 1)
	grad.BackgroundColor3 = Color3.new(1, 1, 1)
	grad.BorderSizePixel = 0
	grad.Parent = gui
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(palette.back:Lerp(Color3.new(1, 1, 1), 0.12), palette.back:Lerp(Color3.new(0, 0, 0), 0.25))
	g.Parent = grad
	self.backGradient = g
	for i = 1, 7 do
		local line = Instance.new("Frame")
		line.BackgroundColor3 = Color3.new(1, 1, 1)
		line.BackgroundTransparency = 0.94
		line.BorderSizePixel = 0
		line.Size = UDim2.new(0, 2, 1, 0)
		line.Position = UDim2.fromScale(i / 8, 0)
		line.Parent = grad
	end
	-- Drain lip at the bottom of the board.
	local drain = Build.block(self.model, Vector3.new(W, 0.35, 0.6), CFrame.new(c + Vector3.new(0, -H / 2 - 0.05, 0.1)), palette.glow, { material = Enum.Material.Neon, name = "Drain" })
	table.insert(self.glowParts, drain)

	-- Frame: pillars, header, base, rounded corners.
	local fc = palette.frame
	local left = Build.block(frame, Vector3.new(SIDE, H + 0.6, DEPTH), CFrame.new(c + Vector3.new(-W / 2 - SIDE / 2, 0, 0.3)), fc)
	local right = Build.block(frame, Vector3.new(SIDE, H + 0.6, DEPTH), CFrame.new(c + Vector3.new(W / 2 + SIDE / 2, 0, 0.3)), fc)
	local header = Build.block(frame, Vector3.new(W + SIDE * 2, TOP, DEPTH + 0.3), CFrame.new(c + Vector3.new(0, H / 2 + TOP / 2, 0.35)), fc)
	local basePart = Build.block(frame, Vector3.new(W + SIDE * 2, BOTTOM, DEPTH + 0.6), CFrame.new(c + Vector3.new(0, -H / 2 - BOTTOM / 2, 0.45)), fc)
	for _, p in { left, right, header, basePart } do
		framePart(p)
	end
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local cx = sx * (W / 2 + SIDE / 2)
			local cy = sy * (H / 2 + (if sy > 0 then TOP else BOTTOM) - 0.2)
			local cap = Build.cylinder(frame, DEPTH + 0.5, SIDE * 1.4, CFrame.new(c + Vector3.new(cx, cy, 0.4)) * CFrame.Angles(0, math.rad(90), 0), fc)
			framePart(cap)
		end
	end
	-- Inner trim strips.
	local tc = palette.trim
	local trims = {
		Build.block(frame, Vector3.new(0.3, H + 0.4, 0.3), CFrame.new(c + Vector3.new(-W / 2 - 0.15, 0, 1.45)), tc),
		Build.block(frame, Vector3.new(0.3, H + 0.4, 0.3), CFrame.new(c + Vector3.new(W / 2 + 0.15, 0, 1.45)), tc),
		Build.block(frame, Vector3.new(W + 0.6, 0.3, 0.3), CFrame.new(c + Vector3.new(0, H / 2 + 0.15, 1.55)), tc),
		Build.block(frame, Vector3.new(W + SIDE * 2 - 0.4, 0.35, 0.3), CFrame.new(c + Vector3.new(0, -H / 2 - BOTTOM + 0.35, 1.8)), tc),
	}
	for _, t in trims do
		table.insert(self.trimParts, t)
		framePart(t)
	end
	-- Marquee panel and bulbs.
	local marquee = Build.block(frame, Vector3.new(W - 1.2, TOP - 0.9, 0.3), CFrame.new(c + Vector3.new(0, H / 2 + TOP / 2 + 0.05, 1.6)), palette.back, { name = "Marquee" })
	framePart(marquee)
	local count = 14
	for i = 1, count do
		local x = -W / 2 + 0.2 + (i - 0.5) * ((W - 0.4) / count)
		local bulb = Build.ball(frame, 0.42, c + Vector3.new(x, H / 2 + TOP - 0.38, 1.7), palette.glow, { material = Enum.Material.Neon })
		table.insert(self.bulbs, bulb)
		framePart(bulb)
	end
	-- Feet on the floor.
	for _, sx in { -1, 1 } do
		local foot = Build.block(frame, Vector3.new(2.2, 1.2, DEPTH + 1), CFrame.new(Vector3.new(c.X + sx * (W / 2 - 0.6), Layout.FLOOR_Y + 0.6, c.Z + 0.4)), Build.INK)
		local leg = Build.block(frame, Vector3.new(1.2, c.Y - H / 2 - BOTTOM - Layout.FLOOR_Y - 1.0, 1.2), CFrame.new(Vector3.new(c.X + sx * (W / 2 - 0.6), (c.Y - H / 2 - BOTTOM + Layout.FLOOR_Y + 1.2) / 2, c.Z + 0.4)), fc)
		framePart(foot)
		framePart(leg)
	end
	Build.outline(frame)

	-- Launcher turret at the board's launch point, poking out of the header.
	local launchPos = Layout.boardToWorld(30, 3, 0.9)
	self.turretBase = Build.ball(self.model, 2.4, launchPos + Vector3.new(0, 0.35, 0), palette.trim, { name = "Turret" })
	self.barrel = Build.cylinder(self.model, 2.0, 1.0, CFrame.new(launchPos), Color3.fromRGB(245, 245, 255), { name = "Barrel" })
	self.barrelCap = Build.cylinder(self.model, 0.35, 1.25, CFrame.new(launchPos), Build.INK, { name = "BarrelCap" })
	local att = Instance.new("Attachment")
	att.Parent = self.barrel
	att.Position = Vector3.new(-1.0, 0, 0)
	self.muzzle = att
	local turretModel = Build.model("TurretOutline", self.model)
	self.turretBase.Parent = turretModel
	self.barrel.Parent = turretModel
	self.barrelCap.Parent = turretModel
	Build.outline(turretModel)

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
	for _, fp in self.frameParts do
		local p = fp.part
		if table.find(self.bulbs, p) then
			to(p, palette.glow)
		elseif table.find(self.trimParts, p) then
			to(p, palette.trim)
		elseif p.Name == "Marquee" then
			to(p, palette.back)
		elseif p.Color ~= Build.INK then
			to(p, palette.frame)
		end
	end
	to(self.backPart, palette.back)
	to(self.turretBase, palette.trim)
	for _, gp in self.glowParts do
		to(gp, palette.glow)
	end
	self.backGradient.Color = ColorSequence.new(palette.back:Lerp(Color3.new(1, 1, 1), 0.12), palette.back:Lerp(Color3.new(0, 0, 0), 0.25))
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
	-- Launcher: points along the aim; recoil slides the barrel back.
	local launchPos = Layout.boardToWorld(30, 3, 0.9)
	self.recoil = math.max(0, self.recoil - dt * 3.5)
	local dir = Vector3.new(math.sin(self.aimAngle), -math.cos(self.aimAngle), 0)
	local back = dir * (-self.recoil * 0.6)
	local cf = CFrame.lookAt(launchPos + dir * 0.9 + back, launchPos + dir * 3 + back) * CFrame.Angles(0, math.rad(90), 0)
	self.barrel.CFrame = cf
	self.barrelCap.CFrame = CFrame.lookAt(launchPos + dir * 1.85 + back, launchPos + dir * 4 + back) * CFrame.Angles(0, math.rad(90), 0)

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

	-- Marquee chase; faster and brighter while celebrating.
	self.celebrate = math.max(0, self.celebrate - dt)
	local speed = if self.celebrate > 0 then 16 else self.chaseSpeed
	self.chase += dt * speed
	for i, b in self.bulbs do
		local phase = (self.chase - i * 0.6) % 3
		local on = phase < 1.2
		b.Transparency = if on then 0 else 0.55
	end
end

function Cabinet.destroy(self: Cabinet)
	if self.conn then
		self.conn:Disconnect()
	end
	self.model:Destroy()
end

return Cabinet
