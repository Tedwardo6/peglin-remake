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
local Skin = require(script.Parent.Skin)
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
		FontFace = if props.Heavy then Theme.FontHeavy elseif props.Title then (if props.Bold then Theme.FontTitleBold else Theme.FontTitle) elseif props.Bold then Theme.FontBold else Theme.Font,
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

-- Frame art ----------------------------------------------------------------

-- A 9-slice image layer behind a frame's children (ZIndex 0 sorts before
-- the default 1, so content always draws on top).
function Kit.sliced(parent: Instance, key: string, scale: number, outset: number, props: Props?): ImageLabel
	local p: Props = props or ({} :: Props)
	return Kit.new("ImageLabel", {
		Name = p.Name or key,
		BackgroundTransparency = 1,
		Image = Skin.id(key),
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = (Skin.Slice :: any)[key],
		SliceScale = scale,
		ImageColor3 = p.Color or Color3.new(1, 1, 1),
		ImageTransparency = p.Transparency or 0,
		Size = UDim2.new(1, outset * 2, 1, outset * 2),
		Position = UDim2.fromOffset(-outset, -outset),
		ZIndex = p.ZIndex or 0,
		Parent = parent,
	})
end

-- Fine grain and an inner shadow over a flat interior colour.
function Kit.texture(parent: Instance, grainAlpha: number?, vignetteAlpha: number?)
	if Skin.has("grain") then
		Kit.new("ImageLabel", {
			Name = "Grain",
			BackgroundTransparency = 1,
			Image = Skin.id("grain"),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(160, 160),
			ImageTransparency = 1 - (grainAlpha or 0.14),
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
			Parent = parent,
		})
	end
	if Skin.has("vignette") then
		Kit.sliced(parent, "vignette", 0.6, 0, { Name = "Shade", Transparency = 1 - (vignetteAlpha or 0.9) })
	end
end

-- A soft coloured glow around a frame (rarity / focus / danger).
function Kit.glow(parent: Instance, color: Color3, outset: number?, transparency: number?): ImageLabel?
	if not Skin.has("glow") then
		return nil
	end
	return Kit.sliced(parent, "glow", 0.5, outset or 6, { Name = "Glow", Color = color, Transparency = transparency or 0 })
end

-- Panels:
--   Style "iron"   (default) iron frame with corner rivets, dark interior
--   Style "ornate" heavier frame with gem bosses, for full screens/modals
--   Style "slot"   an inset item slot (Color = C.panelLight picks this)
--   Style "round"  a round dark seal in a spiked ring (Radius >= 26)
--   Style "chip"   a small coloured gem plate (Radius 12..20 on small panels)
-- `StrokeColor` adds a glow in that colour. The returned Frame's
-- BackgroundColor3 is the interior colour, so callers can still recolour it.
function Kit.panel(props: Props): Frame
	local style: string = props.Style or ""
	if style == "" then
		local r = props.Radius or 0
		if r >= 26 then
			style = "round"
		elseif r >= 12 then
			style = "chip"
		elseif props.Color == C.panelLight then
			style = "slot"
		else
			style = "iron"
		end
	end
	local skinned = Skin.has("frameIron")
	local f = Kit.new("Frame", {
		BackgroundColor3 = props.Color or C.panel,
		BackgroundTransparency = props.Transparency or 0,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
		Name = props.Name or "Panel",
		LayoutOrder = props.LayoutOrder or 0,
		Visible = if props.Visible == nil then true else props.Visible,
		Parent = props.Parent,
	})
	if not skinned then
		-- Plain fallback until the frame art is uploaded.
		Kit.corner(if style == "round" then (props.Radius or 30) else 4).Parent = f
		Kit.stroke(props.StrokeThickness or Theme.Stroke.ui, props.StrokeColor or C.ironLight).Parent = f
		return f
	end
	if props.StrokeColor then
		Kit.glow(f, props.StrokeColor, if style == "chip" then 4 else 8, 0.15)
	end
	if style == "round" then
		f.BackgroundTransparency = 1
		Kit.new("ImageLabel", { Name = "Disc", BackgroundTransparency = 1, Image = Skin.id("disc"), ImageColor3 = if props.Color then props.Color:Lerp(Color3.new(1, 1, 1), 0.25) else Color3.new(1, 1, 1), Size = UDim2.fromScale(1.05, 1.05), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 0, Parent = f })
		Kit.new("ImageLabel", { Name = "Ring", BackgroundTransparency = 1, Image = Skin.id("ring"), Size = UDim2.fromScale(1.32, 1.32), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 0, Parent = f })
	elseif style == "slot" then
		f.BackgroundTransparency = 1
		Kit.sliced(f, "slot", 0.5, 2, { Name = "Well", Color = if props.Color and props.Color ~= C.panelLight then props.Color:Lerp(Color3.new(1, 1, 1), 0.55) else nil })
	elseif style == "chip" then
		Kit.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 110, 120)), Parent = f })
		Kit.sliced(f, "frameIron", 0.22, 3, { Name = "Frame" })
	else
		local ornate = style == "ornate"
		Kit.texture(f)
		Kit.sliced(f, if ornate then "frameOrnate" else "frameIron", props.SliceScale or (if ornate then 0.5 else 0.42), if ornate then 8 else 5, { Name = "Frame" })
	end
	return f
