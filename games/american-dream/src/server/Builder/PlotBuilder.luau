--!strict
-- Construit et met à jour le modèle d'un plot : base, lignes de production, boutons d'achat, totem de Vie,
-- porte de secours, terminal OPA, bandeau boursier. Aucune logique de jeu ici : uniquement des Instances.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotLayout = require(ReplicatedStorage.Shared.WorldGen.PlotLayout)
local Palette = require(ReplicatedStorage.Shared.WorldGen.Palette)
local Machines = require(ReplicatedStorage.Shared.Config.Machines)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local PlotState = require(ReplicatedStorage.Shared.Sim.PlotState)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Format = require(ReplicatedStorage.Shared.Util.Format)
local Types = require(ReplicatedStorage.Shared.Types)
local Greybox = require(script.Parent.Greybox)
local AssetCache = require(script.Parent.AssetCache)
local NpcBuilder = require(script.Parent.NpcBuilder)

type Point = PlotLayout.Point
type Spec = PlotLayout.Spec
type ItemId = Types.ItemId

local PlotBuilder = {}

export type Context = {
	index: number,
	cframe: CFrame,
	spec: Spec,
	locale: string,
	skinAct: number, -- palette appliquée à la base (gamepass skins)
}

local function toCFrame(origin: CFrame, p: Point): CFrame
	return origin * CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0)
end

local function machine(id: string, act: number, targetSize: Vector3): Model
	local model = AssetCache.instance(id)
	if model then
		local extents = model:GetExtentsSize()
		local largest = math.max(extents.X, extents.Y, extents.Z)
		if largest > 0 then
			model:ScaleTo(math.max(targetSize.X, targetSize.Y, targetSize.Z) / largest)
		end
		return model
	end
	return Greybox.model(id, act)
end

local function placeModel(model: Model, origin: CFrame, p: Point)
	local extents = model:GetExtentsSize()
	model:PivotTo(toCFrame(origin, p) * CFrame.new(0, extents.Y / 2, 0))
end

local function lineFolder(plot: Model, act: number): Folder
	local lines = plot:FindFirstChild("Lines") :: Folder
	local name = "Line_" .. act
	local existing = lines:FindFirstChild(name)
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute("Act", act)
	folder:SetAttribute("Droppers", 0)
	folder:SetAttribute("Upgraded", false)
	folder:SetAttribute("FastConveyor", false)
	folder:SetAttribute("Active", false)
	folder.Parent = lines
	return folder
end

local function buildConveyor(plot: Model, ctx: Context, act: number)
	local folder = lineFolder(plot, act)
	if folder:FindFirstChild("Conveyor") then
		return
	end
	local line = ctx.spec.lines[act]
	local ids = Machines.forAct(act)
	local length = line.conveyorEnd.x - line.conveyorStart.x
	local model = machine(ids.conveyor, act, Vector3.new(length, 1, 3))
	model.Name = "Conveyor"
	local base = model.PrimaryPart
	if base and base:IsA("Part") then
		base.Size = Vector3.new(length, 0.8, 3)
		for _, child in model:GetChildren() do
			if child ~= base and child:IsA("BasePart") then
				child.Size = Vector3.new(length, child.Size.Y, child.Size.Z)
			end
		end
	end
	local mid: Point = { x = (line.conveyorStart.x + line.conveyorEnd.x) / 2, y = 0, z = line.conveyorStart.z, yaw = 0 }
	model:PivotTo(toCFrame(ctx.cframe, mid) * CFrame.new(0, 0.6, 0))
	model:SetAttribute("Length", length)
	model:SetAttribute("Act", act)
	CollectionService:AddTag(model, "Conveyor")
	model.Parent = folder
	-- collecteur de la ligne (ou partagé)
	local collectorParent: Instance = folder
	local collectorPoint = line.collector
	if ctx.spec.sharedCollector then
		collectorParent = plot
		if plot:FindFirstChild("Collector") then
			return
		end
	end
	local collector = machine(ids.collector, act, Vector3.new(7, 5, 6))
	collector.Name = "Collector"
	placeModel(collector, ctx.cframe, collectorPoint)
	local primary = collector.PrimaryPart
	if primary then
		primary.CanQuery = true
		primary.CanTouch = true
		primary.CanCollide = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = Strings.get("prompt.collect", ctx.locale)
		prompt.ObjectText = Strings.get("hud.collect", ctx.locale)
		prompt.MaxActivationDistance = 12
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Parent = primary
		local pad = Greybox.part("CollectPad", Vector3.new(6, 0.4, 5), Palette.Collector, Enum.Material.Neon)
		pad.CFrame = toCFrame(ctx.cframe, collectorPoint) * CFrame.new(0, 0.2, 5)
		pad.CanTouch = true
		pad.CanQuery = true
		pad.Parent = collector
	end
	collector:SetAttribute("Act", act)
	CollectionService:AddTag(collector, "Collector")
	collector.Parent = collectorParent
