--!strict
-- Lobby parties: a leader, up to the party cap of members, each with a
-- chosen class (kit) and a ready flag, plus the campaign the leader picked.
-- Pure: no engine services, so it is tested headlessly. The run manager
-- turns a started party into a run and dissolves it.

export type Party = {
	id: string,
	leader: number,
	members: { number },
	kits: { [number]: string },
	ready: { [number]: boolean },
	campaign: string,
	privacy: "open" | "friends" | "closed",
	maxParty: number,
}

export type Lobby = {
	parties: { [string]: Party },
	of: { [number]: string },
	counter: number,
	maxParty: number,
}

export type Result = { ok: boolean, reason: string? }

local PartyCore = {}

function PartyCore.new(maxParty: number): Lobby
	return { parties = {}, of = {}, counter = 0, maxParty = maxParty }
end

function PartyCore.partyOf(l: Lobby, uid: number): Party?
	local id = l.of[uid]
	return if id then l.parties[id] else nil
end

function PartyCore.leave(l: Lobby, uid: number)
	local p = PartyCore.partyOf(l, uid)
	l.of[uid] = nil
	if p == nil then
		return
	end
	local idx = table.find(p.members, uid)
	if idx then
		table.remove(p.members, idx)
	end
	p.kits[uid] = nil
	p.ready[uid] = nil
	if #p.members == 0 then
		l.parties[p.id] = nil
	elseif p.leader == uid then
		p.leader = p.members[1]
	end
end

function PartyCore.create(l: Lobby, uid: number, kit: string, campaign: string, privacy: "open" | "friends" | "closed"): Party
	PartyCore.leave(l, uid)
	l.counter += 1
	local p: Party = {
		id = "party" .. tostring(l.counter),
		leader = uid,
		members = { uid },
		kits = { [uid] = kit },
		ready = { [uid] = true },
		campaign = campaign,
		privacy = privacy,
		maxParty = l.maxParty,
	}
	l.parties[p.id] = p
	l.of[uid] = p.id
	return p
end

function PartyCore.join(l: Lobby, uid: number, partyId: string, kit: string): Result
	local p = l.parties[partyId]
	if p == nil then
		return { ok = false, reason = "gone" }
	end
	if l.of[uid] == partyId then
		return { ok = false, reason = "already" }
	end
	if p.privacy == "closed" then
		return { ok = false, reason = "closed" }
	end
	if #p.members >= p.maxParty then
		return { ok = false, reason = "full" }
	end
	PartyCore.leave(l, uid)
	table.insert(p.members, uid)
	p.kits[uid] = kit
	p.ready[uid] = false
	l.of[uid] = p.id
	return { ok = true }
end

function PartyCore.setKit(l: Lobby, uid: number, kit: string)
	local p = PartyCore.partyOf(l, uid)
	if p then
		p.kits[uid] = kit
	end
end

function PartyCore.setReady(l: Lobby, uid: number, ready: boolean)
	local p = PartyCore.partyOf(l, uid)
	if p and p.leader ~= uid then
		p.ready[uid] = ready
	end
end

function PartyCore.setCampaign(l: Lobby, uid: number, campaign: string): Result
	local p = PartyCore.partyOf(l, uid)
	if p == nil or p.leader ~= uid then
		return { ok = false, reason = "not_leader" }
	end
	p.campaign = campaign
	-- A changed mission needs everyone to confirm again.
	for _, m in p.members do
		if m ~= p.leader then
			p.ready[m] = false
		end
	end
	return { ok = true }
end

-- The leader starts once every other member is ready.
function PartyCore.canStart(l: Lobby, uid: number): Result
	local p = PartyCore.partyOf(l, uid)
	if p == nil then
		return { ok = false, reason = "no_party" }
	end
	if p.leader ~= uid then
		return { ok = false, reason = "not_leader" }
	end
	for _, m in p.members do
		if m ~= p.leader and not p.ready[m] then
			return { ok = false, reason = "not_ready" }
		end
	end
	return { ok = true }
end

-- Removes the party (it became a run) and returns its founders in order.
function PartyCore.dissolve(l: Lobby, partyId: string): { { uid: number, kit: string } }
	local p = l.parties[partyId]
	local out = {}
	if p == nil then
		return out
	end
	-- Leader first: they host the run and break vote ties.
	table.insert(out, { uid = p.leader, kit = p.kits[p.leader] })
	for _, m in p.members do
		if m ~= p.leader then
			table.insert(out, { uid = m, kit = p.kits[m] })
		end
		l.of[m] = nil
	end
	l.parties[partyId] = nil
	return out
end

function PartyCore.view(p: Party): { [string]: any }
	local members = {}
	for _, m in p.members do
		table.insert(members, { uid = m, kit = p.kits[m], ready = p.ready[m] == true or m == p.leader, leader = m == p.leader })
	end
	return { id = p.id, leader = p.leader, members = members, campaign = p.campaign, privacy = p.privacy, maxParty = p.maxParty }
end

-- Parties another player could join from the lobby board.
function PartyCore.list(l: Lobby, forUid: number): { { [string]: any } }
	local out = {}
	for id, p in l.parties do
		if l.of[forUid] ~= id and p.privacy ~= "closed" and #p.members < p.maxParty then
			table.insert(out, PartyCore.view(p))
		end
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

return PartyCore
