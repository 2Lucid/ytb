--!strict
-- Transition d'ambiance selon l'acte du joueur : brumeux et froid en acte 1, publicité aveuglante en acte 5.
-- Interpolation continue (jamais de coupure brutale) via TweenService.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Palette = require(ReplicatedStorage.Shared.WorldGen.Palette)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

type HudSnapshot = Types.HudSnapshot

local LightingController = {}

local TRANSITION = TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
local currentAct = 0

local function color(rgb: { number }): Color3
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

local function applyAct(act: number)
	if act == currentAct then
		return
	end
	currentAct = act
	local palette = Palette.forAct(act)
	TweenService:Create(Lighting, TRANSITION, {
		Ambient = color(palette.ambient),
		OutdoorAmbient = color(palette.ambient):Lerp(Color3.new(1, 1, 1), 0.25),
		FogColor = color(palette.fog),
		FogEnd = palette.fogEnd,
		FogStart = math.max(40, palette.fogEnd * 0.12),
		ClockTime = palette.clockTime,
		Brightness = 1.4 + act * 0.12,
		ExposureCompensation = -0.05 + act * 0.06,
	}):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, TRANSITION, {
			Density = math.max(0.1, 0.42 - act * 0.05),
			Haze = math.max(0.4, 1.8 - act * 0.25),
			Glare = 0.1 + act * 0.18,
			Color = color(palette.fog):Lerp(Color3.new(1, 1, 1), 0.4),
			Decay = color(palette.ambient),
		}):Play()
	end
	local correction = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if correction then
		TweenService:Create(correction, TRANSITION, {
			Saturation = -0.2 + act * 0.1,
			Contrast = act * 0.03,
			TintColor = color(palette.accent):Lerp(Color3.new(1, 1, 1), 0.82),
		}):Play()
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		TweenService:Create(bloom, TRANSITION, {
			Intensity = 0.4 + act * 0.22,
			Threshold = math.max(0.7, 1.4 - act * 0.12),
		}):Play()
	end
end

function LightingController.Init()
	applyAct(1)
end

function LightingController.Start()
	Remotes.getEvent("HudUpdate").OnClientEvent:Connect(function(snapshot: HudSnapshot)
		if type(snapshot.act) == "number" then
			applyAct(math.clamp(snapshot.act, 1, 5))
		end
	end)
	Remotes.getEvent("LifeEvent").OnClientEvent:Connect(function(kind: string)
		if kind == "burnout" then
			-- silence coupé net : tout s'assombrit d'un coup
			currentAct = 0
			TweenService:Create(Lighting, TweenInfo.new(1.2), { Brightness = 0.3, FogEnd = 80, ExposureCompensation = -1 }):Play()
		elseif kind == "renaissance" then
			applyAct(1)
		end
	end)
end

return LightingController
