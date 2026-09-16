--!strict
-- La jauge de Vie, le Burnout et la Renaissance (prestige). Le joueur n'est jamais prévenu au début.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local Lore = require(ReplicatedStorage.Shared.Config.Lore)
local LifeMath = require(ReplicatedStorage.Shared.Sim.LifeMath)
local PlotState = require(ReplicatedStorage.Shared.Sim.PlotState)
local Progression = require(ReplicatedStorage.Shared.Sim.Progression)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local TelemetryService = require(script.Parent.TelemetryService)
local Badges = require(script.Parent.Parent.Badges)

local LifeService = {}

LifeService.Renaissance = Signal.new() :: Signal.Signal<Player, number>

type State = { exhausted: boolean, warned: boolean, exitOpen: boolean, busy: boolean }
local states: { [Player]: State } = {}

local BURNOUT_CINEMATIC = 4.5

local function state(player: Player): State
	local existing: State? = states[player]
	if existing then
		return existing
	end
	local created: State = { exhausted = false, warned = false, exitOpen = false, busy = false }
	states[player] = created
	return created
end

local function fireLife(player: Player, kind: string, payload: { [string]: any })
	Remotes.getEvent("LifeEvent"):FireClient(player, kind, payload)
end

-- Réinitialise la vie du joueur : tout est vendu, le multiplicateur reste.
function LifeService.renaissance(player: Player, voluntary: boolean)
	local data = DataService.getData(player)
	local st = state(player)
	if data == nil or st.busy then
		return
	end
	st.busy = true
	local grantsBonus = LifeMath.renaissanceGrantsBonus(data.highestActThisLife)
	local actReached = data.highestActThisLife
	fireLife(player, "burnout", { bonus = grantsBonus, voluntary = voluntary, act = actReached })
	TelemetryService.custom(player, voluntary and "exit_voluntary" or "burnout", actReached, { act = actReached })
	if data.stats.burnouts == 0 then
		TelemetryService.onboarding(player, Progression.Steps.FIRST_BURNOUT)
	end
	data.stats.burnouts += 1
	task.wait(BURNOUT_CINEMATIC)
	if player.Parent ~= Players then
		st.busy = false
		return
	end
	data.cash = 0
	data.plot.stored = 0
	data.plot.unpaidRent = 0
	data.plot.owned = { A1_UNLOCK = true }
	data.life = Economy.Life.max
	data.highestActThisLife = 1
	if grantsBonus then
		data.renaissances += 1
		if data.renaissances == 1 then
			TelemetryService.onboarding(player, Progression.Steps.FIRST_RENAISSANCE)
			Badges.award(player, "first_renaissance")
		end
	end
	st.exhausted = false
	st.warned = false
	st.exitOpen = false
	PlotService.rebuild(player)
	PlotService.teleportToPlot(player)
	EconomyService.resetProduction(player)
	local multiplier = Economy.renaissanceMultiplier(data.renaissances)
	local lineKey = Lore.RENAISSANCE_LINES[((data.renaissances - 1) % #Lore.RENAISSANCE_LINES) + 1]
	fireLife(player, "renaissance", { multiplier = multiplier, bonus = grantsBonus, lineKey = lineKey, renaissances = data.renaissances })
	TelemetryService.custom(player, "renaissance", data.renaissances)
	LifeService.Renaissance:Fire(player, data.renaissances)
	st.busy = false
end

local function tick(player: Player, dt: number)
	local data = DataService.getData(player)
	if data == nil then
		return
	end
	local st = state(player)
	if st.busy then
		return
	end
	local drain = LifeMath.drainPerMinute(data.plot.owned) / 60 * dt
	data.life = math.max(0, data.life - drain)
	PlotService.setAttribute(player, "Life", data.life)
	local ratio = data.life / Economy.Life.max
	if ratio < 0.5 and not st.warned then
		st.warned = true
		Remotes.getEvent("Notify"):FireClient(player, "notify.life.low", {})
	end
	local exhausted = LifeMath.isExhausted(data.life)
	if exhausted ~= st.exhausted then
		st.exhausted = exhausted
		fireLife(player, exhausted and "exhausted" or "recovered", {})
		if exhausted then
			Remotes.getEvent("Notify"):FireClient(player, "notify.life.exhausted", {})
		end
	end
	local canExit = LifeMath.canExitVoluntarily(data.life, EconomyService.hasFlag(player, "fast_renaissance"))
	if canExit ~= st.exitOpen then
		st.exitOpen = canExit
		PlotService.setExitEnabled(player, canExit)
		if canExit then
			Remotes.getEvent("Notify"):FireClient(player, "notify.exit.open", {})
		end
	end
	if data.life <= 0 then
		task.spawn(LifeService.renaissance, player, false)
	end
end

local function requestExit(player: Player)
	local data = DataService.getData(player)
	if data == nil then
		return
	end
	if not LifeMath.canExitVoluntarily(data.life, EconomyService.hasFlag(player, "fast_renaissance")) then
		Remotes.getEvent("Notify"):FireClient(player, "notify.exit.locked", {})
		return
	end
	local futureMultiplier = Economy.renaissanceMultiplier(data.renaissances + (LifeMath.renaissanceGrantsBonus(data.highestActThisLife) and 1 or 0))
	fireLife(player, "exit_prompt", { multiplier = futureMultiplier, bonus = LifeMath.renaissanceGrantsBonus(data.highestActThisLife), act = PlotState.act(data.plot.owned) })
end

function LifeService.Init() end

function LifeService.Start()
	task.spawn(function()
		while true do
			local dt = task.wait(1)
			for _, player in Players:GetPlayers() do
				tick(player, dt)
			end
		end
	end)
	PlotService.ExitRequested:Connect(requestExit)
	RemoteGuard.connect(Remotes.getEvent("ExitDoor"), { RemoteGuard.isBoolean() }, 1, 2, function(player: Player, confirmed: any)
		if confirmed == true then
			local data = DataService.getData(player)
			if data and LifeMath.canExitVoluntarily(data.life, EconomyService.hasFlag(player, "fast_renaissance")) then
				task.spawn(LifeService.renaissance, player, true)
			end
		else
			requestExit(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
end

return LifeService
