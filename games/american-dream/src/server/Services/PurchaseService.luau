--!strict
-- Achats physiques (boutons) et par remote : validation serveur, construction incrémentale du plot,
-- progression d'acte, télémétrie. Une seule fonction décide : tryPurchase.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local PlotState = require(ReplicatedStorage.Shared.Sim.PlotState)
local Progression = require(ReplicatedStorage.Shared.Sim.Progression)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Strings)
local Types = require(ReplicatedStorage.Shared.Types)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local EconomyService = require(script.Parent.EconomyService)
local TelemetryService = require(script.Parent.TelemetryService)

type ItemId = Types.ItemId

local PurchaseService = {}

PurchaseService.Purchased = Signal.new() :: Signal.Signal<Player, ItemId>
PurchaseService.ActReached = Signal.new() :: Signal.Signal<Player, number>

local firsts: { [Player]: { [string]: boolean } } = {}

local function once(player: Player, key: string): boolean
	local set = firsts[player]
	if set == nil then
		set = {}
		firsts[player] = set
	end
	if set[key] then
		return false
	end
	set[key] = true
	return true
end

local function notify(player: Player, key: string, params: { [string]: any })
	Remotes.getEvent("Notify"):FireClient(player, key, params)
end

-- Renvoie (ok, cléDeRaison)
function PurchaseService.tryPurchase(player: Player, itemId: ItemId): (boolean, string)
	local data = DataService.getData(player)
	if data == nil then
		return false, "shop.reason.plot"
	end
	if PlotService.getModel(player) == nil then
		return false, "shop.reason.plot"
	end
	if DataService.isMock() and not game:GetService("RunService"):IsStudio() then
		return false, "notify.save_failed"
	end
	local ok, reason = PlotState.canBuy(data.plot.owned, data.cash, itemId)
	if not ok then
		return false, reason
	end
	local item = PlotState.item(itemId)
	if item == nil then
		return false, "shop.reason.unknown"
	end
	if not EconomyService.spendCash(player, item.cost, "Shop", itemId) then
		return false, "shop.reason.cost"
	end
	data.plot.owned[itemId] = true
	PlotService.applyItem(player, itemId)
	PlotService.refreshButtons(player)
	EconomyService.markDirty(player)
	local locale = data.settings.locale
	notify(player, "notify.purchase", { name = Strings.get(item.nameKey, locale) })
	if once(player, "purchase") then
		TelemetryService.onboarding(player, Progression.Steps.FIRST_PURCHASE)
	end
	if item.kind == "upgrader" and once(player, "upgrader") then
		TelemetryService.onboarding(player, Progression.Steps.FIRST_UPGRADER)
	elseif item.kind == "employee" then
		notify(player, "notify.employee", {})
		if once(player, "employee") then
			TelemetryService.onboarding(player, Progression.Steps.FIRST_EMPLOYEE)
		end
	elseif item.kind == "unlock" then
		local act = item.act
		if act > data.highestActThisLife then
			data.highestActThisLife = act
		end
		if act > data.highestActEver then
			data.highestActEver = act
		end
		PlotService.setAttribute(player, "Act", act)
		if act >= Economy.Opa.requiredAct then
			PlotService.setOpaEnabled(player, true)
		end
		notify(player, "notify.act", { act = act, name = Strings.get(Economy.tier(act).nameKey, locale) })
		TelemetryService.actReached(player, act)
		PurchaseService.ActReached:Fire(player, act)
	end
	PurchaseService.Purchased:Fire(player, itemId)
	return true, ""
end

function PurchaseService.Init() end

function PurchaseService.Start()
	PlotService.ButtonTouched:Connect(function(player: Player, itemId: ItemId)
		local ok, reason = PurchaseService.tryPurchase(player, itemId)
		if not ok and reason ~= "shop.reason.cost" then
			notify(player, reason, {})
		end
	end)
	RemoteGuard.connect(Remotes.getEvent("Purchase"), { RemoteGuard.isString(32) }, 4, 6, function(player: Player, itemId: any)
		local ok, reason = PurchaseService.tryPurchase(player, itemId :: string)
		if not ok then
			notify(player, reason, {})
		end
	end)
	RemoteGuard.connect(Remotes.getEvent("Collect"), {}, 2, 3, function(player: Player)
		local amount = EconomyService.collect(player, "hud")
		if amount > 0 then
			notify(player, "notify.collect", { amount = math.floor(amount) })
		end
	end)
	DataService.ProfileReleased:Connect(function(player: Player)
		firsts[player] = nil
	end)
end

return PurchaseService
