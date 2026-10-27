--!strict
-- The monster on the battlefield, built from its generated 3D model
-- (ReplicatedStorage.MonsterModels, rebuilt by the server from
-- Content/MonsterModels). Each mesh part is animated procedurally about a
-- joint: breathing idle, threat wind-up and slam, flinch per strike, armor
-- bubble, reveal rising from the floor, and a dissolve on death. A
-- psychedelic rim light and aura sit on top. Same interface as before, so
-- gameplay code is unchanged.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enemies = require(Shared.Content.Enemies)

local Build = require(script.Parent.Build)
local Layout = require(script.Parent.Layout)

type Role = "body" | "head" | "armL" | "armR" | "leg" | "tentacle" | "held" | "base"

type Rig = {
	part: BasePart,
	base: CFrame, -- relative to the model origin, already scaled
	pivot: Vector3, -- joint where this piece meets the core, model space
	role: Role,
	side: number,
	holder: number?, -- held items follow the arm that grips them
	grip: Vector3?, -- where the holding hand meets the held item, model space
	vel: Vector3?,
	spin: Vector3?,
	transparency: number,
}

local Monster = {}
Monster.__index = Monster

export type Monster = typeof(setmetatable(
	{} :: {
		model: Model,
		rig: { Rig },
		base: Vector3,
		origin: CFrame,
		height: number,
		float: boolean,
		glow: Color3,
		highlight: Highlight,
		aura: ParticleEmitter?,
		light: PointLight?,
		bubble: BasePart,
		hip: Vector3,
		seated: boolean, -- sits on a fixed base (a throne): leans less
		t: number,
		telegraph: number,
		teleS: number, -- smoothed wind-up actually shown
		urgent: boolean,
		flinch: number,
		flinchV: number,
		stagger: number,
		lungeT: number,
		reveal: number,
		revealT: number,
		dead: boolean,
		deathT: number,
		flashT: number,
		armorOn: boolean,
		conn: RBXScriptConnection?,
		reducedMotion: boolean,
		hidden: boolean,
		fallback: boolean,
	},
	Monster
))

local function roleOf(name: string): (Role, number)
	local n = string.lower(name)
	local side = if string.find(n, "left", 1, true) then -1 elseif string.find(n, "right", 1, true) then 1 else 0
	if string.find(n, "arm", 1, true) then
		return (if side < 0 then "armL" else "armR"), side
	elseif string.find(n, "leg", 1, true) or n == "roots" then
		return "leg", side
	elseif string.find(n, "tentacle", 1, true) or n == "tail" then
		return "tentacle", side
	elseif n == "head" or n == "hood" or n == "helm" or n == "crown" or string.find(n, "head", 1, true) then
		return "head", side
	elseif n == "staff" or n == "lance" or n == "goblet" then
		return "held", side
	elseif n == "throne" then
		return "base", side
	end
	return "body", side
end

local function fallbackModel(): Model
	-- A shadowy silhouette if the generated model hasn't arrived.
	local m = Instance.new("Model")
	local body = Build.ellipsoid(m, Vector3.new(3.4, 4.6, 2.6), CFrame.new(0, 2.6, 0), Color3.fromRGB(20, 16, 50))
	body.Name = "body"
	local head = Build.ball(m, 2, Vector3.new(0, 5.4, -0.4), Color3.fromRGB(26, 20, 60))
	head.Name = "head"
	for _, sx in { -1, 1 } do
		local arm = Build.ellipsoid(m, Vector3.new(1, 3.4, 1), CFrame.new(sx * 2.1, 2.8, -0.2), Color3.fromRGB(20, 16, 50))
		arm.Name = if sx < 0 then "left arm" else "right arm"
		local eye = Build.ball(m, 0.4, Vector3.new(sx * 0.45, 5.5, -1.3), Color3.fromRGB(255, 140, 60), { material = Enum.Material.Neon })
		eye.Name = "eye"
	end
	m:SetAttribute("Height", 6.4)
	return m
end

