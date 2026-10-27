--!strict
-- Client side of the wire contract (see Shared/Net/Protocol).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Protocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"):WaitForChild("Protocol"))

local Net = {}

local folder: Instance
local request: RemoteEvent
local pushRemote: RemoteEvent
local cosmetic: UnreliableRemoteEvent
local cosmeticUp: UnreliableRemoteEvent
local handlers: { [string]: { (any) -> () } } = {}
local aimHandlers: { (number, number) -> () } = {}

function Net.init()
	folder = ReplicatedStorage:WaitForChild(Protocol.FOLDER)
	request = folder:WaitForChild(Protocol.REQUEST) :: RemoteEvent
	pushRemote = folder:WaitForChild(Protocol.PUSH) :: RemoteEvent
	cosmetic = folder:WaitForChild(Protocol.COSMETIC) :: UnreliableRemoteEvent
	cosmeticUp = folder:WaitForChild(Protocol.COSMETIC_UP) :: UnreliableRemoteEvent
	pushRemote.OnClientEvent:Connect(function(kind: string, payload: any)
		local list = handlers[kind]
		if list then
			for _, fn in list do
				task.spawn(fn, payload)
			end
		end
	end)
	cosmetic.OnClientEvent:Connect(function(uid: number, aim: number)
		for _, fn in aimHandlers do
			fn(uid, aim)
		end
	end)
end

function Net.send(kind: string, payload: { [string]: any }?)
	request:FireServer(kind, payload or {})
end

function Net.on(kind: string, fn: (any) -> ())
	local list = handlers[kind]
	if list == nil then
		list = {}
		handlers[kind] = list
	end
	table.insert(list, fn)
end

function Net.sendAim(aim: number)
	cosmeticUp:FireServer(aim)
end

function Net.onAim(fn: (number, number) -> ())
	table.insert(aimHandlers, fn)
end

return Net
