--!strict
-- Shared constants used by both server and client.
-- Every number here is a tuning hypothesis from the design plan (H), not a
-- measured result. Change values here, not inline in systems.

local Config = {
	GAME_NAME = "Cabinet (working title)",
	-- Bumped whenever a rule, board, or event-map change makes old logs incomparable.
	BUILD_VERSION = "0.1.0",
	EVENT_MAP_VERSION = 1,

	Sim = {
		STEP_HZ = 60, -- fixed simulation steps per second (plan §9 H)
		SUBSTEPS = 4, -- collision substeps per step
		MAX_FLIGHT_STEPS = 480, -- 8 s maximum flight (plan §2 H)
		GRAVITY = 125, -- board units / s^2
		LAUNCH_SPEED = 70, -- fixed launch strength (board units / s)
		MAX_SPEED = 120, -- bound on motion; keeps per-substep travel < peg radius
		WALL_RESTITUTION = 0.72,
		TANGENT_KEEP = 0.985, -- tangential velocity kept on contact
		STALL_SPEED = 2.5, -- below this for STALL_STEPS, apply a deterministic nudge
		STALL_STEPS = 30,
		AIM_STEPS = 1000, -- aim quantization (see Sim/Aim)
		AIM_MAX = 1880, -- clamp; keeps the launch below horizontal
	},

	Board = {
		WIDTH = 60,
		HEIGHT = 80,
		LAUNCH_X = 30,
		LAUNCH_Y = 3,
	},

	Combat = {
		START_HULL = 50,
		SHIELD_CAP = 30,
		THREAT_WARNING = 12, -- seconds the telegraph is visible before it lands
		CADENCE_MIN = 16,
		CADENCE_MAX = 20,
		ENCOUNTER_START_GRACE = 3, -- seconds after the intro before the clock runs
		DEFEATED_RETURN_HULL_FRACTION = 0.5, -- assumption: defeated players return at 50% next encounter
		BOSS_REPAIR_FRACTION = 0.4, -- baseline repair after bosses (plan §4)
		HP_SCALE_PER_EXTRA = 0.75, -- enemy HP = solo × (1 + 0.75 × (active − 1))
		MIN_LAUNCH_INTERVAL = 0.25, -- request-frequency floor (seconds)
	},

	Relay = {
		BONUS_POWER = 2,
		BONUS_HITS = 6,
	},

	Run = {
		LEGS = 3,
		ENCOUNTERS_PER_LEG = 3, -- two ordinary + one boss
		DRAFT_SECONDS = 20,
		RACK_SIZE = 3,
		REROLLS_PER_LEG = 1,
	},

	Party = {
		-- Four-player play is built but held behind this cap until the phone
		-- readability and load checks pass on a physical baseline phone.
		MAX_PARTY = 2,
		MAX_PARTY_TESTING = 4, -- reachable only through developer test mode
		SERVER_CAP = 8,
		SEAT_HOLD_SECONDS = 60,
		IDLE_WARN_SECONDS = 45,
		IDLE_OBSERVER_AFTER_WARN = 15,
	},

	Net = {
		MAX_MESSAGE_FIELDS = 12,
		MAX_REQUESTS_PER_SECOND = 12,
		STATE_BROADCAST_MIN_INTERVAL = 0.1,
	},

	Persistence = {
		PROFILE_VERSION = 2,
		STORE_NAME = "CabinetProfiles",
		-- Studio and test sessions use an isolated scope. Live data is never
		-- touched unless USE_LIVE_SCOPE is deliberately enabled for a release.
		TEST_SCOPE = "isolated-test-v1",
		LIVE_SCOPE = "live-v1",
		USE_LIVE_SCOPE = false,
		MAX_REWARD_IDS = 64,
		AUTOSAVE_SECONDS = 90,
	},
}

return Config
