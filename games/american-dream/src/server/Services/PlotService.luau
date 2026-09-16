--!strict
-- Attribution des plots (6 par serveur), construction via PlotBuilder, interactions physiques
-- (boutons, collecteur, porte, terminal) transformées en signaux pour les autres services.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local PlotLayout = require(ReplicatedStorage.Shared.WorldGen.PlotLayout)
local LifeMath = require(ReplicatedStorage.Shared.Sim.LifeMath)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local PlotBuilder = require(script.Parent.Parent.Builder.PlotBuilder)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local TelemetryService = require(script.Parent.TelemetryService)
local Progression = require(ReplicatedStorage.Shared.Sim.Progression)

type ItemId = Types.ItemId

export type Record = {
	index: number,
	cframe: CFrame,
	owner: Player?,
	model: Model?,
	ctx: PlotBuilder.Context?,
	connections: { RBXScriptConnection },
	lastTouch: { [string]: number },
}

local PlotService = {}

PlotService.ButtonTouched = Signal.new() :: Signal.Signal<Player, ItemId>
PlotService.CollectRequested = Signal.new() :: Signal.Signal<Player>
PlotService.ExitRequested = Signal.new() :: Signal.Signal<Player>
PlotService.OpaRequested = Signal.new() :: Signal.Signal<Player>
PlotService.PlotClaimed = Signal.new() :: Signal.Signal<Player, Record>
PlotService.PlotReleased = Signal.new() :: Signal.Signal<Player>

local records: { [number]: Record } = {}
local byPlayer: { [Player]: Record } = {}
local plotsFolder: Folder? = nil

local TOUCH_DEBOUNCE = 0.6

local function folder(): Folder
	local existing = plotsFolder
	if existing then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "Plots"
	created.Parent = Workspace
	plotsFolder = created
	return created
end

local function disconnectAll(record: Record)
	for _, connection in record.connections do
		connection:Disconnect()
	end
	table.clear(record.connections)
end

local function ownerFromHit(record: Record, hit: BasePart): Player?
	local character = hit:FindFirstAncestorOfClass("Model")
	if character == nil then
		return nil
	end
	local player = Players:GetPlayerFromCharacter(character)
	if player == nil or player ~= record.owner then
		return nil
	end
	return player
end

local function debounced(record: Record, key: string): boolean
	local now = os.clock()
	local last = record.lastTouch[key] or 0
	if now - last < TOUCH_DEBOUNCE then
		return false
	end
	record.lastTouch[key] = now
	return true
end

local function wireModel(record: Record, model: Model)
	disconnectAll(record)
	-- boutons d'achat (présents et futurs)
	local buttons = model:FindFirstChild("Buttons")
	if buttons then
		local function wireButton(button: Instance)
			if not button:IsA("BasePart") then
				return
			end
			table.insert(record.connections, button.Touched:Connect(function(hit: BasePart)
				local player = ownerFromHit(record, hit)
				if player == nil then
					return
				end
				local itemId = button:GetAttribute("ItemId")
				if type(itemId) ~= "string" or not button.CanTouch then
					return
				end
				if debounced(record, "button_" .. itemId) then
					PlotService.ButtonTouched:Fire(player, itemId)
				end
			end))
		end
		for _, button in buttons:GetChildren() do
			wireButton(button)
		end
		table.insert(record.connections, buttons.ChildAdded:Connect(wireButton))
	end
	-- collecteurs
	local function wireCollector(collector: Instance)
		if not collector:IsA("Model") or collector.Name ~= "Collector" then
			return
		end
		local primary = collector.PrimaryPart
		local prompt = primary and primary:FindFirstChild("Prompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			table.insert(record.connections, prompt.Triggered:Connect(function(player: Player)
				if player == record.owner and debounced(record, "collect") then
					PlotService.CollectRequested:Fire(player)
				end
			end))
		end
		local pad = collector:FindFirstChild("CollectPad")
		if pad and pad:IsA("BasePart") then
			table.insert(record.connections, pad.Touched:Connect(function(hit: BasePart)
				local player = ownerFromHit(record, hit)
				if player and debounced(record, "collect") then
					PlotService.CollectRequested:Fire(player)
				end
			end))
		end
	end
	for _, descendant in model:GetDescendants() do
		wireCollector(descendant)
	end
	table.insert(record.connections, model.DescendantAdded:Connect(wireCollector))
	-- porte de secours et terminal OPA
	local function wirePrompt(name: string, signal: Signal.Signal<Player>)
		local holder = model:FindFirstChild(name)
		local primary = holder and (holder :: Model).PrimaryPart
		local prompt = primary and primary:FindFirstChild("Prompt")
		if prompt and prompt:IsA("ProximityPrompt") then
			table.insert(record.connections, prompt.Triggered:Connect(function(player: Player)
				if player == record.owner and debounced(record, name) then
					signal:Fire(player)
				end
			end))
		end
	end
	wirePrompt("ExitDoor", PlotService.ExitRequested)
	wirePrompt("OpaTerminal", PlotService.OpaRequested)
end

