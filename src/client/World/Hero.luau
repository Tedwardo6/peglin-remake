--!strict
-- A party member's hero on the battlefield: a copy of their own Roblox
-- avatar (built by the server), dressed in class gear and a cape in their
-- seat colour. While their ball flies, the damage it earns gathers above the
-- hero; when the ball drains, the hero strikes the monster with it.
-- Presentation only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Build = require(script.Parent.Build)
local Theme = require(script.Parent.Parent.UI.Theme)

export type ClassId = "ricochet" | "relay" | "guard"

local Hero = {}
Hero.__index = Hero

export type Hero = typeof(setmetatable(
	{} :: {
		uid: number,
		color: Color3,
		kit: string,
		model: Model,
		root: BasePart?,
		humanoid: Humanoid?,
		spot: Vector3,
		facing: Vector3,
		lunge: number,
		lungeDir: number,
		cast: number,
		hurt: number,
		down: boolean,
		watching: boolean,
		cape: BasePart?,
		capeWeld: Weld?,
		weaponTip: Attachment?,
		shoulder: Motor6D?,
		shoulderC0: CFrame?,
		plate: BillboardGui,
		nameLabel: TextLabel,
		bankLabel: TextLabel,
		bankScale: UIScale,
		hpFill: Frame,
		shieldFill: Frame,
		banked: number,
		bankShownAt: number,
		idleTrack: AnimationTrack?,
		tracks: { [string]: AnimationTrack },
		t: number,
		conn: RBXScriptConnection?,
		gearParts: { BasePart },
		fallback: boolean,
		reducedMotion: boolean,
	},
	Hero
))

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local COSMIC = rgb(22, 30, 110)
local GOLD = rgb(222, 170, 70)
local STEEL = rgb(150, 156, 190)

local function weldTo(part: BasePart, to: BasePart, offset: CFrame): Weld
	part.Anchored = false
	part.CanCollide = false
	part.Massless = true
	local w = Instance.new("Weld")
	w.Part0 = to
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
	return w
end

local function sparkleOn(part: BasePart, color: Color3)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.6, 1)
	pe.Rate = 4
	pe.Speed = NumberRange.new(0.2, 0.6)
	pe.LightEmission = 1
	pe.Parent = part
end

