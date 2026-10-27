--!strict
-- UI component kit. One shared implementation per component so every
-- screen gets the same states, motion, and sound (handbook ch. 9 component
-- and audio contract):
--   * input area stays fixed while visual layers animate
--   * press feedback is separate from activation; drags/cancels never fire
--   * one click sound at the start of an enabled press
--   * hover is optional decoration; touch works without it

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent.Theme)
local Audio = require(script.Parent.Parent.Juice.Audio)

local C = Theme.Color

local Kit = {}

Kit.Settings = { reducedMotion = false }

-- Iridescent rims: every registered gradient drifts together from one
-- per-frame update (cheap; stops when its owner is destroyed).
local shimmering: { [UIGradient]: number } = {}
local shimmerT = 0
RunService.RenderStepped:Connect(function(dt)
	if Kit.Settings.reducedMotion then
		return
	end
	shimmerT += dt
	for g, speed in shimmering do
		if g.Parent == nil then
			shimmering[g] = nil
		else
			g.Rotation = (shimmerT * speed) % 360
		end
	end
end)

function Kit.shimmer(parent: Instance, speed: number?, colors: ColorSequence?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = colors or Theme.Iridescent
	g.Rotation = 0
	g.Parent = parent
	shimmering[g] = speed or 40
	return g
end

export type Props = { [string]: any }

function Kit.new(className: string, props: Props, children: { Instance }?): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Kit.corner(radius: number?): UICorner
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function Kit.stroke(thickness: number?, color: Color3?, transparency: number?): UIStroke
	return Kit.new("UIStroke", {
		Thickness = thickness or Theme.Stroke.ui,
		Color = color or C.ink,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Kit.textStroke(thickness: number?): UIStroke
	return Kit.new("UIStroke", {
		Thickness = thickness or Theme.Stroke.text,
		Color = C.ink,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
	})
end

function Kit.tween(inst: Instance, time: number, props: Props, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	if Kit.Settings.reducedMotion then
		time = math.min(time, 0.06)
	end
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function Kit.label(props: Props): TextLabel
	local size = props.TextSize or 22
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = if props.Title then (if props.Bold then Theme.FontTitleBold else Theme.FontTitle) elseif props.Bold then Theme.FontBold else Theme.Font,
		TextColor3 = props.TextColor3 or C.text,
		TextSize = size,
		TextScaled = props.TextScaled or false,
		Text = props.Text or "",
		Size = props.Size or UDim2.new(1, 0, 0, size + 6),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		TextWrapped = props.TextWrapped or false,
		RichText = props.RichText or false,
		ZIndex = props.ZIndex or 1,
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "Label",
		Parent = props.Parent,
	})
	if props.Stroke ~= false then
		Kit.textStroke(props.StrokeThickness or math.max(1.5, size / 10)).Parent = label
	end
	if props.MaxTextSize then
		Kit.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize, MinTextSize = props.MinTextSize or 10, Parent = label })
	end
	return label
end

function Kit.panel(props: Props): Frame
	local f = Kit.new("Frame", {
		BackgroundColor3 = props.Color or C.panel,
		BackgroundTransparency = props.Transparency or 0,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
		Name = props.Name or "Panel",
		LayoutOrder = props.LayoutOrder or 0,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	Kit.corner(props.Radius or 8).Parent = f
	local rim = Kit.stroke(props.StrokeThickness or Theme.Stroke.ui, if props.StrokeColor then props.StrokeColor else Color3.new(1, 1, 1))
	rim.Parent = f
	if props.StrokeColor == nil then
		-- Iridescent rune rim.
		Kit.shimmer(rim, props.ShimmerSpeed or 30)
	end
	if props.Gradient ~= false then
		Kit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromRGB(235, 235, 255), Color3.fromRGB(120, 120, 170)),
			Parent = f,
		})
	end
	return f
end

-- Raised Button -----------------------------------------------------------

export type Button = {
	root: TextButton,
	setEnabled: (enabled: boolean) -> (),
	setText: (text: string) -> (),
	setFace: (color: Color3) -> (),
	setSelected: (selected: boolean) -> (),
	content: Frame,
	face: Frame,
	label: TextLabel,
	destroy: () -> (),
}

export type ButtonProps = {
	Text: string?,
	Icon: string?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Face: Color3?,
	TextSize: number?,
	Depth: number?,
	Parent: Instance?,
	LayoutOrder: number?,
	ZIndex: number?,
	Sound: string?,
	OnActivated: (() -> ())?,
	Name: string?,
}

