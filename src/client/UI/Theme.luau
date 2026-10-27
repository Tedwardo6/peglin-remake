--!strict
-- Visual tokens for the game's UI and code-built scene. Screens and builders
-- read named roles from here; nothing hard-codes a colour elsewhere.
-- Direction (Theodore, Oct 27 2026): dark fantasy + psychedelic. Near-black
-- navy and electric blue/indigo dominate; violet glows on top; warm
-- orange/ember and gold are reserved for focal points (actions, damage,
-- loot). UI (second pass, Theodore's references): dark iron and stone frames
-- with violet gems over near-black warm interiors, stone-housed glossy bars,
-- gold serif headings on iron plaques (all built from GUI objects in
-- UI/Ornament; no uploaded images).

local Theme = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Theme.Color = {
	ink = rgb(6, 4, 10), -- outlines, text stroke
	inkSoft = rgb(18, 14, 22),
	panel = rgb(22, 18, 22), -- near-black warm interior inside iron frames
	panelLight = rgb(34, 29, 33), -- inset cards and slots
	panelEdge = rgb(96, 84, 210),
	rune = rgb(110, 150, 255), -- rim glow
	text = rgb(240, 233, 220),
	textDim = rgb(176, 166, 178),
	gold = rgb(240, 196, 96),
	iron = rgb(64, 58, 58),
	ironLight = rgb(120, 110, 104),
	goldDeep = rgb(160, 104, 28),
	ember = rgb(255, 128, 48),
	emberDeep = rgb(170, 60, 20),
	green = rgb(110, 240, 170),
	greenDeep = rgb(30, 130, 90),
	red = rgb(255, 72, 96),
	redDeep = rgb(150, 20, 48),
	blue = rgb(76, 132, 255),
	blueDeep = rgb(30, 50, 170),
	purple = rgb(168, 96, 255),
	purpleDeep = rgb(84, 34, 170),
	pink = rgb(255, 96, 214),
	cyan = rgb(96, 228, 255),
	grey = rgb(110, 108, 150),
	greyDeep = rgb(54, 52, 86),
	hull = rgb(232, 64, 104),
	shield = rgb(96, 196, 255),
	enemyHp = rgb(206, 38, 78),
	armor = rgb(176, 186, 220),
	threat = rgb(255, 120, 48),
}

-- Each seat in a party gets a colour used for its hero's cape trim,
-- nameplate, damage numbers, and contribution bars.
Theme.Slot = {
	rgb(255, 140, 60), -- ember
	rgb(80, 220, 255), -- cyan
	rgb(255, 92, 220), -- magenta
	rgb(170, 255, 110), -- lime
}

Theme.Font = Font.fromEnum(Enum.Font.Merriweather)
Theme.FontBold = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
Theme.FontTitle = Font.fromEnum(Enum.Font.GrenzeGotisch)
Theme.FontTitleBold = Font.new("rbxasset://fonts/families/GrenzeGotisch.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
-- Heavy serif caps for plaque headings and stat lines (the references' gold
-- "CHARACTER" / "STATS" lettering).
Theme.FontHeavy = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Heavy, Enum.FontStyle.Normal)

Theme.Stroke = {
	ui = 2, -- outline thickness for panels/buttons at normal scale
	text = 2,
}

-- Motion vocabulary (seconds). Reduced motion shortens or removes these.
Theme.Motion = {
	hover = 0.15,
	press = 0.08,
	release = 0.10,
	open = 0.28,
	close = 0.18,
	pop = 0.22,
	hoverScale = 1.03,
}

-- The iridescent rim used on panels and focused controls.
Theme.Iridescent = ColorSequence.new({
	ColorSequenceKeypoint.new(0, rgb(70, 120, 255)),
	ColorSequenceKeypoint.new(0.3, rgb(150, 90, 255)),
	ColorSequenceKeypoint.new(0.55, rgb(255, 90, 210)),
	ColorSequenceKeypoint.new(0.8, rgb(90, 230, 255)),
	ColorSequenceKeypoint.new(1, rgb(70, 120, 255)),
})

-- Darkens a colour for the lower "depth" of raised elements.
function Theme.deep(c: Color3, amount: number?): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.08), v * (amount or 0.55))
end

function Theme.light(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount or 0.35)
end

function Theme.slot(index: number): Color3
	return Theme.Slot[((index - 1) % #Theme.Slot) + 1]
end

return Theme