-- Class gear from parts, welded to the avatar's limbs.
local function dress(self: Hero, char: Model)
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	local rHand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
	local lHand = (char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")) :: BasePart?
	local gear = Build.model("Gear", char)
	local function part(p: BasePart): BasePart
		p.Parent = gear
		table.insert(self.gearParts, p)
		return p
	end
	local col = self.color
	-- Cape in the seat colour with a cosmic lining.
	if torso then
		local cape = part(Build.block(nil, Vector3.new(1.9, 2.6, 0.12), CFrame.new(), COSMIC, { material = Enum.Material.Fabric }))
		local trim = part(Build.block(nil, Vector3.new(1.95, 0.22, 0.14), CFrame.new(), col, { material = Enum.Material.Neon }))
		self.capeWeld = weldTo(cape, torso, CFrame.new(0, -0.55, 0.62) * CFrame.Angles(math.rad(8), 0, 0))
		weldTo(trim, cape, CFrame.new(0, -1.25, 0))
		self.cape = cape
		sparkleOn(cape, col)
		local clasp = part(Build.ball(nil, 0.32, Vector3.zero, GOLD, { material = Enum.Material.Metal }))
		weldTo(clasp, torso, CFrame.new(0, 0.55, -0.55))
	end
	if self.kit == "relay" then
		-- Mystic: tall star hat and a staff topped by a glowing orb.
		if head then
			for k = 0, 4 do
				local r = 1.5 - k * 0.28
				local disc = part(Build.cylinder(nil, 0.45, r, CFrame.new(), COSMIC, { material = Enum.Material.Fabric }))
				weldTo(disc, head, CFrame.new(0, 0.62 + k * 0.38, 0.05 + k * 0.04) * CFrame.Angles(math.rad(-6 * k), 0, math.rad(90)))
			end
			local brim = part(Build.cylinder(nil, 0.08, 2.3, CFrame.new(), COSMIC:Lerp(col, 0.2), { material = Enum.Material.Fabric }))
			weldTo(brim, head, CFrame.new(0, 0.48, 0) * CFrame.Angles(0, 0, math.rad(90)))
			local star = part(Build.ball(nil, 0.26, Vector3.zero, col, { material = Enum.Material.Neon }))
			weldTo(star, head, CFrame.new(0, 2.5, 0.4))
		end
		if rHand then
			local staff = part(Build.cylinder(nil, 4.6, 0.22, CFrame.new(), rgb(70, 46, 34), { material = Enum.Material.Wood }))
			weldTo(staff, rHand, CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)))
			local orb = part(Build.ball(nil, 0.7, Vector3.zero, col, { material = Enum.Material.Neon }))
			weldTo(orb, rHand, CFrame.new(0, 2.85, 0))
			local shell = part(Build.ball(nil, 0.95, Vector3.zero, col, { material = Enum.Material.ForceField }))
			weldTo(shell, rHand, CFrame.new(0, 2.85, 0))
			local tip = Instance.new("Attachment")
			tip.Parent = orb
			self.weaponTip = tip
			sparkleOn(orb, col)
		end
	elseif self.kit == "guard" then
		-- Warden: helm with a glowing visor, round shield, short blade.
		if head then
			local helm = part(Build.ellipsoid(nil, Vector3.new(1.5, 1.45, 1.5), CFrame.new(), STEEL, { material = Enum.Material.Metal }))
			weldTo(helm, head, CFrame.new(0, 0.12, 0))
			local visor = part(Build.block(nil, Vector3.new(1.0, 0.16, 0.1), CFrame.new(), col, { material = Enum.Material.Neon }))
			weldTo(visor, head, CFrame.new(0, 0.2, -0.74))
			local crest = part(Build.wedge(nil, Vector3.new(0.18, 0.7, 1.4), CFrame.new(), col, { material = Enum.Material.Neon }))
			weldTo(crest, head, CFrame.new(0, 1.1, 0.1))
		end
		if lHand then
			local shield = part(Build.cylinder(nil, 0.2, 2.2, CFrame.new(), COSMIC, { material = Enum.Material.Metal }))
			weldTo(shield, lHand, CFrame.new(-0.3, 0.3, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, math.rad(-90), 0))
			local rim = part(Build.cylinder(nil, 0.22, 2.4, CFrame.new(), GOLD, { material = Enum.Material.Metal }))
			weldTo(rim, lHand, CFrame.new(-0.32, 0.3, 0))
			local boss = part(Build.ball(nil, 0.6, Vector3.zero, col, { material = Enum.Material.Neon }))
			weldTo(boss, lHand, CFrame.new(-0.5, 0.3, 0))
		end
		if rHand then
			local blade = part(Build.block(nil, Vector3.new(0.18, 2.6, 0.4), CFrame.new(), rgb(210, 220, 255), { material = Enum.Material.Metal }))
			weldTo(blade, rHand, CFrame.new(0, -0.2, -1.5) * CFrame.Angles(math.rad(90), 0, 0))
			local edge = part(Build.block(nil, Vector3.new(0.08, 2.4, 0.1), CFrame.new(), col, { material = Enum.Material.Neon }))
			weldTo(edge, rHand, CFrame.new(0, -0.2, -1.5) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, 0, -0.2))
			local tip = Instance.new("Attachment")
			tip.Position = Vector3.new(0, 1.2, 0)
			tip.Parent = blade
			self.weaponTip = tip
		end
	else
		-- Duelist: hood and twin glowing daggers.
		if head then
			-- An open hood: a shell behind the head that frames the face.
			local hood = part(Build.ellipsoid(nil, Vector3.new(1.75, 1.75, 1.6), CFrame.new(), COSMIC, { material = Enum.Material.Fabric }))
			weldTo(hood, head, CFrame.new(0, 0.18, 0.42))
			local peak = part(Build.ellipsoid(nil, Vector3.new(0.9, 1.1, 0.9), CFrame.new(), COSMIC, { material = Enum.Material.Fabric }))
			weldTo(peak, head, CFrame.new(0, 0.85, 0.75) * CFrame.Angles(math.rad(-35), 0, 0))
			-- Glowing scarf at the neck in the seat colour.
			local scarf = part(Build.ellipsoid(nil, Vector3.new(1.5, 0.34, 1.35), CFrame.new(), col, { material = Enum.Material.Neon }))
			weldTo(scarf, head, CFrame.new(0, -0.72, 0.05))
		end
		for _, hand in { rHand, lHand } do
			if hand then
				local d = part(Build.block(nil, Vector3.new(0.14, 1.7, 0.32), CFrame.new(), rgb(220, 230, 255), { material = Enum.Material.Metal }))
				weldTo(d, hand, CFrame.new(0, -0.2, -0.95) * CFrame.Angles(math.rad(90), 0, 0))
				local e = part(Build.block(nil, Vector3.new(0.06, 1.6, 0.08), CFrame.new(), col, { material = Enum.Material.Neon }))
				weldTo(e, hand, CFrame.new(0, -0.2, -0.95) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, 0, -0.17))
				if hand == rHand then
					local tip = Instance.new("Attachment")
					tip.Position = Vector3.new(0, 0.8, 0)
					tip.Parent = d
					self.weaponTip = tip
				end
			end
		end
	end
