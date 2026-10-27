--!strict
-- Player profile schema, defaults, and migrations. Pure.
-- Bump Config.Persistence.PROFILE_VERSION and add a migration step whenever
-- the shape changes. Migrations must be repeatable and keep existing progress.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

export type Checkpoint = {
	runSeed: string,
	kit: string,
	completed: number, -- last confirmed completed encounter index
	rack: { string },
	components: { string },
	ballLevels: { [string]: number },
	hull: number,
	maxHull: number,
	modifiers: { string },
	at: number,
}

export type Profile = {
	version: number,
	settings: { reducedMotion: boolean, music: number, sfx: number, skipSeen: boolean },
	seen: { [string]: boolean }, -- cutscenes and tips already shown
	unlocked: { [string]: boolean }, -- cosmetics
	equippedTrail: string,
	milestones: { [string]: boolean },
	stats: {
		runsStarted: number,
		runsFinished: number,
		encountersWon: number,
		bossesDefeated: number,
		chargesSent: number,
		chargesUsedByOthers: number,
		biggestShot: number,
		shots: number,
	},
	familyPool: { [string]: boolean },
	codex: { [string]: boolean }, -- items seen (knowledge unlocks)
	checkpoint: Checkpoint?,
	rewardIds: { string }, -- repeat-safe grants (bounded)
	firstJoin: number,
}

local Schema = {}

function Schema.default(now: number): Profile
	return {
		version = Config.Persistence.PROFILE_VERSION,
		settings = { reducedMotion = false, music = 0.6, sfx = 0.9, skipSeen = true },
		seen = {},
		unlocked = { default = true },
		equippedTrail = "default",
		milestones = {},
		stats = {
			runsStarted = 0,
			runsFinished = 0,
			encountersWon = 0,
			bossesDefeated = 0,
			chargesSent = 0,
			chargesUsedByOthers = 0,
			biggestShot = 0,
			shots = 0,
		},
		familyPool = { ricochet = true, relay = true, guard = true, wild = true },
		codex = {},
		checkpoint = nil,
		rewardIds = {},
		firstJoin = now,
	}
end

-- v1 (pre-release draft) stored `trail` and had no family pool.
local MIGRATIONS: { [number]: (data: { [string]: any }) -> () } = {
	[1] = function(data)
		data.equippedTrail = data.trail or "default"
		data.trail = nil
		data.familyPool = data.familyPool or { ricochet = true, relay = true, guard = true, wild = true }
		data.version = 2
	end,
}

-- Fills missing fields from defaults without overwriting stored values.
local function fill(target: { [string]: any }, defaults: { [string]: any })
	for k, v in defaults do
		if target[k] == nil then
			if type(v) == "table" then
				target[k] = table.clone(v)
			else
				target[k] = v
			end
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil and k ~= "rewardIds" then
			fill(target[k], v)
		end
	end
end

-- Upgrades stored data to the current version. Returns nil if the data is
-- from a newer version (never downgrade or overwrite newer progress).
function Schema.migrate(data: { [string]: any }, now: number): (Profile?, string?)
	if type(data) ~= "table" then
		return nil, "corrupt"
	end
	local v = data.version
	if type(v) ~= "number" then
		v = 1
		data.version = 1
	end
	if v > Config.Persistence.PROFILE_VERSION then
		return nil, "newer_version"
	end
	while (data.version :: number) < Config.Persistence.PROFILE_VERSION do
		local step = MIGRATIONS[data.version :: number]
		if step == nil then
			return nil, "no_migration"
		end
		step(data)
	end
	fill(data, Schema.default(now) :: any)
	return data :: any, nil
end

-- Repeat-safe grant: runs `apply` only once per reward id.
function Schema.grantOnce(p: Profile, rewardId: string, apply: (Profile) -> ()): boolean
	for _, id in p.rewardIds do
		if id == rewardId then
			return false
		end
	end
	apply(p)
	table.insert(p.rewardIds, rewardId)
	while #p.rewardIds > Config.Persistence.MAX_REWARD_IDS do
		table.remove(p.rewardIds, 1)
	end
	return true
end

return Schema
