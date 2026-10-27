--!strict
-- The dark-fantasy, psychedelic world around the fight: night lighting with
-- heavy bloom, a slowly turning vortex in the sky, giant eyes that watch the
-- ball, a ringed planet and nebula, a glowing checkerboard battlefield, and
-- one set per act (drowned crypt, floating isle, vortex spire).
-- Presentation only: client-side, anchored, non-colliding.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Campaigns = require(Shared.Content.Campaigns)

local Build = require(script.Parent.Build)
local Layout = require(script.Parent.Layout)

export type ActPalette = { deep: Color3, glow: Color3, accent: Color3, warm: Color3 }

type Eye = {
	model: Model,
	white: BasePart,
	iris: BasePart,
	ring: BasePart,
	pupil: BasePart,
	lidTop: BasePart,
	lidBottom: BasePart,
	center: Vector3,
	radius: number,
	blinkAt: number,
	blink: number,
}

type Spin = { parts: { BasePart }, base: { CFrame }, pivot: CFrame, speed: number, angle: number }

local Scenery = {}

local root: Folder
local skyFolder: Folder
local setFolder: Folder
local floorTiles: { { part: BasePart, a: Color3, b: Color3, phase: number } } = {}
local eyes: { Eye } = {}
local spins: { Spin } = {}
local glowPulse: { { part: BasePart, base: number, speed: number } } = {}
local lookTarget: Vector3? = nil
local currentScene = ""
local palette: ActPalette = Campaigns.ById.abyss.acts[1].palette
local t = 0
local reduced = false
local conn: RBXScriptConnection? = nil

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function pulseOn(part: BasePart, base: number, speed: number)
	table.insert(glowPulse, { part = part, base = base, speed = speed })
end

-- Lighting ------------------------------------------------------------------

local function ensure(className: string, name: string, parent: Instance): Instance
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

function Scenery.applyLighting(p: ActPalette, mood: "fight" | "lobby")
	Lighting.ClockTime = 0.2
	Lighting.Brightness = if mood == "lobby" then 1.6 else 1.4
	Lighting.Ambient = p.deep:Lerp(rgb(70, 64, 140), 0.55)
	Lighting.OutdoorAmbient = p.deep:Lerp(rgb(110, 100, 200), 0.6)
	Lighting.EnvironmentDiffuseScale = 0.35
	Lighting.EnvironmentSpecularScale = 0.7
	Lighting.GlobalShadows = true
	local cc = ensure("ColorCorrectionEffect", "AbyssGrade", Lighting) :: ColorCorrectionEffect
	cc.Brightness = 0.02
	cc.Contrast = 0.2
	cc.Saturation = 0.28
	cc.TintColor = Color3.new(1, 1, 1):Lerp(p.glow, 0.12)
	local bloom = ensure("BloomEffect", "AbyssBloom", Lighting) :: BloomEffect
	bloom.Intensity = 0.85
	bloom.Size = 30
	bloom.Threshold = 0.82
	-- Disable other bloom/sunrays the place may carry so ours is the look.
	for _, e in Lighting:GetChildren() do
		if (e:IsA("BloomEffect") and e ~= bloom) or e:IsA("SunRaysEffect") then
			(e :: any).Enabled = false
		end
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = if mood == "lobby" then 0.2 else 0.3
	atmo.Offset = 0.2
	atmo.Color = p.deep:Lerp(p.glow, 0.35)
	atmo.Decay = p.deep:Lerp(rgb(120, 40, 160), 0.4)
	atmo.Glare = 0.35
	atmo.Haze = 1.4
	atmo.Parent = Lighting
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.StarCount = 3000
	sky.CelestialBodiesShown = true
	sky.MoonAngularSize = 14
	sky.Parent = Lighting
end

-- Sky pieces ----------------------------------------------------------------

