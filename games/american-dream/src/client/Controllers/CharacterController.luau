--!strict
-- Animations du personnage joueur : idle épuisé sous 25 % de Vie, effondrement au burnout, réveil.
-- Chaque animation est optionnelle (identifiant absent = rien ne joue, aucun message d'erreur).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimationRegistry = require(ReplicatedStorage.Shared.AnimationRegistry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CharacterController = {}

local player = Players.LocalPlayer
local tracks: { [string]: AnimationTrack } = {}
local exhausted = false

local function animator(): Animator?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil then
		return nil
	end
	local found = humanoid:FindFirstChildOfClass("Animator")
	return found
end

local function track(name: string): AnimationTrack?
	local existing: AnimationTrack? = tracks[name]
	if existing then
		return existing
	end
	local animation = AnimationRegistry.instance(name)
	if animation == nil then
		return nil
	end
	local target = animator()
	if target == nil then
		return nil
	end
	local ok, loaded = pcall(function()
		return target:LoadAnimation(animation)
	end)
	if not ok or typeof(loaded) ~= "Instance" then
		return nil
	end
	local result = loaded :: AnimationTrack
	tracks[name] = result
	return result
end

function CharacterController.play(name: string, looped: boolean, priority: Enum.AnimationPriority?): AnimationTrack?
	local result = track(name)
	if result == nil then
		return nil
	end
	result.Looped = looped
	result.Priority = priority or Enum.AnimationPriority.Action
	result:Play(0.3)
	return result
end

function CharacterController.stop(name: string)
	local result: AnimationTrack? = tracks[name]
	if result then
		result:Stop(0.3)
	end
end

local function setExhausted(value: boolean)
	if value == exhausted then
		return
	end
	exhausted = value
	if value then
		CharacterController.play("ANM_PLR_Exhausted", true, Enum.AnimationPriority.Idle)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 13
		end
	else
		CharacterController.stop("ANM_PLR_Exhausted")
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = 18
		end
	end
end

function CharacterController.Init() end

function CharacterController.Start()
	player.CharacterAdded:Connect(function()
		table.clear(tracks)
		exhausted = false
	end)
	Remotes.getEvent("LifeEvent").OnClientEvent:Connect(function(kind: string)
		if kind == "exhausted" then
			setExhausted(true)
		elseif kind == "recovered" then
			setExhausted(false)
		elseif kind == "burnout" then
			CharacterController.play("ANM_PLR_Collapse", false, Enum.AnimationPriority.Action4)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 0
				humanoid.JumpPower = 0
			end
		elseif kind == "renaissance" then
			setExhausted(false)
			CharacterController.play("ANM_PLR_WakeUp", false, Enum.AnimationPriority.Action4)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.WalkSpeed = 18
				humanoid.JumpPower = 50
			end
		end
	end)
end

return CharacterController