function Kit.button(props: ButtonProps): Button
	local faceColor = props.Face or C.ember
	local depth = props.Depth or 6
	local travel = math.floor(depth * 0.6 + 0.5)
	local enabled = true
	local hovering = false
	local pressing = false
	local selected = false

	local root: TextButton = Kit.new("TextButton", {
		Name = props.Name or "Button",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(180, 64),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Selectable = true,
	})
	-- Visual layers live in `content` so scaling never moves the input area.
	local content: Frame = Kit.new("Frame", { Name = "Content", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = root })
	local scale: UIScale = Kit.new("UIScale", { Scale = 1, Parent = content })
	local body: Frame = Kit.new("Frame", {
		Name = "Body",
		BackgroundColor3 = Theme.deep(faceColor),
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, 0),
		Parent = content,
	})
	Kit.corner(7).Parent = body
	local bodyStroke = Kit.stroke(Theme.Stroke.ui, C.ink)
	bodyStroke.Parent = body
	local face: Frame = Kit.new("Frame", {
		Name = "Face",
		BackgroundColor3 = faceColor,
		Size = UDim2.new(1, 0, 1, -depth),
		Position = UDim2.fromOffset(0, 0),
		Parent = body,
	})
	Kit.corner(6).Parent = face
	-- Engraved rim: a thin bright line inside the face edge.
	local rim = Kit.new("UIStroke", {
		Thickness = 1.5,
		Color = Color3.new(1, 1, 1),
		Transparency = 0.55,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = face,
	})
	-- Inset shine along the top of the face.
	local shine: Frame = Kit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.78,
		Size = UDim2.new(1, -10, 0.42, 0),
		Position = UDim2.fromOffset(5, 3),
		Parent = face,
	})
	Kit.corner(4).Parent = shine
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0, 1),
		Parent = shine,
	})
	Kit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 190)),
		Parent = face,
	})
	local text = props.Text or ""
	if props.Icon then
		text = props.Icon .. "  " .. text
	end
	local label = Kit.label({
		Text = text,
		TextSize = props.TextSize or 26,
		Size = UDim2.new(1, -12, 1, -4),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextScaled = true,
		MaxTextSize = props.TextSize or 26,
		Parent = face,
	})
	local selectRing: UIStroke = Kit.new("UIStroke", {
		Thickness = 0,
		Color = Color3.new(1, 1, 1),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = face,
	})

	local function apply(t: number)
		local pressed = pressing and enabled
		local targetScale = if (hovering and enabled and not pressing) then Theme.Motion.hoverScale else 1
		if Kit.Settings.reducedMotion then
			targetScale = 1
		end
		Kit.tween(scale, t, { Scale = targetScale })
		Kit.tween(rim, t, { Transparency = if hovering and enabled then 0.1 else 0.55 })
		-- Face moves down; the silhouette top follows; the bottom edge stays put.
		local off = if pressed then travel else 0
		Kit.tween(body, t, { Position = UDim2.fromOffset(0, off), Size = UDim2.new(1, 0, 1, -off) })
		Kit.tween(face, t, { Size = UDim2.new(1, 0, 1, -(depth - off)) })
	end

	local function setVisualEnabled()
		local fc = if enabled then faceColor else C.grey
		face.BackgroundColor3 = fc
		body.BackgroundColor3 = Theme.deep(fc)
		label.TextTransparency = if enabled then 0 else 0.25
	end

	local lastActivate = 0
	root.MouseEnter:Connect(function()
		hovering = true
		if enabled then
			apply(Theme.Motion.hover)
		end
	end)
	root.MouseLeave:Connect(function()
		hovering = false
		pressing = false
		apply(Theme.Motion.hover)
	end)
	root.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or (t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.ButtonA) then
			pressing = true
			if enabled then
				Audio.play(props.Sound or "click")
			end
			apply(Theme.Motion.press)
		end
	end)
	root.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch or t == Enum.UserInputType.Gamepad1 then
			pressing = false
			apply(Theme.Motion.release)
		end
	end)
	root.SelectionGained:Connect(function()
		hovering = true
		apply(Theme.Motion.hover)
	end)
	root.SelectionLost:Connect(function()
		hovering = false
		pressing = false
		apply(Theme.Motion.hover)
	end)
	root.Activated:Connect(function()
		local t = os.clock()
		if not enabled or t - lastActivate < 0.18 then
			if not enabled then
				Audio.play("reject")
			end
			return
		end
		lastActivate = t
		if props.OnActivated then
			(props.OnActivated :: () -> ())()
		end
	end)
	-- Lost window focus clears stale held states.
	local focusConn = UserInputService.WindowFocusReleased:Connect(function()
		pressing = false
		hovering = false
		apply(0.05)
	end)

	if props.Parent then
		root.Parent = props.Parent
	end

	local button: Button = {
		root = root,
		content = content,
		face = face,
		label = label,
		setEnabled = function(on: boolean)
			if on == enabled then
				return
			end
			enabled = on
			if not on then
				pressing = false
			end
			setVisualEnabled()
			apply(0.1)
		end,
		setText = function(t: string)
			label.Text = t
		end,
		setFace = function(c: Color3)
			faceColor = c
			setVisualEnabled()
		end,
		setSelected = function(on: boolean)
			selected = on
			Kit.tween(selectRing, 0.12, { Thickness = if selected then 4 else 0 })
		end,
		destroy = function()
			focusConn:Disconnect()
			root:Destroy()
		end,
	}
	return button
