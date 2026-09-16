--!strict
-- Source unique de vérité pour le Cash : production virtuelle (drops discrets par ligne), collecte, loyers,
-- multiplicateurs (Renaissance, gamepass, marché), taxe d'OPA, HUD. Le client n'additionne jamais rien.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Economy = require(ReplicatedStorage.Shared.Config.Economy)
local EconomyMath = require(ReplicatedStorage.Shared.Sim.EconomyMath)
local PlotState = require(ReplicatedStorage.Shared.Sim.PlotState)
local Progression = require(ReplicatedStorage.Shared.Sim.Progression)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local PlotService = require(script.Parent.PlotService)
local TelemetryService = require(script.Parent.TelemetryService)

type PlayerData = Types.PlayerData
type HudSnapshot = Types.HudSnapshot
type ItemId = Types.ItemId

export type IncomeTax = (player: Player, amount: number) -> (number, Player?)

local EconomyService = {}

EconomyService.CashChanged = Signal.new() :: Signal.Signal<Player, number>
EconomyService.Collected = Signal.new() :: Signal.Signal<Player, number>

type Runtime = {
	accumulators: { [number]: number }, -- par acte : drops fractionnaires en attente
	dirty: boolean,
	lastHud: number,
	lastButtons: number,
	rentClock: number,
	firstCollect: boolean,
	flags: { [string]: boolean },
}

local runtimes: { [Player]: Runtime } = {}
local marketMultiplier = 1
local marketKind = "none"
local taxHooks: { IncomeTax } = {}

local HUD_INTERVAL = 0.25
local BUTTON_REFRESH_INTERVAL = 1

local function runtime(player: Player): Runtime
	local existing: Runtime? = runtimes[player]
	if existing then
		return existing
	end
	local created: Runtime = { accumulators = {}, dirty = true, lastHud = 0, lastButtons = 0, rentClock = 0, firstCollect = false, flags = {} }
	runtimes[player] = created
	return created
end

function EconomyService.setFlag(player: Player, flag: string, value: boolean)
	runtime(player).flags[flag] = value
	runtime(player).dirty = true
end

function EconomyService.hasFlag(player: Player, flag: string): boolean
	local rt: Runtime? = runtimes[player]
	return rt ~= nil and rt.flags[flag] == true
end

function EconomyService.setMarket(kind: string, multiplier: number)
	marketKind = kind
	marketMultiplier = multiplier
	for _, rt in runtimes do
		rt.dirty = true
	end
end

function EconomyService.marketMultiplier(): number
	return marketMultiplier
end

function EconomyService.registerIncomeTax(hook: IncomeTax)
	table.insert(taxHooks, hook)
end

function EconomyService.multiplierFor(player: Player, data: PlayerData): number
	return EconomyMath.globalMultiplier(data.renaissances, EconomyService.hasFlag(player, "double_cash"), marketMultiplier)
end

function EconomyService.snapshot(player: Player): HudSnapshot?
	local data = DataService.getData(player)
	if data == nil then
		return nil
	end
	return {
		cash = data.cash,
		life = data.life,
		act = PlotState.act(data.plot.owned),
		renaissances = data.renaissances,
		multiplier = EconomyService.multiplierFor(player, data),
		stored = data.plot.stored,
		storedCap = EconomyMath.collectorCap(data.plot.owned) * EconomyService.multiplierFor(player, data),
	}
end

function EconomyService.markDirty(player: Player)
	runtime(player).dirty = true
end

local function pushHud(player: Player, rt: Runtime, now: number)
	local snapshot = EconomyService.snapshot(player)
	if snapshot then
		Remotes.getEvent("HudUpdate"):FireClient(player, snapshot)
		PlotService.setAttribute(player, "Stored", math.floor(snapshot.stored))
		PlotService.setAttribute(player, "StoredCap", math.floor(snapshot.storedCap))
	end
	rt.dirty = false
	rt.lastHud = now
end