local function newEye(parent: Instance, center: Vector3, radius: number, iris: Color3, sclera: Color3): Eye
	local m = Build.model("Eye", parent)
	local facing = CFrame.lookAt(center, center + Vector3.new(0, -0.15, 1))
	local white = Build.ellipsoid(m, Vector3.new(radius * 2.4, radius * 1.4, radius * 1.2), facing, sclera, { material = Enum.Material.SmoothPlastic })
	local ring = Build.disc(m, radius * 1.05, 0.1, center + Vector3.new(0, 0, radius * 0.6), iris:Lerp(Color3.new(1, 1, 1), 0.35), { material = Enum.Material.Neon })
	local irisPart = Build.disc(m, radius * 0.92, 0.12, center + Vector3.new(0, 0, radius * 0.62), iris, { material = Enum.Material.Neon })
	local pupil = Build.disc(m, radius * 0.38, 0.14, center + Vector3.new(0, 0, radius * 0.66), rgb(2, 2, 8))
	local lidCol = rgb(12, 10, 30)
	local lidTop = Build.ellipsoid(m, Vector3.new(radius * 2.6, radius * 0.9, radius * 1.4), facing * CFrame.new(0, radius * 0.95, 0), lidCol)
	local lidBottom = Build.ellipsoid(m, Vector3.new(radius * 2.6, radius * 0.9, radius * 1.4), facing * CFrame.new(0, -radius * 0.95, 0), lidCol)
	-- A dark lash ring around the eye.
	Build.ellipsoid(m, Vector3.new(radius * 2.8, radius * 1.7, radius * 1.0), facing * CFrame.new(0, 0, -radius * 0.15), lidCol)
	return {
		model = m,
		white = white,
		iris = irisPart,
		ring = ring,
		pupil = pupil,
		lidTop = lidTop,
		lidBottom = lidBottom,
		center = center,
		radius = radius,
		blinkAt = os.clock() + math.random() * 6 + 2,
		blink = 0,
	}
end