local function freeRecord(): Record?
	for index = 1, Economy.MAX_PLOTS do
		local record = records[index]
		if record and record.owner == nil then
			return record
		end
	end
	return nil
end

local function build(record: Record, player: Player)
	local data = DataService.getData(player)
	if data == nil then
		return
	end
	local ctx: PlotBuilder.Context = {
		index = record.index,
		cframe = record.cframe,
		spec = PlotLayout.build(data.layoutVariant),
		locale = data.settings.locale,
		skinAct = 1,
	}
	local model = PlotBuilder.build(ctx, data.plot.owned, data.cash, data.life)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model.Parent = folder()
	record.ctx = ctx
	record.model = model
	PlotBuilder.setExitEnabled(model, LifeMath.canExitVoluntarily(data.life, false))
	wireModel(record, model)
	local spawn = model:FindFirstChild("Spawn")
	if spawn and spawn:IsA("SpawnLocation") then
		player.RespawnLocation = spawn
	end
end

local function claim(player: Player)
	WorldService.waitUntilReady()
	if byPlayer[player] ~= nil or player.Parent ~= Players then
		return
	end
	local record = freeRecord()
	if record == nil then
		player:Kick("Serveur plein : aucun plot libre.")
		return
	end
	record.owner = player
	byPlayer[player] = record
	build(record, player)
	PlotService.teleportToPlot(player)
	Remotes.getEvent("Notify"):FireClient(player, "notify.plot", { plot = record.index })
	Remotes.getEvent("PlotChanged"):FireClient(player, { index = record.index, variant = record.ctx and record.ctx.spec.variant or 1 })
	TelemetryService.onboarding(player, Progression.Steps.PLOT_CLAIMED)
	PlotService.PlotClaimed:Fire(player, record)
end

local function release(player: Player)
	local record = byPlayer[player]
	if record == nil then
		return
	end
	byPlayer[player] = nil
	disconnectAll(record)
	if record.model then
		record.model:Destroy()
	end
	record.model = nil
	record.ctx = nil
	record.owner = nil
	table.clear(record.lastTouch)
	PlotService.PlotReleased:Fire(player)
end

function PlotService.Init()
	for index = 1, Economy.MAX_PLOTS do
		records[index] = {
			index = index,
			cframe = WorldService.plotCFrame(index),
			owner = nil,
			model = nil,
			ctx = nil,
			connections = {},
			lastTouch = {},
		}
	end
end

function PlotService.Start()
	DataService.ProfileLoaded:Connect(function(player: Player)
		task.spawn(claim, player)
	end)
	DataService.ProfileReleased:Connect(release)
	Players.PlayerRemoving:Connect(release)
end

function PlotService.getRecord(player: Player): Record?
	return byPlayer[player]
end

function PlotService.getModel(player: Player): Model?
	local record = byPlayer[player]
	return record and record.model or nil
end

function PlotService.getContext(player: Player): PlotBuilder.Context?
	local record = byPlayer[player]
	return record and record.ctx or nil
end

function PlotService.ownerOfIndex(index: number): Player?
	local record = records[index]
	return record and record.owner or nil
end

function PlotService.teleportToPlot(player: Player)
	local record = byPlayer[player]
	if record == nil then
		return
	end
	local spec = record.ctx and record.ctx.spec
	local character = player.Character
	if character and spec then
		local target = record.cframe * CFrame.new(spec.spawn.x, 4, spec.spawn.z) * CFrame.Angles(0, math.rad(spec.spawn.yaw), 0)
		character:PivotTo(target)
	end
end

-- Reconstruit entièrement le plot (après une Renaissance)
function PlotService.rebuild(player: Player)
	local record = byPlayer[player]
	if record == nil then
		return
	end
	disconnectAll(record)
	if record.model then
		record.model:Destroy()
		record.model = nil
	end
	build(record, player)
end

function PlotService.applyItem(player: Player, itemId: ItemId)
	local record = byPlayer[player]
	if record and record.model and record.ctx then
		PlotBuilder.applyItem(record.model, record.ctx, itemId)
	end
end

function PlotService.refreshButtons(player: Player)
	local record = byPlayer[player]
	local data = DataService.getData(player)
	if record and record.model and record.ctx and data then
		PlotBuilder.refreshButtons(record.model, record.ctx, data.plot.owned, data.cash)
	end
end

function PlotService.setAttribute(player: Player, name: string, value: any)
	local record = byPlayer[player]
	if record and record.model then
		record.model:SetAttribute(name, value)
	end
end

function PlotService.setExitEnabled(player: Player, enabled: boolean)
	local record = byPlayer[player]
	if record and record.model then
		PlotBuilder.setExitEnabled(record.model, enabled)
	end
end

function PlotService.setOpaEnabled(player: Player, enabled: boolean)
	local record = byPlayer[player]
	if record and record.model then
		PlotBuilder.setOpaEnabled(record.model, enabled)
	end
end

function PlotService.localeOf(player: Player): string
	local data = DataService.getData(player)
	return data and data.settings.locale or Strings.DEFAULT_LOCALE
end

function PlotService.records(): { [number]: Record }
	return records
end

return PlotService
