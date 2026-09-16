--!strict
-- Catalogue de monétisation. Les identifiants sont à 0 tant que les produits n'existent pas sur le Creator Hub :
-- un identifiant à 0 désactive l'offre (jamais d'erreur, jamais de faux bouton).
-- Règles : aucun mur payant, tout est atteignable gratuitement, pas de loot box, pas de fausse rareté.

export type Gamepass = {
	key: "double_cash" | "auto_collect" | "base_skins" | "fast_renaissance",
	id: number,
	nameKey: string,
	descriptionKey: string,
	robux: number, -- prix affiché à titre indicatif, le vrai prix vient de MarketplaceService
}

export type DevProduct = {
	key: string,
	id: number,
	nameKey: string,
	minutesOfIncome: number,
	robux: number,
}

local Monetization = {}

Monetization.Gamepasses = {
	{ key = "double_cash", id = 0, nameKey = "shop.pass.double_cash.name", descriptionKey = "shop.pass.double_cash.desc", robux = 199 },
	{ key = "auto_collect", id = 0, nameKey = "shop.pass.auto_collect.name", descriptionKey = "shop.pass.auto_collect.desc", robux = 149 },
	{ key = "base_skins", id = 0, nameKey = "shop.pass.base_skins.name", descriptionKey = "shop.pass.base_skins.desc", robux = 99 },
	{ key = "fast_renaissance", id = 0, nameKey = "shop.pass.fast_renaissance.name", descriptionKey = "shop.pass.fast_renaissance.desc", robux = 79 },
} :: { Gamepass }

Monetization.DevProducts = {
	{ key = "pack_small", id = 0, nameKey = "shop.pack.small", minutesOfIncome = 5, robux = 25 },
	{ key = "pack_medium", id = 0, nameKey = "shop.pack.medium", minutesOfIncome = 15, robux = 65 },
	{ key = "pack_large", id = 0, nameKey = "shop.pack.large", minutesOfIncome = 40, robux = 150 },
} :: { DevProduct }

-- Badges (identifiants à 0 = désactivés)
Monetization.Badges = {
	first_renaissance = 0,
	act_5 = 0,
	all_journals = 0,
	first_opa = 0,
} :: { [string]: number }

function Monetization.gamepass(key: string): Gamepass?
	for _, pass in Monetization.Gamepasses do
		if pass.key == key then
			return pass
		end
	end
	return nil
end

function Monetization.gamepassById(id: number): Gamepass?
	if id == 0 then
		return nil
	end
	for _, pass in Monetization.Gamepasses do
		if pass.id == id then
			return pass
		end
	end
	return nil
end

function Monetization.devProduct(key: string): DevProduct?
	for _, product in Monetization.DevProducts do
		if product.key == key then
			return product
		end
	end
	return nil
end

function Monetization.devProductById(id: number): DevProduct?
	if id == 0 then
		return nil
	end
	for _, product in Monetization.DevProducts do
		if product.id == id then
			return product
		end
	end
	return nil
end

return Monetization
