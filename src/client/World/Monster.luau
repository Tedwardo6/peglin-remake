--!strict
-- Code-built monster with procedural animation: idle breathing and blinks,
-- threat wind-up, lunge, per-hit flinch, big-hit stagger, armor plating,
-- reveal, and a death burst. Built from the enemy's `look` data and kept in
-- one module so a modelled monster can replace it later.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enemies = require(Shared.Content.Enemies)

local Build = require(script.Parent.Build)

type Rig = {
	part: BasePart,
	offset: CFrame, -- relative to the monster root, unscaled
	size: Vector3,
	group: string,
	vel: Vector3?,
	spin: Vector3?,
}

local Monster = {}
Monster.__index = Monster

export type Monster = typeof(setmetatable(
	{} :: {
		model: Model,
		rig: { Rig },
		base: Vector3,
		scale: number,
		highlight: Highlight,
		t: number,
		telegraph: number,
		urgent: boolean,
		flinchV: number,
		flinch: number,
		flinchDir: number,
		stagger: number,
		lunge: number,
		lungeT: number,
		reveal: number,
		revealT: number,
		dead: boolean,
		deathT: number,
		blink: number,
		nextBlink: number,
		flashT: number,
		armorParts: { BasePart },
		armorOn: boolean,
		eyeGlow: number,
		conn: RBXScriptConnection?,
		reducedMotion: boolean,
		mouthOpen: number,
		hurt: number,
	},
	Monster
))

local INK = Build.INK

