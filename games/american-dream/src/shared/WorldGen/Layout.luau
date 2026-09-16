--!strict
-- Génération procédurale de la ville : grille de blocs, routes, trottoirs, immeubles par quartier,
-- props, plots, panneaux, journaux, PNJ. Pur et déterministe (PRNG à graine fixe) : aucune API Roblox.
-- Le CityBuilder (serveur) transforme ces placements en Parts / MeshParts.

local World = require(script.Parent.Parent.Config.World)
local Layouts = require(script.Parent.Parent.Config.Layouts)
local Lore = require(script.Parent.Parent.Config.Lore)
local PRNG = require(script.Parent.Parent.Util.PRNG)

export type Vec = { x: number, y: number, z: number }

export type Placement = {
	kind: string, -- "road" | "sidewalk" | "building" | "prop" | "plot" | "billboard" | "journal" | "npc" | "plaza" | "spawn"
	id: string, -- identifiant de manifest (ex: MSH_CITY_BuildingBrick) ou primitive
	act: number, -- quartier (1..5)
	x: number,
	y: number,
	z: number,
	yaw: number,
	sx: number, -- taille (studs)
	sy: number,
	sz: number,
	floors: number?, -- immeubles : modules empilés
	style: string?, -- "brick" | "concrete" | "glass" | "gold"
	index: number?, -- plots : 1..6, panneaux : 1..12, journaux : rang
	tag: string?, -- tag CollectionService pour les animations client
}

export type City = {
	seed: number,
	size: number, -- côté total en studs
	placements: { Placement },
	plots: { Placement },
	billboards: { Placement },
	journals: { Placement },
	spawn: Placement,
	counts: { [string]: number },
}

local Layout = {}

local ACT_STYLES: { [number]: { string } } = {
	[1] = { "brick", "brick", "concrete" },
	[2] = { "concrete", "brick", "concrete" },
	[3] = { "concrete", "metal", "metal" },
	[4] = { "glass", "glass", "concrete" },
	[5] = { "gold", "glass", "gold" },
}

local PROPS_BY_ACT: { [number]: { string } } = {
	[1] = { "MSH_A1_DECO_Dumpster", "MSH_A1_DECO_TrashBags", "MSH_A1_DECO_Pallet", "MSH_A1_DECO_ShoppingCart", "MSH_A1_DECO_RustyBike", "MSH_A1_DECO_BentLamppost", "MSH_A1_DECO_Crate", "MSH_A1_DECO_Puddle", "MSH_CITY_Bench", "MSH_CITY_Hydrant" },
	[2] = { "MSH_A2_DECO_Gondola", "MSH_A2_DECO_GlassFridge", "MSH_A2_DECO_NeonOpen", "MSH_A2_DECO_WhiteVan", "MSH_A2_DECO_HandTruck", "MSH_A2_DECO_FruitCrates", "MSH_CITY_Bench", "MSH_CITY_TrashCan", "MSH_CITY_Taxi", "MSH_CITY_BusStop" },
	[3] = { "MSH_A3_DECO_ChemicalTank", "MSH_A3_DECO_ToxicBarrel", "MSH_A3_DECO_Container", "MSH_A3_DECO_Forklift", "MSH_A3_DECO_Generator", "MSH_A3_DECO_SafetySign", "MSH_A3_DECO_Chimney", "MSH_CITY_TrashCan" },
	[4] = { "MSH_A4_DECO_Photocopier", "MSH_A4_DECO_WaterCooler", "MSH_A4_DECO_PlasticPlant", "MSH_A4_DECO_AbstractSculpture", "MSH_CITY_Sedan", "MSH_CITY_PlanterTree", "MSH_CITY_Bench" },
	[5] = { "MSH_A5_DECO_GoldBars", "MSH_A5_DECO_MarbleStatue", "MSH_A5_DECO_ChampagneCart", "MSH_A5_DECO_GoldGlobe", "MSH_A5_DECO_BiometricGate", "MSH_CITY_PlanterTree", "MSH_CITY_Sedan" },
}

