--!strict
-- Wire contract between client and server.
--
-- Client -> server: one reliable RemoteEvent "Request" carrying
--   (kind: string, payload: table). The server validates shape, size, and
--   rate here before any game rule sees the message.
-- Server -> client: reliable RemoteEvent "Push" (state, results, events
--   with ids); UnreliableRemoteEvent "Cosmetic" for disposable visuals only
--   (teammate aim previews). Nothing consequential travels unreliably.

local Config = require(script.Parent.Parent.Config)
local Aim = require(script.Parent.Parent.Sim.Aim)

local Protocol = {}

Protocol.FOLDER = "CabinetNet"
Protocol.REQUEST = "Request"
Protocol.PUSH = "Push"
Protocol.COSMETIC = "Cosmetic"
Protocol.COSMETIC_UP = "CosmeticUp"

export type Schema = { [string]: "int" | "number" | "string" | "bool" | "strlist" | "aim" | "intOpt" }

-- Field schemas per request kind. Unknown kinds and unknown fields are rejected.
Protocol.Requests = {
	ready = { device = "string", reducedMotion = "bool" },
	startRun = { kit = "string", modifiers = "strlist", families = "strlist", privacy = "string", campaign = "string" },
	createParty = { kit = "string", campaign = "string", privacy = "string" },
	joinParty = { partyId = "string", kit = "string" },
	leaveParty = {},
	partyKit = { kit = "string" },
	partyReady = { ready = "bool" },
	partyCampaign = { campaign = "string" },
	startParty = { modifiers = "strlist", families = "strlist" },
	vote = { nodeId = "string" },
	rest = { choice = "string", slot = "intOpt" },
	continueRun = {},
	launch = { seq = "int", slot = "int", aim = "aim", boardRev = "int", predicted = "string" },
	activity = {},
	pick = { choice = "int", slot = "intOpt" },
	reroll = {},
	restart = {},
	rematch = {},
	leaveRun = {},
	joinRun = { runId = "string", kit = "string" },
	setRecipient = { uid = "int" },
	settings = { reducedMotion = "bool", music = "number", sfx = "number", skipSeen = "bool" },
	equipTrail = { id = "string" },
	devTest = { condition = "string" },
	seenCutscene = { id = "string" },
} :: { [string]: Schema }

local MAX_STRING = 64
local MAX_LIST = 8

local function checkField(kind: string, value: any): boolean
	if kind == "int" then
		return type(value) == "number" and value == value and value % 1 == 0 and math.abs(value) < 2 ^ 31
	elseif kind == "intOpt" then
		return value == nil or (type(value) == "number" and value == value and value % 1 == 0 and math.abs(value) < 2 ^ 31)
	elseif kind == "number" then
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	elseif kind == "string" then
		return type(value) == "string" and #value <= MAX_STRING
	elseif kind == "bool" then
		return type(value) == "boolean"
	elseif kind == "aim" then
		return Aim.isValid(value)
	elseif kind == "strlist" then
		if type(value) ~= "table" then
			return false
		end
		local n = 0
		for k, v in value do
			n += 1
			if type(k) ~= "number" or type(v) ~= "string" or #v > MAX_STRING then
				return false
			end
		end
		return n <= MAX_LIST
	end
	return false
end

-- Returns the validated payload (a fresh table with only known fields) or
-- nil and a reason. Missing optional fields stay nil.
function Protocol.validate(kind: any, payload: any): ({ [string]: any }?, string?)
	if type(kind) ~= "string" then
		return nil, "kind"
	end
	local schema = Protocol.Requests[kind]
	if schema == nil then
		return nil, "unknown_kind"
	end
	if payload == nil then
		payload = {}
	end
	if type(payload) ~= "table" then
		return nil, "payload"
	end
	local count = 0
	for key in payload do
		count += 1
		if type(key) ~= "string" or schema[key] == nil then
			return nil, "unknown_field"
		end
	end
	if count > Config.Net.MAX_MESSAGE_FIELDS then
		return nil, "too_large"
	end
	local out = {}
	for key, fieldKind in schema do
		local v = payload[key]
		if v == nil and fieldKind ~= "intOpt" then
			-- Optional booleans/numbers/lists may be omitted; required ints
			-- (seq, slot, choice...) and aim may not.
			if fieldKind == "int" or fieldKind == "aim" then
				return nil, "missing_" .. key
			end
		elseif not checkField(fieldKind, v) then
			return nil, "bad_" .. key
		else
			out[key] = v
		end
	end
	return out, nil
end

return Protocol
