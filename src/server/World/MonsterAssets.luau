--!strict
-- Builds the monster models at server start from the recorded mesh and
-- texture ids (Shared/Content/MonsterModels) and shares them through
-- ReplicatedStorage.MonsterModels. Keeping the ids in code means the models
-- travel with the branch: no saved place edits are needed for a checkout to
-- show them. Clients fall back to a simple silhouette if a model is missing.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonsterModels = require(Shared.Content.MonsterModels)

local MonsterAssets = {}

local function build(key: string, def: MonsterModels.ModelDef, folder: Folder)
	local model = Instance.new("Model")
	model.Name = key
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(1, 1, 1)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root
	for _, p in def.parts do
		local ok, part = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri(p.mesh), {
				CollisionFidelity = Enum.CollisionFidelity.Box,
				RenderFidelity = Enum.RenderFidelity.Automatic,
			})
		end)
		if not ok or part == nil then
			warn(`[Cabinet] monster part {key}/{p.name} failed: {part}`)
			continue
		end
		local mp = part :: MeshPart
		mp.Name = p.name
		mp.TextureID = p.tex
		mp.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		mp.CFrame = CFrame.new(table.unpack(p.cf))
		mp.Anchored = true
		mp.CanCollide = false
		mp.CanQuery = false
		mp.CanTouch = false
		mp.CastShadow = true
		mp.Parent = model
	end
	model:SetAttribute("Height", def.height)
	model.Parent = folder
end

function MonsterAssets.start()
	local folder = ReplicatedStorage:FindFirstChild("MonsterModels")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "MonsterModels"
		folder.Parent = ReplicatedStorage
	end
	for key, def in MonsterModels.Models do
		task.spawn(build, key, def, folder :: Folder)
	end
end

return MonsterAssets
