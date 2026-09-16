--!strict
-- Les employés collectent en AFK (et consomment de la Vie via LifeMath). Le gamepass auto-collecte sans employé.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local PlotState = require(ReplicatedStorage.Shared.Sim.PlotState)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)

local EmployeeService = {}

local lastEmployeeCollect: { [Player]: number } = {}
local lastAutoCollect: { [Player]: number } = {}

function EmployeeService.Init() end

function EmployeeService.Start()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.clock()
			for _, player in Players:GetPlayers() do
				local data = DataService.getData(player)
				if data == nil then
					continue
				end
				if PlotState.employeeCount(data.plot.owned) > 0 then
					local last = lastEmployeeCollect[player] or now
					lastEmployeeCollect[player] = last
					if now - last >= Economy.EMPLOYEE_COLLECT_INTERVAL then
						lastEmployeeCollect[player] = now
						EconomyService.collect(player, "employee")
					end
				end
				if EconomyService.hasFlag(player, "auto_collect") then
					local last = lastAutoCollect[player] or now
					lastAutoCollect[player] = last
					if now - last >= Economy.Gamepass.autoCollectInterval then
						lastAutoCollect[player] = now
						EconomyService.collect(player, "auto_collect")
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastEmployeeCollect[player] = nil
		lastAutoCollect[player] = nil
	end)
end

return EmployeeService