function Monster.new(parent: Instance, enemyId: string, base: Vector3): Monster
	local def = Enemies.ById[enemyId]
	local look = def.look
	local self = setmetatable({}, Monster) :: any
	self.base = base
	self.rig = {}
	self.t = math.random() * 10
	self.telegraph = 0
	self.teleS = 0
	self.urgent = false
	self.flinch = 0
	self.flinchV = 0
	self.stagger = 0
	self.lungeT = 99
	self.reveal = 0
	self.revealT = 99
	self.dead = false
	self.deathT = 0
	self.flashT = 0
	self.armorOn = false
	self.reducedMotion = false
	self.hidden = false
	self.float = look.float == true
	self.glow = look.glow

	local folder = ReplicatedStorage:FindFirstChild("MonsterModels")
	local src = if folder then folder:FindFirstChild(look.model) else nil
	local m: Model
	if src and src:IsA("Model") then
		m = src:Clone()
		self.fallback = false
	else
		m = fallbackModel()
		self.fallback = true
	end
	m.Name = "Monster_" .. enemyId
	local srcHeight = (m:GetAttribute("Height") :: number?) or 6
	local scale = look.height / srcHeight
	self.height = look.height
	local rootPart = m:FindFirstChild("Root")
	if rootPart then
		rootPart:Destroy()
	end
	-- Facing: the model faces -Z; turn it toward the heroes (3/4 view).
	local f = Layout.MONSTER_FACING
	self.origin = CFrame.lookAt(base, base + f)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			local rel = d.CFrame -- model space (origin at the feet)
			local scaled = CFrame.new(rel.Position * scale) * (rel - rel.Position)
			d.Size = d.Size * scale
			local role, side = roleOf(d.Name)
			table.insert(self.rig, { part = d, base = scaled, pivot = scaled.Position, role = role, side = side, transparency = d.Transparency })
		end
	end
	Monster._joints(self)
	m.Parent = parent
	self.model = m

	-- Psychedelic rim light + white flash on strikes.
	local hl = Instance.new("Highlight")
	hl.Adornee = m
	hl.FillColor = look.glow
	hl.FillTransparency = 0.88
	hl.OutlineColor = look.glow
	hl.OutlineTransparency = 0.25
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = m
	self.highlight = hl
	-- Aura motes and a soft glow.
	local host = self.rig[1] and self.rig[1].part
	if host then
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(look.glow, Color3.fromRGB(255, 120, 230))
		pe.LightEmission = 1
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35 * scale + 0.15), NumberSequenceKeypoint.new(1, 0) })
		pe.Lifetime = NumberRange.new(1, 1.8)
		pe.Rate = 10
		pe.Speed = NumberRange.new(1, 2.5)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = host
		self.aura = pe
		local pl = Instance.new("PointLight")
		pl.Color = look.glow
		pl.Brightness = 1.2
		pl.Range = math.max(10, look.height * 1.6)
		pl.Parent = host
		self.light = pl
		if look.sparkle then
			-- Gold-and-diamond glints across the body: quick, bright, tiny.
			for _, r in self.rig do
				if r.role == "body" or r.role == "head" or r.role == "held" then
					local g = Instance.new("ParticleEmitter")
					g.Texture = "rbxasset://textures/particles/sparkles_main.dds"
					g.Color = ColorSequence.new(Color3.fromRGB(255, 250, 220), Color3.fromRGB(255, 205, 90))
					g.LightEmission = 1
					g.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.28 * scale + 0.12), NumberSequenceKeypoint.new(1, 0) })
					g.Lifetime = NumberRange.new(0.25, 0.5)
					g.Rate = if r.role == "body" then 14 else 5
					g.Speed = NumberRange.new(0)
					g.Rotation = NumberRange.new(0, 360)
					g.RotSpeed = NumberRange.new(-90, 90)
					g.ZOffset = 1
					g.Parent = r.part
				end
			end
		end
	end
	-- Armor bubble.
	self.bubble = Build.ellipsoid(m, Vector3.new(look.height * 0.95, look.height * 1.1, look.height * 0.95), self.origin * CFrame.new(0, look.height * 0.5, 0), Color3.fromRGB(150, 180, 255), {
		material = Enum.Material.ForceField,
		transparency = 1,
		name = "ArmorBubble",
	})

	Monster._step(self, 0)
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
	local power = math.clamp(damage / 25, 0.2, 1.3)
	self.flinchV = math.min(1.4, self.flinchV + power)
	if big then
		self.stagger = 1
	end
	self.flashT = 0.07 + math.min(power, 1) * 0.08
