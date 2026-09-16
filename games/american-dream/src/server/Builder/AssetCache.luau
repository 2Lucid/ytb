--!strict
-- Charge une fois les meshes du registre (AssetService:CreateMeshPartAsync) et fournit des gabarits à cloner.
-- Un asset manquant ou refusé rend nil : l'appelant tombe sur le greybox. Aucune exception ne sort d'ici.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetIds = require(ReplicatedStorage.Shared.Generated.AssetIds)
local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)

local AssetCache = {}

local templates: { [string]: Model } = {}
local failed: { [string]: boolean } = {}
local loading = false
local loaded = false

local function folder(): Folder
	local existing = ReplicatedStorage:FindFirstChild("Assets")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Assets"
	created.Parent = ReplicatedStorage
	return created
end

local function loadMesh(id: string, assetId: number): Model?
	local ok, result = pcall(function()
		return AssetService:CreateMeshPartAsync(Content.fromAssetId(assetId), {
			CollisionFidelity = Enum.CollisionFidelity.Box,
			RenderFidelity = Enum.RenderFidelity.Automatic,
		})
	end)
	if not ok or typeof(result) ~= "Instance" then
		warn(string.format("[AssetCache] mesh %s (%d) non chargé : %s", id, assetId, tostring(result)))
		return nil
	end
	local meshPart = result :: MeshPart
	meshPart.Name = "Base"
	meshPart.Anchored = true
	meshPart.CanCollide = false
	meshPart.CanQuery = false
	meshPart.CanTouch = false
	local model = Instance.new("Model")
	model.Name = id
	meshPart.Parent = model
	model.PrimaryPart = meshPart
	return model
end

-- Précharge tous les meshes du registre. À appeler une fois au démarrage (yield).
function AssetCache.preload()
	if loading or loaded then
		return
	end
	loading = true
	local parent = folder()
	local count = 0
	local total = 0
	for id, assetId in AssetIds.meshes do
		total += 1
		if assetId > 0 then
			local model = loadMesh(id, assetId)
			if model then
				model.Parent = parent
				templates[id] = model
				count += 1
			else
				failed[id] = true
			end
		end
	end
	loaded = true
	loading = false
	print(string.format("[AssetCache] %d mesh(es) chargé(s), %d en greybox", count, total - count))
end

function AssetCache.template(id: string): Model?
	local template: Model? = templates[id]
	return template
end

-- Un clone du mesh si disponible, sinon nil
function AssetCache.instance(id: string): Model?
	local template: Model? = templates[id]
	if template == nil then
		return nil
	end
	return template:Clone()
end

function AssetCache.hasAsset(id: string): boolean
	local template: Model? = templates[id]
	return template ~= nil or (AssetRegistry.hasMesh(id) and not failed[id] and not loaded)
end

return AssetCache
