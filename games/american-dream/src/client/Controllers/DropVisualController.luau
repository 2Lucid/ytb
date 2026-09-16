--!strict
-- Les objets qui tombent du dropper et glissent sur le tapis. Purement visuel et local :
-- le serveur ne réplique aucune part (le revenu est calculé virtuellement dans EconomyService).
-- Plafond strict de parts vivantes par plot pour tenir 60 FPS sur mobile.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Machines = require(ReplicatedStorage.Shared.Config.Machines)
local MachineAnimator = require(script.Parent.MachineAnimator)

local DropVisualController = {}

local LOCAL_PLAYER = Players.LocalPlayer
local MAX_LIVE_DROPS = Economy.LIVE_DROPS_PER_PLOT
local MAX_DISTANCE = 200

local liveDrops = 0
local timers: { [Folder]: number } = {}

local function plotOf(line: Instance): Model?
	local plot = line:FindFirstAncestorOfClass("Model")
	while plot and plot:GetAttribute("PlotIndex") == nil do
		plot = plot:FindFirstAncestorOfClass("Model")
	end
	return plot
end

local function collectorFor(line: Folder, plot: Model): Model?
	local own = line:FindFirstChild("Collector")
	if own and own:IsA("Model") then
		return own
	end
	local shared = plot:FindFirstChild("Collector")
	if shared and shared:IsA("Model") then
		return shared
	end
	return nil
end

local function emit(line: Folder)
	local plot = plotOf(line)
	if plot == nil then
		return
	end
	local droppers = line:GetAttribute("Droppers")
	if type(droppers) ~= "number" or droppers <= 0 then
		return
	end
	local collector = collectorFor(line, plot)
	if collector == nil or collector.PrimaryPart == nil then
		return
	end
	local act = line:GetAttribute("Act")
	local actNumber = type(act) == "number" and act or 1
	local colorRgb = Machines.forAct(actNumber).productColor
	local dropColor = Color3.new(colorRgb[1], colorRgb[2], colorRgb[3])
	local travel = line:GetAttribute("FastConveyor") == true and Economy.CONVEYOR_TRAVEL_TIME_UPGRADED or Economy.CONVEYOR_TRAVEL_TIME
	local target = collector.PrimaryPart.CFrame
	for slot = 1, droppers do
		if liveDrops >= MAX_LIVE_DROPS then
			return
		end
		local dropper = line:FindFirstChild("Dropper_" .. slot)
		if dropper == nil or not dropper:IsA("Model") or dropper.PrimaryPart == nil then
			continue
		end
		local from = dropper.PrimaryPart.CFrame * CFrame.new(0, 1, 2.5)
		-- coupure à distance : rien n'est instancié si le joueur ne peut pas le voir
		local character = LOCAL_PLAYER.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - from.Position).Magnitude > MAX_DISTANCE then
			continue
		end
		liveDrops += 1
		local drop = MachineAnimator.spawnDrop(from, target, travel, dropColor)
		drop.Destroying:Once(function()
			liveDrops -= 1
		end)
	end
end

function DropVisualController.Init() end

function DropVisualController.Start()
	RunService.Heartbeat:Connect(function(dt: number)
		for _, plot in CollectionService:GetTagged("Plot") do
			local owner = plot:GetAttribute("OwnerUserId")
			-- n'anime que les plots proches (le sien et ceux visités)
			local lines = plot:FindFirstChild("Lines")
			if lines == nil then
				continue
			end
			for _, line in lines:GetChildren() do
				if not line:IsA("Folder") or line:GetAttribute("Active") ~= true then
					continue
				end
				local act = line:GetAttribute("Act")
				local actNumber = type(act) == "number" and act or 1
				local interval = Economy.tier(actNumber).dropInterval
				local timer = (timers[line] or 0) + dt
				if timer >= interval then
					timer -= interval
					if owner ~= nil then
						emit(line)
					end
				end
				timers[line] = timer
			end
		end
	end)
end

function DropVisualController.liveDrops(): number
	return liveDrops
end

return DropVisualController
