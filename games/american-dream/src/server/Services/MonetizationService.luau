--!strict
-- Gamepasses, developer products, PolicyService. Monétisation par la valeur : aucune offre n'expire,
-- aucun contenu aléatoire payant, les packs suivent la production du joueur (jamais un mur).

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local EconomyMath = require(ReplicatedStorage.Shared.Sim.EconomyMath)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Strings = require(ReplicatedStorage.Shared.Strings)
local RemoteGuard = require(script.Parent.Parent.RemoteGuard)
local DataService = require(script.Parent.DataService)
local EconomyService = require(script.Parent.EconomyService)
local TelemetryService = require(script.Parent.TelemetryService)

local MonetizationService = {}

local passesOwned: { [Player]: { [string]: boolean } } = {}
local policies: { [Player]: { [string]: any } } = {}

local function shopState(player: Player): { [string]: any }
	local data = DataService.getData(player)
	local packs: { [string]: number } = {}
	if data then
		for _, product in Monetization.DevProducts do
			packs[product.key] = EconomyMath.cashPackAmount(data.plot.owned, product.minutesOfIncome)
		end
	end
	local catalogPasses = {}
	for _, pass in Monetization.Gamepasses do
		table.insert(catalogPasses, { key = pass.key, id = pass.id, robux = pass.robux, owned = (passesOwned[player] or {})[pass.key] == true })
	end
	local catalogProducts = {}
	for _, product in Monetization.DevProducts do
		table.insert(catalogProducts, { key = product.key, id = product.id, robux = product.robux, amount = packs[product.key] or 0 })
	end
	return { passes = catalogPasses, products = catalogProducts }
end

function MonetizationService.sendState(player: Player)
	Remotes.getEvent("ShopState"):FireClient(player, shopState(player))
end

local function grantPass(player: Player, key: string, announce: boolean)
	local owned = passesOwned[player]
	if owned == nil then
		owned = {}
		passesOwned[player] = owned
	end
	if owned[key] then
		return
	end
	owned[key] = true
	EconomyService.setFlag(player, key, true)
	if announce then
		local pass = Monetization.gamepass(key)
		local data = DataService.getData(player)
		if pass then
			Remotes.getEvent("Notify"):FireClient(player, "notify.pass", { name = Strings.get(pass.nameKey, data and data.settings.locale or nil) })
		end
		TelemetryService.custom(player, "gamepass_" .. key, 1)
	end
	MonetizationService.sendState(player)
end

local function loadPasses(player: Player)
	for _, pass in Monetization.Gamepasses do
		if pass.id > 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, pass.id)
			end)
			if ok and owns == true then
				grantPass(player, pass.key, false)
			end
		end
	end
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	if ok and type(info) == "table" then
		policies[player] = info
	end
	MonetizationService.sendState(player)
end

function MonetizationService.policy(player: Player, key: string): boolean?
	local info = policies[player]
	if info == nil then
		return nil
	end
	local value = info[key]
	if type(value) == "boolean" then
		return value
	end
	return nil
end

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if player == nil then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = DataService.get(player)
	if profile == nil or not profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = profile.Data
	local purchaseId = tostring(receipt.PurchaseId)
	if data.purchases[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local product = Monetization.devProductById(receipt.ProductId)
	if product == nil then
		warn("[Monetization] produit inconnu : " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local amount = EconomyMath.cashPackAmount(data.plot.owned, product.minutesOfIncome)
	data.purchases[purchaseId] = true
	EconomyService.addCash(player, amount, "IAP", product.key)
	Remotes.getEvent("Notify"):FireClient(player, "notify.pack", { amount = amount })
	TelemetryService.custom(player, "devproduct_" .. product.key, receipt.CurrencySpent or 0)
	-- sauvegarde immédiate : un achat Robux ne doit jamais se perdre
	task.spawn(function()
		pcall(function()
			profile:Save()
		end)
	end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService.Init()
	MarketplaceService.ProcessReceipt = processReceipt
end

function MonetizationService.Start()
	DataService.ProfileLoaded:Connect(function(player: Player)
		task.spawn(loadPasses, player)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, purchased: boolean)
		if not purchased then
			return
		end
		local pass = Monetization.gamepassById(gamePassId)
		if pass then
			grantPass(player, pass.key, true)
		end
	end)
	RemoteGuard.connect(Remotes.getEvent("PromptPurchase"), { RemoteGuard.oneOf({ "pass", "product" }), RemoteGuard.isString(32) }, 1, 3, function(player: Player, kind: any, key: any)
		if kind == "pass" then
			local pass = Monetization.gamepass(key :: string)
			if pass and pass.id > 0 then
				MarketplaceService:PromptGamePassPurchase(player, pass.id)
			else
				Remotes.getEvent("Notify"):FireClient(player, "shop.unavailable", {})
			end
		else
			local product = Monetization.devProduct(key :: string)
			if product and product.id > 0 then
				MarketplaceService:PromptProductPurchase(player, product.id)
			else
				Remotes.getEvent("Notify"):FireClient(player, "shop.unavailable", {})
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		passesOwned[player] = nil
		policies[player] = nil
	end)
end

return MonetizationService