local function buildVortex(parent: Instance, center: Vector3, radius: number, colors: { Color3 })
	local parts: { BasePart } = {}
	local base: { CFrame } = {}
	local pivot = CFrame.lookAt(center, center + Vector3.new(0, 0.2, 1))
	local arms = 5
	local segs = 26
	for a = 1, arms do
		local col = colors[(a - 1) % #colors + 1]
		for s = 1, segs do
			local u = s / segs
			local ang = (a / arms) * math.pi * 2 + u * math.pi * 2.6
			local r = radius * (0.08 + u * 0.92)
			local pos = Vector3.new(math.cos(ang) * r, math.sin(ang) * r, -u * 2)
			local len = radius * 0.16 * (0.5 + u)
			local p = Build.block(parent, Vector3.new(len, radius * 0.05 * (0.4 + u), 0.4), CFrame.new(), col, {
				material = Enum.Material.Neon,
				transparency = 0.25 + u * 0.55,
			})
			local cf = CFrame.new(pos) * CFrame.Angles(0, 0, ang + math.pi / 2)
			table.insert(parts, p)
			table.insert(base, cf)
		end
	end
	-- Bright core.
	local core = Build.ball(parent, radius * 0.18, center, rgb(230, 240, 255), { material = Enum.Material.Neon })
	pulseOn(core, 0, 1.3)
	local halo = Build.ball(parent, radius * 0.5, center + Vector3.new(0, 0, -1), colors[1], { material = Enum.Material.ForceField, transparency = 0.2 })
	table.insert(spins, { parts = parts, base = base, pivot = pivot, speed = 0.12, angle = 0 })
	return halo
end

local function buildPlanet(parent: Instance, center: Vector3, radius: number, body: Color3, ringCol: Color3)
	Build.ball(parent, radius * 2, center, body, { material = Enum.Material.SmoothPlastic })
	local tilt = CFrame.new(center) * CFrame.Angles(math.rad(70), math.rad(10), math.rad(-18))
	Build.cylinder(parent, 0.2, radius * 4.2, tilt * CFrame.Angles(0, 0, math.rad(90)), ringCol, { material = Enum.Material.Neon, transparency = 0.45 })
	Build.cylinder(parent, 0.22, radius * 3.3, tilt * CFrame.Angles(0, 0, math.rad(90)), Color3.new(0, 0, 0), { transparency = 0.2 })
end

local function nebula(parent: Instance, center: Vector3, size: Vector3, col: Color3, transparency: number)
	Build.ellipsoid(parent, size, CFrame.new(center) * CFrame.Angles(0, 0, math.rad(math.random(-30, 30))), col, { material = Enum.Material.Neon, transparency = transparency })
end

local function buildSky(p: ActPalette, scene: string)
	skyFolder:ClearAllChildren()
	eyes = {}
	spins = {}
	glowPulse = {}
	local c = Layout.BOARD_CENTER
	local far = c.Z - 120
	-- Vortex high above the battlefield.
	buildVortex(skyFolder, Vector3.new(c.X + 22, c.Y + 34, far), 34, { p.glow, p.accent, rgb(255, 90, 210), rgb(90, 230, 255) })
	-- Nebula clouds.
	nebula(skyFolder, Vector3.new(c.X - 30, c.Y + 26, far - 10), Vector3.new(70, 34, 2), rgb(255, 90, 170), 0.86)
	nebula(skyFolder, Vector3.new(c.X + 60, c.Y + 18, far - 14), Vector3.new(80, 40, 2), p.glow, 0.84)
	-- Ringed planet in later acts; the moon carries act I.
	if scene ~= "crypt" then
		buildPlanet(skyFolder, Vector3.new(c.X + 70, c.Y + 40, far + 10), 10, rgb(60, 70, 150), rgb(220, 200, 255))
	end
	-- Giant eyes watching from the dark.
	local eyeSpots: { { any } } = {
		{ Vector3.new(c.X - 34, c.Y + 22, far + 20), 6, p.glow },
		{ Vector3.new(c.X + 58, c.Y + 28, far + 18), 7, p.warm },
		{ Vector3.new(c.X - 10, c.Y + 40, far + 6), 4.5, p.accent },
		{ Vector3.new(c.X + 44, c.Y + 52, far + 4), 4, p.warm },
		{ Vector3.new(c.X + 2, c.Y + 18, far + 30), 3, p.glow },
	}
	if scene == "isle" then
		table.insert(eyeSpots, { Vector3.new(c.X + 82, c.Y + 12, far + 26) :: any, 5, p.accent })
	elseif scene == "spire" then
		table.insert(eyeSpots, { Vector3.new(c.X - 54, c.Y + 44, far + 14) :: any, 8, p.warm })
	end
	for _, spot in eyeSpots do
		table.insert(eyes, newEye(skyFolder, spot[1] :: Vector3, spot[2] :: number, spot[3] :: Color3, rgb(190, 200, 255):Lerp(p.glow, 0.25)))
	end
	-- Mountains on the horizon.
	for i = -4, 7 do
		local h = 18 + (i * 37 % 13) * 2.4
		local w = 22 + (i * 17 % 7) * 3
		local x = c.X + i * 16
		local z = far + 40 + (i % 3) * 6
		local m = Build.wedge(skyFolder, Vector3.new(6, h, w / 2), CFrame.new(x - w / 4, Layout.FLOOR_Y + h / 2 - 8, z) * CFrame.Angles(0, math.rad(90), 0), p.deep:Lerp(rgb(40, 50, 120), 0.5), { material = Enum.Material.Slate })
		local m2 = Build.wedge(skyFolder, Vector3.new(6, h, w / 2), CFrame.new(x + w / 4, Layout.FLOOR_Y + h / 2 - 8, z) * CFrame.Angles(0, math.rad(-90), 0), p.deep:Lerp(rgb(30, 36, 100), 0.5), { material = Enum.Material.Slate })
		m.Name = "Mountain"
		m2.Name = "Mountain"
	end
end

-- Battlefield ---------------------------------------------------------------

local function buildFloor(p: ActPalette)
	floorTiles = {}
	local c = Layout.BOARD_CENTER
	local tile = 3
	local x0 = c.X + 7.5
	local z0 = c.Z + 6
	local a = rgb(212, 204, 255):Lerp(p.glow, 0.15)
	local b = rgb(14, 14, 44)
	for ix = 0, 11 do
		for iz = 0, 7 do
			local dark = (ix + iz) % 2 == 0
			local col = if dark then b else a
			local part = Build.block(setFolder, Vector3.new(tile, 0.6, tile), CFrame.new(x0 + ix * tile + tile / 2, Layout.FLOOR_Y - 0.3, z0 - iz * tile - tile / 2), col, {
				material = if dark then Enum.Material.Glass else Enum.Material.Marble,
				reflect = if dark then 0.15 else 0.05,
			})
			table.insert(floorTiles, { part = part :: BasePart, a = col, b = if dark then p.glow:Lerp(b, 0.6) else a:Lerp(p.accent, 0.5), phase = ix * 0.35 + iz * 0.2 })
		end
	end
	-- Stone apron under the altar and around the checkerboard.
	Build.block(setFolder, Vector3.new(80, 1, 40), CFrame.new(c.X + 14, Layout.FLOOR_Y - 1.1, c.Z - 10), rgb(20, 18, 48), { material = Enum.Material.Slate })
	-- Rails along the front edge.
	for i = 0, 7 do
		local x = x0 + 1 + i * 4.6
		Build.cylinder(setFolder, 1.4, 0.3, CFrame.new(x, Layout.FLOOR_Y + 0.7, z0 + 0.2) * CFrame.Angles(0, 0, math.rad(90)), rgb(90, 60, 40), { material = Enum.Material.Wood })
	end
	Build.block(setFolder, Vector3.new(34, 0.25, 0.3), CFrame.new(x0 + 17, Layout.FLOOR_Y + 1.45, z0 + 0.2), rgb(110, 76, 50), { material = Enum.Material.Wood })
end

local function torch(pos: Vector3, p: ActPalette)
	Build.cylinder(setFolder, 3, 0.4, CFrame.new(pos + Vector3.new(0, 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(40, 36, 60), { material = Enum.Material.Metal })
	local bowl = Build.cylinder(setFolder, 0.6, 1.1, CFrame.new(pos + Vector3.new(0, 3.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(60, 50, 40), { material = Enum.Material.Metal })
	local flame = Build.ball(setFolder, 0.6, pos + Vector3.new(0, 3.6, 0), p.warm, { material = Enum.Material.Neon })
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 7
	fire.Color = p.warm
	fire.SecondaryColor = rgb(255, 220, 140)
	fire.Parent = flame
	local light = Instance.new("PointLight")
	light.Color = p.warm
	light.Brightness = 1.4
	light.Range = 12
	light.Parent = flame
	pulseOn(flame, 0, 7)
	local _ = bowl
end

local function arch(center: Vector3, width: number, height: number, col: Color3)
	local th = 1.6
	Build.block(setFolder, Vector3.new(th, height, th), CFrame.new(center + Vector3.new(-width / 2, height / 2, 0)), col, { material = Enum.Material.Slate })
	Build.block(setFolder, Vector3.new(th, height, th), CFrame.new(center + Vector3.new(width / 2, height / 2, 0)), col, { material = Enum.Material.Slate })
	for _, sx in { -1, 1 } do
		Build.wedge(setFolder, Vector3.new(th, width * 0.35, width / 2 + th / 2), CFrame.new(center + Vector3.new(sx * (width / 4), height + width * 0.175, 0)) * CFrame.Angles(0, math.rad(sx * -90), 0), col, { material = Enum.Material.Slate })
	end
end

local function waterfall(top: Vector3, height: number, width: number, p: ActPalette)
	local fall = Build.block(setFolder, Vector3.new(width, height, 0.4), CFrame.new(top - Vector3.new(0, height / 2, 0)), p.accent, { material = Enum.Material.ForceField, transparency = 0.05 })
	local core = Build.block(setFolder, Vector3.new(width * 0.6, height, 0.2), CFrame.new(top - Vector3.new(0, height / 2, -0.25)), p.glow, { material = Enum.Material.Neon, transparency = 0.55 })
	pulseOn(core, 0.55, 2.2)
	local _ = fall
end

local function tower(base: Vector3, height: number, radius: number, p: ActPalette)
	local stone = rgb(30, 30, 62)
	Build.cylinder(setFolder, height, radius * 2, CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), stone, { material = Enum.Material.Cobblestone })
	-- Conical roof from stacked shrinking discs.
	for k = 0, 5 do
		local r = radius * (1.25 - k * 0.2)
		Build.cylinder(setFolder, 1.1, r * 2, CFrame.new(base + Vector3.new(0, height + 0.5 + k * 1.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(26, 20, 60), { material = Enum.Material.Slate })
	end
	Build.block(setFolder, Vector3.new(0.3, 2.2, 0.3), CFrame.new(base + Vector3.new(0, height + 7.2, 0)), p.warm, { material = Enum.Material.Neon })
	-- Warm windows.
	for k = 1, math.floor(height / 5) do
		local win = Build.block(setFolder, Vector3.new(1, 1.6, 0.2), CFrame.new(base + Vector3.new((k % 2 - 0.5) * radius * 0.6, k * 5 - 1, radius)), p.warm, { material = Enum.Material.Neon })
		pulseOn(win, 0, 0.7 + k * 0.13)
	end
end

local function buildSet(scene: string, p: ActPalette)
	local c = Layout.BOARD_CENTER
	local fy = Layout.FLOOR_Y
	local backZ = c.Z - 22
	if scene == "crypt" then
		-- Drowned crypt: broken arches, torches, glowing water channel.
		for i = 0, 3 do
			arch(Vector3.new(c.X + 6 + i * 11, fy, backZ - (i % 2) * 4), 7, 9 + (i % 2) * 2, rgb(26, 26, 58))
		end
		Build.block(setFolder, Vector3.new(70, 0.4, 6), CFrame.new(c.X + 18, fy - 0.4, backZ + 6), p.glow, { material = Enum.Material.ForceField, transparency = 0.1 })
		torch(Vector3.new(c.X + 8.5, fy, c.Z - 9), p)
		torch(Vector3.new(c.X + 37, fy, c.Z - 9), p)
		for i = 0, 5 do
			local h = 3 + (i * 7 % 5)
			Build.block(setFolder, Vector3.new(1.6, h, 1.6), CFrame.new(c.X + 2 + i * 7, fy + h / 2, backZ - 12) * CFrame.Angles(0, math.rad(i * 23), math.rad((i % 3 - 1) * 8)), rgb(22, 22, 52), { material = Enum.Material.Slate })
		end
	elseif scene == "isle" then
		-- Floating isle: the battlefield sits on an island; waterfalls pour
		-- from its edges into a glowing sea far below; ruined temples behind.
		Build.block(setFolder, Vector3.new(56, 8, 34), CFrame.new(c.X + 18, fy - 5.2, c.Z - 10), rgb(16, 18, 40), { material = Enum.Material.Rock })
		Build.wedge(setFolder, Vector3.new(56, 10, 14), CFrame.new(c.X + 18, fy - 14, c.Z + 0) * CFrame.Angles(math.rad(180), 0, 0), rgb(14, 14, 34), { material = Enum.Material.Rock })
		for i = 0, 2 do
			waterfall(Vector3.new(c.X + 6 + i * 18, fy - 1.5, c.Z + 6.5), 40, 3, p)
		end
		Build.block(setFolder, Vector3.new(400, 1, 300), CFrame.new(c.X, fy - 60, c.Z - 80), p.glow:Lerp(p.deep, 0.5), { material = Enum.Material.ForceField, transparency = 0.1 })
		for i = 0, 2 do
			local x = c.X + 8 + i * 13
			Build.block(setFolder, Vector3.new(9, 0.8, 7), CFrame.new(x, fy + 0.4, backZ), rgb(30, 30, 60), { material = Enum.Material.Slate })
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					Build.cylinder(setFolder, 7, 0.9, CFrame.new(x + sx * 3.5, fy + 4, backZ + sz * 2.6) * CFrame.Angles(0, 0, math.rad(90)), rgb(36, 36, 70), { material = Enum.Material.Marble })
				end
			end
			Build.ellipsoid(setFolder, Vector3.new(8, 4, 6), CFrame.new(x, fy + 8.4, backZ), rgb(26, 26, 58), { material = Enum.Material.Slate })
		end
		torch(Vector3.new(c.X + 8.5, fy, c.Z - 9), p)
		torch(Vector3.new(c.X + 37, fy, c.Z - 9), p)
	else
		-- Vortex spire: a dark castle with warm windows under the swirl.
		tower(Vector3.new(c.X + 4, fy, backZ - 6), 22, 3.4, p)
		tower(Vector3.new(c.X + 40, fy, backZ - 4), 26, 3.8, p)
		tower(Vector3.new(c.X + 22, fy, backZ - 16), 34, 4.6, p)
		Build.block(setFolder, Vector3.new(40, 12, 3), CFrame.new(c.X + 22, fy + 6, backZ - 8), rgb(28, 28, 60), { material = Enum.Material.Cobblestone })
		for i = 0, 9 do
			Build.block(setFolder, Vector3.new(1.6, 1.6, 3), CFrame.new(c.X + 3.6 + i * 4.1, fy + 12.8, backZ - 8), rgb(28, 28, 60), { material = Enum.Material.Cobblestone })
		end
		local gate = Build.block(setFolder, Vector3.new(5, 7, 0.3), CFrame.new(c.X + 22, fy + 3.5, backZ - 6.3), p.warm, { material = Enum.Material.Neon, transparency = 0.25 })
		pulseOn(gate, 0.25, 1.1)
		torch(Vector3.new(c.X + 8.5, fy, c.Z - 9), p)
		torch(Vector3.new(c.X + 37, fy, c.Z - 9), p)
	end
	-- Drifting purple smoke over the field.
	local smokeHost = Build.block(setFolder, Vector3.new(30, 0.2, 10), CFrame.new(c.X + 22, fy + 0.2, c.Z - 4), Color3.new(1, 1, 1), { transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
	pe.Color = ColorSequence.new(p.glow:Lerp(rgb(150, 60, 255), 0.5), p.deep)
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.82), NumberSequenceKeypoint.new(1, 1) })
	pe.Size = NumberSequence.new(4, 9)
	pe.Lifetime = NumberRange.new(6, 9)
	pe.Rate = 3
	pe.Speed = NumberRange.new(0.4, 1)
	pe.SpreadAngle = Vector2.new(30, 30)
	pe.LightEmission = 0.3
	pe.Parent = smokeHost
end

-- Public --------------------------------------------------------------------

function Scenery.init(parent: Instance)
	root = Instance.new("Folder")
	root.Name = "Scenery"
	root.Parent = parent
	skyFolder = Instance.new("Folder")
	skyFolder.Name = "Sky"
	skyFolder.Parent = root
	setFolder = Instance.new("Folder")
	setFolder.Name = "Set"
	setFolder.Parent = root
	conn = RunService.RenderStepped:Connect(function(dt)
		Scenery._step(dt)
	end)
end

function Scenery.setReducedMotion(on: boolean)
	reduced = on
end

-- Builds (or rebuilds) the world for an act's scene.
function Scenery.setScene(scene: string, p: ActPalette)
	palette = p
	Scenery.applyLighting(p, "fight")
	if scene == currentScene then
		return
	end
	currentScene = scene
	setFolder:ClearAllChildren()
	buildSky(p, scene)
	buildFloor(p)
	buildSet(scene, p)
end

-- What the giant eyes watch (the ball in flight, else the monster).
function Scenery.setLookTarget(pos: Vector3?)
	lookTarget = pos
end

-- A pulse across the checkerboard (big hits, strikes).
function Scenery.pulse(strength: number)
	for _, ft in floorTiles do
		ft.phase -= strength * 0.8
	end
end

function Scenery._step(dt: number)
	t += dt
	local now = os.clock()
	-- Vortex rotation.
	for _, sp in spins do
		if not reduced then
			sp.angle += dt * sp.speed
		end
		local rot = sp.pivot * CFrame.Angles(0, 0, sp.angle)
		local cfs = table.create(#sp.parts)
		for i, b in sp.base do
			cfs[i] = rot * b
		end
		workspace:BulkMoveTo(sp.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- Eyes: track the target and blink now and then.
	local target = lookTarget or (Layout.MONSTER_BASE + Vector3.new(0, 5, 0))
	for _, e in eyes do
		local toT = (target - e.center).Unit
		local dx = math.clamp(toT.X * 0.6, -0.42, 0.42) * e.radius
		local dy = math.clamp(toT.Y * 0.6, -0.25, 0.25) * e.radius
		local z = e.radius * 0.62
		local base = e.center + Vector3.new(dx, dy, z)
		e.iris.CFrame = CFrame.new(base) * CFrame.Angles(0, math.rad(90), 0)
		e.ring.CFrame = CFrame.new(base - Vector3.new(0, 0, 0.02)) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(t * 0.8, 0, 0)
		e.pupil.CFrame = CFrame.new(base + Vector3.new(0, 0, 0.04)) * CFrame.Angles(0, math.rad(90), 0)
		if now >= e.blinkAt then
			e.blink = 0.22
			e.blinkAt = now + 3 + math.random() * 7
		end
		local closed = 0
		if e.blink > 0 then
			e.blink -= dt
			closed = math.sin(math.clamp(e.blink / 0.22, 0, 1) * math.pi)
		end
		local facing = CFrame.lookAt(e.center, e.center + Vector3.new(0, -0.15, 1))
		local open = e.radius * (0.95 - closed * 0.62)
		e.lidTop.CFrame = facing * CFrame.new(0, open, 0)
		e.lidBottom.CFrame = facing * CFrame.new(0, -open, 0)
		e.iris.Color = palette.glow:Lerp(palette.warm, 0.5 + 0.5 * math.sin(t * 0.6 + e.radius))
	end
	-- Checkerboard shimmer.
	if not reduced then
		for _, ft in floorTiles do
			local k = 0.5 + 0.5 * math.sin(t * 1.2 + ft.phase)
			ft.part.Color = ft.a:Lerp(ft.b, k * 0.35)
		end
	end
	for _, g in glowPulse do
		if g.part.Parent then
			g.part.Transparency = math.clamp(g.base + 0.2 * (0.5 + 0.5 * math.sin(t * g.speed)), 0, 0.95)
		end
	end
end

function Scenery.destroy()
	if conn then
		conn:Disconnect()
	end
	root:Destroy()
end

return Scenery
