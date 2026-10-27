--!strict
-- The lobby: a cosmic tavern hall. Stone walls and pillars, long wooden
-- tables with candles, glowing galaxy potions and stacks of gold, iron
-- chandeliers, and tall arched windows open onto a nebula and a ringed
-- planet. The party stands on a rune dais in front. Code-built set dressing,
-- presentation only.

local RunService = game:GetService("RunService")

local Build = require(script.Parent.Build)
local Layout = require(script.Parent.Layout)

local LobbyHall = {}

export type Handles = {
	model: Model,
	spots: { Vector3 }, -- where party heroes stand (dais)
	facing: Vector3,
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local STONE = rgb(32, 34, 78)
local STONE_D = rgb(20, 20, 52)
local WOOD = rgb(92, 56, 34)
local GOLD = rgb(226, 172, 70)

local flickers: { { part: BasePart, light: PointLight?, seed: number } } = {}
local potions: { { part: BasePart, seed: number } } = {}
local runeRing: { BasePart } = {}
local windowGlow: { BasePart } = {}
local planetRing: BasePart? = nil
local t = 0

local function candle(model: Model, pos: Vector3, h: number, withLight: boolean)
	Build.cylinder(model, h, 0.28, CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), rgb(236, 220, 196))
	local flame = Build.ball(model, 0.2, pos + Vector3.new(0, h + 0.14, 0), rgb(255, 176, 80), { material = Enum.Material.Neon })
	local light: PointLight? = nil
	if withLight then
		local l = Instance.new("PointLight")
		l.Color = rgb(255, 160, 80)
		l.Brightness = 0.9
		l.Range = 9
		l.Shadows = false
		l.Parent = flame
		light = l
	end
	table.insert(flickers, { part = flame :: BasePart, light = light, seed = math.random() * 10 })
end

local function potion(model: Model, pos: Vector3, col: Color3)
	local body = Build.ball(model, 0.75, pos + Vector3.new(0, 0.38, 0), col, { material = Enum.Material.Glass, transparency = 0.25 })
	local core = Build.ball(model, 0.5, pos + Vector3.new(0, 0.38, 0), col, { material = Enum.Material.Neon })
	Build.cylinder(model, 0.45, 0.22, CFrame.new(pos + Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), col, { material = Enum.Material.Glass, transparency = 0.3 })
	Build.cylinder(model, 0.12, 0.26, CFrame.new(pos + Vector3.new(0, 1.15, 0)) * CFrame.Angles(0, 0, math.rad(90)), WOOD)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(col, Color3.new(1, 1, 1))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.6, 1.2)
	pe.Rate = 3
	pe.Speed = NumberRange.new(0.2, 0.5)
	pe.LightEmission = 1
	pe.Parent = core
	table.insert(potions, { part = core :: BasePart, seed = math.random() * 10 })
	local _ = body
end

local function coins(model: Model, pos: Vector3, n: number)
	for i = 0, n - 1 do
		Build.cylinder(model, 0.08, 0.5, CFrame.new(pos + Vector3.new((i % 2) * 0.05, 0.04 + i * 0.085, 0)) * CFrame.Angles(0, 0, math.rad(90)), GOLD, { material = Enum.Material.Metal, reflect = 0.2 })
	end
end

