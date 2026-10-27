--!strict
-- Feedback effects: peg sparks, damage numbers scaled by size, combo
-- callouts, shockwave rings, screen flashes, and the Relay Charge arc.
-- Every effect is bounded (pooled objects, fixed lifetimes) and respects
-- reduced motion.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Kit = require(script.Parent.Parent.UI.Kit)
local Build = require(script.Parent.Parent.World.Build)

local Fx = {}

local worldRoot: Folder
local overlay: ScreenGui
local sparkHost: Part
local sparkAttachments: { Attachment } = {}
local sparkIndex = 0
local numberPool: { BillboardGui } = {}
local numberIndex = 0
local flashFrame: Frame
local calloutLabel: TextLabel
local calloutScale: UIScale
local reduced = false

local SPARK_COUNT = 10
local NUMBER_COUNT = 28

function Fx.setReducedMotion(on: boolean)
	reduced = on
end

function Fx.init(parentWorld: Instance, gui: ScreenGui)
	worldRoot = Instance.new("Folder")
	worldRoot.Name = "Fx"
	worldRoot.Parent = parentWorld
	overlay = gui

	sparkHost = Build.block(worldRoot, Vector3.one * 0.1, CFrame.new(0, -500, 0), Color3.new(1, 1, 1), { transparency = 1 })
	for i = 1, SPARK_COUNT do
		local att = Instance.new("Attachment")
		att.Parent = sparkHost
		local pe = Instance.new("ParticleEmitter")
		pe.Enabled = false
		pe.Rate = 0
		pe.Lifetime = NumberRange.new(0.25, 0.45)
		pe.Speed = NumberRange.new(6, 12)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Drag = 6
		pe.LightEmission = 0.8
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.ZOffset = 2
		pe.Parent = att
		sparkAttachments[i] = att
	end

	for i = 1, NUMBER_COUNT do
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(160, 70)
		bb.AlwaysOnTop = false -- AlwaysOnTop billboards failed to render in Studio play tests
		bb.LightInfluence = 0
		bb.Enabled = false
		bb.Name = "DamageNumber"
		bb.Adornee = sparkHost
		bb.Parent = worldRoot
		local label = Kit.label({ Text = "", TextSize = 34, Size = UDim2.fromScale(1, 1), Bold = true, Parent = bb })
		label.Name = "Text"
		Kit.new("UIScale", { Parent = label })
		numberPool[i] = bb
	end

	flashFrame = Kit.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 50,
		Parent = overlay,
	})
	calloutLabel = Kit.label({
		Name = "Callout",
		Text = "",
		TextSize = 54,
		Bold = true,
		Size = UDim2.fromOffset(520, 70),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.36, 0.2),
		ZIndex = 40,
		Parent = overlay,
	})
	calloutLabel.TextTransparency = 1
	calloutScale = Kit.new("UIScale", { Parent = calloutLabel })
end

function Fx.sparks(pos: Vector3, color: Color3, count: number)
	sparkIndex = sparkIndex % SPARK_COUNT + 1
	local att = sparkAttachments[sparkIndex]
	att.WorldPosition = pos
	local pe = att:FindFirstChildOfClass("ParticleEmitter") :: ParticleEmitter
	pe.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	pe:Emit(if reduced then math.max(1, math.floor(count / 3)) else count)
end

-- Damage/shield/repair number popping off a peg; size grows with magnitude.
function Fx.number(pos: Vector3, text: string, color: Color3, magnitude: number)
	numberIndex = numberIndex % NUMBER_COUNT + 1
	local bb = numberPool[numberIndex]
	local label = bb:FindFirstChild("Text") :: TextLabel
	local scale = label:FindFirstChildOfClass("UIScale") :: UIScale
	bb.Adornee = sparkHost
	-- Nudged toward the camera so pegs and the board never hide the number.
	bb.StudsOffsetWorldSpace = pos - sparkHost.Position + Vector3.new(0, 0, 1.5)
	bb.Enabled = true
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	local size = math.clamp(0.75 + magnitude / 14, 0.75, 2.2)
	label.TextSize = 30
	scale.Scale = if reduced then size else size * 1.5
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = size }):Play()
	local rise = if reduced then 0.6 else 1.6 + size * 0.4
	local drift = (math.random() - 0.5) * 0.8
	local start = bb.StudsOffsetWorldSpace
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local u = (os.clock() - t0) / 0.75
		if u >= 1 or not bb.Enabled then
			conn:Disconnect()
			bb.Enabled = false
			return
		end
		local e = 1 - (1 - u) ^ 2
		bb.StudsOffsetWorldSpace = start + Vector3.new(drift * e, rise * e, 0)
		if u > 0.6 then
			local f = (u - 0.6) / 0.4
			label.TextTransparency = f
			if stroke then
				stroke.Transparency = f
			end
		end
	end)
end

