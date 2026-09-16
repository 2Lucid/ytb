--!strict
-- AssetForge : plugin Studio de génération en lot des assets du manifest via Cube 3D.
--
-- Avant de lancer :
--   1. Game Settings > Security : activer "Allow Mesh & Image APIs" (EditableImage / EditableMesh),
--      sinon les textures sont supprimées silencieusement.
--   2. Ouvrir le place du jeu (le manifest est lu depuis ReplicatedStorage.AssetForgeManifest,
--      posé par Rojo depuis assets/manifest.json).
--
-- Le lot respecte la limite de 5 générations par minute, reprend après un plantage, et écrit
-- un rapport que `forge/assetforge/import_results.py` réinjecte dans le manifest et dans
-- src/shared/Generated/AssetIds.luau.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Selection = game:GetService("Selection")
local ServerStorage = game:GetService("ServerStorage")
local StudioService = game:GetService("StudioService")

local Generator = require(script.Generator)
local Quality = require(script.Quality)
local Queue = require(script.Queue)
local State = require(script.State)

type Entry = Generator.Entry

local RATE_LIMIT = 5
local OUTPUT_FOLDER = "AssetForgeOutput"

local toolbar = plugin:CreateToolbar("AssetForge")
local runButton = toolbar:CreateButton("AssetForgeRun", "Générer les assets manquants du manifest", "rbxasset://textures/ui/common/robux.png", "Générer")
local auditButton = toolbar:CreateButton("AssetForgeAudit", "Contrôle qualité du lot déjà généré", "rbxasset://textures/ui/common/search.png", "Contrôler")
local exportButton = toolbar:CreateButton("AssetForgeExport", "Copier le rapport JSON dans un ModuleScript à récupérer", "rbxasset://textures/ui/common/file.png", "Exporter")
local resetButton = toolbar:CreateButton("AssetForgeReset", "Oublier la progression (ne supprime aucun asset publié)", "rbxasset://textures/ui/common/delete.png", "Réinitialiser")

local store = State.new(plugin)
local running = false
local stopRequested = false

local function manifest(): { assets: { Entry } }?
	local holder = ReplicatedStorage:FindFirstChild("AssetForgeManifest") or ServerStorage:FindFirstChild("AssetForgeManifest")
	if holder == nil then
		warn("[AssetForge] manifest introuvable. Attendu : ReplicatedStorage.AssetForgeManifest (ModuleScript ou StringValue).")
		return nil
	end
	if holder:IsA("ModuleScript") then
		local ok, value = pcall(require, holder)
		if ok and type(value) == "table" then
			return value :: any
		end
		warn("[AssetForge] le ModuleScript du manifest n'a pas renvoyé de table : " .. tostring(value))
		return nil
	end
	if holder:IsA("StringValue") then
		local ok, value = pcall(function()
			return HttpService:JSONDecode(holder.Value)
		end)
		if ok and type(value) == "table" then
			return value :: any
		end
		warn("[AssetForge] JSON du manifest illisible : " .. tostring(value))
		return nil
	end
	warn("[AssetForge] type de manifest non géré : " .. holder.ClassName)
	return nil
end

local function outputFolder(): Folder
	local existing = ServerStorage:FindFirstChild(OUTPUT_FOLDER)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = OUTPUT_FOLDER
	created.Parent = ServerStorage
	return created
end

local function creator(): (number?, Enum.AssetCreatorType?)
	local ok, userId = pcall(function()
		return StudioService:GetUserId()
	end)
	if ok and type(userId) == "number" and userId > 0 then
		return userId, Enum.AssetCreatorType.User
	end
	return nil, nil
end

