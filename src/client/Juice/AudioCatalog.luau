--!strict
-- Every sound the game plays, with mix level and concurrency. Assets are
-- Roblox-provided client sounds (rbxasset://sounds/...) shipped with every
-- Roblox client, so they need no upload, licence, or permission grant.
-- Provenance and the Studio load check are recorded in docs/ASSETS.md.
-- To swap in a custom sound later, change `asset` here only.

export type CueDef = {
	asset: string,
	volume: number,
	pitch: number, -- base playback speed
	vary: number, -- ± random pitch variation
	voices: number, -- simultaneous instances
	gap: number, -- minimum seconds between triggers
	start: number, -- trim: start offset in seconds
}

local function cue(asset: string, volume: number, pitch: number, vary: number, voices: number, gap: number, start: number?): CueDef
	return { asset = asset, volume = volume, pitch = pitch, vary = vary, voices = voices, gap = gap, start = start or 0 }
end

local S = "rbxasset://sounds/"

local Cues: { [string]: CueDef } = {
	-- Board
	peg = cue(S .. "electronicpingshort.wav", 0.45, 1.0, 0, 6, 0.012),
	pegGuard = cue(S .. "electronicpingshort.wav", 0.5, 0.62, 0.02, 3, 0.03),
	pegRelay = cue(S .. "electronicpingshort.wav", 0.55, 1.5, 0, 2, 0.05),
	pegPower = cue(S .. "electronicpingshort.wav", 0.6, 0.8, 0, 2, 0.05),
	pegMend = cue(S .. "electronicpingshort.wav", 0.45, 1.25, 0.02, 2, 0.05),
	burst = cue(S .. "Rocket shot.wav", 0.5, 1.6, 0.05, 2, 0.06),
	spring = cue(S .. "action_jump.mp3", 0.55, 1.3, 0.05, 2, 0.05),
	wall = cue(S .. "clickfast.wav", 0.4, 0.7, 0.08, 3, 0.03),
	launch = cue(S .. "Rocket shot.wav", 0.45, 1.25, 0.03, 2, 0.1),
	drain = cue(S .. "swoosh.wav", 0.35, 0.7, 0.03, 2, 0.1),
	aimTick = cue(S .. "clickfast.wav", 0.12, 1.8, 0.05, 2, 0.06),
	-- Monster and threats
	flinch = cue(S .. "collide.wav", 0.35, 1.1, 0.1, 3, 0.06),
	bigHit = cue(S .. "Rocket shot.wav", 0.55, 0.75, 0.04, 2, 0.08),
	telegraph = cue(S .. "HalloweenThunder.wav", 0.35, 1.4, 0, 1, 0.5),
	countdown = cue(S .. "clickfast.wav", 0.45, 1.0, 0, 2, 0.3),
	threatHit = cue(S .. "HalloweenThunder.wav", 0.6, 1.9, 0.03, 2, 0.2),
	shieldBlock = cue(S .. "unsheath.wav", 0.55, 1.1, 0.05, 2, 0.1),
	monsterDeath = cue(S .. "glassbreak.wav", 0.6, 0.8, 0, 1, 0.5),
	armorUp = cue(S .. "unsheath.wav", 0.5, 0.7, 0, 1, 0.3),
	-- Relay
	chargeSend = cue(S .. "swoosh.wav", 0.6, 1.5, 0, 2, 0.1),
	chargeArrive = cue(S .. "electronicpingshort.wav", 0.6, 2.0, 0, 2, 0.1),
	chargeUse = cue(S .. "Rocket whoosh 01.wav", 0.5, 1.4, 0, 2, 0.1),
	-- UI
	click = cue(S .. "clickfast.wav", 0.5, 1.0, 0.03, 3, 0.04),
	hover = cue(S .. "clickfast.wav", 0.12, 1.6, 0.03, 2, 0.05),
	open = cue(S .. "swoosh.wav", 0.3, 1.3, 0.03, 2, 0.1),
	reward = cue(S .. "electronicpingshort.wav", 0.6, 0.9, 0, 2, 0.1),
	victory = cue(S .. "electronicpingshort.wav", 0.6, 0.67, 0, 1, 0.5),
	defeat = cue(S .. "HalloweenGhost.wav", 0.45, 1.0, 0, 1, 0.5),
	reject = cue(S .. "clickfast.wav", 0.4, 0.5, 0, 1, 0.15),
	whoosh = cue(S .. "swoosh.wav", 0.4, 1.0, 0.05, 2, 0.1),
}

return {
	Cues = Cues,
	Music = "", -- no music track selected yet (see docs/ASSETS.md)
	MusicLevel = 0.5,
}
