--!strict
-- Journaux ramassables, PNJ de la ruelle, badges de lore. Les panneaux sont gérés côté client (texte par acte).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lore = require(ReplicatedStorage.Shared.Config.Lore)
local PlotState = require(ReplicatedStorage.Shared.Sim.PlotState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Strings)
local DataService = require(script.Parent.DataService)
local TelemetryService = require(script.Parent.TelemetryService)
local Badges = require(script.Parent.Parent.Badges)

local LoreService = {}

local MAX_PICKUP_DISTANCE = 14

local function distanceTo(player: Player, instance: Instance): number
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local part = if instance:IsA("Model") then instance.PrimaryPart else (if instance:IsA("BasePart") then instance else nil)
	if root == nil or not root:IsA("BasePart") or part == nil then
		return math.huge
	end
	return (root.Position - part.Position).Magnitude
end

local function collectJournal(player: Player, model: Instance)
	local data = DataService.getData(player)
	local id = model:GetAttribute("JournalId")
	if data == nil or type(id) ~= "string" then
		return
	end
	if distanceTo(player, model) > MAX_PICKUP_DISTANCE then
		return
	end
	if data.journals[id] then
		Remotes.getEvent("LoreEvent"):FireClient(player, "journal", { id = id, already = true })
		return
	end
	data.journals[id] = true
	local journal = Lore.journal(id)
	local count = 0
	for _ in data.journals do
		count += 1
	end
	Remotes.getEvent("LoreEvent"):FireClient(player, "journal", { id = id, already = false, count = count, total = #Lore.Journals })
	if journal then
		Remotes.getEvent("Notify"):FireClient(player, "notify.journal", { title = Strings.get(journal.titleKey, data.settings.locale) })
	end
	TelemetryService.custom(player, "journal", count, { id = id })
	if count >= #Lore.Journals then
		Badges.award(player, "all_journals")
	end
end

local function talk(player: Player, npc: Instance)
	local data = DataService.getData(player)
	if data == nil or distanceTo(player, npc) > MAX_PICKUP_DISTANCE then
		return
	end
	local act = math.max(PlotState.act(data.plot.owned), data.highestActEver >= 5 and 5 or 1)
	Remotes.getEvent("LoreEvent"):FireClient(player, "npc", { key = Lore.HOMELESS_LINES[act], act = act })
	TelemetryService.custom(player, "npc_talk", act)
end

local function wireJournal(model: Instance)
	local base = model:IsA("Model") and model.PrimaryPart or nil
	local prompt = base and base:FindFirstChild("Prompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player: Player)
			collectJournal(player, model)
		end)
	end
end

local function wireNpc(model: Instance)
	local root = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")) or nil
	local prompt = root and root:FindFirstChild("Prompt")
	if prompt and prompt:IsA("ProximityPrompt") then
		prompt.Triggered:Connect(function(player: Player)
			talk(player, model)
		end)
	end
end

function LoreService.sendState(player: Player)
	local data = DataService.getData(player)
	if data then
		Remotes.getEvent("LoreEvent"):FireClient(player, "owned", { journals = data.journals, total = #Lore.Journals })
	end
end

function LoreService.Init() end

function LoreService.Start()
	for _, journal in CollectionService:GetTagged("Journal") do
		wireJournal(journal)
	end
	CollectionService:GetInstanceAddedSignal("Journal"):Connect(wireJournal)
	for _, npc in CollectionService:GetTagged("HomelessNpc") do
		wireNpc(npc)
	end
	CollectionService:GetInstanceAddedSignal("HomelessNpc"):Connect(wireNpc)
	Players.PlayerRemoving:Connect(function() end)
end

return LoreService
