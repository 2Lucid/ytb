--!strict
-- Génération d'un asset du manifest via GenerationService (Cube 3D), post-traitement, puis publication
-- en asset persistant via AssetService:CreateAssetAsync.
--
-- Rappels vérifiés dans la doc officielle :
--  - GenerateModelAsync(inputs, schema) yield et peut lever : toujours sous pcall.
--  - inputs : TextPrompt, Size (Vector3, approximatif), MaxTriangles, GenerateTextures.
--  - schema : PredefinedSchema "Body1" (un mesh) ou "Car5" (corps + 4 roues), ou SchemaDefinition.Groups.
--  - CreateAssetAsync renvoie (Enum.CreateAssetResult, assetId).
--  - Activer EditableImage / EditableMesh dans Game Settings > Security, sinon les textures
--    sont supprimées silencieusement.

local AssetService = game:GetService("AssetService")
local GenerationService = game:GetService("GenerationService")

local Generator = {}

export type Entry = {
	id: string,
	kind: string,
	category: string,
	act: number,
	prompt: string,
	schema: string?,
	scale: { number }?,
	maxTriangles: number?,
	decalSlot: string?,
	hero: boolean?,
	status: string,
	assetId: number,
}

export type Result = {
	ok: boolean,
	assetId: number,
	reason: string,
	triangles: number,
	textured: boolean,
	seconds: number,
}

local function vector(scale: { number }?): Vector3
	if scale == nil or #scale < 3 then
		return Vector3.new(4, 4, 4)
	end
	return Vector3.new(scale[1], scale[2], scale[3])
end

-- Compte approximatif des triangles : somme sur les MeshPart du modèle
local function countTriangles(model: Model): number
	local total = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("MeshPart") then
			local ok, mesh = pcall(function()
				return AssetService:CreateEditableMeshAsync(descendant.MeshContent)
			end)
			if ok and typeof(mesh) == "Instance" and mesh:IsA("EditableMesh") then
				total += #mesh:GetFaces()
				mesh:Destroy()
			end
		end
	end
	return total
end

local function isTextured(model: Model): boolean
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("MeshPart") then
			-- ContentSourceType.None = pas de texture attachée au MeshPart
			if descendant.TextureContent.SourceType ~= Enum.ContentSourceType.None then
				return true
			end
			if descendant:FindFirstChildOfClass("SurfaceAppearance") then
				return true
			end
		end
	end
	return false
end

-- Post-traitement commun : PrimaryPart, échelle cible, collision, requête, ancrage.
function Generator.postProcess(model: Model, entry: Entry)
	model.Name = entry.id
	local parts: { BasePart } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	if #parts == 0 then
		return
	end
	-- échelle vers la taille cible du manifest
	local target = vector(entry.scale)
	local extents = model:GetExtentsSize()
	local largest = math.max(extents.X, extents.Y, extents.Z)
	if largest > 0 then
		local wanted = math.max(target.X, target.Y, target.Z)
		local factor = wanted / largest
		if math.abs(factor - 1) > 0.01 then
			model:ScaleTo(factor)
		end
	end
	-- décor : ni collision ni requête (coût nul en physique et en raycast)
	local interactive = entry.category == "COLL" or entry.category == "GP" or entry.category == "LORE"
	for _, part in parts do
		part.Anchored = true
		part.CanCollide = interactive
		part.CanQuery = interactive
		part.CanTouch = interactive
		part.CastShadow = true
		if part:IsA("MeshPart") then
			-- Box sauf pour ce que le joueur doit pouvoir traverser précisément
			part.CollisionFidelity = Enum.CollisionFidelity.Box
			part.RenderFidelity = entry.hero == true and Enum.RenderFidelity.Precise or Enum.RenderFidelity.Automatic
		end
	end
	if model.PrimaryPart == nil then
		-- le plus gros volume sert de PrimaryPart : c'est la base au sol
		local best: BasePart = parts[1]
		local bestVolume = 0
		for _, part in parts do
			local volume = part.Size.X * part.Size.Y * part.Size.Z
			if volume > bestVolume then
				bestVolume = volume
				best = part
			end
		end
		model.PrimaryPart = best
	end
	if entry.decalSlot then
		model:SetAttribute("DecalSlot", entry.decalSlot)
	end
	model:SetAttribute("ManifestId", entry.id)
	model:SetAttribute("Act", entry.act)
end

-- Génère un asset. `creatorId` et `creatorType` sont requis hors contexte plugin.
function Generator.generate(entry: Entry, creatorId: number?, creatorType: Enum.AssetCreatorType?): (Result, Model?)
	local started = os.clock()
	local inputs: { [string]: any } = {
		TextPrompt = entry.prompt,
		Size = vector(entry.scale),
		GenerateTextures = true,
	}
	if entry.maxTriangles then
		inputs.MaxTriangles = entry.maxTriangles
	end
	local schema: { [string]: any } = { PredefinedSchema = entry.schema or "Body1" }
	local ok, result = pcall(function()
		return GenerationService:GenerateModelAsync(inputs, schema)
	end)
	if not ok then
		return { ok = false, assetId = 0, reason = "génération : " .. tostring(result), triangles = 0, textured = false, seconds = os.clock() - started }, nil
	end
	if typeof(result) ~= "Instance" or not (result :: Instance):IsA("Model") then
		return { ok = false, assetId = 0, reason = "la génération n'a pas renvoyé de Model", triangles = 0, textured = false, seconds = os.clock() - started }, nil
	end
	local model = result :: Model
	Generator.postProcess(model, entry)
	local triangles = countTriangles(model)
	local textured = isTextured(model)

	local parameters: { [string]: any } = {
		Name = entry.id,
		Description = string.format("American Dream / %s / acte %d", entry.category, entry.act),
		IsPackage = false,
	}
	if creatorId then
		parameters.CreatorId = creatorId
		parameters.CreatorType = creatorType or Enum.AssetCreatorType.User
	end
	local publishOk, publishResult, assetId = pcall(function()
		return AssetService:CreateAssetAsync(model, Enum.AssetType.Model, parameters)
	end)
	if not publishOk then
		return { ok = false, assetId = 0, reason = "publication : " .. tostring(publishResult), triangles = triangles, textured = textured, seconds = os.clock() - started }, model
	end
	if publishResult ~= Enum.CreateAssetResult.Success then
		return { ok = false, assetId = 0, reason = "publication refusée : " .. tostring(publishResult), triangles = triangles, textured = textured, seconds = os.clock() - started }, model
	end
	return {
		ok = true,
		assetId = tonumber(assetId) or 0,
		reason = "",
		triangles = triangles,
		textured = textured,
		seconds = os.clock() - started,
	}, model
end

return Generator