end

local function buildDropper(plot: Model, ctx: Context, act: number, slot: number)
	local folder = lineFolder(plot, act)
	local name = "Dropper_" .. slot
	if folder:FindFirstChild(name) then
		return
	end
	local line = ctx.spec.lines[act]
	local ids = Machines.forAct(act)
	local model = machine(ids.dropper, act, Vector3.new(4, 5, 4))
	model.Name = name
	placeModel(model, ctx.cframe, line.droppers[slot])
	model:SetAttribute("Act", act)
	model:SetAttribute("Slot", slot)
	CollectionService:AddTag(model, "Dropper")
	model.Parent = folder
	folder:SetAttribute("Droppers", slot)
	folder:SetAttribute("Active", true)
end

local function buildUpgrader(plot: Model, ctx: Context, act: number)
	local folder = lineFolder(plot, act)
	if folder:FindFirstChild("Upgrader") then
		return
	end
	local line = ctx.spec.lines[act]
	local ids = Machines.forAct(act)
	local model = machine(ids.upgrader, act, Vector3.new(6, 6, 3))
	model.Name = "Upgrader"
	placeModel(model, ctx.cframe, line.upgrader)
	model:SetAttribute("Act", act)
	CollectionService:AddTag(model, "Upgrader")
	model.Parent = folder
	folder:SetAttribute("Upgraded", true)
end

local function buildEmployee(plot: Model, ctx: Context, act: number, slot: number)
	local folder = lineFolder(plot, act)
	local name = "Employee_" .. slot
	if folder:FindFirstChild(name) then
		return
	end
	local line = ctx.spec.lines[act]
	local ids = Machines.forAct(act)
	task.spawn(function()
		local npc = NpcBuilder.create(ids.employee, toCFrame(ctx.cframe, line.employees[slot]), "npc.worker.name", ctx.locale)
		npc.Name = name
		npc:SetAttribute("Act", act)
		CollectionService:AddTag(npc, "Employee")
		npc.Parent = folder
	end)
end

local function buildDecor(plot: Model, ctx: Context, act: number, slot: number)
	local folder = lineFolder(plot, act)
	local name = "Decor_" .. slot
	if folder:FindFirstChild(name) then
		return
	end
	local line = ctx.spec.lines[act]
	local ids = Machines.forAct(act)
	local model = machine(ids.decor[slot] or ids.decor[1], act, Vector3.new(3, 4, 3))
	model.Name = name
	placeModel(model, ctx.cframe, line.decor[slot] or line.decor[1])
	model:SetAttribute("Act", act)
	CollectionService:AddTag(model, "Decor")
	model.Parent = folder
end

-- Applique un objet possédé au modèle (idempotent)
function PlotBuilder.applyItem(plot: Model, ctx: Context, itemId: ItemId)
	local item = PlotState.item(itemId)
	if item == nil then
		return
	end
	if item.kind == "unlock" then
		buildConveyor(plot, ctx, item.act)
		buildDropper(plot, ctx, item.act, 1)
	elseif item.kind == "dropper" then
		local slot = tonumber(string.match(itemId, "_DROPPER_(%d)$")) or 2
		buildDropper(plot, ctx, item.act, slot)
	elseif item.kind == "upgrader" then
		buildUpgrader(plot, ctx, item.act)
	elseif item.kind == "conveyor" then
		lineFolder(plot, item.act):SetAttribute("FastConveyor", true)
	elseif item.kind == "employee" then
		local slot = tonumber(string.match(itemId, "_EMPLOYEE_(%d)$")) or 1
		buildEmployee(plot, ctx, item.act, slot)
	elseif item.kind == "decor" then
		local slot = tonumber(string.match(itemId, "_DECOR_(%d)$")) or 1
		buildDecor(plot, ctx, item.act, slot)
	end
	plot:SetAttribute("Act", PlotState.act({ [itemId] = true }) > (plot:GetAttribute("Act") :: number? or 1) and PlotState.act({ [itemId] = true }) or plot:GetAttribute("Act"))
end

local function buttonLabel(item: Types.ShopItem, locale: string): string
	return Strings.get(item.nameKey, locale) .. "\n" .. Format.money(item.cost)