local BUILDING_ID: { [string]: string } = {
	brick = "MSH_CITY_BuildingBrick",
	concrete = "MSH_CITY_BuildingConcrete",
	glass = "MSH_CITY_BuildingGlass",
	metal = "MSH_CITY_BuildingConcrete",
	gold = "MSH_CITY_BuildingGlass",
}

local FLOOR_HEIGHT = 10

local function place(kind: string, id: string, act: number, x: number, z: number, yaw: number, sx: number, sy: number, sz: number): Placement
	return { kind = kind, id = id, act = act, x = x, y = sy / 2, z = z, yaw = yaw, sx = sx, sy = sy, sz = sz }
end

-- Anneau (distance de Chebyshev au centre) d'une cellule de grille
local function ring(i: number, j: number, center: number): number
	return math.max(math.abs(i - center), math.abs(j - center))
end

-- Acte d'une cellule : centre = ruelle, anneau 1 = plots, anneau 2 = commerce, anneau 3 = secteurs 3/4/5
local function actForCell(i: number, j: number, center: number): number
	local r = ring(i, j, center)
	if r <= 1 then
		return 1
	elseif r == 2 then
		return 2
	end
	local angle = math.deg(math.atan2(j - center, i - center)) -- -180..180
	if angle >= -180 and angle < -60 then
		return 3
	elseif angle >= -60 and angle < 60 then
		return 4
	end
	return 5
end

