--!strict
-- OPA (acte 5) : PvP doux. L'attaquant paie, siphonne 5 % des revenus de la cible pendant 2 minutes,
-- la cible est prévenue et peut racheter ses parts. Tout est validé par OpaRules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local OpaRules = require(ReplicatedStorage.Shared.Sim.OpaRules)
local PlotState = require(ReplicatedStorage.Shared.Sim.PlotState)
local Progression = require(ReplicatedStorage.Shared.Sim.Progression)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local TelemetryService = require(script.Parent.TelemetryService)
local Badges = require(script.Parent.Parent.Badges)

type OpaState = Types.OpaState

local OpaService = {}

local activeByTarget: { [number]: OpaState } = {}
local cooldownUntil: { [number]: number } = {}
local firstOpa: { [number]: boolean } = {}

local function party(player: Player): OpaRules.Party?
	local data = DataService.getData(player)
	if data == nil then
		return nil
	end
	return { userId = player.UserId, act = PlotState.act(data.plot.owned), cash = data.cash }
end

local function notify(player: Player, key: string, params: { [string]: any })
	Remotes.getEvent("Notify"):FireClient(player, key, params)
end

local function candidates(player: Player): { { userId: number, name: string, cost: number } }
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local p = party(other)
			if p and p.act >= Economy.Opa.requiredAct then
				table.insert(list, { userId = other.UserId, name = other.DisplayName, cost = OpaRules.canAttack(party(player) or { userId = 0, act = 0, cash = 0 }, p, os.clock(), cooldownUntil[player.UserId] or 0, activeByTarget[other.UserId]) and select(3, OpaRules.canAttack(party(player) :: OpaRules.Party, p, os.clock(), 0, nil)) or select(3, OpaRules.canAttack({ userId = 0, act = 5, cash = 0 }, p, os.clock(), 0, nil)) })
			end
		end
	end
	return list
end

local function endOpa(state: OpaState, reason: string)
	if activeByTarget[state.targetUserId] ~= state then
		return
	end
	activeByTarget[state.targetUserId] = nil
	local target = Players:GetPlayerByUserId(state.targetUserId)
	local attacker = Players:GetPlayerByUserId(state.attackerUserId)
	if target then
		notify(target, reason == "buyback" and "notify.opa.buyback" or "notify.opa.ended", {})
		Remotes.getEvent("OpaEvent"):FireClient(target, "ended", { reason = reason })
	end
	if attacker then
		Remotes.getEvent("OpaEvent"):FireClient(attacker, "ended", { reason = reason })
	end
end

local function attack(player: Player, targetUserId: number)
	local target = Players:GetPlayerByUserId(targetUserId)
	local attackerParty = party(player)
	local targetParty = target and party(target)
	if target == nil or attackerParty == nil or targetParty == nil then
		notify(player, "opa.reason.target_act", {})
		return
	end
	local now = os.clock()
	local ok, reason, cost = OpaRules.canAttack(attackerParty, targetParty, now, cooldownUntil[player.UserId] or 0, activeByTarget[targetUserId])
	if not ok then
		notify(player, reason, { cost = cost })
		return
	end
	if not EconomyService.spendCash(player, cost, "Opa", "opa_attack") then
		notify(player, "opa.reason.cost", { cost = cost })
		return
	end
	local state = OpaRules.start(attackerParty, targetParty, now, cost)
	activeByTarget[targetUserId] = state
	cooldownUntil[player.UserId] = now + Economy.Opa.attackerCooldown
	notify(player, "notify.opa.launched", { name = target.DisplayName })
	notify(target, "notify.opa.attacked", { name = player.DisplayName })
	Remotes.getEvent("OpaEvent"):FireClient(target, "attacked", { attacker = player.DisplayName, buyback = OpaRules.buybackCost(state), endsIn = Economy.Opa.duration })
	Remotes.getEvent("OpaEvent"):FireClient(player, "launched", { target = target.DisplayName, endsIn = Economy.Opa.duration })
	TelemetryService.custom(player, "opa_attack", cost)
	if not firstOpa[player.UserId] then
		firstOpa[player.UserId] = true
		TelemetryService.onboarding(player, Progression.Steps.FIRST_OPA)
		Badges.award(player, "first_opa")
	end
	task.delay(Economy.Opa.duration, endOpa, state, "expired")
end

local function buyback(player: Player)
	local state = activeByTarget[player.UserId]
	if state == nil then
		return
	end
	local cost = OpaRules.buybackCost(state)
	if not EconomyService.spendCash(player, cost, "Opa", "opa_buyback") then
		notify(player, "opa.reason.cost", { cost = cost })
		return
	end
	TelemetryService.custom(player, "opa_buyback", cost)
	endOpa(state, "buyback")
end

function OpaService.Init()
	EconomyService.registerIncomeTax(function(player: Player, amount: number): (number, Player?)
		local state = activeByTarget[player.UserId]
		if state == nil then
			return 0, nil
		end
		local siphoned = OpaRules.split(amount, state, os.clock())
		if siphoned <= 0 then
			return 0, nil
		end
		return siphoned, Players:GetPlayerByUserId(state.attackerUserId)
	end)
end

function OpaService.Start()
	PlotService.OpaRequested:Connect(function(player: Player)
		Remotes.getEvent("OpaEvent"):FireClient(player, "open", { candidates = candidates(player), active = activeByTarget[player.UserId] ~= nil })
	end)
	RemoteGuard.connect(Remotes.getEvent("OpaAttack"), { RemoteGuard.isInteger(1) }, 1, 2, function(player: Player, targetUserId: any)
		attack(player, targetUserId :: number)
	end)
	RemoteGuard.connect(Remotes.getEvent("OpaBuyback"), {}, 1, 2, function(player: Player)
		buyback(player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local state = activeByTarget[player.UserId]
		if state then
			endOpa(state, "left")
		end
		cooldownUntil[player.UserId] = nil
		firstOpa[player.UserId] = nil
	end)
end

return OpaService