-- Ajoute du cash (taxe d'OPA appliquée). Renvoie le montant net crédité.
function EconomyService.addCash(player: Player, amount: number, reason: string, sku: string?): number
	local data = DataService.getData(player)
	if data == nil or amount <= 0 then
		return 0
	end
	local net = amount
	for _, hook in taxHooks do
		local taxed, beneficiary = hook(player, net)
		if taxed > 0 and beneficiary ~= nil then
			net -= taxed
			local target = DataService.getData(beneficiary)
			if target then
				target.cash += taxed
				target.stats.totalEarned += taxed
				runtime(beneficiary).dirty = true
			end
		end
	end
	data.cash += net
	data.stats.totalEarned += net
	runtime(player).dirty = true
	TelemetryService.economy(player, "source", net, data.cash, reason, sku)
	EconomyService.CashChanged:Fire(player, data.cash)
	return net
end

function EconomyService.spendCash(player: Player, amount: number, reason: string, sku: string?): boolean
	local data = DataService.getData(player)
	if data == nil or amount < 0 or data.cash < amount then
		return false
	end
	data.cash -= amount
	data.stats.totalSpent += amount
	runtime(player).dirty = true
	TelemetryService.economy(player, "sink", amount, data.cash, reason, sku)
	EconomyService.CashChanged:Fire(player, data.cash)
	return true
end

-- Vide le collecteur dans le cash. Renvoie le montant collecté.
function EconomyService.collect(player: Player, source: string): number
	local data = DataService.getData(player)
	if data == nil then
		return 0
	end
	local amount = math.floor(data.plot.stored)
	if amount <= 0 then
		return 0
	end
	data.plot.stored = 0
	local net = EconomyService.addCash(player, amount, "Gameplay", source)
	local rt = runtime(player)
	if not rt.firstCollect then
		rt.firstCollect = true
		TelemetryService.onboarding(player, Progression.Steps.FIRST_COLLECT)
	end
	EconomyService.Collected:Fire(player, net)
	return net
end

-- Production d'une seconde de jeu pour un joueur (appelée par la boucle)
local function produce(player: Player, data: PlayerData, rt: Runtime, dt: number)
	local owned = data.plot.owned
	local multiplier = EconomyService.multiplierFor(player, data)
	local cap = EconomyMath.collectorCap(owned) * multiplier
	local produced = 0
	for act = 1, Economy.maxAct() do
		local droppers = PlotState.dropperCount(owned, act)
		if droppers == 0 then
			continue
		end
		local tier = Economy.tier(act)
		local acc = (rt.accumulators[act] or -(EconomyMath.travelTime(owned, act) / tier.dropInterval)) + dt / tier.dropInterval * droppers
		local drops = math.floor(acc)
		if drops > 0 then
			acc -= drops
			produced += drops * EconomyMath.dropValue(owned, act) * multiplier
		end
		rt.accumulators[act] = acc
	end
	if produced > 0 then
		local before = data.plot.stored
		data.plot.stored = math.min(cap, data.plot.stored + produced)
		if data.plot.stored ~= before then
			rt.dirty = true
		end
	end
end

local function chargeRent(player: Player, data: PlayerData)
	local rent = EconomyMath.rentPerMinute(data.plot.owned)
	if rent <= 0 then
		return
	end
	local paid = math.min(rent, data.cash)
	if paid > 0 then
		EconomyService.spendCash(player, paid, "Rent")
	end
	if paid < rent then
		data.plot.unpaidRent += 1
		Remotes.getEvent("Notify"):FireClient(player, "notify.rent.unpaid", {})
	else
		Remotes.getEvent("Notify"):FireClient(player, "notify.rent", { amount = paid })
	end
end

local function step(dt: number)
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local data = DataService.getData(player)
		if data == nil then
			continue
		end
		local rt = runtime(player)
		produce(player, data, rt, dt)
		rt.rentClock += dt
		if rt.rentClock >= Economy.RENT_INTERVAL then
			rt.rentClock -= Economy.RENT_INTERVAL
			chargeRent(player, data)
		end
		data.stats.playtime += dt
		if rt.dirty and now - rt.lastHud >= HUD_INTERVAL then
			pushHud(player, rt, now)
		end
		if now - rt.lastButtons >= BUTTON_REFRESH_INTERVAL then
			rt.lastButtons = now
			PlotService.refreshButtons(player)
		end
	end
end

function EconomyService.sendState(player: Player)
	local rt = runtime(player)
	pushHud(player, rt, os.clock())
	Remotes.getEvent("MarketChanged"):FireClient(player, { kind = marketKind, multiplier = marketMultiplier })
end

function EconomyService.Init() end

function EconomyService.Start()
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed < 0.5 then
			return
		end
		local slice = elapsed
		elapsed = 0
		step(slice)
	end)
	PlotService.CollectRequested:Connect(function(player: Player)
		local amount = EconomyService.collect(player, "collector")
		if amount > 0 then
			Remotes.getEvent("Notify"):FireClient(player, "notify.collect", { amount = math.floor(amount) })
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		runtimes[player] = nil
	end)
	DataService.ProfileLoaded:Connect(function(player: Player)
		local data = DataService.getData(player)
		if data then
			TelemetryService.setLayout(player, data.layoutVariant)
			TelemetryService.onboarding(player, Progression.Steps.JOINED)
		end
		runtime(player).dirty = true
	end)
end

return EconomyService