end

local function buildButton(plot: Model, ctx: Context, item: Types.ShopItem)
	local buttons = plot:FindFirstChild("Buttons") :: Folder
	local name = "Button_" .. item.id
	if buttons:FindFirstChild(name) then
		return
	end
	local point = ctx.spec.buttons[item.id]
	if point == nil then
		return
	end
	local button = Greybox.part(name, Vector3.new(4, 0.6, 4), Palette.ButtonLocked, Enum.Material.Neon, Enum.PartType.Cylinder)
	button.CFrame = toCFrame(ctx.cframe, point) * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
	button.CanTouch = true
	button.CanQuery = true
	button:SetAttribute("ItemId", item.id)
	button:SetAttribute("Cost", item.cost)
	button:SetAttribute("Act", item.act)
	button:SetAttribute("State", "locked")
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(160, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 4, 0)
	gui.MaxDistance = 60
	gui.AlwaysOnTop = false
	gui.Parent = button
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = buttonLabel(item, ctx.locale)
	label.Parent = gui
	CollectionService:AddTag(button, "PurchaseButton")
	button.Parent = buttons
end

-- Met à jour l'état visuel de tous les boutons selon les possessions et le cash
function PlotBuilder.refreshButtons(plot: Model, _ctx: Context, owned: { [ItemId]: boolean }, cash: number)
	local buttons = plot:FindFirstChild("Buttons") :: Folder
	for _, item in PlotState.catalog() do
		local button = buttons:FindFirstChild("Button_" .. item.id)
		if button == nil or not button:IsA("Part") then
			continue
		end
		if owned[item.id] then
			button:Destroy()
			continue
		end
		local unlocked = true
		for _, required in item.requires do
			if not owned[required] then
				unlocked = false
				break
			end
		end
		if not unlocked then
			button.Transparency = 1
			button.CanTouch = false
			button:SetAttribute("State", "locked")
			local label = button:FindFirstChild("Label")
			if label and label:IsA("BillboardGui") then
				label.Enabled = false
			end
		else
			button.Transparency = 0
			button.CanTouch = true
			local affordable = cash >= item.cost
			button.Color = Greybox.color(affordable and Palette.ButtonAvailable or Palette.ButtonLocked)
			button:SetAttribute("State", affordable and "available" or "expensive")
			local label = button:FindFirstChild("Label")
			if label and label:IsA("BillboardGui") then
				label.Enabled = true
			end
		end
	end
end