end

-- Simple robed stand-in when the avatar copy isn't available yet.
local function fallbackFigure(self: Hero, parent: Instance): Model
	local m = Build.model("HeroFallback", parent)
	local body = Build.block(m, Vector3.new(1.8, 3.2, 1.2), CFrame.new(0, 1.6, 0), COSMIC, { material = Enum.Material.Fabric })
	local head = Build.ball(m, 1.3, Vector3.new(0, 3.8, 0), rgb(210, 190, 170))
	local hood = Build.ball(m, 1.6, Vector3.new(0, 3.95, 0.12), COSMIC, { material = Enum.Material.Fabric, transparency = 0 })
	local trim = Build.block(m, Vector3.new(1.85, 0.25, 1.25), CFrame.new(0, 0.2, 0), self.color, { material = Enum.Material.Neon })
	m.PrimaryPart = body
	local _ = head
	local _ = hood
	local _ = trim
	return m
end

local function plate(self: Hero, adornee: Instance)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HeroPlate"
	bb.Size = UDim2.fromOffset(150, 74)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 4.4, 0)
	-- Not AlwaysOnTop: those billboards failed to render in Studio play tests.
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = 400
	bb.Adornee = adornee
	bb.Parent = self.model
	local bank = Instance.new("TextLabel")
	bank.BackgroundTransparency = 1
	bank.Size = UDim2.new(1, 0, 0, 34)
	bank.FontFace = Theme.FontTitleBold
	bank.TextSize = 32
	bank.TextColor3 = self.color
	bank.Text = ""
	bank.Parent = bb
	local bs = Instance.new("UIStroke")
	bs.Thickness = 2.5
	bs.Color = Theme.Color.ink
	bs.Parent = bank
	local scale = Instance.new("UIScale")
	scale.Parent = bank
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 18)
	name.Position = UDim2.fromOffset(0, 36)
	name.FontFace = Theme.FontBold
	name.TextSize = 14
	name.TextColor3 = self.color
	local p = Players:GetPlayerByUserId(self.uid)
	name.Text = if p then p.DisplayName else "Hero"
	name.Parent = bb
	local ns = Instance.new("UIStroke")
	ns.Thickness = 1.5
	ns.Color = Theme.Color.ink
	ns.Parent = name
	local hpBack = Instance.new("Frame")
	hpBack.Size = UDim2.fromOffset(84, 8)
	hpBack.Position = UDim2.new(0.5, 0, 0, 58)
	hpBack.AnchorPoint = Vector2.new(0.5, 0)
	hpBack.BackgroundColor3 = rgb(10, 8, 24)
	hpBack.BorderSizePixel = 0
	hpBack.Parent = bb
	local hs = Instance.new("UIStroke")
	hs.Thickness = 1
	hs.Color = Theme.Color.goldDeep
	hs.Parent = hpBack
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Theme.Color.hull
	fill.BorderSizePixel = 0
	fill.Parent = hpBack
	local sh = Instance.new("Frame")
	sh.Size = UDim2.fromScale(0, 1)
	sh.BackgroundColor3 = Theme.Color.shield
	sh.BackgroundTransparency = 0.15
	sh.BorderSizePixel = 0
	sh.Parent = hpBack
	self.plate = bb
	self.bankLabel = bank
	self.bankScale = scale
	self.nameLabel = name
	self.hpFill = fill
	self.shieldFill = sh
end

