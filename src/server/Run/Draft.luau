--!strict
-- Three-option drafts (plan §5): one kit-compatible, one flexible, one
-- wildcard. If a tagged pool is exhausted, offer an owned-ball upgrade.
-- One free reroll and one guaranteed kit component ("Kit pick") per leg.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Balls = require(Shared.Content.Balls)
local Components = require(Shared.Content.Components)
local Kits = require(Shared.Content.Kits)
local Rng = require(script.Parent.Rng)

export type Option = {
	kind: "component" | "ball" | "upgrade",
	id: string,
	badge: "kit" | "flex" | "wild" | "targeted",
}

export type MemberView = {
	kit: string,
	rack: { string },
	components: { string },
	ballLevels: { [string]: number },
}

export type Context = {
	seed: string, -- run seed .. member uid .. encounter index .. reroll count
	targeted: boolean, -- this offer carries the leg's guaranteed kit pick
	familyPool: { [string]: boolean }, -- ball families allowed in offers
}

local Draft = {}

local function owns(list: { string }, id: string): boolean
	for _, v in list do
		if v == id then
			return true
		end
	end
	return false
end

local function take(rng: Rng.Rng, pool: { Option }, used: { [string]: boolean }): Option?
	local avail = {}
	for _, o in pool do
		if not used[o.kind .. ":" .. o.id] then
			table.insert(avail, o)
		end
	end
	if #avail == 0 then
		return nil
	end
	local o = avail[Rng.pick(rng, #avail)]
	used[o.kind .. ":" .. o.id] = true
	return o
end

local function upgradeOption(m: MemberView, used: { [string]: boolean }, badge: "kit" | "flex" | "wild" | "targeted"): Option
	-- Upgrade the least-upgraded special ball (slot order breaks ties).
	local best: string? = nil
	local bestLevel = math.huge
	for i = 2, #m.rack do
		local id = m.rack[i]
		local lvl = m.ballLevels[id] or 0
		if lvl < bestLevel and not used["upgrade:" .. id] then
			best = id
			bestLevel = lvl
		end
	end
	local id = best or m.rack[1]
	used["upgrade:" .. id] = true
	return { kind = "upgrade", id = id, badge = badge }
end

function Draft.generate(m: MemberView, ctx: Context): { Option }
	local rng = Rng.new(ctx.seed)
	local kit = Kits.ById[m.kit]
	local used: { [string]: boolean } = {}

	local kitComponents: { Option } = {}
	local kitPool: { Option } = {}
	local flexPool: { Option } = {}
	local wildPool: { Option } = {}

	for _, cid in Components.Order do
		local c = Components.ById[cid]
		if not owns(m.components, cid) then
			local o: Option = { kind = "component", id = cid, badge = "kit" }
			if c.tag == kit.tag then
				table.insert(kitComponents, { kind = "component", id = cid, badge = "targeted" })
				table.insert(kitPool, o)
			elseif c.tag == "flex" then
				table.insert(flexPool, { kind = "component", id = cid, badge = "flex" })
			elseif c.tag == "wild" then
				table.insert(wildPool, { kind = "component", id = cid, badge = "wild" })
			end
		end
	end
	for _, bid in Balls.Order do
		local b = Balls.ById[bid]
		if b.family ~= "core" and not owns(m.rack, bid) and ctx.familyPool[b.family] ~= false then
			local isKit = false
			for _, f in kit.families do
				if f == b.family then
					isKit = true
				end
			end
			if isKit then
				table.insert(kitPool, { kind = "ball", id = bid, badge = "kit" })
			else
				table.insert(wildPool, { kind = "ball", id = bid, badge = "wild" })
			end
		end
	end

	local first: Option?
	if ctx.targeted then
		first = take(rng, kitComponents, used)
	end
	if first == nil then
		first = take(rng, kitPool, used)
	end
	local options: { Option } = {
		first or upgradeOption(m, used, "kit"),
		take(rng, flexPool, used) or upgradeOption(m, used, "flex"),
		take(rng, wildPool, used) or upgradeOption(m, used, "wild"),
	}
	return options
end

-- Fixed catch-up kit for a newcomer who joins after `completed` encounters:
-- one kit component per completed encounter (kit tag first, then flex), in
-- catalogue order. Deterministic, so rejoining cannot reroll it.
function Draft.catchUp(kitId: string, completed: number): { string }
	local kit = Kits.ById[kitId]
	local list = { kit.starter }
	if completed <= 0 then
		return list
	end
	local ordered = {}
	for _, cid in Components.Order do
		if Components.ById[cid].tag == kit.tag and cid ~= kit.starter then
			table.insert(ordered, cid)
		end
	end
	for _, cid in Components.Order do
		if Components.ById[cid].tag == "flex" then
			table.insert(ordered, cid)
		end
	end
	for i = 1, math.min(completed, #ordered) do
		table.insert(list, ordered[i])
	end
	return list
end

return Draft
