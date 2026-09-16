--!strict
-- Gabarit de sauvegarde et migrations versionnées. Pur.
-- Règles ProfileStore : pas de tables mixtes, pas de trous numériques, pas d'Instances ni de userdata.

local Types = require(script.Parent.Parent.Types)
local Economy = require(script.Parent.Parent.Config.Economy)

type PlayerData = Types.PlayerData

local SaveSchema = {}

SaveSchema.VERSION = 1
SaveSchema.STORE_NAME = "PlayerData_v1"
SaveSchema.LAYOUT_VARIANTS = 5

function SaveSchema.template(): PlayerData
	return {
		version = SaveSchema.VERSION,
		cash = 0,
		life = Economy.Life.max,
		renaissances = 0,
		highestActThisLife = 1,
		highestActEver = 1,
		plot = { owned = { A1_UNLOCK = true }, stored = 0, unpaidRent = 0 },
		journals = {},
		badges = {},
		purchases = {},
		stats = { totalEarned = 0, totalSpent = 0, playtime = 0, sessions = 0, firstJoin = 0, lastJoin = 0, burnouts = 0 },
		settings = { locale = "fr", musicVolume = 0.5, sfxVolume = 0.8 },
		layoutVariant = 0,
	}
end

-- Variante A/B stable : hachage de l'userId, jamais re-tirée
function SaveSchema.layoutVariantFor(userId: number): number
	local h = bit32.band(math.floor(userId) * 2654435761, 0xFFFFFFFF)
	return (h % SaveSchema.LAYOUT_VARIANTS) + 1
end

type Migration = (data: { [string]: any }) -> ()

local migrations: { [number]: Migration } = {
	-- [1] = function(data) ... end  -- migration de 1 vers 2
}

-- Applique les migrations manquantes puis ré-assainit les bornes. Idempotent.
function SaveSchema.migrate(data: { [string]: any }): PlayerData
	local version = tonumber(data.version) or 1
	while version < SaveSchema.VERSION do
		local step = migrations[version]
		if step then
			step(data)
		end
		version += 1
		data.version = version
	end
	return SaveSchema.sanitize(data)
end

local function clampNumber(value: any, min: number, max: number, default: number): number
	local n = tonumber(value)
	if n == nil or n ~= n then
		return default
	end
	return math.clamp(n, min, max)
end

-- Ramène les valeurs dans des bornes sûres (données corrompues ou d'anciennes versions)
function SaveSchema.sanitize(data: { [string]: any }): PlayerData
	local template = SaveSchema.template()
	data.cash = clampNumber(data.cash, 0, 1e18, 0)
	data.life = clampNumber(data.life, 0, Economy.Life.max, Economy.Life.max)
	data.renaissances = clampNumber(data.renaissances, 0, 10000, 0)
	data.highestActThisLife = clampNumber(data.highestActThisLife, 1, Economy.maxAct(), 1)
	data.highestActEver = clampNumber(data.highestActEver, 1, Economy.maxAct(), 1)
	if type(data.plot) ~= "table" then
		data.plot = template.plot
	end
	if type(data.plot.owned) ~= "table" then
		data.plot.owned = { A1_UNLOCK = true }
	end
	data.plot.owned.A1_UNLOCK = true
	data.plot.stored = clampNumber(data.plot.stored, 0, 1e18, 0)
	data.plot.unpaidRent = clampNumber(data.plot.unpaidRent, 0, 1e18, 0)
	for _, key in { "journals", "badges", "purchases" } do
		if type(data[key]) ~= "table" then
			data[key] = {}
		end
	end
	if type(data.stats) ~= "table" then
		data.stats = template.stats
	end
	if type(data.settings) ~= "table" then
		data.settings = template.settings
	end
	data.layoutVariant = clampNumber(data.layoutVariant, 0, SaveSchema.LAYOUT_VARIANTS, 0)
	data.version = SaveSchema.VERSION
	return (data :: any) :: PlayerData
end

return SaveSchema
