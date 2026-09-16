--!strict
-- Maths d'économie : revenus, multiplicateurs, plafonds, loyers. Pur.

local Economy = require(script.Parent.Parent.Config.Economy)
local PlotState = require(script.Parent.PlotState)
local Types = require(script.Parent.Parent.Types)

type ItemId = Types.ItemId

local EconomyMath = {}

-- Revenu par seconde d'une ligne d'acte (sans multiplicateurs globaux)
function EconomyMath.actIncomePerSecond(owned: { [ItemId]: boolean }, act: number): number
	local droppers = PlotState.dropperCount(owned, act)
	if droppers == 0 then
		return 0
	end
	local tier = Economy.tier(act)
	local perDropper = tier.dropValue / tier.dropInterval
	local upgrade = PlotState.hasUpgrader(owned, act) and 2 or 1
	return droppers * perDropper * upgrade
end

function EconomyMath.baseIncomePerSecond(owned: { [ItemId]: boolean }): number
	local total = 0
	for act = 1, Economy.maxAct() do
		total += EconomyMath.actIncomePerSecond(owned, act)
	end
	return total
end

-- Valeur d'un drop d'un acte (après upgrader, avant multiplicateurs globaux)
function EconomyMath.dropValue(owned: { [ItemId]: boolean }, act: number): number
	local tier = Economy.tier(act)
	return tier.dropValue * (PlotState.hasUpgrader(owned, act) and 2 or 1)
end

function EconomyMath.globalMultiplier(renaissances: number, hasDoubleCash: boolean, marketMultiplier: number): number
	local multiplier = Economy.renaissanceMultiplier(renaissances)
	if hasDoubleCash then
		multiplier *= Economy.Gamepass.doubleCashMultiplier
	end
	return multiplier * marketMultiplier
end

-- Plafond du collecteur : N minutes de production de base (minimum 50)
function EconomyMath.collectorCap(owned: { [ItemId]: boolean }): number
	local act = PlotState.act(owned)
	local minutes = Economy.tier(act).collectorCapMinutes
	return math.max(50, EconomyMath.baseIncomePerSecond(owned) * minutes * 60)
end

-- Loyer par minute : somme des loyers des actes débloqués (0 en acte 1)
function EconomyMath.rentPerMinute(owned: { [ItemId]: boolean }): number
	local rent = 0
	for act = 2, Economy.maxAct() do
		if owned["A" .. act .. "_UNLOCK"] then
			rent += Economy.tier(act).rentPerMinute
		end
	end
	return rent
end

-- Montant d'un pack de cash : minutes de production théorique de la base actuelle (minimum : 20 x coût du prochain achat le moins cher)
function EconomyMath.cashPackAmount(owned: { [ItemId]: boolean }, minutesOfIncome: number): number
	local income = EconomyMath.baseIncomePerSecond(owned) * 60 * minutesOfIncome
	local available = PlotState.available(owned)
	local floorAmount = 0
	if #available > 0 then
		floorAmount = available[1].cost * 2
	end
	return math.floor(math.max(income, floorAmount, 100))
end

function EconomyMath.opaCost(targetCash: number): number
	return math.max(Economy.Opa.minCost, math.floor(targetCash * Economy.Opa.costRatioOfTargetCash))
end

function EconomyMath.travelTime(owned: { [ItemId]: boolean }, act: number): number
	return PlotState.hasConveyorUpgrade(owned, act) and Economy.CONVEYOR_TRAVEL_TIME_UPGRADED or Economy.CONVEYOR_TRAVEL_TIME
end

-- Valeur nette affichée au classement : cash + valeur des achats
function EconomyMath.netWorth(owned: { [ItemId]: boolean }, cash: number): number
	local total = cash
	for id in owned do
		local item = PlotState.item(id)
		if item then
			total += item.cost
		end
	end
	return total
end

return EconomyMath
