--!strict
-- The UI's dark-fantasy ornament, built only from Studio GUI objects
-- (Frames, UIStroke, UIGradient, UICorner, rotation): no uploaded images.
--   ironFrame  bevelled iron band around a panel, square corner bosses with
--              violet gems (ornate) or gold rivets
--   gem        a faceted diamond gem
--   plaque     an iron title plate with diamond end caps and gems
--   seal       a round portrait seal: dark disc, iron ring, eight spikes
--   housing    a row of bevelled stones framing a bar
--   well       an inset item slot
--   glow       a coloured rim glow (selection / rarity / danger)
-- Every layer uses ZIndex 0 so a panel's own content (ZIndex >= 1) always
-- draws on top.

local Ornament = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Ornament.IRON_HI = rgb(168, 156, 146)
Ornament.IRON = rgb(86, 78, 76)
Ornament.IRON_LO = rgb(30, 27, 28)
Ornament.EDGE = rgb(8, 6, 9)
Ornament.GEM = rgb(176, 72, 255)
Ornament.GOLD = rgb(226, 172, 72)

local IRON_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Ornament.IRON_HI),
	ColorSequenceKeypoint.new(0.18, rgb(118, 108, 104)),
	ColorSequenceKeypoint.new(0.55, Ornament.IRON),
	ColorSequenceKeypoint.new(1, Ornament.IRON_LO),
})

local function new(className: string, props: { [string]: any }): any
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function ring(parent: Instance, inset: number, thickness: number, color: Color3, transparency: number?, gradient: ColorSequence?, rotation: number?, round: boolean?): Frame
	-- UIStroke draws outside its frame, so a frame inset by `inset` with a
	-- stroke of `thickness` paints a band from `inset` inside the host
	-- outward.
	local f = new("Frame", {
		Name = "Band",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -inset * 2, 1, -inset * 2),
		Position = UDim2.fromOffset(inset, inset),
		ZIndex = 0,
		Parent = parent,
	})
	if round then
		new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = f })
	end
	local s = new("UIStroke", {
		Thickness = thickness,
		Color = if gradient then Color3.new(1, 1, 1) else color,
		Transparency = transparency or 0,
		LineJoinMode = if round then Enum.LineJoinMode.Round else Enum.LineJoinMode.Miter,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = f,
	})
	if gradient then
		new("UIGradient", { Color = gradient, Rotation = rotation or 90, Parent = s })
	end
	return f
end

local function ironBlock(parent: Instance, size: UDim2, pos: UDim2, anchor: Vector2, rotation: number?, z: number?): Frame
	local f = new("Frame", {
		Name = "Boss",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = size,
		Position = pos,
		AnchorPoint = anchor,
		Rotation = rotation or 0,
		ZIndex = z or 0,
		Parent = parent,
	})
	new("UIGradient", { Color = IRON_SEQ, Rotation = 60, Parent = f })
	new("UIStroke", { Thickness = 1.5, Color = Ornament.EDGE, LineJoinMode = Enum.LineJoinMode.Miter, Parent = f })
	-- Inner bevel highlight.
	local hi = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), ZIndex = z or 0, Parent = f })
	new("UIStroke", { Thickness = 1, Color = Ornament.IRON_HI, Transparency = 0.45, LineJoinMode = Enum.LineJoinMode.Miter, Parent = hi })
	return f
end

-- A faceted diamond gem centred at `pos`.
function Ornament.gem(parent: Instance, size: number, pos: UDim2, color: Color3?, z: number?): Frame
	local col = color or Ornament.GEM
	local g = new("Frame", {
		Name = "Gem",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = 45,
		ZIndex = z or 0,
		Parent = parent,
	})
	local h, s, v = col:ToHSV()
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHSV(h, s * 0.35, 1)),
			ColorSequenceKeypoint.new(0.35, col),
			ColorSequenceKeypoint.new(0.5, Color3.fromHSV(h, s, v * 0.62)),
			ColorSequenceKeypoint.new(1, Color3.fromHSV(h, s, v * 0.35)),
		}),
		Rotation = 0,
		Parent = g,
	})
	new("UIStroke", { Thickness = math.max(1, size / 9), Color = Ornament.GOLD, LineJoinMode = Enum.LineJoinMode.Miter, Parent = g })
	-- Glint.
	local glint = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.15, BorderSizePixel = 0, Size = UDim2.fromScale(0.26, 0.26), Position = UDim2.fromScale(0.18, 0.18), ZIndex = z or 0, Parent = g })
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = glint })
	return g
end

