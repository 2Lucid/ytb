--!strict
-- Le lore : panneaux dont le slogan change avec la fortune, journaux ramassables, PNJ.
-- Les textes sont des clés Strings (FR + EN). Les slogans sont une première version à valider par le
-- propriétaire du projet : c'est là que vit le propos du jeu.

export type Journal = {
	id: string,
	act: number, -- quartier où il est posé
	titleKey: string,
	bodyKey: string,
}

local Lore = {}

-- 12 panneaux publicitaires : chaque panneau a un slogan par acte du joueur qui regarde
Lore.BILLBOARD_COUNT = 12

-- Retourne la clé du slogan pour un panneau et un acte : "ad.<index>.<act>"
function Lore.slogan(index: number, act: number): string
	local i = ((index - 1) % Lore.BILLBOARD_COUNT) + 1
	return string.format("ad.%d.%d", i, math.clamp(act, 1, 5))
end

Lore.Journals = {
	{ id = "J01", act = 1, titleKey = "journal.J01.title", bodyKey = "journal.J01.body" },
	{ id = "J02", act = 1, titleKey = "journal.J02.title", bodyKey = "journal.J02.body" },
	{ id = "J03", act = 1, titleKey = "journal.J03.title", bodyKey = "journal.J03.body" },
	{ id = "J04", act = 2, titleKey = "journal.J04.title", bodyKey = "journal.J04.body" },
	{ id = "J05", act = 2, titleKey = "journal.J05.title", bodyKey = "journal.J05.body" },
	{ id = "J06", act = 2, titleKey = "journal.J06.title", bodyKey = "journal.J06.body" },
	{ id = "J07", act = 3, titleKey = "journal.J07.title", bodyKey = "journal.J07.body" },
	{ id = "J08", act = 3, titleKey = "journal.J08.title", bodyKey = "journal.J08.body" },
	{ id = "J09", act = 3, titleKey = "journal.J09.title", bodyKey = "journal.J09.body" },
	{ id = "J10", act = 4, titleKey = "journal.J10.title", bodyKey = "journal.J10.body" },
	{ id = "J11", act = 4, titleKey = "journal.J11.title", bodyKey = "journal.J11.body" },
	{ id = "J12", act = 5, titleKey = "journal.J12.title", bodyKey = "journal.J12.body" },
} :: { Journal }

-- Le PNJ de la ruelle : une réplique par acte ; à l'acte 5 il révèle qui il est
Lore.HOMELESS_LINES = {
	[1] = "npc.homeless.1",
	[2] = "npc.homeless.2",
	[3] = "npc.homeless.3",
	[4] = "npc.homeless.4",
	[5] = "npc.homeless.5",
}

-- Phrases de la Renaissance : les slogans du début, retournés
Lore.RENAISSANCE_LINES = { "renaissance.line.1", "renaissance.line.2", "renaissance.line.3" }

function Lore.journal(id: string): Journal?
	for _, journal in Lore.Journals do
		if journal.id == id then
			return journal
		end
	end
	return nil
end

return Lore
