--!strict
-- Event audio on Roblox's modular audio objects (handbook ch. 11):
--   AudioPlayer --Wire--> AudioFader (SFX / Music) --Wire--> AudioDeviceOutput
-- Each cue has a voice limit, a minimum retrigger gap, and a mix level.
-- Missing or failed audio never blocks input: a cue whose asset is not ready
-- simply stays silent. Asset provenance lives in docs/ASSETS.md.

local SoundService = game:GetService("SoundService")

local AudioCatalog = require(script.Parent.AudioCatalog)

type Voice = { player: AudioPlayer, busyUntil: number }
type Cue = { voices: { Voice }, lastAt: number, def: AudioCatalog.CueDef }

local Audio = {}

local root: Folder
local sfxFader: AudioFader
local musicFader: AudioFader
local output: AudioDeviceOutput
local cues: { [string]: Cue } = {}
local music: AudioPlayer? = nil
local sfxVolume = 0.9
local musicVolume = 0.6
local started = false

local function wire(source: Instance, target: Instance)
	local w = Instance.new("Wire")
	w.SourceInstance = source
	w.TargetInstance = target
	w.Parent = source
end

local function newPlayer(asset: string, fader: AudioFader, name: string): AudioPlayer
	local p = Instance.new("AudioPlayer")
	p.Name = name
	p.Asset = asset
	p.AutoLoad = true
	p.Parent = root
	wire(p, fader)
	return p
end

function Audio.init()
	if started then
		return
	end
	started = true
	root = Instance.new("Folder")
	root.Name = "CabinetAudio"
	root.Parent = SoundService
	output = Instance.new("AudioDeviceOutput")
	output.Parent = root
	sfxFader = Instance.new("AudioFader")
	sfxFader.Name = "SfxFader"
	sfxFader.Volume = sfxVolume
	sfxFader.Parent = root
	musicFader = Instance.new("AudioFader")
	musicFader.Name = "MusicFader"
	musicFader.Volume = musicVolume
	musicFader.Parent = root
	wire(sfxFader, output)
	wire(musicFader, output)

	for name, def in AudioCatalog.Cues do
		local voices: { Voice } = {}
		if def.asset ~= "" then
			for i = 1, def.voices do
				table.insert(voices, { player = newPlayer(def.asset, sfxFader, `{name}_{i}`), busyUntil = 0 })
			end
		end
		cues[name] = { voices = voices, lastAt = -1, def = def }
	end
end

export type PlayOpts = { pitch: number?, volume: number? }

function Audio.play(name: string, opts: PlayOpts?)
	local cue = cues[name]
	if cue == nil or #cue.voices == 0 then
		return
	end
	local now = os.clock()
	if now - cue.lastAt < cue.def.gap then
		return
	end
	-- Pick a free voice, or steal the one closest to finishing.
	local chosen: Voice? = nil
	local soonest = math.huge
	for _, v in cue.voices do
		if v.busyUntil <= now then
			chosen = v
			break
		end
		if v.busyUntil < soonest then
			soonest = v.busyUntil
			chosen = v
		end
	end
	if chosen == nil then
		return
	end
	local p = chosen.player
	if not p.IsReady then
		return
	end
	cue.lastAt = now
	local pitch = (if opts and opts.pitch then opts.pitch else 1) * cue.def.pitch
	-- Small natural variation so repeats don't sound mechanical.
	if cue.def.vary > 0 then
		pitch *= 1 + (math.random() * 2 - 1) * cue.def.vary
	end
	p.PlaybackSpeed = pitch
	p.Volume = cue.def.volume * (if opts and opts.volume then opts.volume else 1)
	if p.IsPlaying then
		p:Stop()
	end
	p.TimePosition = cue.def.start
	p:Play()
	local length = if p.TimeLength > 0 then p.TimeLength else 1
	chosen.busyUntil = now + (length - cue.def.start) / math.max(0.05, pitch)
end

function Audio.setVolumes(sfx: number, musicLevel: number)
	sfxVolume = sfx
	musicVolume = musicLevel
	if started then
		sfxFader.Volume = sfx
		musicFader.Volume = musicLevel
	end
end

function Audio.startMusic()
	if not started or AudioCatalog.Music == "" then
		return
	end
	if music == nil then
		local m = newPlayer(AudioCatalog.Music, musicFader, "Music")
		m.Looping = true
		m.Volume = AudioCatalog.MusicLevel
		music = m
	end
	local m = music :: AudioPlayer
	if not m.IsPlaying then
		m:Play()
	end
end

-- Loaded/total, for the Studio verification log.
function Audio.status(): (number, number, { string })
	local ready, total = 0, 0
	local missing = {}
	for name, cue in cues do
		total += 1
		local ok = #cue.voices > 0 and cue.voices[1].player.IsReady
		if ok then
			ready += 1
		else
			table.insert(missing, name)
		end
	end
	return ready, total, missing
end

-- Pentatonic steps so a rising combo sounds musical rather than shrill.
local STEPS = { 0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24 }
function Audio.comboPitch(combo: number): number
	local i = math.clamp(combo, 1, #STEPS)
	local extra = math.max(0, combo - #STEPS) * 0.5
	return 2 ^ ((STEPS[i] + extra) / 12)
end

return Audio
