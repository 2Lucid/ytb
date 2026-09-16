--!strict
-- Cinq variantes de disposition du plot (A/B test par hachage de l'userId, voir SaveSchema.layoutVariantFor).
-- PlotLayout.build(variant) transforme ces paramètres en positions concrètes. Les chiffres choisissent :
-- distance dropper-collecteur, position des boutons d'achat, orientation de la vue au spawn.

export type Variant = {
	name: string,
	lineSpacing: number, -- distance entre les lignes d'actes (studs)
	lineLength: number, -- longueur du tapis
	buttonsNearSpawn: boolean, -- boutons regroupés près du spawn ou le long de la ligne
	collectorAtCenter: boolean, -- un collecteur central partagé ou un par ligne
	spawnYaw: number, -- orientation de la vue au spawn (degrés)
	compact: boolean,
}

local Layouts = {}

Layouts.PLOT_SIZE = 72 -- studs, carré
Layouts.PLOT_HEIGHT = 1

Layouts.Variants = {
	{ name = "classique", lineSpacing = 12, lineLength = 30, buttonsNearSpawn = false, collectorAtCenter = false, spawnYaw = 0, compact = false },
	{ name = "compact", lineSpacing = 9, lineLength = 22, buttonsNearSpawn = true, collectorAtCenter = true, spawnYaw = 0, compact = true },
	{ name = "vitrine", lineSpacing = 12, lineLength = 34, buttonsNearSpawn = true, collectorAtCenter = false, spawnYaw = 180, compact = false },
	{ name = "central", lineSpacing = 11, lineLength = 26, buttonsNearSpawn = false, collectorAtCenter = true, spawnYaw = 90, compact = false },
	{ name = "couloir", lineSpacing = 8, lineLength = 36, buttonsNearSpawn = false, collectorAtCenter = false, spawnYaw = 270, compact = true },
} :: { Variant }

function Layouts.variant(index: number): Variant
	return Layouts.Variants[math.clamp(index, 1, #Layouts.Variants)]
end

return Layouts