function Hero.new(parent: Instance, uid: number, kit: string, color: Color3, spot: Vector3, facing: Vector3): Hero
	local self = setmetatable({}, Hero) :: any
	self.uid = uid
	self.color = color
	self.kit = kit
	self.spot = spot
	self.facing = facing
	self.lunge = 0
	self.lungeDir = 0
	self.cast = 0
	self.hurt = 0
	self.down = false
	self.watching = false
	self.banked = 0
	self.bankShownAt = 0
	self.t = math.random() * 10
	self.gearParts = {}
	self.tracks = {}
	self.fallback = false
	self.reducedMotion = false

	local folder = ReplicatedStorage:FindFirstChild("HeroModels")
	local source = if folder then folder:FindFirstChild(tostring(uid)) else nil
	if source and source:IsA("Model") then
		local m = source:Clone()
		m.Name = "Hero_" .. tostring(uid)
		self.model = m
		self.root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		self.humanoid = m:FindFirstChildOfClass("Humanoid")
		local hum = self.humanoid
		if hum then
			hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		dress(self, m)
		m.Parent = parent
		-- Motion from the avatar's own animation set: idle, tool slash for the
		-- strike, point for support casts, cheer for victories.
		local anims = m:FindFirstChild("AnimIds")
		local function idOf(key: string): string?
			local v = anims and anims:FindFirstChild(key)
			return if v and v:IsA("StringValue") then v.Value else nil
		end
		if hum then
			local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
			animator.Parent = hum
			local function load(name: string, id: string?, looped: boolean, priority: Enum.AnimationPriority): AnimationTrack?
				if id == nil then
					return nil
				end
				local a = Instance.new("Animation")
				a.AnimationId = id
				local ok, track = pcall(function()
					return (animator :: Animator):LoadAnimation(a)
				end)
				if ok and track then
					track.Looped = looped
					track.Priority = priority
					self.tracks[name] = track
					return track
				end
				return nil
			end
			local idle = load("idle", idOf("idle_Animation1"), true, Enum.AnimationPriority.Idle)
			if idle then
				idle:Play(0.2)
				self.idleTrack = idle
			end
			load("slash", idOf("toolslash_ToolSlashAnim"), false, Enum.AnimationPriority.Action)
			load("lunge", idOf("toollunge_ToolLungeAnim"), false, Enum.AnimationPriority.Action)
			load("point", idOf("point_PointAnim"), false, Enum.AnimationPriority.Action)
			load("cheer", idOf("cheer_CheerAnim"), false, Enum.AnimationPriority.Action)
			load("wave", idOf("wave_WaveAnim"), false, Enum.AnimationPriority.Action)
		end
		local rightArm = if self.tracks.slash then nil else m:FindFirstChild("RightUpperArm")
		if rightArm then
			local sh = rightArm:FindFirstChild("RightShoulder")
			if sh and sh:IsA("Motor6D") then
				self.shoulder = sh
				self.shoulderC0 = sh.C0
			end
		end
	else
		self.model = fallbackFigure(self, parent)
		self.fallback = true
	end
	plate(self, self.root or self.model.PrimaryPart or self.model)
	Hero._place(self)
	self.conn = RunService.RenderStepped:Connect(function(dt)
		Hero._step(self, dt)
	end)
	return self
end

function Hero._place(self: Hero)
	local lunge = self.lunge
	local pos = self.spot + self.facing * (lunge * 2.2)
	local cf = CFrame.lookAt(pos, pos + self.facing)
	if self.down then
		cf = cf * CFrame.Angles(math.rad(-75), 0, 0) * CFrame.new(0, -1.5, 0)
	elseif self.watching then
		cf = cf * CFrame.Angles(math.rad(-12), 0, 0)
	elseif self.hurt > 0 then
		cf = cf * CFrame.Angles(math.rad(-10 * self.hurt), 0, 0)
	end
	if self.root then
		-- Root sits ~3 studs above the feet for R15.
		local hum = self.humanoid
		local hip = if hum then hum.HipHeight + (self.root :: BasePart).Size.Y / 2 else 3
		self.model:PivotTo(cf + Vector3.new(0, hip, 0))
	else
		self.model:PivotTo(cf)
	end
end

