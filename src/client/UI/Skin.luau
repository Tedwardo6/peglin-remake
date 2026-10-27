--!strict
-- Frame art for the UI kit: iron and stone frames, the title plaque, the
-- round portrait ring, inset item slots, the stone bar housing and its
-- glossy fills. The images are our own, drawn by tools/make_ui_art.py
-- (sources in art/ui/) and uploaded to Roblox under Theodore's account;
-- see docs/ASSETS.md. Slice rectangles are in source pixels and must match
-- the generator.
--
-- An empty id means "not uploaded yet": the kit then falls back to plain
-- coloured frames, so nothing breaks before the art arrives.

local Skin = {}

Skin.Image = {
	frameIron = "",
	frameOrnate = "",
	slot = "",
	glow = "",
	vignette = "",
	grain = "",
	plaque = "",
	ring = "",
	disc = "",
	trough = "",
	fillRed = "",
	fillBlue = "",
	fillWhite = "",
}

Skin.Slice = {
	frameIron = Rect.new(60, 60, 196, 196),
	frameOrnate = Rect.new(80, 80, 176, 176),
	slot = Rect.new(24, 24, 104, 104),
	glow = Rect.new(32, 32, 96, 96),
	vignette = Rect.new(48, 48, 80, 80),
	plaque = Rect.new(150, 12, 874, 116),
	trough = Rect.new(40, 30, 984, 66),
}

-- Source sizes (px) of the band each frame draws, used to keep content clear.
Skin.Band = {
	frameIron = 30,
	frameOrnate = 44,
	trough = { x = 40, y = 30 },
}

function Skin.has(key: string): boolean
	local id = (Skin.Image :: any)[key]
	return type(id) == "string" and id ~= ""
end

function Skin.id(key: string): string
	return (Skin.Image :: any)[key] or ""
end

return Skin
