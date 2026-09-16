--!strict
-- Musique par acte, ambiances, effets. Chaque piste est optionnelle : un identifiant à 0 ne joue rien
-- et n'affiche aucune erreur (le jeu reste jouable avant le premier passage chez Suno / ElevenLabs).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AssetRegistry = require(ReplicatedStorage.Shared.AssetRegistry)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

type HudSnapshot = Types.HudSnapshot

local SoundController = {}

local MUSIC_BY_ACT = { "SFX_MUS_Act1", "SFX_MUS_Act2", "SFX_MUS_Act3", "SFX_MUS_Act4", "SFX_MUS_Act5" }
local AMBIENCE_BY_ACT = { "SFX_AMB_Alley", "SFX_AMB_Street", "SFX_AMB_Factory", "SFX_AMB_Office", "SFX_AMB_Penthouse" }

local currentAct = 0
local musicSound: Sound? = nil
local ambienceSound: Sound? = nil

local function group(name: string): SoundGroup?
	local found = SoundService:FindFirstChild(name)
	if found and found:IsA("SoundGroup") then
		return found
	end
	return nil
end

local function play(id: string, groupName: string, volume: number, previous: Sound?): Sound?
	local assetId = AssetRegistry.audio(id)
	if assetId <= 0 then
		return previous
	end
	local sound = Instance.new("Sound")
	sound.Name = id
	sound.SoundId = AssetRegistry.contentId(assetId)
	sound.Looped = true
	sound.Volume = 0
	sound.SoundGroup = group(groupName)
	sound.Parent = SoundService
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(2.5), { Volume = volume }):Play()
	if previous then
		local fade = TweenService:Create(previous, TweenInfo.new(2.5), { Volume = 0 })
		fade:Play()
		fade.Completed:Once(function()
			previous:Destroy()
		end)
	end
	return sound
end

function SoundController.playEffect(id: string, volume: number?)
	local assetId = AssetRegistry.audio(id)
	if assetId <= 0 then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = id
	sound.SoundId = AssetRegistry.contentId(assetId)
	sound.Volume = volume or 0.6
	sound.SoundGroup = group("SFX")
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(10, function()
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

local function applyAct(act: number)
	if act == currentAct then
		return
	end
	currentAct = act
	musicSound = play(MUSIC_BY_ACT[act] or MUSIC_BY_ACT[1], "Music", 0.45, musicSound)
	ambienceSound = play(AMBIENCE_BY_ACT[act] or AMBIENCE_BY_ACT[1], "Ambience", 0.5, ambienceSound)
end

function SoundController.Init() end

function SoundController.Start()
	applyAct(1)
	Remotes.getEvent("HudUpdate").OnClientEvent:Connect(function(snapshot: HudSnapshot)
		applyAct(math.clamp(snapshot.act, 1, 5))
	end)
	Remotes.getEvent("Notify").OnClientEvent:Connect(function(key: string)
		if key == "notify.collect" then
			SoundController.playEffect("SFX_UI_Collect", 0.4)
		elseif key == "notify.purchase" then
			SoundController.playEffect("SFX_UI_Purchase", 0.6)
		elseif key == "notify.rent" or key == "notify.rent.unpaid" then
			SoundController.playEffect("SFX_UI_Rent", 0.5)
		elseif key == "notify.act" then
			SoundController.playEffect("SFX_UI_TierUp", 0.7)
		elseif key == "notify.life.exhausted" then
			SoundController.playEffect("SFX_UI_Heartbeat", 0.5)
		end
	end)
	Remotes.getEvent("MarketChanged").OnClientEvent:Connect(function(payload: { [string]: any })
		if payload.kind == "boom" then
			SoundController.playEffect("SFX_EVT_BoomFanfare", 0.7)
		elseif payload.kind == "crash" then
			SoundController.playEffect("SFX_EVT_CrashAlarm", 0.7)
		end
	end)
	Remotes.getEvent("LifeEvent").OnClientEvent:Connect(function(kind: string)
		if kind == "burnout" then
			-- silence coupé net : c'est le moment le plus fort du jeu
			for _, sound in { musicSound, ambienceSound } do
				if sound then
					sound:Stop()
				end
			end
			currentAct = 0
		elseif kind == "renaissance" then
			SoundController.playEffect("SFX_MUS_Renaissance", 0.6)
			task.delay(6, applyAct, 1)
		end
	end)
end

return SoundController