function Layout.generate(seed: number?): City
	local actualSeed = seed or World.SEED
	local rng = PRNG.new(actualSeed)
	local grid = World.GRID
	local block = World.BLOCK_SIZE
	local road = World.ROAD_WIDTH
	local pitch = block + road
	local size = grid * block + (grid + 1) * road
	local origin = -size / 2 + road -- coin du premier bloc
	local center = (grid + 1) / 2
	local placements: { Placement } = {}
	local plots: { Placement } = {}
	local billboards: { Placement } = {}
	local journals: { Placement } = {}
	local counts: { [string]: number } = {}

	local function add(p: Placement)
		table.insert(placements, p)
		counts[p.kind] = (counts[p.kind] or 0) + 1
	end

	-- Routes : bandes traversantes (grid + 1 dans chaque sens)
	for k = 0, grid do
		local offset = -size / 2 + k * pitch + road / 2
		add(place("road", "PRIM_Road", 1, offset, 0, 0, road, 0.4, size))
		add(place("road", "PRIM_Road", 1, 0, offset, 90, road, 0.4, size))
		-- plaques d'égout et feux aux intersections (échantillonnés)
		for m = 0, grid do
			local other = -size / 2 + m * pitch + road / 2
			if (k + m) % 3 == 0 then
				add(place("prop", "MSH_CITY_Manhole", 1, offset + 3, other - 3, 0, 3, 0.2, 3))
			end
			if k > 0 and k < grid and m > 0 and m < grid and (k + m) % 2 == 0 then
				local light = place("prop", "MSH_CITY_TrafficLight", 1, offset + road / 2 - 1, other + road / 2 - 1, 0, 1, 12, 1)
				light.tag = "TrafficLight"
				add(light)
			end
		end
	end

	-- Cellules
	local plotOrder = { { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 }, { 1, -1 }, { -1, 1 } } -- N, E, S, O, NE, SO
	local plotIndex = 0
	local billboardIndex = 0
	local journalSpots: { Placement } = {}
	for i = 1, grid do
		for j = 1, grid do
			local cx = origin + (i - 1) * pitch + block / 2
			local cz = origin + (j - 1) * pitch + block / 2
			local act = actForCell(i, j, center)
			local r = ring(i, j, center)
			local cellRng = rng:fork(string.format("cell_%d_%d", i, j))
			-- trottoirs autour du bloc
			local sw = World.SIDEWALK_WIDTH
			add(place("sidewalk", "PRIM_Sidewalk", act, cx, cz - block / 2 + sw / 2, 0, block, 0.6, sw))
			add(place("sidewalk", "PRIM_Sidewalk", act, cx, cz + block / 2 - sw / 2, 0, block, 0.6, sw))
			add(place("sidewalk", "PRIM_Sidewalk", act, cx - block / 2 + sw / 2, cz, 0, sw, 0.6, block))
			add(place("sidewalk", "PRIM_Sidewalk", act, cx + block / 2 - sw / 2, cz, 0, sw, 0.6, block))

			local isPlot = false
			if r == 1 then
				for index, offset in plotOrder do
					if i - center == offset[1] and j - center == offset[2] then
						isPlot = true
						plotIndex = index
					end
				end
			end
			if r == 0 then
				-- la place centrale : spawn, ruelle, PNJ
				local plaza = place("plaza", "PRIM_Plaza", 1, cx, cz, 0, block - 2 * sw, 0.8, block - 2 * sw)
				add(plaza)
				local spawn = place("spawn", "PRIM_Spawn", 1, cx, cz + 10, 180, 8, 1, 8)
				add(spawn)
				local npc = place("npc", "CHAR_Homeless", 1, cx - 18, cz - 12, 45, 3, 5, 3)
				npc.tag = "HomelessNpc"
				add(npc)
				for _, offset in { { -22, 20 }, { 22, 20 }, { -22, -22 }, { 22, -22 } } do
					local prop = place("prop", "MSH_A1_DECO_BentLamppost", 1, cx + offset[1], cz + offset[2], 0, 1.2, 14, 1.2)
					prop.tag = "StreetLight"
					add(prop)
				end
				add(place("prop", "MSH_A1_DECO_CardboardShelter", 1, cx - 24, cz - 8, 20, 6, 4, 5))
				add(place("prop", "MSH_A1_DECO_Dumpster", 1, cx + 20, cz - 14, 0, 7, 4.5, 4))
			elseif isPlot then
				local plotSize = Layouts.PLOT_SIZE
				local plot = place("plot", "PRIM_Plot", 1, cx, cz, 0, plotSize, Layouts.PLOT_HEIGHT, plotSize)
				plot.index = plotIndex
				-- le plot regarde vers la place centrale
				plot.yaw = math.deg(math.atan2(-(cx), -(cz)))
				add(plot)
				table.insert(plots, plot)
			else
				-- immeubles le long des quatre façades (modules de 20 studs), cour intérieure avec props
				local styles = ACT_STYLES[act]
				local maxFloors = World.MAX_FLOORS[act]
				local module = World.BLOCK
				local inner = block - 2 * sw
				local slots = math.floor(inner / module)
				local depth = module
				local function facade(side: number)
					for s = 1, slots do
						if cellRng:chance(0.18) then
							continue -- une dent creuse : parking, terrain vague
						end
						local floors = cellRng:int(math.max(1, maxFloors // 2), maxFloors)
						local style = cellRng:pick(styles)
						local along = -inner / 2 + module / 2 + (s - 1) * module
						local x, z, yaw
						if side == 1 then
							x, z, yaw = cx + along, cz - inner / 2 + depth / 2, 0
						elseif side == 2 then
							x, z, yaw = cx + along, cz + inner / 2 - depth / 2, 180
						elseif side == 3 then
							x, z, yaw = cx - inner / 2 + depth / 2, cz + along, 90
						else
							x, z, yaw = cx + inner / 2 - depth / 2, cz + along, 270
						end
						-- évite les doublons dans les coins : les côtés 3 et 4 sautent les extrémités
						if (side == 3 or side == 4) and (s == 1 or s == slots) then
							continue
						end
						local height = floors * FLOOR_HEIGHT
						local b = place("building", BUILDING_ID[style], act, x, z, yaw, module - 1, height, depth - 1)
						b.floors = floors
						b.style = style
						if act >= 4 and cellRng:chance(0.3) then
							b.tag = "NeonTower"
						end
						add(b)
					end
				end
				for side = 1, 4 do
					facade(side)
				end
				-- props dans la cour et sur les trottoirs
				local density = World.PROP_DENSITY[act]
				local propCount = math.floor(density * 6 + 0.5)
				for _ = 1, propCount do
					local id = cellRng:pick(PROPS_BY_ACT[act])
					local px = cx + cellRng:range(-inner / 2 + depth + 2, inner / 2 - depth - 2)
					local pz = cz + cellRng:range(-inner / 2 + depth + 2, inner / 2 - depth - 2)
					local p = place("prop", id, act, px, pz, cellRng:int(0, 359), 3, 3, 3)
					if id == "MSH_A3_DECO_Chimney" then
						p.sy = 30
						p.y = 15
						p.tag = "Chimney"
					elseif id == "MSH_A2_DECO_NeonOpen" then
						p.tag = "Neon"
					elseif id == "MSH_A1_DECO_Puddle" then
						p.sy = 0.1
						p.y = 0.05
						p.tag = "Puddle"
					end
					add(p)
				end
				-- lampadaires aux coins des trottoirs
				for _, corner in { { -1, -1 }, { 1, 1 } } do
					local lamp = place("prop", "MSH_CITY_Lamppost", act, cx + corner[1] * (block / 2 - 1.5), cz + corner[2] * (block / 2 - 1.5), 0, 1, 14, 1)
					lamp.tag = "StreetLight"
					add(lamp)
				end
				-- panneaux publicitaires : anneau 2, face à la place, 12 au total
				if r == 2 and billboardIndex < World.BILLBOARDS and cellRng:chance(0.85) then
					billboardIndex += 1
					local towardX = center - i
					local towardZ = center - j
					local yaw = math.deg(math.atan2(towardX, towardZ))
					local bb = place("billboard", "MSH_CITY_BillboardPole", act, cx - towardX * (block / 2 - 6), cz - towardZ * (block / 2 - 6), yaw, 16, 22, 1.5)
					bb.index = billboardIndex
					bb.tag = "Billboard"
					add(bb)
					table.insert(billboards, bb)
				end
				-- emplacements candidats pour les journaux
				local jx = cx + cellRng:range(-8, 8)
				local jz = cz + cellRng:range(-8, 8)
				table.insert(journalSpots, place("journal", "MSH_LORE_Journal", act, jx, jz, cellRng:int(0, 359), 1.5, 0.3, 1))
			end
		end
	end

	-- Journaux : un par entrée de Lore.Journals, choisi dans le quartier correspondant (3 dans la ruelle)
	local spotsByAct: { [number]: { Placement } } = {}
	for _, spot in journalSpots do
		spotsByAct[spot.act] = spotsByAct[spot.act] or {}
		table.insert(spotsByAct[spot.act], spot)
	end
	local alleySpots = {
		place("journal", "MSH_LORE_Journal", 1, 14, -16, 30, 1.5, 0.3, 1),
		place("journal", "MSH_LORE_Journal", 1, -26, 14, 120, 1.5, 0.3, 1),
		place("journal", "MSH_LORE_Journal", 1, 26, 24, 200, 1.5, 0.3, 1),
	}
	local usedAlley = 0
	local journalRng = rng:fork("journals")
	for rank, journal in Lore.Journals do
		local spot: Placement
		if journal.act == 1 then
			usedAlley += 1
			spot = alleySpots[((usedAlley - 1) % #alleySpots) + 1]
		else
			local candidates = spotsByAct[journal.act]
			if candidates and #candidates > 0 then
				local pick = journalRng:int(1, #candidates)
				spot = table.remove(candidates, pick) :: Placement
			else
				spot = alleySpots[1]
			end
		end
		local copy = table.clone(spot)
		copy.index = rank
		copy.id = "MSH_LORE_Journal"
		copy.tag = "Journal"
		copy.y = 1.5
		add(copy)
		table.insert(journals, copy)
	end

	-- Spawn
	local spawn: Placement? = nil
	for _, p in placements do
		if p.kind == "spawn" then
			spawn = p
		end
	end
	assert(spawn ~= nil, "spawn manquant")
	assert(#plots == World.PLOTS, "nombre de plots incorrect : " .. #plots)

	return {
		seed = actualSeed,
		size = size,
		placements = placements,
		plots = plots,
		billboards = billboards,
		journals = journals,
		spawn = spawn,
		counts = counts,
	}
end

return Layout