-- Génère tous les assets encore en attente. Les assets héros sont ignorés par défaut :
-- ils passent par un modèle détaillé importé à la main (voir docs/ASSETS.md).
local function runBatch(includeHeroes: boolean)
	if running then
		stopRequested = true
		print("[AssetForge] arrêt demandé, fin de l'asset en cours…")
		return
	end
	local data = manifest()
	if data == nil then
		return
	end
	running = true
	stopRequested = false
	runButton:SetActive(true)

	local queue = Queue.new(RATE_LIMIT)
	local creatorId, creatorType = creator()
	local folder = outputFolder()
	local pending: { Entry } = {}
	for _, entry in data.assets do
		if entry.kind ~= "mesh" then
			continue
		end
		if entry.hero == true and not includeHeroes then
			continue
		end
		local record = store:get(entry.id)
		if record == nil or record.status == "pending" or record.status == "failed" then
			table.insert(pending, entry)
		end
	end
	print(string.format("[AssetForge] %d asset(s) à générer (%d par minute). %s", #pending, RATE_LIMIT, Quality.summary(data.assets :: any, store:all())))

	local generated, failed = 0, 0
	for index, entry in pending do
		if stopRequested then
			print("[AssetForge] arrêté à la demande.")
			break
		end
		local wait = queue:delayFor(os.clock())
		if wait > 0 then
			print(string.format("[AssetForge] limite atteinte, pause de %.0f s…", wait))
			task.wait(wait)
		end
		queue:consume(os.clock())
		print(string.format("[AssetForge] %d/%d : %s", index, #pending, entry.id))
		local result, model = Generator.generate(entry, creatorId, creatorType)
		if model then
			local previous = folder:FindFirstChild(entry.id)
			if previous then
				previous:Destroy()
			end
			model.Parent = folder
		end
		store:set(entry.id, {
			status = result.ok and "done" or "failed",
			assetId = result.assetId,
			reason = result.reason,
			triangles = result.triangles,
			textured = result.textured,
			at = os.time(),
		})
		if result.ok then
			generated += 1
			print(string.format("   ok : id %d, %d triangles, texture %s, %.1f s", result.assetId, result.triangles, result.textured and "oui" or "non", result.seconds))
		else
			failed += 1
			warn(string.format("   échec : %s", result.reason))
		end
	end

	running = false
	runButton:SetActive(false)
	print(string.format("[AssetForge] terminé : %d généré(s), %d échec(s). %s", generated, failed, Quality.summary(data.assets :: any, store:all())))
	print("[AssetForge] cliquer sur Exporter pour récupérer le rapport, puis lancer forge/assetforge/import_results.py")
end

local function audit()
	local data = manifest()
	if data == nil then
		return
	end
	local issues = Quality.audit(data.assets :: any, store:all())
	print("[AssetForge] " .. Quality.summary(data.assets :: any, store:all()))
	if #issues == 0 then
		print("[AssetForge] aucun problème détecté.")
		return
	end
	print(string.format("[AssetForge] %d point(s) à regarder :", #issues))
	print(string.format("%-34s %-14s %-28s %s", "ASSET", "GRAVITÉ", "PROBLÈME", "DÉTAIL"))
	for _, issue in issues do
		print(string.format("%-34s %-14s %-28s %s", issue.id, issue.severity, issue.problem, issue.detail))
	end
end

-- Écrit le rapport dans un ModuleScript sélectionné : copier-coller vers forge/assetforge/results.json
local function exportReport()
	local records = store:all()
	local payload: { [string]: any } = { generatedAt = os.time(), results = {} }
	for id, record in records do
		payload.results[id] = {
			status = record.status,
			assetId = record.assetId,
			reason = record.reason,
			triangles = record.triangles,
			textured = record.textured,
		}
	end
	local json = HttpService:JSONEncode(payload)
	local holder = ServerStorage:FindFirstChild("AssetForgeResults")
	if holder == nil or not holder:IsA("StringValue") then
		local created = Instance.new("StringValue")
		created.Name = "AssetForgeResults"
		created.Parent = ServerStorage
		holder = created
	end
	(holder :: StringValue).Value = json
	Selection:Set({ holder })
	print(string.format("[AssetForge] rapport de %d asset(s) écrit dans ServerStorage.AssetForgeResults (sélectionné).", #json > 0 and (function()
		local count = 0
		for _ in records do
			count += 1
		end
		return count
	end)() or 0))
	print("[AssetForge] copier sa valeur dans forge/assetforge/results.json puis : python3 forge/assetforge/import_results.py")
end

runButton.Click:Connect(function()
	task.spawn(runBatch, false)
end)
auditButton.Click:Connect(audit)
exportButton.Click:Connect(exportReport)
resetButton.Click:Connect(function()
	store:clear()
	print("[AssetForge] progression oubliée. Les assets déjà publiés restent sur ton compte.")
end)

print("[AssetForge] prêt. " .. (function()
	local counts = store:counts()
	return string.format("%d généré(s), %d échec(s) en mémoire.", counts.done, counts.failed)
end)())