-- Big centred callout for combos and moments ("COMBO x12", "RELAY!").
function Fx.callout(text: string, color: Color3, size: number?)
	calloutLabel.Text = text
	calloutLabel.TextColor3 = color
	calloutLabel.TextTransparency = 0
	local stroke = calloutLabel:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	calloutScale.Scale = if reduced then 1 else 1.6
	calloutLabel.Rotation = if reduced then 0 else (math.random() - 0.5) * 8
	local target = size or 1
	TweenService:Create(calloutScale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = target }):Play()
	task.delay(0.7, function()
		if calloutLabel.Text == text then
			TweenService:Create(calloutLabel, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			if stroke then
				TweenService:Create(stroke, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
		end
	end)
end

function Fx.setCalloutAnchor(pos: UDim2)
	calloutLabel.Position = pos
end

function Fx.flash(color: Color3, strength: number)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 1 - (if reduced then strength * 0.4 else strength)
	TweenService:Create(flashFrame, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
end

-- Expanding ring in the world (burst peg, monster death, landing).
function Fx.ring(pos: Vector3, color: Color3, radius: number, duration: number?)
	local d = Build.disc(worldRoot, 0.4, 0.06, pos, color, { material = Enum.Material.Neon, transparency = 0.2 })
	local t = duration or 0.35
	TweenService:Create(d, TweenInfo.new(t, Enum.EasingStyle.Quad), { Size = Vector3.new(0.06, radius * 2, radius * 2), Transparency = 1 }):Play()
	task.delay(t + 0.05, function()
		d:Destroy()
	end)
end

-- Strike bolt: a glowing orb with a trail flies from a hero's weapon to the
-- monster on a shallow arc, then calls onArrive.
function Fx.bolt(from: Vector3, to: Vector3, color: Color3, duration: number, onArrive: (() -> ())?)
	local orb = Build.ball(worldRoot, 0.9, from, color, { material = Enum.Material.Neon })
	local core = Build.ball(worldRoot, 0.45, from, Color3.new(1, 1, 1), { material = Enum.Material.Neon })
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.35, 0)
	a0.Parent = orb
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.35, 0)
	a1.Parent = orb
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = orb
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 2
	light.Range = 8
	light.Parent = orb
	local t0 = os.clock()
	local d = math.max(0.05, if reduced then duration * 0.6 else duration)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local u = math.clamp((os.clock() - t0) / d, 0, 1)
		local p = from:Lerp(to, u) + Vector3.new(0, math.sin(u * math.pi) * 2.2, 0)
		orb.CFrame = CFrame.new(p)
		core.CFrame = CFrame.new(p)
		if u >= 1 then
			conn:Disconnect()
			orb:Destroy()
			core:Destroy()
			Fx.ring(to, color, 3.5, 0.3)
			if onArrive then
				onArrive()
			end
		end
	end)
end

-- Confetti burst for victories (bounded, one-shot).
function Fx.confetti(pos: Vector3, colors: { Color3 })
	local host = Build.block(worldRoot, Vector3.one * 0.2, CFrame.new(pos), Color3.new(1, 1, 1), { transparency = 1 })
	for _, col in colors do
		local pe = Instance.new("ParticleEmitter")
		pe.Enabled = false
		pe.Lifetime = NumberRange.new(1.0, 1.6)
		pe.Speed = NumberRange.new(14, 24)
		pe.SpreadAngle = Vector2.new(70, 70)
		pe.Acceleration = Vector3.new(0, -26, 0)
		pe.Drag = 1.5
		pe.Rotation = NumberRange.new(0, 360)
		pe.RotSpeed = NumberRange.new(-300, 300)
		pe.Size = NumberSequence.new(0.35)
		pe.Color = ColorSequence.new(col)
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Parent = host
		pe:Emit(if reduced then 6 else 18)
	end
	task.delay(2, function()
		host:Destroy()
	end)
end

-- Relay Charge arc: a glowing orb travels on a curve between two screen
-- points, leaving a short sparkle trail, then calls onArrive.
function Fx.arc(fromScreen: Vector2, toScreen: Vector2, color: Color3, duration: number, onArrive: (() -> ())?)
	local orb = Kit.new("Frame", {
		Size = UDim2.fromOffset(30, 30),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		ZIndex = 45,
		Parent = overlay,
	})
	Kit.corner(15).Parent = orb
	Kit.stroke(3).Parent = orb
	local core = Kit.new("Frame", {
		Size = UDim2.fromScale(0.45, 0.45),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 46,
		Parent = orb,
	})
	Kit.corner(8).Parent = core
	local mid = (fromScreen + toScreen) / 2 + Vector2.new(0, -math.max(80, (toScreen - fromScreen).Magnitude * 0.35))
	local t0 = os.clock()
	local lastTrail = 0
	local dur = if reduced then duration * 0.6 else duration
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local u = math.clamp((os.clock() - t0) / dur, 0, 1)
		local e = u * u * (3 - 2 * u)
		local a = fromScreen:Lerp(mid, e)
		local b = mid:Lerp(toScreen, e)
		local p = a:Lerp(b, e)
		orb.Position = UDim2.fromOffset(p.X, p.Y)
		local s = 1 + math.sin(u * math.pi) * 0.5
		orb.Size = UDim2.fromOffset(30 * s, 30 * s)
		if not reduced and os.clock() - lastTrail > 0.03 then
			lastTrail = os.clock()
			local dot = Kit.new("Frame", {
				Size = UDim2.fromOffset(14, 14),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(p.X, p.Y),
				BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.4),
				ZIndex = 44,
				Parent = overlay,
			})
			Kit.corner(7).Parent = dot
			TweenService:Create(dot, TweenInfo.new(0.35), { Size = UDim2.fromOffset(2, 2), BackgroundTransparency = 1 }):Play()
			task.delay(0.4, function()
				dot:Destroy()
			end)
		end
		if u >= 1 then
			conn:Disconnect()
			orb:Destroy()
			if onArrive then
				onArrive()
			end
		end
	end)
end

function Fx.toScreen(pos: Vector3): Vector2
	local cam = workspace.CurrentCamera
	local v = cam:WorldToViewportPoint(pos)
	return Vector2.new(v.X, v.Y)
end

-- Short pause used for hit-stop on big hits (presentation only).
Fx.HIT_STOP_SMALL = 0.045
Fx.HIT_STOP_BIG = 0.09

return Fx
