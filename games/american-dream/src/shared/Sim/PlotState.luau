--!strict
-- Catalogue des achats d'un plot et règles de possession. Pur, dérivé de Config/Economy.

local Economy = require(script.Parent.Parent.Config.Economy)
local Types = require(script.Parent.Parent.Types)

type ShopItem = Types.ShopItem
type PlotData = Types.PlotData
type ItemId = Types.ItemId

local PlotState = {}

local catalog: { ShopItem } = {}
local byId: { [ItemId]: ShopItem } = {}

local function add(item: ShopItem)
	table.insert(catalog, item)
	byId[item.id] = item
end

for act, tier in Economy.Tiers do
	local prefix = "A" .. act .. "_"
	local unlockId = prefix .. "UNLOCK"
	add({
		id = unlockId,
		kind = "unlock",
		act = act,
		cost = tier.unlockCost,
		nameKey = "item.unlock." .. act,
		requires = act > 1 and { "A" .. (act - 1) .. "_UNLOCK" } or {},
	})
	for index, cost in tier.extraDropperCosts do
		local number = index + 1
		add({
			id = prefix .. "DROPPER_" .. number,
			kind = "dropper",
			act = act,
			cost = cost,
			nameKey = "item.dropper",
			requires = { number == 2 and unlockId or prefix .. "DROPPER_" .. (number - 1) },
		})
	end
	add({ id = prefix .. "UPGRADER", kind = "upgrader", act = act, cost = tier.upgraderCost, nameKey = "item.upgrader", requires = { unlockId } })
	add({ id = prefix .. "CONVEYOR", kind = "conveyor", act = act, cost = tier.conveyorCost, nameKey = "item.conveyor", requires = { unlockId } })
	for index, cost in tier.employeeCosts do
		if cost > 0 then
			add({
				id = prefix .. "EMPLOYEE_" .. index,
				kind = "employee",
				act = act,
				cost = cost,
				nameKey = "item.employee",
				requires = { index == 1 and unlockId or prefix .. "EMPLOYEE_" .. (index - 1) },
			})
		end
	end
	for index, cost in tier.decorCosts do
		add({ id = prefix .. "DECOR_" .. index, kind = "decor", act = act, cost = cost, nameKey = "item.decor." .. act .. "." .. index, requires = { unlockId } })
	end
end

function PlotState.catalog(): { ShopItem }
	return catalog
end

function PlotState.item(id: ItemId): ShopItem?
	return byId[id]
end

function PlotState.newPlot(): PlotData
	return { owned = { A1_UNLOCK = true }, stored = 0, unpaidRent = 0 }
end

-- Acte le plus haut débloqué (1 minimum)
function PlotState.act(owned: { [ItemId]: boolean }): number
	local act = 1
	for a = 2, Economy.maxAct() do
		if owned["A" .. a .. "_UNLOCK"] then
			act = a
		end
	end
	return act
end

function PlotState.dropperCount(owned: { [ItemId]: boolean }, act: number): number
	if not owned["A" .. act .. "_UNLOCK"] then
		return 0
	end
	local count = 1
	for n = 2, 4 do
		if owned["A" .. act .. "_DROPPER_" .. n] then
			count += 1
		end
	end
	return count
end

function PlotState.hasUpgrader(owned: { [ItemId]: boolean }, act: number): boolean
	return owned["A" .. act .. "_UPGRADER"] == true
end

function PlotState.hasConveyorUpgrade(owned: { [ItemId]: boolean }, act: number): boolean
	return owned["A" .. act .. "_CONVEYOR"] == true
end

function PlotState.employeeCount(owned: { [ItemId]: boolean }): number
	local count = 0
	for id in owned do
		if string.find(id, "_EMPLOYEE_") then
			count += 1
		end
	end
	return count
end

function PlotState.machineCount(owned: { [ItemId]: boolean }, act: number): number
	local count = PlotState.dropperCount(owned, act)
	if count > 0 then
		count += 2 -- tapis + collecteur de la ligne
		if PlotState.hasUpgrader(owned, act) then
			count += 1
		end
	end
	return count
end

-- Renvoie (ok, cléDeRaison). Raisons : "owned", "unknown", "requires", "cost"
function PlotState.canBuy(owned: { [ItemId]: boolean }, cash: number, id: ItemId): (boolean, string)
	local item = byId[id]
	if item == nil then
		return false, "shop.reason.unknown"
	end
	if owned[id] then
		return false, "shop.reason.owned"
	end
	for _, required in item.requires do
		if not owned[required] then
			return false, "shop.reason.requires"
		end
	end
	if cash < item.cost then
		return false, "shop.reason.cost"
	end
	return true, ""
end

-- Achats visibles : possédés non, prérequis remplis, triés par coût
function PlotState.available(owned: { [ItemId]: boolean }): { ShopItem }
	local list = {}
	for _, item in catalog do
		if not owned[item.id] then
			local ok = true
			for _, required in item.requires do
				if not owned[required] then
					ok = false
					break
				end
			end
			if ok then
				table.insert(list, item)
			end
		end
	end
	table.sort(list, function(a, b)
		return a.cost < b.cost
	end)
	return list
end

return PlotState
