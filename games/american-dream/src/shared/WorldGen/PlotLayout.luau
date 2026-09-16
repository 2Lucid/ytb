--!strict
-- Disposition des machines d'un plot pour une variante donnée. Pur : coordonnées locales au plot
-- (origine au centre, sol à y = 0). Le PlotBuilder les convertit en CFrame.

local Layouts = require(script.Parent.Parent.Config.Layouts)
local Economy = require(script.Parent.Parent.Config.Economy)
local PlotState = require(script.Parent.Parent.Sim.PlotState)

export type Point = { x: number, y: number, z: number, yaw: number }

export type Line = {
	act: number,
	droppers: { Point }, -- 4 emplacements
	conveyorStart: Point,
	conveyorEnd: Point,
	upgrader: Point,
	collector: Point,
	employees: { Point },
	decor: { Point },
}

export type Spec = {
	variant: number,
	size: number,
	spawn: Point,
	lines: { Line }, -- indexé par acte
	buttons: { [string]: Point }, -- itemId -> position du bouton d'achat
	exitDoor: Point,
	lifeTotem: Point,
	opaTerminal: Point,
	tickerRadius: number,
	sharedCollector: Point?,
}

local PlotLayout = {}

local function point(x: number, z: number, yaw: number?, y: number?): Point
	return { x = x, y = y or 0, z = z, yaw = yaw or 0 }
end

function PlotLayout.build(variantIndex: number): Spec
	local variant = Layouts.variant(variantIndex)
	local size = Layouts.PLOT_SIZE
	local half = size / 2
	local margin = 5
	local L = variant.lineLength
	local acts = Economy.maxAct()
	-- Les lignes sont empilées le long de Z : l'acte 1 est proche du spawn (z positif), l'acte 5 au fond.
	local firstZ = half - margin - 10
	local lines: { Line } = {}
	local buttons: { [string]: Point } = {}
	local sharedCollector: Point? = nil
	local collectorX = L / 2 + 5
	if variant.collectorAtCenter then
		sharedCollector = point(collectorX, firstZ - ((acts - 1) * variant.lineSpacing) / 2, 270, 0)
	end
	for act = 1, acts do
		local z = firstZ - (act - 1) * variant.lineSpacing
		local droppers = {}
		for slot = 1, 4 do
			-- les droppers sont alignés au début du tapis, séparés de 4 studs
			table.insert(droppers, point(-L / 2 + (slot - 1) * 4 - 2, z, 180, 0))
		end
		local collector = if sharedCollector then sharedCollector else point(collectorX, z, 270, 0)
		local line: Line = {
			act = act,
			droppers = droppers,
			conveyorStart = point(-L / 2, z, 0, 0),
			conveyorEnd = point(L / 2, z, 0, 0),
			upgrader = point(L / 6, z, 0, 0),
			collector = collector,
			employees = { point(L / 2 - 6, z + 3.5, 90, 0), point(-L / 2 + 10, z + 3.5, 90, 0) },
			decor = { point(-L / 2 - 6, z, 90, 0), point(L / 2 - 2, z - 3.5, 0, 0) },
		}
		lines[act] = line
	end
	-- Boutons d'achat : près du spawn (grille) ou le long de la ligne concernée
	local catalog = PlotState.catalog()
	if variant.buttonsNearSpawn then
		local column = 0
		local row = 0
		for _, item in catalog do
			if item.kind == "unlock" and item.act == 1 then
				continue
			end
			local x = -half + margin + column * 6
			local z = half - margin - row * 6
			buttons[item.id] = point(x, z, 0, 0)
			column += 1
			if column >= 4 then
				column = 0
				row += 1
			end
		end
	else
		local perLine: { [number]: number } = {}
		for _, item in catalog do
			if item.kind == "unlock" and item.act == 1 then
				continue
			end
			local line = lines[item.act]
			local index = perLine[item.act] or 0
			perLine[item.act] = index + 1
			-- une rangée de boutons 4 studs devant la ligne, espacés de 5 studs
			buttons[item.id] = point(-L / 2 + index * 5, line.conveyorStart.z - 4.5, 0, 0)
		end
	end
	local spawnYaw = variant.spawnYaw
	local spec: Spec = {
		variant = variantIndex,
		size = size,
		spawn = point(0, half - margin - 2, spawnYaw, 0),
		lines = lines,
		buttons = buttons,
		exitDoor = point(half - margin, -half + margin, 225, 0),
		lifeTotem = point(-half + margin + 2, half - margin - 2, 0, 0),
		opaTerminal = point(half - margin - 2, firstZ - (acts - 1) * variant.lineSpacing - 6, 180, 0),
		tickerRadius = half + 3,
		sharedCollector = sharedCollector,
	}
	return spec
end

-- Toutes les positions "machine" d'un spec (pour les tests d'emprise)
function PlotLayout.machinePoints(spec: Spec): { Point }
	local list = {}
	for _, line in spec.lines do
		for _, p in line.droppers do
			table.insert(list, p)
		end
		table.insert(list, line.upgrader)
		if spec.sharedCollector == nil then
			table.insert(list, line.collector)
		end
		for _, p in line.employees do
			table.insert(list, p)
		end
	end
	if spec.sharedCollector then
		table.insert(list, spec.sharedCollector)
	end
	table.insert(list, spec.exitDoor)
	table.insert(list, spec.lifeTotem)
	table.insert(list, spec.opaTerminal)
	return list
end

return PlotLayout
