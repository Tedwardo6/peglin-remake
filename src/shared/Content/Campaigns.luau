--!strict
-- Campaigns chosen in the lobby. A campaign is a run of acts; each act is a
-- branching map (see Sim/MapGen) ending in a boss. One campaign for now.
-- All names are placeholders until the theme/title decision is made.

export type SceneId = "crypt" | "isle" | "spire"

export type Act = {
	id: string,
	name: string,
	subtitle: string,
	scene: SceneId,
	-- Ordinary enemies that can appear in fight and elite nodes of this act.
	pool: { string },
	-- The first node of the act (act 1 uses a gentle intro fight).
	opener: string?,
	boss: string,
	boards: { string },
	bossBoard: string,
	-- Presentation colours for the scene and board trim.
	palette: { deep: Color3, glow: Color3, accent: Color3, warm: Color3 },
}

export type Campaign = {
	id: string,
	name: string,
	blurb: string,
	acts: { Act },
	recommended: string,
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local LIST: { Campaign } = {
	{
		id = "abyss",
		name = "The Dreaming Abyss",
		blurb = "Descend through the Drowned Crypt, the Floating Isle and the Vortex Spire, and close the Vortex Eye.",
		recommended = "1–2 heroes",
		acts = {
			{
				id = "crypt",
				name = "The Drowned Crypt",
				subtitle = "Act I",
				scene = "crypt",
				pool = { "brute", "twin" },
				opener = "brute_intro",
				boss = "boss_crusher",
				boards = { "warmup", "lanes", "funnel" },
				bossBoard = "fortress",
				palette = { deep = c(6, 10, 34), glow = c(60, 120, 255), accent = c(120, 220, 255), warm = c(255, 140, 60) },
			},
			{
				id = "isle",
				name = "The Floating Isle",
				subtitle = "Act II",
				scene = "isle",
				pool = { "jammer", "grower" },
				boss = "boss_warden",
				boards = { "funnel", "bumpers", "zigzag" },
				bossBoard = "zigzag",
				palette = { deep = c(10, 6, 36), glow = c(120, 70, 255), accent = c(190, 140, 255), warm = c(255, 120, 40) },
			},
			{
				id = "spire",
				name = "The Vortex Spire",
				subtitle = "Act III",
				scene = "spire",
				pool = { "shell", "piercer" },
				boss = "boss_overseer",
				boards = { "lanes", "bumpers", "zigzag" },
				bossBoard = "fortress",
				palette = { deep = c(14, 4, 30), glow = c(200, 70, 255), accent = c(90, 255, 200), warm = c(255, 90, 60) },
			},
		},
	},
}

local byId: { [string]: Campaign } = {}
local order: { string } = {}
for _, camp in LIST do
	byId[camp.id] = camp
	table.insert(order, camp.id)
end

return {
	ById = byId,
	Order = order,
	DEFAULT = "abyss",
}