function Monster.new(parent: Instance, enemyId: string, base: Vector3): Monster
	local def = Enemies.ById[enemyId]
	local look = def.look
	local self = setmetatable({}, Monster) :: any
	self.model = Build.model("Monster_" .. enemyId, parent)
	self.rig = {}
	self.base = base
	self.scale = look.scale * 1.15
	self.t = math.random() * 10
	self.telegraph = 0
	self.urgent = false
	self.flinchV = 0
	self.flinch = 0
	self.flinchDir = 1
	self.stagger = 0
	self.lunge = 0
	self.lungeT = -1
	self.reveal = 0
	self.revealT = -1
	self.dead = false
	self.deathT = -1
	self.blink = 0
	self.nextBlink = 2 + math.random() * 3
	self.flashT = 0
	self.armorParts = {}
	self.armorOn = false
	self.eyeGlow = 0
	self.reducedMotion = false
	self.mouthOpen = 0
	self.hurt = 0

	local k = self.scale
	local m = self.model
	local function add(p: BasePart, group: string)
		local rel = CFrame.new(base):ToObjectSpace(p.CFrame)
		table.insert(self.rig, { part = p, offset = rel, size = p.Size, group = group })
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(base + Vector3.new(x, y, z) * k)
	end
	local body = look.body
	local belly = look.belly
	local deep = Color3.new(body.R * 0.62, body.G * 0.62, body.B * 0.62)

	-- Feet (grounded), arms, body, belly.
	for _, sx in { -1, 1 } do
		add(Build.ellipsoid(m, Vector3.new(2.4, 1.3, 2.8) * k, at(sx * 1.9, 0.65, 0.7), deep), "foot")
		add(Build.ellipsoid(m, Vector3.new(1.7, 2.9, 1.7) * k, at(sx * 3.75, 3.6, 0.6) * CFrame.Angles(0, 0, sx * math.rad(-18)), body), if sx < 0 then "armL" else "armR")
		add(Build.ellipsoid(m, Vector3.new(1.1, 1.0, 1.1) * k, at(sx * 4.25, 2.15, 0.9), belly), if sx < 0 then "handL" else "handR")
	end
	if look.horn == "shell" then
		add(Build.ellipsoid(m, Vector3.new(7.4, 6.4, 4.6) * k, at(0, 4.6, -1.6), deep), "body")
		for i = -1, 1 do
			add(Build.block(m, Vector3.new(0.7, 4.6, 0.7) * k, at(i * 2.1, 5.2, -3.3) * CFrame.Angles(0, 0, math.rad(i * 18)), belly), "body")
		end
	end
	add(Build.ellipsoid(m, Vector3.new(7.2, 6.6, 6.0) * k, at(0, 4.4, 0), body), "body")
	add(Build.ellipsoid(m, Vector3.new(4.8, 4.0, 1.4) * k, at(0, 3.5, 2.55), belly), "body")

	-- Head decorations.
	if look.horn == "horns" then
		for _, sx in { -1, 1 } do
			add(Build.wedge(m, Vector3.new(0.9, 2.4, 1.6) * k, at(sx * 2.3, 7.9, 0.2) * CFrame.Angles(0, if sx < 0 then 0 else math.pi, math.rad(sx * -20)), Color3.fromRGB(255, 244, 214)), "head")
		end
	elseif look.horn == "antenna" then
		for _, sx in { -1, 1 } do
			add(Build.cylinder(m, 2.6 * k, 0.32 * k, at(sx * 1.2, 8.4, 0) * CFrame.Angles(0, 0, math.rad(90 + sx * -20)), deep), "head")
			add(Build.ball(m, 0.95 * k, (at(sx * 1.65, 9.6, 0)).Position, Color3.fromRGB(255, 240, 110), { material = Enum.Material.Neon }), "head")
		end
	elseif look.horn == "spikes" then
		for i = -1, 1 do
			add(Build.wedge(m, Vector3.new(0.8, 1.9, 1.7) * k, at(i * 1.8, 7.9 - math.abs(i) * 0.45, -0.2) * CFrame.Angles(0, 0, math.rad(i * -15)), Color3.fromRGB(255, 250, 235)), "head")
		end
	elseif look.horn == "crown" then
		add(Build.block(m, Vector3.new(4.2, 0.9, 3.0) * k, at(0, 7.6, 0), Color3.fromRGB(255, 205, 60)), "head")
		for i = -1, 1 do
			add(Build.wedge(m, Vector3.new(0.9, 1.5, 0.9) * k, at(i * 1.5, 8.6, 0.6), Color3.fromRGB(255, 205, 60)), "head")
			add(Build.ball(m, 0.55 * k, (at(i * 1.5, 7.6, 1.55)).Position, if i == 0 then Color3.fromRGB(255, 60, 90) else Color3.fromRGB(80, 200, 255), { material = Enum.Material.Neon }), "head")
		end
	end

	-- Eyes, pupils, glints, lids.
	local n = look.eyes
	local xs: { number } = if n == 1 then { 0 } elseif n == 2 then { -1.4, 1.4 } else { -2.0, 0, 2.0 }
	local eyeD = if n == 1 then 2.8 elseif n == 2 then 2.0 else 1.6
	for _, ex in xs do
		add(Build.ball(m, (eyeD + 0.28) * k, (at(ex, 5.5, 2.45)).Position, INK), "eyeRim")
		add(Build.ball(m, eyeD * k, (at(ex, 5.5, 2.62)).Position, Color3.new(1, 1, 1)), "eye")
		add(Build.ball(m, eyeD * 0.5 * k, (at(ex, 5.42, 3.25 + eyeD * 0.12)).Position, INK), "pupil")
		add(Build.ball(m, eyeD * 0.18 * k, (at(ex - eyeD * 0.12, 5.62, 3.55 + eyeD * 0.14)).Position, Color3.new(1, 1, 1)), "glint")
		add(Build.ellipsoid(m, Vector3.new(eyeD * 1.08, eyeD * 0.6, eyeD * 1.02) * k, at(ex, 5.5 + eyeD * 0.62, 2.62), body), "lid")
	end
	-- Mouth.
	if look.mouth == "flat" then
		add(Build.block(m, Vector3.new(2.6, 0.38, 0.4) * k, at(0, 3.25, 3.15), INK), "mouth")
	else
		add(Build.ellipsoid(m, Vector3.new(2.9, 1.15, 0.6) * k, at(0, 3.15, 3.0), INK), "mouth")
		add(Build.ellipsoid(m, Vector3.new(1.4, 0.45, 0.3) * k, at(0, 2.85, 3.2), Color3.fromRGB(255, 110, 140)), "tongue")
		if look.mouth == "fangs" then
			for _, sx in { -1, 1 } do
				add(Build.wedge(m, Vector3.new(0.35, 0.65, 0.3) * k, at(sx * 0.75, 3.35, 3.28) * CFrame.Angles(math.pi, 0, 0), Color3.new(1, 1, 1)), "fang")
			end
		end
	end
	-- Armor plating (hidden until the monster armors up).
	for i = -1, 1 do
		local plate = Build.block(m, Vector3.new(2.1, 2.7, 0.5) * k, at(i * 2.2, 4.3, 3.0 - math.abs(i) * 0.7) * CFrame.Angles(0, math.rad(i * -28), 0), Color3.fromRGB(190, 205, 230), { transparency = 1, reflect = 0.15 })
		add(plate, "armor")
		table.insert(self.armorParts, plate)
	end

	self.highlight = Build.outline(m)
	self.conn = RunService.RenderStepped:Connect(function(dt)
		Monster._step(self, dt)
	end)
	return self