-- `watching` (idle, sitting this fight out) slumps the hero instead of
-- knocking them flat: only a real knock-out lies them down.
function Hero.setVitals(self: Hero, hull: number, maxHull: number, shield: number, defeated: boolean, watching: boolean?)
	local f = if maxHull > 0 then math.clamp(hull / maxHull, 0, 1) else 0
	self.hpFill.Size = UDim2.fromScale(f, 1)
	self.shieldFill.Size = UDim2.fromScale(if maxHull > 0 then math.clamp(shield / maxHull, 0, 1) else 0, 1)
	local w = (watching == true) and not defeated
	if defeated ~= self.down or w ~= self.watching then
		self.down = defeated
		self.watching = w
		self.nameLabel.TextTransparency = if defeated or w then 0.5 else 0
	end
end

-- Damage gathering above the hero while their ball flies.
function Hero.bank(self: Hero, total: number)
	self.banked = total
	self.bankLabel.Text = if total > 0 then `⚔ {total}` else ""
	self.bankShownAt = os.clock()
	if not self.reducedMotion then
		self.bankScale.Scale = 1.25
		TweenService:Create(self.bankScale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
end

function Hero.clearBank(self: Hero)
	self.banked = 0
	self.bankLabel.Text = ""
end

-- Starts the strike; `impact` is called when the blow should land.
function Hero.strike(self: Hero, impactIn: number, onImpact: () -> ())
	local wind = math.max(0.05, impactIn)
	self.lungeDir = 1
	local anim = if self.kit == "guard" then (self.tracks.lunge or self.tracks.slash) else self.tracks.slash
	if anim then
		anim:Play(0.05, 1, 1.4)
	end
	task.delay(wind, function()
		self.lungeDir = -1
		self:clearBank()
		onImpact()
	end)
end

function Hero.castSupport(self: Hero)
	self.cast = 1
	local p = self.tracks.point
	if p then
		p:Play(0.1, 1, 1.3)
	end
end

function Hero.cheer(self: Hero)
	local c = self.tracks.cheer
	if c then
		c:Play(0.15)
	end
end

function Hero.wave(self: Hero)
	local w = self.tracks.wave
	if w then
		w:Play(0.15)
	end
end

function Hero.hit(self: Hero)
	self.hurt = 1
end

function Hero.weaponPosition(self: Hero): Vector3
	local tip = self.weaponTip
	if tip and tip.Parent then
		return tip.WorldPosition
	end
	return self.spot + Vector3.new(0, 3, 0) + self.facing * 1.5
end

function Hero.headPosition(self: Hero): Vector3
	return self.spot + Vector3.new(0, 5.2, 0)
end

function Hero.setSpot(self: Hero, spot: Vector3, facing: Vector3)
	self.spot = spot
	self.facing = facing
end

function Hero._step(self: Hero, dt: number)
	self.t += dt
	if self.lungeDir > 0 then
		self.lunge = math.min(1, self.lunge + dt * 6)
	elseif self.lungeDir < 0 then
		self.lunge = math.max(0, self.lunge - dt * 3)
		if self.lunge <= 0 then
			self.lungeDir = 0
		end
	end
	self.hurt = math.max(0, self.hurt - dt * 3)
	self.cast = math.max(0, self.cast - dt * 2)
	-- Weapon arm: raised during the wind-up, swung through on impact.
	local sh = self.shoulder
	if sh and self.shoulderC0 then
		local raise = if self.lungeDir > 0 then self.lunge else self.lunge * 0.4
		local castLift = self.cast
		sh.C0 = (self.shoulderC0 :: CFrame) * CFrame.Angles(math.rad(raise * 150 + castLift * 110), 0, math.rad(-castLift * 20))
	end
	-- Cape sway.
	local w = self.capeWeld
	if w and not self.reducedMotion then
		w.C0 = CFrame.new(0, -0.55, 0.62) * CFrame.Angles(math.rad(8 + math.sin(self.t * 2.1) * 6 + self.lunge * 25), math.rad(math.sin(self.t * 1.3) * 4), 0)
	end
	-- The banked number fades if it lingers (e.g. a shot with no damage).
	if self.banked > 0 and os.clock() - self.bankShownAt > 9 then
		self:clearBank()
	end
	Hero._place(self)
end

function Hero.destroy(self: Hero)
	if self.conn then
		self.conn:Disconnect()
	end
	if self.idleTrack then
		self.idleTrack:Stop(0)
	end
	self.model:Destroy()
end

return Hero