end

-- A heading on an iron plaque with gem caps (the references' "CHARACTER").
function Kit.plaque(props: Props): Frame
	local h = props.Height or 54
	local holder = Kit.new("Frame", {
		Name = props.Name or "Plaque",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromOffset(360, h),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	})
	if Skin.has("plaque") then
		Kit.new("ImageLabel", {
			Name = "Plate",
			BackgroundTransparency = 1,
			Image = Skin.id("plaque"),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Skin.Slice.plaque,
			SliceScale = h / 128,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 0,
			Parent = holder,
		})
	end
	local label = Kit.label({
		Text = string.upper(props.Text or ""),
		Heavy = true,
		TextSize = props.TextSize or math.floor(h * 0.5),
		TextColor3 = props.TextColor3 or C.gold,
		Size = UDim2.new(1, -math.floor(h * 2.6), 1, -6),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		TextScaled = true,
		MaxTextSize = props.TextSize or math.floor(h * 0.5),
		ZIndex = 1,
		Parent = holder,
	})
	label.Name = "Title"
	return holder
end

-- A round portrait seal (disc + spiked ring); returns the frame and the
-- inner holder to put an image or viewport in.
function Kit.portrait(props: Props): (Frame, Frame)
	local f = Kit.panel({ Name = props.Name or "Portrait", Size = props.Size or UDim2.fromOffset(84, 84), Position = props.Position, AnchorPoint = props.AnchorPoint, Radius = 999, Style = "round", ZIndex = props.ZIndex, Parent = props.Parent })
	local inner = Kit.new("Frame", { Name = "Face", BackgroundTransparency = 1, Size = UDim2.fromScale(0.82, 0.82), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ClipsDescendants = true, ZIndex = 1, Parent = f })
	Kit.corner(999).Parent = inner
	return f, inner
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
	local skinned = Skin.has("frameIron")
	Kit.corner(if skinned then 3 else 7).Parent = body
	local bodyStroke = Kit.stroke(Theme.Stroke.ui, C.ink)
	bodyStroke.Parent = body
	local face: Frame = Kit.new("Frame", {
		Name = "Face",
		BackgroundColor3 = faceColor,
		Size = UDim2.new(1, 0, 1, -depth),
		Position = UDim2.fromOffset(0, 0),
		Parent = body,
	})
	Kit.corner(if skinned then 3 else 6).Parent = face
	-- Hover rim: a thin gold line inside the face edge.
	local rim = Kit.new("UIStroke", {
		Thickness = 1.5,
		Color = if skinned then C.gold else Color3.new(1, 1, 1),
		Transparency = if skinned then 1 else 0.55,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = face,
	})
	-- Inset shine along the top of the face.
	local shine: Frame = Kit.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = if skinned then 0.86 else 0.78,
		Size = UDim2.new(1, -10, 0.42, 0),
		Position = UDim2.fromOffset(5, 3),
		Parent = face,
	})
	Kit.corner(if skinned then 2 else 4).Parent = shine
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0, 1),
		Parent = shine,
	})
	Kit.new("UIGradient", {
		Rotation = 90,
		Color = if skinned then ColorSequence.new(Color3.fromRGB(235, 225, 215), Color3.fromRGB(95, 85, 85)) else ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 190)),
		Parent = face,
	})
	if skinned then
		-- Hammered texture on the face and an iron frame around the button.
		Kit.texture(face, 0.18, 0.55)
		local h = if props.Size then props.Size.Y.Offset else 64
		Kit.sliced(body, "frameIron", math.clamp(h / 230, 0.2, 0.36), 3, { Name = "Frame", ZIndex = 2 })
	end
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
	-- Selected: a cyan rarity glow around the whole button.
	local selectGlow = Kit.glow(content, C.cyan, 7, 0)
	if selectGlow then
		selectGlow.Visible = false
		selectGlow.ZIndex = 3
	end

	local function apply(t: number)
		local pressed = pressing and enabled
		local targetScale = if (hovering and enabled and not pressing) then Theme.Motion.hoverScale else 1
		if Kit.Settings.reducedMotion then
			targetScale = 1
		end
		Kit.tween(scale, t, { Scale = targetScale })
		Kit.tween(rim, t, { Transparency = if hovering and enabled then 0.1 else (if skinned then 1 else 0.55) })
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
			if selectGlow then
				selectGlow.Visible = selected
			else
				Kit.tween(selectRing, 0.12, { Thickness = if selected then 4 else 0 })
			end
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
	local skinned = Skin.has("trough")
	if skinned then
		root.BackgroundColor3 = Color3.fromRGB(10, 7, 11)
	else
		Kit.corner(props.Radius or 5).Parent = root
		Kit.stroke(1.5, props.RimColor or C.goldDeep).Parent = root
	end
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
	if not skinned then
		Kit.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 180)),
			Parent = fill,
		})
	end
	local overlay: Frame = Kit.new("Frame", {
		Name = "Overlay",
		BackgroundColor3 = props.OverlayColor or C.shield,
		BackgroundTransparency = 0.1,
		Size = UDim2.fromScale(0, 1),
		Parent = inner,
	})
	Kit.corner(math.max(2, (props.Radius or 5) - 2)).Parent = overlay
	if skinned then
		-- Glossy liquid textures inside the fill, and the stone housing on top.
		local function liquid(host: Frame, color: Color3)
			local key = if color == C.hull or color == C.enemyHp or color == C.red then "fillRed" elseif color == C.shield or color == C.blue then "fillBlue" else "fillWhite"
			Kit.new("ImageLabel", {
				Name = "Liquid",
				BackgroundTransparency = 1,
				Image = Skin.id(key),
				ImageColor3 = if key == "fillWhite" then color else Color3.new(1, 1, 1),
				ScaleType = Enum.ScaleType.Tile,
				TileSize = UDim2.new(0, 110, 1, 0),
				Size = UDim2.fromScale(1, 1),
				Parent = host,
			})
		end
		liquid(fill, props.Color or C.hull)
		liquid(overlay, props.OverlayColor or C.shield)
		overlay.BackgroundTransparency = 0
		ghost.BackgroundColor3 = Color3.fromRGB(255, 236, 214)
		local h = if props.Size then props.Size.Y.Offset else 26
		local s = math.clamp(h * 0.012, 0.22, 0.42)
		local px = math.floor(Skin.Band.trough.x * s + 0.5) - 3
		local py = math.floor(Skin.Band.trough.y * s + 0.5) - 2
		Kit.new("ImageLabel", {
			Name = "Housing",
			BackgroundTransparency = 1,
			Image = Skin.id("trough"),
			ScaleType = Enum.ScaleType.Slice,
			SliceCenter = Skin.Slice.trough,
			SliceScale = s,
			Size = UDim2.new(1, px * 2, 1, py * 2),
			Position = UDim2.fromOffset(-px, -py),
			ZIndex = 2,
			Parent = root,
		})
	end
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