end

-- 0..1 wind-up as the threat approaches; `urgent` in the last 3 seconds.
function Monster.setTelegraph(self: Monster, level: number, urgent: boolean)
	self.telegraph = math.clamp(level, 0, 1)
	self.urgent = urgent
end

function Monster.hit(self: Monster, damage: number, big: boolean)
	if self.dead then
		return
	end
	local power = math.clamp(damage / 12, 0.15, 1)
	self.flinchV += power * 9
	self.flinchDir = if math.random() < 0.5 then -1 else 1
	self.hurt = math.min(1, self.hurt + power * 0.6)
	if big then
		self.stagger = 1
	end
	self.flashT = 0.08 + power * 0.06
end

function Monster.attack(self: Monster)
	self.lungeT = 0
	self.mouthOpen = 1
end

function Monster.setArmor(self: Monster, on: boolean)
	if on == self.armorOn then
		return
	end
	self.armorOn = on
	for _, p in self.armorParts do
		TweenService:Create(p, TweenInfo.new(0.3), { Transparency = if on then 0 else 1 }):Play()
	end
end

function Monster.revealIn(self: Monster, seconds: number)
	self.revealT = 0
	self.reveal = seconds
	self.mouthOpen = 1
end

function Monster.die(self: Monster)
	if self.dead then
		return
	end
	self.dead = true
	self.deathT = 0
	for _, r in self.rig do
		local dir = (r.part.Position - (self.base + Vector3.new(0, 4 * self.scale, 0)))
		if dir.Magnitude < 0.01 then
			dir = Vector3.new(0, 1, 0)
		end
		r.vel = dir.Unit * (10 + math.random() * 12) + Vector3.new((math.random() - 0.5) * 6, 10 + math.random() * 8, 6 + math.random() * 6)
		r.spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 14
	end
	self.highlight.FillColor = Color3.new(1, 1, 1)
	self.highlight.FillTransparency = 0.2
end

