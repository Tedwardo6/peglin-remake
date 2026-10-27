--!strict
-- Builds each player's hero from their own Roblox avatar (R15, their
-- current outfit) on the server and shares it through ReplicatedStorage, so
-- every client can place the whole party on the battlefield. The client
-- dresses the copy in class gear and animates it; nothing here affects
-- gameplay.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Heroes = {}

local folder: Folder? = nil

local function getFolder(): Folder
	local existing = folder
	if existing then
		return existing
	end
	local f = ReplicatedStorage:FindFirstChild("HeroModels")
	if f == nil then
		f = Instance.new("Folder")
		f.Name = "HeroModels"
		f.Parent = ReplicatedStorage
	end
	folder = f :: Folder
	return f :: Folder
end

local function describe(uid: number): HumanoidDescription
	if uid > 0 then
		local ok, desc = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(uid)
		end)
		if ok and desc then
			return desc
		end
	end
	-- Studio test players (negative ids) and lookup failures get a plain
	-- default body; class gear still makes them distinct.
	return Instance.new("HumanoidDescription")
end

function Heroes.ensure(player: Player)
	local uid = player.UserId
	task.spawn(function()
		local f = getFolder()
		if f:FindFirstChild(tostring(uid)) then
			return
		end
		local desc = describe(uid)
		local ok, model = pcall(function()
			return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
		end)
		if not ok or model == nil then
			warn(`[Cabinet] hero model for {uid} failed: {model}`)
			return
		end
		local m = model :: Model
		m.Name = tostring(uid)
		-- Keep the animation ids (Animate's StringValues) but no running code.
		for _, d in m:GetDescendants() do
			if d:IsA("BaseScript") then
				local anims = Instance.new("Folder")
				anims.Name = "AnimIds"
				for _, v in d:GetDescendants() do
					if v:IsA("Animation") then
						local s = Instance.new("StringValue")
						s.Name = (v.Parent and v.Parent.Name or "anim") .. "_" .. v.Name
						s.Value = v.AnimationId
						s.Parent = anims
					end
				end
				anims.Parent = m
				d:Destroy()
			end
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				-- Only the root is anchored so Motor6D animation still moves limbs.
				d.Anchored = d.Name == "HumanoidRootPart"
				d.CanCollide = false
				d.Massless = true
				d.CanQuery = false
				d.CanTouch = false
			end
		end
		if player.Parent then
			m.Parent = f
		else
			m:Destroy()
		end
	end)
end

function Heroes.forget(uid: number)
	local f = getFolder()
	local m = f:FindFirstChild(tostring(uid))
	if m then
		m:Destroy()
	end
end

return Heroes
