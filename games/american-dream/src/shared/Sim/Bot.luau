--!strict
-- Bot glouton : joue "parfaitement" une session, seconde par seconde. Sert aux tests d'équilibrage
-- (sim.spec) et au job de réglage LEDGER. Aucune dépendance Roblox.

local Economy = require(script.Parent.Parent.Config.Economy)
local PlotState = require(script.Parent.PlotState)
local EconomyMath = require(script.Parent.EconomyMath)
local LifeMath = require(script.Parent.LifeMath)
local Types = require(script.Parent.Parent.Types)

type ItemId = Types.ItemId
type ShopItem = Types.ShopItem

local Bot = {}

export type Options = {
	maxSeconds: number,
	collectEvery: number, -- le bot marche jusqu'au collecteur toutes les N secondes
	renaissances: number,
	buyDecor: boolean,
	buyEmployees: boolean,
	hasDoubleCash: boolean,
	stopAtBurnout: boolean,
}

export type Timeline = {
	actReachedAt: { [number]: number }, -- acte -> seconde
	burnoutAt: number?, -- seconde du burnout (Vie = 0)
	finalCash: number,
	finalLife: number,
	purchases: { { id: ItemId, at: number } },
	seconds: number,
	totalRentPaid: number,
}

local KIND_PRIORITY: { [string]: number } = {
	unlock = 1,
	dropper = 2,
	upgrader = 3,
	employee = 4,
	conveyor = 5,
	decor = 6,
}

local function pickPurchase(owned: { [ItemId]: boolean }, cash: number, options: Options): ShopItem?
	local best: ShopItem? = nil
	local bestScore = math.huge
	for _, item in PlotState.available(owned) do
		if item.cost > cash then
			continue
		end
		if item.kind == "decor" and not options.buyDecor then
			continue
		end
		if item.kind == "employee" and not options.buyEmployees then
			continue
		end
		-- priorité par genre, puis par acte (le plus haut d'abord), puis par coût
		local score = KIND_PRIORITY[item.kind] * 1e12 - item.act * 1e9 + item.cost
		if score < bestScore then
			bestScore = score
			best = item
		end
	end
	return best
end

function Bot.defaultOptions(): Options
	return {
		maxSeconds = 4 * 3600,
		collectEvery = 15,
		renaissances = 0,
		buyDecor = false,
		buyEmployees = true,
		hasDoubleCash = false,
		stopAtBurnout = true,
	}
end

function Bot.run(options: Options): Timeline
	local owned: { [ItemId]: boolean } = { A1_UNLOCK = true }
	local cash = 0
	local stored = 0
	local life = Economy.Life.max
	local timeline: Timeline = {
		actReachedAt = { [1] = 0 },
		burnoutAt = nil,
		finalCash = 0,
		finalLife = life,
		purchases = {},
		seconds = 0,
		totalRentPaid = 0,
	}
	local multiplier = EconomyMath.globalMultiplier(options.renaissances, options.hasDoubleCash, 1)
	local employees = 0
	for second = 1, options.maxSeconds do
		-- production vers le collecteur (plafonnée)
		local income = EconomyMath.baseIncomePerSecond(owned) * multiplier
		stored = math.min(stored + income, EconomyMath.collectorCap(owned) * multiplier)
		-- collecte : le joueur passe toutes les N secondes, les employés toutes les 20 s
		if second % options.collectEvery == 0 or (employees > 0 and second % Economy.EMPLOYEE_COLLECT_INTERVAL == 0) then
			cash += stored
			stored = 0
		end
		-- loyer chaque minute
		if second % Economy.RENT_INTERVAL == 0 then
			local rent = EconomyMath.rentPerMinute(owned)
			local paid = math.min(rent, cash)
			cash -= paid
			timeline.totalRentPaid += paid
		end
		-- Vie
		life -= LifeMath.drainPerMinute(owned) / 60
		if life <= 0 then
			life = 0
			timeline.burnoutAt = second
			if options.stopAtBurnout then
				timeline.seconds = second
				break
			end
		end
		-- achats (plusieurs par seconde si possible)
		while true do
			local item = pickPurchase(owned, cash, options)
			if item == nil then
				break
			end
			cash -= item.cost
			owned[item.id] = true
			table.insert(timeline.purchases, { id = item.id, at = second })
			if item.kind == "unlock" and timeline.actReachedAt[item.act] == nil then
				timeline.actReachedAt[item.act] = second
			end
			if item.kind == "employee" then
				employees += 1
			end
		end
		timeline.seconds = second
	end
	timeline.finalCash = cash + stored
	timeline.finalLife = life
	return timeline
end

return Bot