function Monster._step(self: Monster, dt: number)
	self.t += dt
	local k = self.scale
	if self.dead then
		self.deathT += dt
		local parts = table.create(#self.rig)
		local cfs = table.create(#self.rig)
		for i, r in self.rig do
			local v = r.vel :: Vector3
			r.vel = v + Vector3.new(0, -60 * dt, 0)
			local spin = r.spin :: Vector3
			parts[i] = r.part
			cfs[i] = (r.part.CFrame + v * dt) * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
			r.part.Transparency = math.max(r.part.Transparency, math.clamp((self.deathT - 0.5) / 0.6, 0, 1))
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		self.highlight.FillTransparency = math.min(1, 0.2 + self.deathT * 2)
		self.highlight.OutlineTransparency = math.clamp((self.deathT - 0.4) / 0.5, 0, 1)
		if self.deathT > 1.4 then
			if self.conn then
				self.conn:Disconnect()
				self.conn = nil
			end
			self.model:Destroy()
		end
		return
	end

	local rm = self.reducedMotion
	-- Springs: flinch (tilt), stagger (lean back), hurt squash.
	self.flinchV += (-self.flinch * 140 - self.flinchV * 14) * dt
	self.flinch += self.flinchV * dt
	self.stagger = math.max(0, self.stagger - dt * 1.8)
	self.hurt = math.max(0, self.hurt - dt * 2.5)
	self.mouthOpen = math.max(if self.telegraph > 0.75 then 0.45 else 0, self.mouthOpen - dt * 2.5)

	local tel = self.telegraph
	local breathe = math.sin(self.t * 2.2)
	local bob = if rm then 0 else breathe * 0.12 * k
	local sy = 1 + breathe * 0.025 - tel * 0.08 - self.hurt * 0.08
	local sx = 1 - breathe * 0.015 + tel * 0.05 + self.hurt * 0.05
	local lean = -tel * 0.18 + self.stagger * -0.22
	local tilt = self.flinch * 0.06 * self.flinchDir
	local shake = Vector3.zero
	if not rm then
		local sh = (if self.urgent then 0.12 else 0) + self.stagger * 0.15
		if sh > 0 then
			shake = Vector3.new((math.random() - 0.5) * sh, (math.random() - 0.5) * sh, 0) * k
		end
	end
	-- Lunge toward the cabinet when a threat lands.
	local lungeZ, lungeX = 0, 0
	if self.lungeT >= 0 then
		self.lungeT += dt
		local u = self.lungeT
		local a = if u < 0.12 then u / 0.12 else math.max(0, 1 - (u - 0.12) / 0.35)
		lungeZ = a * 2.6
		lungeX = -a * 3.2
		lean += a * 0.35
		sy -= a * 0.06
		if u > 0.5 then
			self.lungeT = -1
		end
	end
	-- Reveal: rise from behind the pedestal with a landing squash.
	local rise = 0
	if self.revealT >= 0 then
		self.revealT += dt
		local u = math.clamp(self.revealT / math.max(0.2, self.reveal), 0, 1)
		local e = 1 - (1 - u) ^ 3
		rise = (e - 1) * 9 * k
		if u >= 1 then
			self.revealT = -1
		elseif u > 0.85 then
			sy -= (1 - u) * 0.6
			sx += (1 - u) * 0.4
		end
	end
	-- Blink.
	self.nextBlink -= dt
	if self.nextBlink <= 0 then
		self.blink = 0.14
		self.nextBlink = 2.5 + math.random() * 3.5
	end
	self.blink = math.max(0, self.blink - dt)
	local lidDown = if self.blink > 0 then 1 else (if tel > 0.6 then 0.35 else 0)

	local root = CFrame.new(self.base + Vector3.new(lungeX, bob + rise, lungeZ) + shake) * CFrame.Angles(lean, 0, tilt)
	local parts = table.create(#self.rig)
	local cfs = table.create(#self.rig)
	for i, r in self.rig do
		local o = r.offset
		local p = o.Position
		local sxx, syy = sx, sy
		local extra = CFrame.identity
		if r.group == "foot" then
			sxx, syy = 1, 1
		elseif r.group == "armL" or r.group == "armR" or r.group == "handL" or r.group == "handR" then
			-- Arms rise during the wind-up and slam on the lunge.
			local raise = tel * 1.6 * k
			local side = if string.find(r.group, "L") then -1 else 1
			p += Vector3.new(0, raise, 0)
			extra = CFrame.Angles(0, 0, side * tel * 0.5)
		elseif r.group == "lid" then
			p += Vector3.new(0, -lidDown * r.size.Y * 0.75, 0)
		elseif r.group == "mouth" or r.group == "tongue" then
			syy = sy * (1 + self.mouthOpen * 0.9)
		end
		local pos = Vector3.new(p.X * sxx, p.Y * syy, p.Z * sxx)
		if r.group == "foot" then
			pos = Vector3.new(p.X, p.Y, p.Z)
			parts[i] = r.part
			cfs[i] = CFrame.new(self.base + pos + Vector3.new(lungeX * 0.4, rise, lungeZ * 0.4)) * o.Rotation
		else
			parts[i] = r.part
			cfs[i] = root * CFrame.new(pos) * o.Rotation * extra
		end
		if r.group == "mouth" or r.group == "tongue" then
			r.part.Size = Vector3.new(r.size.X * sxx, r.size.Y * (1 + self.mouthOpen * 1.2), r.size.Z)
		end
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)

	-- Eyes glow red when the threat is imminent; white flash on hits.
	local glow = if self.urgent then 1 else 0
	self.eyeGlow += (glow - self.eyeGlow) * math.min(1, dt * 8)
	for _, r in self.rig do
		if r.group == "pupil" then
			r.part.Color = Build.INK:Lerp(Color3.fromRGB(255, 50, 50), self.eyeGlow)
			r.part.Material = if self.eyeGlow > 0.5 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
	if self.flashT > 0 then
		self.flashT -= dt
		self.highlight.FillColor = Color3.new(1, 1, 1)
		self.highlight.FillTransparency = 0.35
	else
		self.highlight.FillTransparency = 1
	end
end

function Monster.headPosition(self: Monster): Vector3
	return self.base + Vector3.new(0, 9.5 * self.scale, 0)
end

function Monster.centerPosition(self: Monster): Vector3
	return self.base + Vector3.new(0, 4.4 * self.scale, 2)
end

function Monster.destroy(self: Monster)
	if self.conn then
		self.conn:Disconnect()
	end
	self.model:Destroy()
end

return Monster