end

function Monster.attack(self: Monster)
	self.lungeT = 0
end

function Monster.setArmor(self: Monster, on: boolean)
	if on == self.armorOn then
		return
	end
	self.armorOn = on
	TweenService:Create(self.bubble, TweenInfo.new(0.35), { Transparency = if on then 0.15 else 1 }):Play()
end

function Monster.hide(self: Monster)
	self.hidden = true
	Monster._step(self, 0)
end

function Monster.revealIn(self: Monster, seconds: number)
	self.hidden = false
	self.revealT = 0
	self.reveal = math.max(0.05, seconds)
end

function Monster.die(self: Monster)
	if self.dead then
		return
	end
	self.dead = true
	self.deathT = 0
	local center = self.base + Vector3.new(0, self.height * 0.5, 0)
	for _, r in self.rig do
		local dir = r.part.Position - center
		if dir.Magnitude < 0.01 then
			dir = Vector3.new(0, 1, 0)
		end
		r.vel = dir.Unit * (4 + math.random() * 5) + Vector3.new(0, 3 + math.random() * 4, 2)
		r.spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
	end
	self.highlight.FillColor = Color3.new(1, 1, 1)
	self.highlight.FillTransparency = 0.1
	if self.aura then
		local a = self.aura :: ParticleEmitter
		a.Rate = 0
		a:Emit(60)
	end
end

-- Joints: where each limb's box overlaps the core's box (the seam the
-- generator already hides), else the limb point nearest the core. Rotating
-- about these keeps limbs attached through every pose.
type Box = { min: Vector3, max: Vector3 }

local function boxOf(r: Rig): Box
	local cf = r.base
	local h = r.part.Size / 2
	-- Axis-aligned bounds of the rotated box.
	local ex = Vector3.new(
		math.abs(cf.RightVector.X) * h.X + math.abs(cf.UpVector.X) * h.Y + math.abs(cf.LookVector.X) * h.Z,
		math.abs(cf.RightVector.Y) * h.X + math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z,
		math.abs(cf.RightVector.Z) * h.X + math.abs(cf.UpVector.Z) * h.Y + math.abs(cf.LookVector.Z) * h.Z
	)
	return { min = cf.Position - ex, max = cf.Position + ex }
end

local function clampV(v: Vector3, lo: Vector3, hi: Vector3): Vector3
	return Vector3.new(math.clamp(v.X, lo.X, hi.X), math.clamp(v.Y, lo.Y, hi.Y), math.clamp(v.Z, lo.Z, hi.Z))
end

