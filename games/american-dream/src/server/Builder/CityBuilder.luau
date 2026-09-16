--!strict
-- Instancie la ville générée par WorldGen.Layout : routes, trottoirs, immeubles, props, panneaux, journaux, PNJ.
-- Greybox partout où le registre n'a pas encore d'asset. Les tags CollectionService pilotent les animations client.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Layout = require(ReplicatedStorage.Shared.WorldGen.Layout)
local Palette = require(ReplicatedStorage.Shared.WorldGen.Palette)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Lore = require(ReplicatedStorage.Shared.Config.Lore)
local PRNG = require(ReplicatedStorage.Shared.Util.PRNG)
local Greybox = require(script.Parent.Greybox)
local AssetCache = require(script.Parent.AssetCache)
local NpcBuilder = require(script.Parent.NpcBuilder)

type Placement = Layout.Placement

local CityBuilder = {}

local STYLE_MATERIAL: { [string]: Enum.Material } = {
	brick = Enum.Material.Brick,
	concrete = Enum.Material.Concrete,
	glass = Enum.Material.Glass,
	metal = Enum.Material.CorrodedMetal,
	gold = Enum.Material.Marble,
}

local function cframeOf(p: Placement): CFrame
	return CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0)
end

local function solid(p: Placement, name: string, rgb: { number }, material: Enum.Material): Part
	local part = Greybox.part(name, Vector3.new(p.sx, p.sy, p.sz), rgb, material)
	part.CFrame = cframeOf(p)
	part.CanCollide = true
	part.CanQuery = true
	return part
end

local function tagIf(instance: Instance, p: Placement)
	if p.tag then
		CollectionService:AddTag(instance, p.tag)
	end
end

local function buildBuilding(p: Placement, rng: PRNG.PRNG, parent: Instance)
	local palette = Palette.forAct(p.act)
	local rgb = rng:pick(palette.building)
	local material = STYLE_MATERIAL[p.style or "concrete"] or Enum.Material.Concrete
	local template = AssetCache.template(p.id)
	if template then
		-- modules de 20 studs empilés
		local modules = math.max(1, math.floor(p.sy / 20 + 0.5))
		local model = Instance.new("Model")
		model.Name = p.id
		for k = 1, modules do
			local clone = template:Clone()
			clone:PivotTo(CFrame.new(p.x, (k - 0.5) * 20, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0))
			clone.Parent = model
		end
		tagIf(model, p)
		model.Parent = parent
		return
	end
	local part = solid(p, "Building", rgb, material)
	part.Reflectance = material == Enum.Material.Glass and 0.15 or 0
	-- toit + bandeau lumineux pour les tours néon
	if p.tag == "NeonTower" then
		local band = Greybox.part("Band", Vector3.new(p.sx + 0.4, 0.8, p.sz + 0.4), palette.accent, Enum.Material.Neon)
		band.CFrame = cframeOf(p) * CFrame.new(0, p.sy / 2 - 1.5, 0)
		band.Parent = part
	end
	tagIf(part, p)
	part.Parent = parent
end

local function buildProp(p: Placement, parent: Instance)
	local model = AssetCache.instance(p.id) or Greybox.model(p.id, p.act)
	if p.tag == "Puddle" then
		local base = model.PrimaryPart
		if base then
			base.Size = Vector3.new(p.sx * 2, 0.1, p.sz * 1.4)
			base.Material = Enum.Material.Glass
			base.Transparency = 0.35
			base.Reflectance = 0.6
			base.Color = Color3.new(0.2, 0.22, 0.3)
		end
	elseif p.tag == "StreetLight" then
		local pole = model.PrimaryPart
		if pole then
			pole.Size = Vector3.new(0.6, p.sy, 0.6)
			pole.Material = Enum.Material.Metal
			pole.Color = Color3.new(0.2, 0.2, 0.22)
			local lamp = Greybox.part("Lamp", Vector3.new(1.4, 0.6, 1.4), Palette.forAct(p.act).accent, Enum.Material.Neon)
			lamp.CFrame = CFrame.new(0, p.sy / 2, 0)
			lamp.Parent = model
			local light = Instance.new("PointLight")
			light.Range = 24
			light.Brightness = 1.2
			light.Color = Greybox.color(Palette.forAct(p.act).accent)
			light.Parent = lamp
		end
	elseif p.tag == "Chimney" then
		local base = model.PrimaryPart
		if base then
			base.Size = Vector3.new(4, p.sy, 4)
			base.Material = Enum.Material.Brick
			base.Color = Color3.new(0.4, 0.25, 0.2)
		end
	elseif p.tag == "TrafficLight" then
		local pole = model.PrimaryPart
		if pole then
			pole.Size = Vector3.new(0.5, p.sy, 0.5)
			pole.Color = Color3.new(0.15, 0.15, 0.15)
		end
	else
		Greybox.fit(model, Vector3.new(p.sx, p.sy, p.sz))
	end
	model:PivotTo(cframeOf(p) * CFrame.new(0, 0, 0))
	-- pose au sol : la base est centrée sur y
	local base = model.PrimaryPart
	if base then
		local extents = model:GetExtentsSize()
		model:PivotTo(CFrame.new(p.x, extents.Y / 2, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0))
	end
	-- fixe : relie les parts secondaires au PrimaryPart pour que PivotTo les suive (déjà le cas via Model)
	tagIf(model, p)
	model:SetAttribute("Act", p.act)
	model.Parent = parent
