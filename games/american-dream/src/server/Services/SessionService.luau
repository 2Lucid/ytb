--!strict
-- Réglages du joueur et envoi de l'état complet à la demande du client (RequestState).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Strings)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local MarketEventService = require(script.Parent.MarketEventService)
local LeaderboardService = require(script.Parent.LeaderboardService)
local LoreService = require(script.Parent.LoreService)
local MonetizationService = require(script.Parent.MonetizationService)
local PlotService = require(script.Parent.PlotService)
local TelemetryService = require(script.Parent.TelemetryService)

local SessionService = {}

local function sendAll(player: Player)
	if DataService.getData(player) == nil then
		return
	end
	EconomyService.sendState(player)
	MarketEventService.sendState(player)
	LeaderboardService.sendState(player)
	LoreService.sendState(player)
	MonetizationService.sendState(player)
	local record = PlotService.getRecord(player)
	if record and record.ctx then
		Remotes.getEvent("PlotChanged"):FireClient(player, { index = record.index, variant = record.ctx.spec.variant })
	end
end

function SessionService.Init() end

function SessionService.Start()
	RemoteGuard.connect(Remotes.getEvent("RequestState"), {}, 0.5, 3, function(player: Player)
		sendAll(player)
	end)
	RemoteGuard.connect(Remotes.getEvent("SetSetting"), { RemoteGuard.oneOf({ "locale", "musicVolume", "sfxVolume" }), RemoteGuard.optional(RemoteGuard.isNumber(0, 1)), RemoteGuard.optional(RemoteGuard.isString(8)) }, 2, 4, function(player: Player, key: any, numberValue: any, stringValue: any)
		local data = DataService.getData(player)
		if data == nil then
			return
		end
		if key == "locale" and type(stringValue) == "string" then
			data.settings.locale = Strings.normalizeLocale(stringValue)
		elseif key == "musicVolume" and type(numberValue) == "number" then
			data.settings.musicVolume = numberValue
		elseif key == "sfxVolume" and type(numberValue) == "number" then
			data.settings.sfxVolume = numberValue
		end
	end)
	RemoteGuard.connect(Remotes.getEvent("ClientEvent"), { RemoteGuard.oneOf({ "shop_open", "journal_read", "settings_open", "tutorial_done" }), RemoteGuard.optional(RemoteGuard.isNumber(0, 1e9)) }, 1, 5, function(player: Player, name: any, value: any)
		TelemetryService.custom(player, "ui_" .. tostring(name), type(value) == "number" and value or 1)
	end)
	DataService.ProfileLoaded:Connect(function(player: Player)
		task.delay(1, sendAll, player)
	end)
end

return SessionService
