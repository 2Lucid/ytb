--!strict
-- Types partagés entre serveur, client et tests.

export type ItemKind = "unlock" | "dropper" | "upgrader" | "conveyor" | "employee" | "decor"

export type ItemId = string -- ex : "A2_DROPPER_3", "A3_UPGRADER", "A1_UNLOCK"

export type PlotData = {
	owned: { [ItemId]: boolean },
	stored: number, -- cash en attente dans le collecteur
	unpaidRent: number,
}

export type PlayerData = {
	version: number,
	cash: number,
	life: number,
	renaissances: number,
	highestActThisLife: number,
	highestActEver: number,
	plot: PlotData,
	journals: { [string]: boolean },
	badges: { [string]: boolean },
	purchases: { [string]: boolean }, -- PurchaseId des developer products déjà traités
	stats: {
		totalEarned: number,
		totalSpent: number,
		playtime: number,
		sessions: number,
		firstJoin: number,
		lastJoin: number,
		burnouts: number,
	},
	settings: {
		locale: string,
		musicVolume: number,
		sfxVolume: number,
	},
	layoutVariant: number, -- 1..5 : variante de plot A/B assignée à la première connexion
}

export type MarketState = {
	kind: "none" | "boom" | "crash",
	multiplier: number,
	endsAt: number, -- os.clock côté serveur ; 0 si aucun
	nextAt: number,
}

export type OpaState = {
	attackerUserId: number,
	targetUserId: number,
	endsAt: number,
	ratio: number,
	cost: number,
}

export type HudSnapshot = {
	cash: number,
	life: number,
	act: number,
	renaissances: number,
	multiplier: number,
	stored: number,
	storedCap: number,
}

export type ShopItem = {
	id: ItemId,
	kind: ItemKind,
	act: number,
	cost: number,
	nameKey: string,
	requires: { ItemId },
}

return {}