-- Bevelled iron band around `host`. `t` is the band width in pixels.
-- `ornate` adds a groove and gem bosses; `corners = false` drops the bosses.
function Ornament.ironFrame(host: Instance, t: number, ornate: boolean?, corners: boolean?)
	local k = math.floor(t * 0.45 + 0.5)
	local holder = new("Folder", { Name = "Ornament", Parent = host })
	-- Layers paint in creation order: outline, band, groove, highlights.
	ring(host, k, t + 2, Ornament.EDGE)
	ring(host, k, t, Color3.new(1, 1, 1), 0, IRON_SEQ, 90)
	if ornate then
		ring(host, k - math.floor(t * 0.5), 1.5, Ornament.EDGE, 0.15)
		ring(host, k - math.floor(t * 0.5) - 1, 1, Ornament.IRON_HI, 0.55)
	end
	ring(host, k - t + 2, 1, Ornament.IRON_HI, 0.5)
	ring(host, k, 1, Ornament.IRON_HI, 0.35)
	ring(host, k + 1, 1.5, Ornament.EDGE, 0.25)
	if corners ~= false then
		local c = math.floor(t * (if ornate then 2.3 else 1.75) + 0.5)
		local centre = k - t / 2
		for _, corner in { Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) } do
			local px = UDim.new(corner.X, if corner.X == 0 then centre else -centre)
			local py = UDim.new(corner.Y, if corner.Y == 0 then centre else -centre)
			local pos = UDim2.new(px, py)
			ironBlock(host, UDim2.fromOffset(c, c), pos, Vector2.new(0.5, 0.5), 0, 0)
			if ornate then
				Ornament.gem(host, math.floor(c * 0.56), pos, Ornament.GEM, 0)
			else
				local r = new("Frame", { Name = "Rivet", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromOffset(math.floor(c * 0.36), math.floor(c * 0.36)), Position = pos, AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 0, Parent = host })
				new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = r })
				new("UIGradient", { Color = ColorSequence.new(rgb(255, 226, 150), rgb(120, 76, 24)), Rotation = 50, Parent = r })
				new("UIStroke", { Thickness = 1, Color = Ornament.EDGE, Parent = r })
			end
		end
	end
	local _ = holder
end

-- Interior shading: lighter at the top, a dark lip along the bottom.
function Ornament.interior(host: GuiObject)
	new("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 245)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(215, 205, 205)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 140, 145)),
		}),
		Rotation = 90,
		Parent = host,
	})
end

-- An iron title plate with diamond end caps. Returns the recessed face.
function Ornament.plaque(holder: Frame, h: number): Frame
	local cap = math.floor(h * 0.42)
	local plate = new("Frame", {
		Name = "Plate",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.new(1, -cap * 2, 1, -math.floor(h * 0.14)),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 0,
		Parent = holder,
	})
	new("UIGradient", { Color = IRON_SEQ, Rotation = 90, Parent = plate })
	new("UIStroke", { Thickness = 2, Color = Ornament.EDGE, LineJoinMode = Enum.LineJoinMode.Miter, Parent = plate })
	-- Diamond caps behind the plate's ends, with gems.
	for _, sx in { 0, 1 } do
		local pos = UDim2.new(sx, if sx == 0 then cap else -cap, 0.5, 0)
		ironBlock(holder, UDim2.fromOffset(math.floor(h * 0.62), math.floor(h * 0.62)), pos, Vector2.new(0.5, 0.5), 45, 0)
	end
	-- Recessed dark face for the title.
	local face = new("Frame", {
		Name = "Face",
		BackgroundColor3 = rgb(26, 21, 24),
		BorderSizePixel = 0,
		Size = UDim2.new(1, -cap * 2 - math.floor(h * 0.5), 1, -math.floor(h * 0.42)),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 0,
		Parent = holder,
	})
	new("UIGradient", { Color = ColorSequence.new(rgb(150, 140, 140), Color3.new(1, 1, 1)), Rotation = 90, Parent = face })
	new("UIStroke", { Thickness = 1.5, Color = Ornament.IRON_HI, Transparency = 0.45, LineJoinMode = Enum.LineJoinMode.Miter, Parent = face })
	for _, sx in { 0, 1 } do
		Ornament.gem(holder, math.floor(h * 0.28), UDim2.new(sx, if sx == 0 then cap else -cap, 0.5, 0), Ornament.GEM, 0)
	end
	return face
end

