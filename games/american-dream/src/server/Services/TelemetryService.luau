--!strict
-- LEDGER côté jeu : entonnoir d'onboarding, progression par acte, flux d'économie, événements personnalisés.
-- Tout passe par AnalyticsService (tableaux de bord Roblox). Un collecteur HTTP externe est optionnel.

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Progression = require(ReplicatedStorage.Shared.Sim.Progression)
local TelemetryConfig = require(ReplicatedStorage.Shared.Config.Telemetry)

local TelemetryService = {}

local layoutOf: { [Player]: number } = {}
local sessionStart: { [Player]: number } = {}
local httpQueue: { { [string]: any } } = {}
local httpEnabled = false

local function fields(player: Player): { [string]: string }
	local variant = layoutOf[player] or 0
	return {
		[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = "layout_" .. tostring(variant),
	}
end

local function safe(label: string, fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok then
		warn("[Telemetry] " .. label .. " : " .. tostring(err))
	end
end

local function enqueue(event: string, player: Player?, payload: { [string]: any })
	if not httpEnabled then
		return
	end
	payload.event = event
	payload.userId = player and player.UserId or 0
	payload.layout = player and layoutOf[player] or 0
	payload.t = os.time()
	payload.placeId = game.PlaceId
	payload.jobId = game.JobId
	table.insert(httpQueue, payload)
	if #httpQueue > 500 then
		table.remove(httpQueue, 1)
	end
end

function TelemetryService.setLayout(player: Player, variant: number)
	layoutOf[player] = variant
end

function TelemetryService.onboarding(player: Player, step: number)
	safe("onboarding", function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, Progression.StepNames[step] or tostring(step), fields(player))
	end)
	enqueue("onboarding", player, { step = step })
end

function TelemetryService.actReached(player: Player, act: number)
	safe("progression", function()
		AnalyticsService:LogProgressionCompleteEvent(player, Progression.PROGRESSION_PATH, act, "act_" .. act, fields(player))
	end)
	local step = Progression.stepForAct(act)
	if step then
		TelemetryService.onboarding(player, step)
	end
	enqueue("act", player, { act = act })
end

function TelemetryService.economy(player: Player, flow: "source" | "sink", amount: number, balance: number, transactionType: string, sku: string?)
	if amount <= 0 then
		return
	end
	safe("economy", function()
		local flowType = flow == "source" and Enum.AnalyticsEconomyFlowType.Source or Enum.AnalyticsEconomyFlowType.Sink
		AnalyticsService:LogEconomyEvent(player, flowType, "Cash", math.floor(amount), math.max(0, math.floor(balance)), transactionType, sku or "", fields(player))
	end)
end

function TelemetryService.custom(player: Player?, name: string, value: number?, extra: { [string]: any }?)
	if player then
		safe("custom", function()
			AnalyticsService:LogCustomEvent(player, name, value or 1, fields(player))
		end)
	end
	local payload: { [string]: any } = {}
	if extra then
		for key, item in extra do
			payload[key] = item
		end
	end
	payload.value = value or 1
	enqueue(name, player, payload)
end

local function flushHttp()
	if not httpEnabled or #httpQueue == 0 then
		return
	end
	local batch = httpQueue
	httpQueue = {}
	local ok, err = pcall(function()
		HttpService:PostAsync(TelemetryConfig.COLLECTOR_URL, HttpService:JSONEncode({ key = TelemetryConfig.COLLECTOR_KEY, events = batch }), Enum.HttpContentType.ApplicationJson, false)
	end)
	if not ok then
		warn("[Telemetry] envoi HTTP échoué : " .. tostring(err))
	end
end

function TelemetryService.Init()
	httpEnabled = TelemetryConfig.COLLECTOR_URL ~= ""
	if httpEnabled then
		local ok = pcall(function()
			return HttpService.HttpEnabled
		end)
		if not ok then
			httpEnabled = false
		end
	end
end

function TelemetryService.Start()
	Players.PlayerAdded:Connect(function(player)
		sessionStart[player] = os.clock()
	end)
	Players.PlayerRemoving:Connect(function(player)
		local started = sessionStart[player]
		if started then
			local duration = os.clock() - started
			safe("session_end", function()
				AnalyticsService:LogCustomEvent(player, "session_seconds", math.floor(duration), fields(player))
			end)
			enqueue("session_end", player, { seconds = math.floor(duration) })
		end
		sessionStart[player] = nil
		layoutOf[player] = nil
	end)
	if httpEnabled then
		task.spawn(function()
			while true do
				task.wait(TelemetryConfig.FLUSH_INTERVAL)
				flushHttp()
			end
		end)
		game:BindToClose(flushHttp)
	end
end

return TelemetryService
