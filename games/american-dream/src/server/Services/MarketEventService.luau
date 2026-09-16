--!strict
-- Booms et krachs toutes les 8 à 10 minutes, annoncés à tout le serveur.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MarketModel = require(ReplicatedStorage.Shared.Sim.MarketModel)
local PRNG = require(ReplicatedStorage.Shared.Util.PRNG)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local EconomyService = require(script.Parent.EconomyService)
local TelemetryService = require(script.Parent.TelemetryService)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

type MarketState = Types.MarketState

local MarketEventService = {}

local rng = PRNG.new(os.time() % 2147483647)
local state: MarketState = MarketModel.initial(os.clock(), rng)

local function broadcast()
	local payload = { kind = state.kind, multiplier = state.multiplier, endsIn = math.max(0, state.endsAt - os.clock()) }
	Remotes.getEvent("MarketChanged"):FireAllClients(payload)
end

local function announce(key: string, params: { [string]: any })
	for _, player in Players:GetPlayers() do
		Remotes.getEvent("Notify"):FireClient(player, key, params)
	end
end

function MarketEventService.sendState(player: Player)
	Remotes.getEvent("MarketChanged"):FireClient(player, { kind = state.kind, multiplier = state.multiplier, endsIn = math.max(0, state.endsAt - os.clock()) })
end

function MarketEventService.state(): MarketState
	return state
end

function MarketEventService.Init() end

function MarketEventService.Start()
	task.spawn(function()
		while true do
			task.wait(1)
			local event
			state, event = MarketModel.step(state, os.clock(), rng)
			if event == "boom" then
				EconomyService.setMarket("boom", state.multiplier)
				announce("notify.market.boom", { seconds = Economy.Market.boomDuration })
				TelemetryService.custom(nil, "market_boom", 1)
				broadcast()
			elseif event == "crash" then
				EconomyService.setMarket("crash", state.multiplier)
				announce("notify.market.crash", { seconds = Economy.Market.crashDuration })
				TelemetryService.custom(nil, "market_crash", 1)
				broadcast()
			elseif event == "end" then
				EconomyService.setMarket("none", 1)
				announce("notify.market.end", {})
				broadcast()
			end
		end
	end)
end

return MarketEventService
