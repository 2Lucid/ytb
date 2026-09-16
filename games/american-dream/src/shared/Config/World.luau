--!strict
-- Paramètres de génération de la ville. Même graine = même ville partout.

local World = {}

World.SEED = 20260814 -- date du lancement du projet
World.BLOCK = 20 -- taille d'un module d'immeuble (studs), conforme au manifest d'assets
World.ROAD_WIDTH = 16
World.SIDEWALK_WIDTH = 4
World.GRID = 7 -- ville de 7 x 7 blocs
World.BLOCK_SIZE = 80 -- côté d'un bloc (studs), plots inclus
World.MAX_FLOORS = { 2, 4, 6, 12, 16 } -- étages max par quartier (acte)
World.PROP_DENSITY = { 0.9, 0.7, 0.6, 0.4, 0.3 } -- densité de props par quartier
World.BILLBOARDS = 12
World.PLOTS = 6
World.PLAZA_RADIUS = 60

-- Le quartier de chaque bloc est déterminé par sa distance au centre (la ruelle est au centre,
-- la holding au bord) : la ville raconte les cinq actes en s'éloignant du spawn.
World.ZONE_RINGS = { 0, 1, 2, 3, 4 } -- anneau -> acte

return World