end

local function buildBillboard(p: Placement, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Billboard_" .. tostring(p.index)
	local pole = Greybox.part("Pole", Vector3.new(1, 10, 1), { 0.2, 0.2, 0.22 }, Enum.Material.Metal)
	pole.CFrame = cframeOf(p) * CFrame.new(0, -p.sy / 2 + 5, 0)
	pole.Parent = model
	local board = Greybox.part("Board", Vector3.new(p.sx, p.sy * 0.55, p.sz), { 0.08, 0.08, 0.1 }, Enum.Material.SmoothPlastic)
	board.CFrame = cframeOf(p) * CFrame.new(0, p.sy * 0.2, 0)
	board.Parent = model
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ad"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0
	gui.Brightness = 2
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Slogan"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(0.05, 0.05, 0.07)
	label.BackgroundTransparency = 0
	label.TextColor3 = Greybox.color(Palette.forAct(p.act).accent)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Text = Strings.get(Lore.slogan(p.index or 1, 1))
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.06, 0)
	padding.PaddingRight = UDim.new(0.06, 0)
	padding.PaddingTop = UDim.new(0.1, 0)
	padding.PaddingBottom = UDim.new(0.1, 0)
	padding.Parent = label
	model.PrimaryPart = board
	model:SetAttribute("Index", p.index or 1)
	model:SetAttribute("Act", p.act)
	CollectionService:AddTag(model, "Billboard")
	model.Parent = parent
end

local function buildJournal(p: Placement, parent: Instance)
	local journal = Lore.Journals[p.index or 1]
	local model = AssetCache.instance(p.id) or Greybox.model(p.id, p.act)
	model.Name = "Journal_" .. journal.id
	model:PivotTo(CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0))
	local base = model.PrimaryPart
	if base then
		base.CanQuery = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = Strings.get("prompt.journal")
		prompt.ObjectText = Strings.get(journal.titleKey)
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0.4
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Parent = base
		local light = Instance.new("PointLight")
		light.Range = 8
		light.Brightness = 0.8
		light.Color = Color3.new(1, 0.95, 0.8)
		light.Parent = base
	end
	model:SetAttribute("JournalId", journal.id)
	model:SetAttribute("Act", p.act)
	CollectionService:AddTag(model, "Journal")
	model.Parent = parent
end

local function buildNpc(p: Placement, parent: Instance)
	local model = NpcBuilder.create(p.id, cframeOf(p), "npc.homeless.name")
	local root = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.CanQuery = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = Strings.get("prompt.talk")
		prompt.ObjectText = Strings.get("npc.homeless.name")
		prompt.MaxActivationDistance = 10
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = root
	end
	if p.tag then
		CollectionService:AddTag(model, p.tag)
	end
	model.Parent = parent
end

-- Construit la ville dans Workspace.City. Renvoie le dossier racine.
function CityBuilder.build(city: Layout.City): Folder
	local existing = Workspace:FindFirstChild("City")
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "City"
	local folders: { [string]: Folder } = {}
	for _, kind in { "Roads", "Sidewalks", "Buildings", "Props", "Billboards", "Journals", "Npcs", "Plaza" } do
		local folder = Instance.new("Folder")
		folder.Name = kind
		folder.Parent = root
		folders[kind] = folder
	end
	local rng = PRNG.new(city.seed):fork("builder")
	local spawnPart: SpawnLocation? = nil
	for _, p in city.placements do
		if p.kind == "road" then
			solid(p, "Road", Palette.Road, Enum.Material.Asphalt).Parent = folders.Roads
		elseif p.kind == "sidewalk" then
			solid(p, "Sidewalk", Palette.Sidewalk, Enum.Material.Concrete).Parent = folders.Sidewalks
		elseif p.kind == "plaza" then
			solid(p, "Plaza", { 0.2, 0.2, 0.23 }, Enum.Material.Cobblestone).Parent = folders.Plaza
		elseif p.kind == "spawn" then
			local spawn = Instance.new("SpawnLocation")
			spawn.Name = "CitySpawn"
			spawn.Size = Vector3.new(p.sx, 1, p.sz)
			spawn.CFrame = CFrame.new(p.x, 0.9, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0)
			spawn.Anchored = true
			spawn.Neutral = true
			spawn.Duration = 0
			spawn.Transparency = 1
			spawn.CanCollide = false
			spawn.Parent = folders.Plaza
			spawnPart = spawn
		elseif p.kind == "building" then
			buildBuilding(p, rng, folders.Buildings)
		elseif p.kind == "prop" then
			buildProp(p, folders.Props)
		elseif p.kind == "billboard" then
			buildBillboard(p, folders.Billboards)
		elseif p.kind == "journal" then
			buildJournal(p, folders.Journals)
		elseif p.kind == "npc" then
			task.spawn(buildNpc, p, folders.Npcs)
		end
		-- les plots sont construits par PlotService
	end
	root:SetAttribute("Seed", city.seed)
	root:SetAttribute("Size", city.size)
	root.Parent = Workspace
	assert(spawnPart ~= nil, "spawn de la ville manquant")
	return root
end

return CityBuilder