local function longTable(model: Model, center: Vector3, length: number)
	local top = Build.block(model, Vector3.new(length, 0.4, 3), CFrame.new(center + Vector3.new(0, 2.6, 0)), WOOD, { material = Enum.Material.WoodPlanks })
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.block(model, Vector3.new(0.5, 2.4, 0.5), CFrame.new(center + Vector3.new(sx * (length / 2 - 0.6), 1.2, sz * 1.1)), WOOD:Lerp(Color3.new(0, 0, 0), 0.2), { material = Enum.Material.Wood })
		end
	end
	for _, sz in { -1, 1 } do
		Build.block(model, Vector3.new(length - 1, 0.3, 0.9), CFrame.new(center + Vector3.new(0, 1.5, sz * 2.4)), WOOD, { material = Enum.Material.WoodPlanks })
	end
	-- Dressing along the table.
	local cols = { rgb(80, 120, 255), rgb(170, 90, 255), rgb(255, 90, 210), rgb(90, 220, 255) }
	local n = math.floor(length / 3)
	for i = 0, n - 1 do
		local x = -length / 2 + 1.5 + i * 3
		local p = center + Vector3.new(x, 2.8, (i % 2 - 0.5) * 1.2)
		if i % 3 == 0 then
			potion(model, p, cols[(i // 3) % #cols + 1])
		elseif i % 3 == 1 then
			candle(model, p, 0.6 + (i % 2) * 0.3, i % 6 == 1)
		else
			coins(model, p, 3 + i % 3)
		end
	end
	local _ = top
end

local function chandelier(model: Model, pos: Vector3, radius: number)
	Build.block(model, Vector3.new(0.15, 8, 0.15), CFrame.new(pos + Vector3.new(0, 4, 0)), rgb(20, 18, 30), { material = Enum.Material.Metal })
	local ring = Build.cylinder(model, 0.2, radius * 2, CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), rgb(30, 26, 40), { material = Enum.Material.Metal })
	local _ = ring
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		candle(model, pos + Vector3.new(math.cos(a) * radius, 0.1, math.sin(a) * radius), 0.5, k % 4 == 0)
	end
end

local function archWindow(model: Model, center: Vector3, w: number, h: number)
	-- Opening frame.
	Build.block(model, Vector3.new(0.8, h, 1.2), CFrame.new(center + Vector3.new(-w / 2, 0, 0)), STONE_D, { material = Enum.Material.Slate })
	Build.block(model, Vector3.new(0.8, h, 1.2), CFrame.new(center + Vector3.new(w / 2, 0, 0)), STONE_D, { material = Enum.Material.Slate })
	for _, sx in { -1, 1 } do
		Build.wedge(model, Vector3.new(1.2, w * 0.45, w / 2 + 0.4), CFrame.new(center + Vector3.new(sx * (w / 4), h / 2 + w * 0.225, 0)) * CFrame.Angles(0, math.rad(sx * -90), 0), STONE_D, { material = Enum.Material.Slate })
	end
	-- The night beyond: nebula glass.
	local glass = Build.block(model, Vector3.new(w, h + w * 0.3, 0.2), CFrame.new(center + Vector3.new(0, w * 0.1, -0.7)), rgb(70, 50, 190), { material = Enum.Material.Neon, transparency = 0.35 })
	table.insert(windowGlow, glass)
	local swirl = Build.block(model, Vector3.new(w * 0.9, h * 0.6, 0.1), CFrame.new(center + Vector3.new(0, h * 0.15, -0.6)) * CFrame.Angles(0, 0, math.rad(20)), rgb(255, 90, 180), { material = Enum.Material.ForceField, transparency = 0.2 })
	local _ = swirl
	-- Mullion.
	Build.block(model, Vector3.new(0.25, h, 0.3), CFrame.new(center + Vector3.new(0, 0, -0.3)), STONE_D, { material = Enum.Material.Slate })
end

function LobbyHall.build(parent: Instance): Handles
	local o = Layout.LOBBY
	local model = Build.model("LobbyHall", parent)
	local fy = o.Y

	-- Floor: dark flagstones with a rune dais.
	Build.block(model, Vector3.new(80, 1, 70), CFrame.new(o + Vector3.new(0, -0.5, -20)), rgb(30, 28, 60), { material = Enum.Material.Slate })
	for ix = -3, 3 do
		for iz = 0, 3 do
			local dark = (ix + iz) % 2 == 0
			Build.block(model, Vector3.new(3.4, 0.2, 3.4), CFrame.new(o + Vector3.new(ix * 3.5, 0.05, -iz * 3.5 + 1)), if dark then rgb(18, 18, 48) else rgb(160, 150, 220), {
				material = if dark then Enum.Material.Glass else Enum.Material.Marble,
				reflect = 0.08,
			})
		end
	end
	local dais = Build.cylinder(model, 0.6, 11, CFrame.new(o + Vector3.new(0, 0.3, -1)) * CFrame.Angles(0, 0, math.rad(90)), STONE, { material = Enum.Material.Slate })
	local _ = dais
	-- Key light over the dais so the party reads clearly against the hall.
	local keyHost = Build.block(model, Vector3.new(0.5, 0.5, 0.5), CFrame.lookAt(o + Vector3.new(3, 11, 7), o + Vector3.new(0, 2, -1)), Color3.new(1, 1, 1), { transparency = 1 })
	local key = Instance.new("SpotLight")
	key.Face = Enum.NormalId.Front
	key.Angle = 70
	key.Range = 24
	key.Brightness = 2.4
	key.Color = rgb(225, 215, 255)
	key.Shadows = true
	key.Parent = keyHost
	local rim = Instance.new("PointLight")
	rim.Color = rgb(120, 140, 255)
	rim.Brightness = 1.4
	rim.Range = 12
	rim.Parent = Build.block(model, Vector3.new(0.5, 0.5, 0.5), CFrame.new(o + Vector3.new(0, 5, -6)), Color3.new(1, 1, 1), { transparency = 1 })
	for k = 0, 23 do
		local a = k / 24 * math.pi * 2
		local p = Build.block(model, Vector3.new(0.5, 0.08, 0.5), CFrame.new(o + Vector3.new(math.cos(a) * 5, 0.64, -1 + math.sin(a) * 5)) * CFrame.Angles(0, -a, 0), rgb(110, 150, 255), { material = Enum.Material.Neon })
		table.insert(runeRing, p)
	end

	-- Back wall with three tall arched windows.
	local wallZ = o.Z - 32
	Build.block(model, Vector3.new(80, 40, 2), CFrame.new(o + Vector3.new(0, 20, -32)), STONE, { material = Enum.Material.Cobblestone })
	for i = -1, 1 do
		archWindow(model, Vector3.new(o.X + i * 15, fy + 12, wallZ + 1.4), 8, 14)
	end
	-- Beyond the windows: a ringed planet and a galaxy swirl.
	local planetPos = Vector3.new(o.X + 16, fy + 20, wallZ - 30)
	Build.ball(model, 14, planetPos, rgb(60, 70, 170))
	local pr = Build.cylinder(model, 0.3, 30, CFrame.new(planetPos) * CFrame.Angles(math.rad(72), math.rad(8), math.rad(-15)) * CFrame.Angles(0, 0, math.rad(90)), rgb(230, 210, 255), { material = Enum.Material.Neon, transparency = 0.4 })
	planetRing = pr
	Build.ellipsoid(model, Vector3.new(60, 30, 2), CFrame.new(o + Vector3.new(-14, 22, -70)) * CFrame.Angles(0, 0, math.rad(-20)), rgb(255, 90, 170), { material = Enum.Material.Neon, transparency = 0.75 })
	Build.ellipsoid(model, Vector3.new(70, 34, 2), CFrame.new(o + Vector3.new(10, 18, -76)) * CFrame.Angles(0, 0, math.rad(25)), rgb(80, 90, 255), { material = Enum.Material.Neon, transparency = 0.7 })

	-- Side walls with pillars and banners.
	for _, sx in { -1, 1 } do
		Build.block(model, Vector3.new(2, 40, 70), CFrame.new(o + Vector3.new(sx * 30, 20, -5)), STONE, { material = Enum.Material.Cobblestone })
		for k = 0, 3 do
			local z = o.Z + 6 - k * 10
			Build.block(model, Vector3.new(2.2, 26, 2.2), CFrame.new(Vector3.new(o.X + sx * 27, fy + 13, z)), STONE_D, { material = Enum.Material.Slate })
			local banner = Build.block(model, Vector3.new(0.1, 8, 3), CFrame.new(Vector3.new(o.X + sx * 25.8, fy + 15, z + 4.5)), if k % 2 == 0 then rgb(60, 30, 140) else rgb(30, 40, 130), { material = Enum.Material.Fabric })
			Build.block(model, Vector3.new(0.12, 0.4, 3), CFrame.new(Vector3.new(o.X + sx * 25.75, fy + 11.2, z + 4.5)), GOLD, { material = Enum.Material.Metal })
			local _ = banner
		end
	end
	-- Vaulted ceiling beams.
	for k = 0, 4 do
		Build.block(model, Vector3.new(60, 1.2, 1.2), CFrame.new(o + Vector3.new(0, 26, 6 - k * 9)), rgb(40, 26, 20), { material = Enum.Material.Wood })
	end

	-- Long tables either side of the dais.
	longTable(model, o + Vector3.new(-14, 0, -10), 18)
	longTable(model, o + Vector3.new(14, 0, -10), 18)
	longTable(model, o + Vector3.new(0, 0, -22), 22)
	-- Chandeliers.
	chandelier(model, o + Vector3.new(-12, 14, -8), 2.6)
	chandelier(model, o + Vector3.new(12, 14, -8), 2.6)
	chandelier(model, o + Vector3.new(0, 16, -20), 3.2)

	-- Warm hearth glow on the left, cool window light on the right.
	local hearth = Build.block(model, Vector3.new(6, 4, 1), CFrame.new(o + Vector3.new(-22, 2, -24)), rgb(255, 110, 40), { material = Enum.Material.Neon, transparency = 0.2 })
	local fire = Instance.new("Fire")
	fire.Size = 5
	fire.Heat = 9
	fire.Color = rgb(255, 120, 40)
	fire.SecondaryColor = rgb(255, 210, 120)
	fire.Parent = hearth
	local hl = Instance.new("PointLight")
	hl.Color = rgb(255, 140, 60)
	hl.Brightness = 1.6
	hl.Range = 18
	hl.Parent = hearth
	table.insert(flickers, { part = hearth :: BasePart, light = hl :: PointLight?, seed = 3 })

	-- Drifting violet smoke near the floor.
	local host = Build.block(model, Vector3.new(30, 0.2, 20), CFrame.new(o + Vector3.new(0, 0.3, -10)), Color3.new(1, 1, 1), { transparency = 1 })
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(rgb(150, 80, 255), rgb(40, 30, 120))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.86), NumberSequenceKeypoint.new(1, 1) })
	smoke.Size = NumberSequence.new(3, 7)
	smoke.Lifetime = NumberRange.new(6, 9)
	smoke.Rate = 2
	smoke.Speed = NumberRange.new(0.3, 0.8)
	smoke.LightEmission = 0.4
	smoke.Parent = host

	RunService.RenderStepped:Connect(function(dt)
		t += dt
		for _, f in flickers do
			local k = 0.5 + 0.5 * math.noise(t * 3, f.seed)
			f.part.Transparency = 0.05 + k * 0.25
			local l = f.light
			if l then
				l.Brightness = 0.7 + k * 0.9
			end
		end
		for _, p in potions do
			p.part.Transparency = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(t * 1.5 + p.seed))
		end
		for i, r in runeRing do
			r.Transparency = 0.15 + 0.6 * (0.5 + 0.5 * math.sin(t * 2 - i * 0.5))
		end
		for _, g in windowGlow do
			g.Transparency = 0.3 + 0.12 * math.sin(t * 0.6)
		end
		local ring = planetRing
		if ring then
			ring.Transparency = 0.35 + 0.1 * math.sin(t)
		end
	end)

	local spots = {
		o + Vector3.new(0, 0.6, -1),
		o + Vector3.new(-3.2, 0.6, -2.2),
		o + Vector3.new(3.2, 0.6, -2.2),
		o + Vector3.new(0, 0.6, -4.2),
	}
	return { model = model, spots = spots, facing = Vector3.new(0.15, 0, 1).Unit }
end

return LobbyHall
