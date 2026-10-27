--!strict
-- Session-locked profile storage with ordered, bounded retries.
--
-- * load: UpdateAsync claims a session lock (job id + timestamp). A live
--   lock from another server is retried, then taken over once stale.
-- * a failed load NEVER becomes a fresh default that later overwrites real
--   progress: the session plays with in-memory defaults and saving is off.
-- * saves are serialized per player (ordered) and check lock ownership; if
--   the lock was lost, writes stop.
-- * backend, clock, wait, and jitter are injected, so the same code is
--   tested headlessly against a failure-injecting in-memory backend.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Schema = require(script.Parent.Schema)

export type Backend = {
	update: (self: Backend, key: string, fn: (old: any) -> any) -> any, -- may error
}

export type Deps = {
	backend: Backend,
	jobId: string,
	clock: () -> number, -- unix seconds
	wait: (seconds: number) -> (),
	jitter: () -> number, -- 0..1
	log: (msg: string) -> (),
}

export type Session = {
	uid: number,
	key: string,
	profile: Schema.Profile,
	canSave: boolean,
	status: "loaded" | "failed" | "released" | "lost",
	reason: string?,
	saving: boolean,
	saveQueued: boolean,
	lastSaveAt: number,
}

local LOCK_STALE_SECONDS = 300
local MAX_ATTEMPTS = 5

local ProfileStore = {}
ProfileStore.__index = ProfileStore

export type Store = typeof(setmetatable({} :: { deps: Deps, sessions: { [number]: Session } }, ProfileStore))

function ProfileStore.new(deps: Deps): Store
	return setmetatable({ deps = deps, sessions = {} }, ProfileStore)
end

local function keyFor(uid: number): string
	return "u_" .. tostring(uid)
end

local function backoff(deps: Deps, attempt: number)
	-- Exponential backoff with jitter: 0.5, 1, 2, 4 s (+ up to 50%).
	local base = 0.5 * 2 ^ (attempt - 1)
	deps.wait(base * (1 + 0.5 * deps.jitter()))
end

function ProfileStore.load(self: Store, uid: number): Session
	local deps = self.deps
	local key = keyFor(uid)
	local result: Schema.Profile? = nil
	local reason: string? = nil
	for attempt = 1, MAX_ATTEMPTS do
		local lockedByOther = false
		local ok, err = pcall(function()
			deps.backend:update(key, function(old: any)
				local now = deps.clock()
				local record = old
				if type(record) ~= "table" then
					record = { data = nil, lock = nil }
				end
				local lock = record.lock
				if type(lock) == "table" and lock.job ~= deps.jobId and now - (lock.at or 0) < LOCK_STALE_SECONDS then
					lockedByOther = true
					return nil -- abort the write; nothing changes
				end
				local data = record.data
				local migrated: Schema.Profile?
				if data == nil then
					migrated = Schema.default(now)
				else
					local m, why = Schema.migrate(data, now)
					if m == nil then
						reason = why
						return nil
					end
					migrated = m
				end
				result = migrated
				return { data = migrated, lock = { job = deps.jobId, at = now } }
			end)
		end)
		if ok and result then
			break
		end
		if ok and reason then
			break -- newer version / corrupt: do not retry or overwrite
		end
		if not ok then
			reason = "error: " .. tostring(err)
			deps.log(`profile load attempt {attempt} for {uid} failed: {err}`)
		elseif lockedByOther then
			reason = "locked"
			deps.log(`profile {uid} locked by another server (attempt {attempt})`)
		end
		if attempt < MAX_ATTEMPTS then
			backoff(deps, attempt)
		end
	end
	local session: Session
	if result then
		session = {
			uid = uid,
			key = key,
			profile = result :: Schema.Profile,
			canSave = true,
			status = "loaded",
			reason = nil,
			saving = false,
			saveQueued = false,
			lastSaveAt = deps.clock(),
		}
	else
		-- Failed-load protection: play on defaults, never save over the record.
		session = {
			uid = uid,
			key = key,
			profile = Schema.default(deps.clock()),
			canSave = false,
			status = "failed",
			reason = reason,
			saving = false,
			saveQueued = false,
			lastSaveAt = deps.clock(),
		}
	end
	self.sessions[uid] = session
	return session
end

-- Ordered save: if a save is running, mark one more and return; the running
-- save loop picks it up, so writes never overlap or reorder.
function ProfileStore.save(self: Store, uid: number, release: boolean?): boolean
	local s = self.sessions[uid]
	if s == nil or not s.canSave then
		return false
	end
	if s.saving then
		s.saveQueued = true
		if release then
			s.status = "released"
		end
		return true
	end
	s.saving = true
	local deps = self.deps
	local success = false
	repeat
		s.saveQueued = false
		local releasing = release or s.status == "released"
		local wrote = false
		for attempt = 1, MAX_ATTEMPTS do
			local lost = false
			local ok, err = pcall(function()
				deps.backend:update(s.key, function(old: any)
					if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.job ~= deps.jobId then
						lost = true
						return nil
					end
					local lock = if releasing then nil else { job = deps.jobId, at = deps.clock() }
					return { data = s.profile, lock = lock }
				end)
			end)
			if ok and lost then
				s.status = "lost"
				s.canSave = false
				deps.log(`profile {uid}: session lock lost; saving stopped`)
				break
			end
			if ok then
				wrote = true
				break
			end
			deps.log(`profile save attempt {attempt} for {uid} failed: {err}`)
			if attempt < MAX_ATTEMPTS then
				backoff(deps, attempt)
			end
		end
		success = wrote
		if wrote then
			s.lastSaveAt = deps.clock()
		end
	until not s.saveQueued or not s.canSave
	s.saving = false
	if release and s.status ~= "lost" then
		s.status = "released"
		s.canSave = false
	end
	return success
end

function ProfileStore.get(self: Store, uid: number): Session?
	return self.sessions[uid]
end

function ProfileStore.forget(self: Store, uid: number)
	self.sessions[uid] = nil
end

-- In-memory backend with failure injection, for tests and Studio sessions
-- without API access. Not used against live data.
function ProfileStore.memoryBackend(): any
	local store: { [string]: any } = {}
	local backend = { store = store, failNext = 0, calls = 0 }
	function backend.update(self: any, key: string, fn: (any) -> any): any
		self.calls += 1
		if self.failNext > 0 then
			self.failNext -= 1
			error("injected failure")
		end
		local old = self.store[key]
		local copy = if old ~= nil then table.clone(old) else nil
		local new = fn(copy)
		if new ~= nil then
			self.store[key] = new
		end
		return new
	end
	return backend
end

-- Real backend wrapper around a DataStore. The scope is the isolated test
-- scope unless Config.Persistence.USE_LIVE_SCOPE is deliberately enabled.
function ProfileStore.dataStoreBackend(dataStore: any): any
	local backend = {}
	function backend.update(_self: any, key: string, fn: (any) -> any): any
		return dataStore:UpdateAsync(key, function(old)
			return fn(old)
		end)
	end
	return backend
end

ProfileStore.LOCK_STALE_SECONDS = LOCK_STALE_SECONDS
ProfileStore.SCOPE = if Config.Persistence.USE_LIVE_SCOPE then Config.Persistence.LIVE_SCOPE else Config.Persistence.TEST_SCOPE

return ProfileStore