end

-- Bar with outline, animated fill, and a trailing "ghost" that shows recent loss.
export type Bar = {
	root: Frame,
	set: (value: number, max: number, instant: boolean?) -> (),
	setOverlay: (value: number, max: number) -> (),
	setText: (text: string) -> (),
	fill: Frame,
}

function Kit.bar(props: Props): Bar
	local root: Frame = Kit.new("Frame", {
		Name = props.Name or "Bar",
		BackgroundColor3 = Color3.fromRGB(6, 6, 18),
		Size = props.Size or UDim2.fromOffset(220, 26),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	Kit.corner(props.Radius or 5).Parent = root
	Kit.stroke(1.5, props.RimColor or C.goldDeep).Parent = root
	local inner: Frame = Kit.new("Frame", {
		Name = "Inner",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -4, 1, -4),
		Position = UDim2.fromOffset(2, 2),
		ClipsDescendants = true,
		Parent = root,
	})
	Kit.corner(math.max(2, (props.Radius or 5) - 2)).Parent = inner
	local ghost: Frame = Kit.new("Frame", {
		Name = "Ghost",
		BackgroundColor3 = Color3.fromRGB(255, 230, 200),
		Size = UDim2.fromScale(1, 1),
		Parent = inner,
	})
	Kit.corner(math.max(2, (props.Radius or 5) - 2)).Parent = ghost
	local fill: Frame = Kit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = props.Color or C.hull,
		Size = UDim2.fromScale(1, 1),
		Parent = inner,
	})
	Kit.corner(math.max(2, (props.Radius or 5) - 2)).Parent = fill
	Kit.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 180)),
		Parent = fill,
	})
	local overlay: Frame = Kit.new("Frame", {
		Name = "Overlay",
		BackgroundColor3 = props.OverlayColor or C.shield,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromScale(0, 1),
		Parent = inner,
	})
	Kit.corner(math.max(2, (props.Radius or 5) - 2)).Parent = overlay
	local text = Kit.label({
		Text = "",
		TextSize = props.TextSize or 18,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Parent = root,
	})
	local lastFrac = 1
	local lastOverlay = 0
	local bar: Bar = {
		root = root,
		fill = fill,
		set = function(value: number, max: number, instant: boolean?)
			local frac = if max > 0 then math.clamp(value / max, 0, 1) else 0
			if frac == lastFrac and not instant then
				return
			end
			if instant then
				fill.Size = UDim2.fromScale(frac, 1)
				ghost.Size = UDim2.fromScale(frac, 1)
			else
				Kit.tween(fill, 0.18, { Size = UDim2.fromScale(frac, 1) })
				if frac < lastFrac then
					-- The ghost lingers, then drains: loss reads clearly.
					task.delay(0.35, function()
						Kit.tween(ghost, 0.45, { Size = UDim2.fromScale(frac, 1) })
					end)
				else
					ghost.Size = UDim2.fromScale(frac, 1)
				end
			end
			lastFrac = frac
		end,
		setOverlay = function(value: number, max: number)
			local frac = if max > 0 then math.clamp(value / max, 0, 1) else 0
			if frac == lastOverlay then
				return
			end
			lastOverlay = frac
			Kit.tween(overlay, 0.18, { Size = UDim2.fromScale(frac, 1) })
		end,
		setText = function(t: string)
			if text.Text ~= t then
				text.Text = t
			end
		end,
	}
	return bar
end

-- Pops a GUI object in: scale from 0.6 with a slight overshoot.
function Kit.popIn(gui: GuiObject, delayTime: number?)
	local s = gui:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = gui })
	if Kit.Settings.reducedMotion then
		s.Scale = 1
		return
	end
	s.Scale = 0.6
	task.delay(delayTime or 0, function()
		Kit.tween(s, Theme.Motion.pop, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
end

function Kit.bounce(gui: GuiObject, amount: number?)
	if Kit.Settings.reducedMotion then
		return
	end
	local s = gui:FindFirstChildOfClass("UIScale") or Kit.new("UIScale", { Parent = gui })
	s.Scale = 1 + (amount or 0.15)
	Kit.tween(s, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
end

return Kit