function Monster._joints(self: Monster)
	local core: Rig? = nil
	local best = -1
	for _, r in self.rig do
		if r.role == "body" then
			local s = r.part.Size
			local v = s.X * s.Y * s.Z
			if v > best then
				best = v
				core = r
			end
		end
	end
	if core == nil then
		-- No body piece: the largest piece is the core.
		for _, r in self.rig do
			local s = r.part.Size
			local v = s.X * s.Y * s.Z
			if v > best then
				best = v
				core = r
			end
		end
	end
	local cb = boxOf(core :: Rig)
	local coreCenter = (cb.min + cb.max) / 2
	local legTop = -math.huge
	self.seated = false
	for _, r in self.rig do
		local b = boxOf(r)
		if r.role == "base" then
			self.seated = true
		end
		if r.role == "leg" then
			legTop = math.max(legTop, b.max.Y)
		end
		if r == core then
			r.pivot = Vector3.new(coreCenter.X, cb.min.Y, coreCenter.Z)
		elseif r.role ~= "leg" and r.role ~= "base" then
			local lo = Vector3.new(math.max(b.min.X, cb.min.X), math.max(b.min.Y, cb.min.Y), math.max(b.min.Z, cb.min.Z))
			local hi = Vector3.new(math.min(b.max.X, cb.max.X), math.min(b.max.Y, cb.max.Y), math.min(b.max.Z, cb.max.Z))
			if lo.X <= hi.X and lo.Y <= hi.Y and lo.Z <= hi.Z then
				local mid = (lo + hi) / 2
				-- Arms hinge near the top of the overlap (the shoulder).
				if r.role == "armL" or r.role == "armR" then
					mid = Vector3.new(mid.X, hi.Y - (hi.Y - lo.Y) * 0.25, mid.Z)
				end
				r.pivot = mid
			else
				r.pivot = clampV(coreCenter, b.min, b.max)
			end
		end
	end
	-- Held items follow the nearest arm.
	for i, r in self.rig do
		if r.role == "held" then
			local nearest: number? = nil
			local d = math.huge
			for j, a in self.rig do
				if a.role == "armL" or a.role == "armR" then
					local dist = (a.base.Position - r.base.Position).Magnitude
					if dist < d then
						d = dist
						nearest = j
					end
				end
			end
			r.holder = nearest
			if nearest then
				-- Grip: the point of the item nearest the holding arm's far end.
				local a = self.rig[nearest]
				local ab = boxOf(a)
				local hand = Vector3.new((ab.min.X + ab.max.X) / 2, ab.min.Y + (ab.max.Y - ab.min.Y) * 0.15, (ab.min.Z + ab.max.Z) / 2)
				local hb = boxOf(r)
				r.grip = clampV(hand, hb.min, hb.max)
			end
			local _ = i
		end
	end
	-- Hips: upper body leans about the top of the legs (or the core's base).
	if legTop > -math.huge then
		self.hip = Vector3.new(coreCenter.X, legTop, coreCenter.Z)
	else
		self.hip = Vector3.new(coreCenter.X, cb.min.Y, coreCenter.Z)
	end
end

local function rotAbout(pivot: Vector3, rot: CFrame): CFrame
	return CFrame.new(pivot) * rot * CFrame.new(-pivot)
end

function Monster._step(self: Monster, dt: number)
	self.t += dt
	local parts = table.create(#self.rig)
	local cfs = table.create(#self.rig)
	if self.dead then
		self.deathT += dt
		local fade = math.clamp(self.deathT / 1.1, 0, 1)
		for i, r in self.rig do
			local v = r.vel :: Vector3
			r.vel = v + Vector3.new(0, -9 * dt, 0)
			local spin = r.spin :: Vector3
			parts[i] = r.part
			cfs[i] = (r.part.CFrame + v * dt) * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
			r.part.Transparency = math.max(r.transparency, fade)
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		self.highlight.FillTransparency = 0.1 + fade * 0.9
		self.highlight.OutlineTransparency = 0.25 + fade * 0.75
		if self.deathT > 1.6 then
			Monster.destroy(self)
		end
		return
	end
	local rm = self.reducedMotion
	local t = self.t
	-- Reveal: rise out of the floor.
	local rise = 0
	if self.hidden then
		rise = -self.height * 1.3
	elseif self.revealT < self.reveal then
		self.revealT += dt
		local u = math.clamp(self.revealT / self.reveal, 0, 1)
		rise = -self.height * 1.3 * (1 - (1 - (1 - u) ^ 3))
	end
	-- Threat: lean back and raise arms; slam forward on landing.
	self.lungeT += dt
	local lunge = 0
	if self.lungeT < 0.7 then
		local u = self.lungeT / 0.7
		lunge = math.sin(u * math.pi)
	end
	-- Flinch eases toward the impulse, which then decays: no snapping.
	self.flinchV = math.max(0, self.flinchV - dt * 2.6)
	self.flinch += (self.flinchV - self.flinch) * math.min(1, dt * 16)
	self.stagger = math.max(0, self.stagger - dt * 2)
	-- Smooth the wind-up; the slam releases it quickly but never snaps.
	local rate = if self.lungeT < 0.7 then 9 else 3
	self.teleS += (self.telegraph - self.teleS) * math.min(1, dt * rate)
	local tele = self.teleS
	local breathe = if rm then 0 else math.sin(t * 2.2)
	local hover = if self.float then (if rm then 0 else math.sin(t * 1.3) * 0.35) + self.height * 0.06 else 0
	if self.float then
		-- Floaters gather upward on the wind-up and dive on the slam.
		hover += tele * self.height * 0.1 - lunge * self.height * 0.08
	end
	local shake = if self.urgent and not rm then (math.random() - 0.5) * 0.12 else 0
	-- Whole-body pose (model space): flinch leans away from the heroes
	-- (+Z in model space is behind the monster), lunge leans in.
	local lean = math.rad(self.flinch * 9 + self.stagger * 8 - lunge * 16 + tele * 6) * (if self.seated then 0.55 else 1)
	local bodyPose = CFrame.new(shake, rise + hover + breathe * 0.012 * self.height, self.flinch * 0.35 - lunge * 0.9) * rotAbout(self.hip, CFrame.Angles(lean, 0, 0))
	local poses: { CFrame } = table.create(#self.rig)
	local armPitch: { number } = table.create(#self.rig, 0)
	for i, r in self.rig do
		local pose = CFrame.identity
		if r.role == "head" then
			pose = rotAbout(r.pivot, CFrame.Angles(math.rad(breathe * 3 + tele * 10 - lunge * 14 + self.flinch * 8), math.rad(math.sin(t * 0.7) * 6), 0))
		elseif r.role == "armL" or r.role == "armR" then
			-- Wind-up raises the arms forward/up; the slam drives them down.
			local raise = tele * 80 + (if self.urgent then 10 else 0) - lunge * 25
			local sway = if rm then 0 else math.sin(t * 1.6 + r.side) * 4
			local pitch = math.rad(raise + sway - self.flinch * 14)
			armPitch[i] = pitch
			pose = rotAbout(r.pivot, CFrame.Angles(pitch, 0, math.rad(-r.side * (tele * 10 + breathe * 1.5))))
		elseif r.role == "tentacle" then
			-- Tentacles writhe; the wind-up flares them out, the slam whips them in.
			local flare = r.side * (tele * 22 - lunge * 10)
			local curl = (if rm then 0 else math.sin(t * 2 + r.side) * 7) + (if r.side == 0 then tele * 18 else tele * 8) - lunge * 18
			pose = rotAbout(r.pivot, CFrame.Angles(math.rad(curl), 0, math.rad(flare + r.side * (if rm then 0 else math.sin(t * 1.4) * 8))))
		elseif r.role == "body" then
			pose = rotAbout(r.pivot, CFrame.Angles(math.rad(breathe * 1.2), 0, 0))
		end
		poses[i] = pose
	end
	for i, r in self.rig do
		local pose = poses[i]
		if r.role == "held" and r.holder then
			-- The item rides the hand but mostly stays upright (a staff is
			-- raised, not swung flat), then thrusts forward on the slam.
			local h = r.holder :: number
			local grip = r.grip or r.base.Position
			pose = poses[h] * rotAbout(grip, CFrame.Angles(-armPitch[h] * 0.8 - math.rad(lunge * 18), 0, 0))
		end
		local whole = if r.role == "leg" or r.role == "base" then CFrame.new(0, rise + (if self.float then hover else 0), 0) else bodyPose
		parts[i] = r.part
		cfs[i] = self.origin * whole * pose * r.base
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	self.bubble.CFrame = self.origin * CFrame.new(0, rise + self.height * 0.5, 0)
	-- Rim and flash.
	local hl = self.highlight
	if self.flashT > 0 then
		self.flashT -= dt
		hl.FillColor = Color3.new(1, 1, 1)
		hl.FillTransparency = 0.25
	else
		local threatCol = Color3.fromRGB(255, 110, 40)
		local pulse = 0.5 + 0.5 * math.sin(t * (if self.urgent then 14 else 2))
		hl.FillColor = self.glow:Lerp(threatCol, tele)
		hl.FillTransparency = 0.9 - tele * 0.25 * pulse
		hl.OutlineColor = self.glow:Lerp(threatCol, tele):Lerp(Color3.fromRGB(255, 120, 230), (0.5 + 0.5 * math.sin(t * 0.8)) * 0.4)
	end
	if self.light then
		(self.light :: PointLight).Brightness = 1 + tele * 1.5
	end
	if self.aura then
		(self.aura :: ParticleEmitter).Rate = if self.hidden then 0 else 8 + tele * 30
	end
end

function Monster.headPosition(self: Monster): Vector3
	return self.base + Vector3.new(0, self.height * 0.95, 0)
end

function Monster.centerPosition(self: Monster): Vector3
	return self.base + Vector3.new(0, self.height * 0.55, 1)
end

function Monster.destroy(self: Monster)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	self.model:Destroy()
end

return Monster
