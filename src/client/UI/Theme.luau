--!strict
-- Visual tokens for the game's UI and code-built scene. Screens and builders
-- read named roles from here; nothing hard-codes a colour elsewhere.
-- Style: chunky, bright toy-machine look — flat colour regions, thick
-- midnight-navy outlines (#080f38), Raised Buttons from the Seawind handbook
-- (Brainrot UI recipe: 1.025× hover, face-depression press, Quad Out).

local Theme = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Theme.Color = {
	ink = rgb(8, 15, 56), -- outlines, text stroke
	inkSoft = rgb(28, 36, 92),
	panel = rgb(20, 27, 77),
	panelLight = rgb(38, 50, 120),
	panelEdge = rgb(70, 90, 190),
	text = rgb(255, 255, 255),
	textDim = rgb(184, 196, 240),
	gold = rgb(255, 210, 63),
	goldDeep = rgb(214, 140, 18),
	green = rgb(88, 226, 120),
	greenDeep = rgb(32, 150, 72),
	red = rgb(255, 84, 92),
	redDeep = rgb(176, 30, 52),
	blue = rgb(72, 160, 255),
	blueDeep = rgb(28, 82, 200),
	purple = rgb(190, 100, 255),
	purpleDeep = rgb(116, 40, 200),
	pink = rgb(255, 120, 186),
	cyan = rgb(100, 230, 255),
	grey = rgb(150, 156, 184),
	greyDeep = rgb(88, 94, 128),
	hull = rgb(88, 226, 120),
	shield = rgb(96, 180, 255),
	enemyHp = rgb(255, 84, 92),
	armor = rgb(176, 190, 214),
	threat = rgb(255, 120, 60),
}

Theme.Font = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
Theme.FontBold = Font.new("rbxasset://fonts/families/FredokaOne.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

Theme.Stroke = {
	ui = 3, -- outline thickness for panels/buttons at normal scale
	text = 2.5,
}

-- Motion vocabulary (seconds). Reduced motion shortens or removes these.
Theme.Motion = {
	hover = 0.15,
	press = 0.08,
	release = 0.10,
	open = 0.28,
	close = 0.18,
	pop = 0.22,
	hoverScale = 1.025,
}

-- Darkens a colour for the lower "depth" of raised elements.
function Theme.deep(c: Color3, amount: number?): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.08), v * (amount or 0.68))
end

function Theme.light(c: Color3, amount: number?): Color3
	return c:Lerp(Color3.new(1, 1, 1), amount or 0.35)
end

return Theme
