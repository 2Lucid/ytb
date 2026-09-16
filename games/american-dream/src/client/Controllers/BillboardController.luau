--!strict
-- Les panneaux publicitaires changent de slogan selon l'acte du joueur qui les regarde.
-- C'est purement local : deux joueurs d'actes différents lisent deux phrases différentes sur le même panneau.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Lore = require(ReplicatedStorage.Shared.Config.Lore)
local Palette = require(ReplicatedStorage.Shared.WorldGen.Palette)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Types = require(ReplicatedStorage.Shared.Types)

type HudSnapshot = Types.HudSnapshot

local BillboardController = {}

local currentAct = 1
local locale = Strings.DEFAULT_LOCALE

local function labelOf(model: Instance): TextLabel?
	local board = model:FindFirstChild("Board")
	local gui = board and board:FindFirstChild("Ad")
	local label = gui and gui:FindFirstChild("Slogan")
	if label and label:IsA("TextLabel") then
		return label
	end
	return nil
end

local function apply(model: Instance, act: number, fade: boolean)
	local label = labelOf(model)
	if label == nil then
		return
	end
	local index = model:GetAttribute("Index")
	local text = Strings.get(Lore.slogan(type(index) == "number" and index or 1, act), locale)
	local rgb = Palette.forAct(act).accent
	local accent = Color3.new(rgb[1], rgb[2], rgb[3])
	if not fade then
		label.Text = text
		label.TextColor3 = accent
		return
	end
	local out = TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 1 })
	out:Play()
	out.Completed:Once(function()
		label.Text = text
		label.TextColor3 = accent
		TweenService:Create(label, TweenInfo.new(0.6), { TextTransparency = 0 }):Play()
	end)
end

local function applyAll(act: number, fade: boolean)
	for _, model in CollectionService:GetTagged("Billboard") do
		apply(model, act, fade)
	end
end

function BillboardController.Init() end

function BillboardController.Start()
	applyAll(currentAct, false)
	CollectionService:GetInstanceAddedSignal("Billboard"):Connect(function(model: Instance)
		apply(model, currentAct, false)
	end)
	Remotes.getEvent("HudUpdate").OnClientEvent:Connect(function(snapshot: HudSnapshot)
		local act = math.clamp(snapshot.act, 1, 5)
		if act ~= currentAct then
			currentAct = act
			applyAll(act, true)
		end
	end)
end

function BillboardController.setLocale(next: string)
	locale = Strings.normalizeLocale(next)
	applyAll(currentAct, false)
end

return BillboardController
