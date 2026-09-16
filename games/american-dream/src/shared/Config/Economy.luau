--!strict
-- Économie d'American Dream : source unique des chiffres de gameplay.
-- Tout est une hypothèse à valider par la télémétrie (LEDGER). Les tests `economy.spec` et `sim.spec`
-- garantissent que les invariants et les temps par tier restent dans la fourchette cible.

export type TierConfig = {
	act: number,
	nameKey: string, -- clé Strings
	unlockCost: number, -- coût d'entrée dans l'acte (achète la ligne : 1er dropper + tapis + collecteur)
	dropValue: number, -- revenu de base d'un drop
	dropInterval: number, -- secondes entre deux drops d'un dropper
	targetMinutes: number, -- temps théorique passé dans l'acte avant de pouvoir payer le suivant
	extraDropperCosts: { number }, -- droppers 2, 3, 4 (fraction du coût de l'acte suivant appliquée dans Economy.itemCost)
	upgraderCost: number,
	conveyorCost: number,
	employeeCosts: { number }, -- employés 1 et 2 (0 = indisponible dans cet acte)
	decorCosts: { number },
	rentPerMinute: number, -- loyer et charges prélevés toutes les 60 s (0 avant l'acte 2)
	lifeDrainPerMachine: number, -- points de Vie / minute par machine possédée dans cet acte
	lifeDrainPerEmployee: number,
	collectorCapMinutes: number, -- le collecteur plafonne à N minutes de production
}

export type MarketConfig = {
	minInterval: number,
	maxInterval: number,
	boomMultiplier: number,
	boomDuration: number,
	crashMultiplier: number,
	crashDuration: number,
	boomProbability: number,
}

export type OpaConfig = {
	requiredAct: number,
	siphonRatio: number,
	duration: number,
	costRatioOfTargetCash: number,
	minCost: number,
	attackerCooldown: number,
	buybackRatio: number,
}

export type LifeConfig = {
	max: number,
	exhaustedThreshold: number, -- sous ce ratio l'animation idle passe en "Exhausted"
	baseDrainPerMinute: number, -- respiration de base, toujours présente
	renaissanceMinAct: number, -- acte minimum atteint pour que le burnout donne un multiplicateur
	renaissanceBonus: number, -- multiplicateur = 1 + bonus * nbRenaissances
	voluntaryExitThreshold: number, -- la porte de secours s'ouvre sous ce ratio de Vie
}

local Economy = {}

Economy.CURRENCY = "Cash"
Economy.MAX_PLOTS = 6
Economy.LIVE_DROPS_PER_PLOT = 150 -- parts visuelles vivantes max par plot (côté client)
Economy.SAVE_INTERVAL = 120
Economy.RENT_INTERVAL = 60
Economy.EMPLOYEE_COLLECT_INTERVAL = 20
Economy.CONVEYOR_TRAVEL_TIME = 6 -- secondes entre le dropper et le collecteur (visuel + délai de crédit)
Economy.CONVEYOR_TRAVEL_TIME_UPGRADED = 3.5

Economy.Tiers = {
	{
		act = 1,
		nameKey = "act.1.name",
		unlockCost = 0,
		dropValue = 1,
		dropInterval = 2.0,
		targetMinutes = 2,
		extraDropperCosts = { 8, 15, 25 },
		upgraderCost = 40,
		conveyorCost = 20,
		employeeCosts = { 0, 0 },
		decorCosts = { 10, 20 },
		rentPerMinute = 0,
		lifeDrainPerMachine = 0.01,
		lifeDrainPerEmployee = 0,
		collectorCapMinutes = 30,
	},
	{
		act = 2,
		nameKey = "act.2.name",
		unlockCost = 500,
		dropValue = 8,
		dropInterval = 1.8,
		targetMinutes = 6,
		extraDropperCosts = { 120, 300, 600 },
		upgraderCost = 900,
		conveyorCost = 200,
		employeeCosts = { 500, 0 },
		decorCosts = { 100, 250 },
		rentPerMinute = 12,
		lifeDrainPerMachine = 0.03,
		lifeDrainPerEmployee = 0.08,
		collectorCapMinutes = 30,
	},
	{
		act = 3,
		nameKey = "act.3.name",
		unlockCost = 7500,
		dropValue = 60,
		dropInterval = 1.5,
		targetMinutes = 15,
		extraDropperCosts = { 4000, 9000, 18000 },
		upgraderCost = 24000,
		conveyorCost = 5000,
		employeeCosts = { 10000, 20000 },
		decorCosts = { 2000, 5000 },
		rentPerMinute = 180,
		lifeDrainPerMachine = 0.07,
		lifeDrainPerEmployee = 0.12,
		collectorCapMinutes = 30,
	},
	{
		act = 4,
		nameKey = "act.4.name",
		unlockCost = 120000,
		dropValue = 500,
		dropInterval = 1.2,
		targetMinutes = 35,
		extraDropperCosts = { 90000, 200000, 400000 },
		upgraderCost = 550000,
		conveyorCost = 100000,
		employeeCosts = { 220000, 480000 },
		decorCosts = { 40000, 90000 },
		rentPerMinute = 2200,
		lifeDrainPerMachine = 0.09,
		lifeDrainPerEmployee = 0.16,
		collectorCapMinutes = 30,
	},
	{
		act = 5,
		nameKey = "act.5.name",
		unlockCost = 2500000,
		dropValue = 5000,
		dropInterval = 1.0,
		targetMinutes = 70,
		extraDropperCosts = { 2000000, 4500000, 9000000 },
		upgraderCost = 12000000,
		conveyorCost = 2200000,
		employeeCosts = { 5000000, 11000000 },
		decorCosts = { 900000, 2000000 },
		rentPerMinute = 30000,
		lifeDrainPerMachine = 0.15,
		lifeDrainPerEmployee = 0.25,
		collectorCapMinutes = 30,
	},
} :: { TierConfig }

Economy.Market = {
	minInterval = 480,
	maxInterval = 600,
	boomMultiplier = 2,
	boomDuration = 60,
	crashMultiplier = 0.5,
	crashDuration = 45,
	boomProbability = 0.5,
} :: MarketConfig

Economy.Opa = {
	requiredAct = 5,
	siphonRatio = 0.05,
	duration = 120,
	costRatioOfTargetCash = 0.02,
	minCost = 250000,
	attackerCooldown = 300,
	buybackRatio = 1.0,
} :: OpaConfig

Economy.Life = {
	max = 100,
	exhaustedThreshold = 0.25,
	baseDrainPerMinute = 0.05,
	renaissanceMinAct = 3,
	renaissanceBonus = 0.25,
	voluntaryExitThreshold = 0.25,
} :: LifeConfig

-- Multiplicateurs de gamepass (aucun mur payant : tout est atteignable gratuitement, plus lentement)
Economy.Gamepass = {
	doubleCashMultiplier = 2,
	autoCollectInterval = 10,
}

-- Packs de cash (developer products) : exprimés en minutes de production théorique de l'acte courant,
-- pour rester équitables à tous les niveaux. Un premier pack bon marché fait plus de LTV qu'un gros pack.
Economy.CashPacks = {
	{ id = "pack_small", minutesOfIncome = 5 },
	{ id = "pack_medium", minutesOfIncome = 15 },
	{ id = "pack_large", minutesOfIncome = 40 },
}

function Economy.tier(act: number): TierConfig
	local tier = Economy.Tiers[act]
	assert(tier ~= nil, "acte inconnu : " .. tostring(act))
	return tier
end

function Economy.maxAct(): number
	return #Economy.Tiers
end

-- Multiplicateur permanent après N renaissances : 1 + 0.25 * N
function Economy.renaissanceMultiplier(renaissances: number): number
	return 1 + Economy.Life.renaissanceBonus * math.max(0, math.floor(renaissances))
end

return Economy
