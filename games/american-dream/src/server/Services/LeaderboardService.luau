--!strict
-- Classement affiché comme un indice boursier : serveur (toutes les 30 s) et global (OrderedDataStore, budget respecté).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyMath = require(ReplicatedStorage.Shared.Sim.EconomyMath)
local PlotState = require(ReplicatedStorage.Shared.Sim.PlotState)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)

local LeaderboardService = {}

export type Row = { userId: number, name: string, worth: number, act: number, renaissances: number }

LeaderboardService.GLOBAL_ENABLED = true
local STORE_NAME = "NetWorth_v1"
local SERVER_INTERVAL = 30
local GLOBAL_INTERVAL = 120

local serverRows: { Row } = {}
local globalRows: { Row } = {}
local nameCache: { [number]: string } = {}
local orderedStore: OrderedDataStore? = nil

local function computeServerRows(): { Row }
	local rows: { Row } = {}
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		if data then
			table.insert(rows, {
				userId = player.UserId,
				name = player.DisplayName,
				worth = math.floor(EconomyMath.netWorth(data.plot.owned, data.cash)),
				act = PlotState.act(data.plot.owned),
				renaissances = data.renaissances,
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.worth > b.worth
	end)
	return rows
end

local function nameOf(userId: number): string
	local cached: string? = nameCache[userId]
	if cached then
		return cached
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = ok and tostring(result) or ("#" .. userId)
	nameCache[userId] = name
	return name
end

local function syncGlobal()
	local store = orderedStore
	if store == nil then
		return
	end
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		if data and not DataService.isMock() then
			local worth = math.floor(EconomyMath.netWorth(data.plot.owned, data.cash))
			pcall(function()
				store:SetAsync(tostring(player.UserId), worth)
			end)
		end
	end
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, 10)
	end)
	if ok and pages then
		local rows: { Row } = {}
		for _, entry in (pages :: DataStorePages):GetCurrentPage() do
			local userId = tonumber(entry.key) or 0
			table.insert(rows, { userId = userId, name = nameOf(userId), worth = tonumber(entry.value) or 0, act = 0, renaissances = 0 })
		end
		globalRows = rows
	end
end

function LeaderboardService.sendState(player: Player)
	Remotes.getEvent("LeaderboardChanged"):FireClient(player, { server = serverRows, global = globalRows })
end

function LeaderboardService.Init()
	if LeaderboardService.GLOBAL_ENABLED then
		local ok, store = pcall(function()
			return DataStoreService:GetOrderedDataStore(STORE_NAME)
		end)
		if ok then
			orderedStore = store
		end
	end
end

function LeaderboardService.Start()
	task.spawn(function()
		while true do
			serverRows = computeServerRows()
			Remotes.getEvent("LeaderboardChanged"):FireAllClients({ server = serverRows, global = globalRows })
			task.wait(SERVER_INTERVAL)
		end
	end)
	if orderedStore then
		task.spawn(function()
			while true do
				task.wait(GLOBAL_INTERVAL)
				syncGlobal()
			end
		end)
	end
end

return LeaderboardService