-- Round seal: dark disc, iron ring, eight spikes and four small gems.
-- `px` is the seal's diameter in pixels.
function Ornament.seal(host: Frame, px: number, discColor: Color3?)
	local th = math.max(4, math.floor(px * 0.085 + 0.5))
	-- Spikes first so the ring covers their roots.
	for i = 0, 7 do
		local a = i * math.pi / 4 - math.pi / 2
		local long = i % 2 == 0
		local r = 0.5 + (th / px) * (if long then 1.35 else 1.0)
		local s = math.floor(px * (if long then 0.19 else 0.13) + 0.5)
		ironBlock(host, UDim2.fromOffset(s, s), UDim2.fromScale(0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r), Vector2.new(0.5, 0.5), 45 + i * 45, 0)
	end
	local disc = new("Frame", {
		Name = "Disc",
		BackgroundColor3 = discColor or rgb(30, 22, 38),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 0,
		Parent = host,
	})
	new("UICorner", { CornerRadius = UDim.new(0.5, 0), Parent = disc })
	new("UIGradient", { Color = ColorSequence.new(rgb(200, 190, 215), rgb(90, 80, 100)), Rotation = 90, Parent = disc })
	ring(host, 0, th + 2, Ornament.EDGE, 0, nil, nil, true)
	ring(host, 0, th, Color3.new(1, 1, 1), 0, IRON_SEQ, 90, true)
	ring(host, -th + 2, 1, Ornament.IRON_HI, 0.45, nil, nil, true)
	ring(host, 1, 1.5, Ornament.EDGE, 0.1, nil, nil, true)
	for i = 0, 3 do
		local a = math.pi / 4 + i * math.pi / 2
		local r = 0.5 + (th / px) * 0.5
		Ornament.gem(host, math.max(6, math.floor(th * 1.15)), UDim2.fromScale(0.5 + math.cos(a) * r, 0.5 + math.sin(a) * r), Ornament.GEM, 0)
	end
end

-- Bevelled stones around a bar. `h` is the bar's height in pixels.
local stoneRng = Random.new(1027)
function Ornament.housing(bar: Frame, h: number, z: number)
	local band = math.clamp(math.floor(h * 0.3 + 0.5), 4, 9)
	local px = band + 2
	local holder = new("Frame", {
		Name = "Housing",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, px * 2, 1, band * 2),
		Position = UDim2.fromOffset(-px, -band),
		ZIndex = z,
		Parent = bar,
	})
	local function stone(size: UDim2, pos: UDim2)
		local tone = stoneRng:NextNumber(0.78, 1.08)
		local f = new("Frame", {
			Name = "Stone",
			BackgroundColor3 = Color3.fromRGB(150 * tone, 144 * tone, 152 * tone),
			BorderSizePixel = 0,
			Size = size,
			Position = pos,
			ZIndex = z,
			Parent = holder,
		})
		new("UICorner", { CornerRadius = UDim.new(0, 2), Parent = f })
		new("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
				ColorSequenceKeypoint.new(0.3, Color3.fromRGB(190, 186, 190)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(88, 84, 90)),
			}),
			Rotation = 90 + stoneRng:NextNumber(-12, 12),
			Parent = f,
		})
		new("UIStroke", { Thickness = 1, Color = Ornament.EDGE, Parent = f })
	end
	-- Rows above and below: random lengths that exactly fill the span.
	for _, row in { 0, 1 } do
		local cuts = { 0 }
		local x = 0
		while x < 1 do
			x = math.min(1, x + stoneRng:NextNumber(0.07, 0.15))
			if 1 - x < 0.05 then
				x = 1
			end
			table.insert(cuts, x)
		end
		for i = 1, #cuts - 1 do
			local a, b = cuts[i], cuts[i + 1]
			local jitter = stoneRng:NextInteger(0, 1)
			local y = if row == 0 then UDim.new(0, jitter) else UDim.new(1, -band - jitter + 1)
			stone(UDim2.new(UDim.new(b - a, -(b - a) * px * 2 - 2), UDim.new(0, band)), UDim2.new(UDim.new(a, px - a * px * 2 + 1), y))
		end
	end
	-- End blocks, full height.
	stone(UDim2.new(0, px, 1, 0), UDim2.fromOffset(0, 0))
	stone(UDim2.new(0, px, 1, 0), UDim2.new(1, -px, 0, 0))
end

-- Inset slot rim on `host` (the host keeps its own dark fill).
function Ornament.well(host: Frame)
	new("UIGradient", { Color = ColorSequence.new(rgb(150, 140, 140), Color3.new(1, 1, 1)), Rotation = 90, Parent = host })
	ring(host, 0, 4, Color3.new(1, 1, 1), 0, IRON_SEQ, 270)
	ring(host, -4, 1, Ornament.EDGE, 0)
	ring(host, 0, 1, Ornament.EDGE, 0.2)
	ring(host, 2, 1.5, rgb(0, 0, 0), 0.55)
end

-- A coloured rim glow. Returns the holder so callers can hide it.
function Ornament.glow(host: Instance, color: Color3, outset: number?): Frame
	local o = outset or 5
	local g = new("Frame", {
		Name = "Glow",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, o * 2, 1, o * 2),
		Position = UDim2.fromOffset(-o, -o),
		ZIndex = 0,
		Parent = host,
	})
	ring(g, -2, 5, color, 0.82)
	ring(g, 0, 3, color, 0.55)
	ring(g, 1, 1.5, color, 0.15)
	return g
end

return Ornament