-- Construit le plot complet depuis les possessions
function PlotBuilder.build(ctx: Context, owned: { [ItemId]: boolean }, cash: number, life: number): Model
	local plot = Instance.new("Model")
	plot.Name = "Plot_" .. ctx.index
	plot:SetAttribute("PlotIndex", ctx.index)
	plot:SetAttribute("Variant", ctx.spec.variant)
	plot:SetAttribute("Act", PlotState.act(owned))
	plot:SetAttribute("Life", life)
	plot:SetAttribute("Stored", 0)
	plot:SetAttribute("StoredCap", 0)
	local size = ctx.spec.size
	local palette = Palette.forAct(ctx.skinAct)
	local base = Greybox.part("Base", Vector3.new(size, 1, size), Palette.Plot, Enum.Material.Concrete)
	base.CFrame = ctx.cframe * CFrame.new(0, 0.5, 0)
	base.CanCollide = true
	base.CanQuery = true
	base.Parent = plot
	plot.PrimaryPart = base
	for side = 1, 4 do
		local strip = Greybox.part("Border_" .. side, Vector3.new(size, 0.3, 0.6), palette.accent, Enum.Material.Neon)
		strip.CFrame = ctx.cframe * CFrame.Angles(0, math.rad(90 * side), 0) * CFrame.new(0, 1.1, size / 2 - 0.3)
		strip.Parent = plot
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size = Vector3.new(6, 0.4, 6)
	spawn.CFrame = toCFrame(ctx.cframe, ctx.spec.spawn) * CFrame.new(0, 1.2, 0)
	spawn.Anchored = true
	spawn.Enabled = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = plot
	local lines = Instance.new("Folder")
	lines.Name = "Lines"
	lines.Parent = plot
	local buttons = Instance.new("Folder")
	buttons.Name = "Buttons"
	buttons.Parent = plot
	-- totem de Vie
	local totem = machine(Machines.Gameplay.lifeTotem, 1, Vector3.new(2, 8, 2))
	totem.Name = "LifeTotem"
	local totemBase = totem.PrimaryPart
	if totemBase and totemBase:IsA("Part") then
		totemBase.Size = Vector3.new(1.5, 8, 1.5)
		totemBase.Material = Enum.Material.Neon
		totemBase.Color = Color3.new(0.3, 0.9, 0.6)
	end
	placeModel(totem, ctx.cframe, ctx.spec.lifeTotem)
	CollectionService:AddTag(totem, "LifeTotem")
	totem.Parent = plot
	-- porte de secours
	local door = machine(Machines.Gameplay.exitDoor, 1, Vector3.new(4, 7, 1))
	door.Name = "ExitDoor"
	local doorBase = door.PrimaryPart
	if doorBase and doorBase:IsA("Part") then
		doorBase.Size = Vector3.new(4, 7, 0.8)
		doorBase.Material = Enum.Material.Metal
		doorBase.Color = Color3.new(0.6, 0.15, 0.12)
		doorBase.CanQuery = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = Strings.get("exit.action", ctx.locale)
		prompt.ObjectText = Strings.get("exit.prompt", ctx.locale)
		prompt.MaxActivationDistance = 8
		prompt.HoldDuration = 1.5
		prompt.RequiresLineOfSight = false
		prompt.Enabled = true
		prompt.Parent = doorBase
	end
	placeModel(door, ctx.cframe, ctx.spec.exitDoor)
	CollectionService:AddTag(door, "ExitDoor")
	door.Parent = plot
	-- terminal OPA (acte 5)
	local terminal = machine(Machines.Gameplay.opaTerminal, 5, Vector3.new(3, 4, 1))
	terminal.Name = "OpaTerminal"
	local terminalBase = terminal.PrimaryPart
	if terminalBase and terminalBase:IsA("Part") then
		terminalBase.CanQuery = true
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "Prompt"
		prompt.ActionText = Strings.get("opa.title", ctx.locale)
		prompt.ObjectText = Strings.get("prompt.opa", ctx.locale)
		prompt.MaxActivationDistance = 8
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.Enabled = PlotState.act(owned) >= Economy.Opa.requiredAct
		prompt.Parent = terminalBase
	end
	placeModel(terminal, ctx.cframe, ctx.spec.opaTerminal)
	CollectionService:AddTag(terminal, "OpaTerminal")
	terminal.Parent = plot
	-- bandeau boursier : quatre pans autour du plot
	local ticker = Instance.new("Model")
	ticker.Name = "Ticker"
	local radius = ctx.spec.tickerRadius
	for side = 1, 4 do
		local pane = Greybox.part("Pane_" .. side, Vector3.new(radius * 2, 2.5, 0.4), { 0.05, 0.05, 0.07 }, Enum.Material.SmoothPlastic)
		pane.CFrame = ctx.cframe * CFrame.Angles(0, math.rad(90 * side), 0) * CFrame.new(0, 11, radius)
		pane.Parent = ticker
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Ticker"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.LightInfluence = 0
		gui.Brightness = 2
		gui.Parent = pane
		local label = Instance.new("TextLabel")
		label.Name = "Text"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Greybox.color(palette.accent)
		label.TextScaled = true
		label.Font = Enum.Font.Code
		label.Text = Strings.get("board.empty", ctx.locale)
		label.Parent = gui
	end
	CollectionService:AddTag(ticker, "Ticker")
	ticker.Parent = plot
	-- lignes possédées
	for _, item in PlotState.catalog() do
		if owned[item.id] then
			PlotBuilder.applyItem(plot, ctx, item.id)
		end
	end
	-- boutons
	for _, item in PlotState.catalog() do
		if not (item.kind == "unlock" and item.act == 1) and not owned[item.id] then
			buildButton(plot, ctx, item)
		end
	end
	PlotBuilder.refreshButtons(plot, ctx, owned, cash)
	CollectionService:AddTag(plot, "Plot")
	return plot
end

function PlotBuilder.setExitEnabled(plot: Model, enabled: boolean)
	local door = plot:FindFirstChild("ExitDoor")
	local base = door and (door :: Model).PrimaryPart
	local prompt = base and base:FindFirstChild("Prompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = enabled
	end
	if door then
		door:SetAttribute("Open", enabled)
	end
end

function PlotBuilder.setOpaEnabled(plot: Model, enabled: boolean)
	local terminal = plot:FindFirstChild("OpaTerminal")
	local base = terminal and (terminal :: Model).PrimaryPart
	local prompt = base and base:FindFirstChild("Prompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Enabled = enabled
	end
end

return PlotBuilder
