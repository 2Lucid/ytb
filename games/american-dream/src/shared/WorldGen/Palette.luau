--!strict
-- Direction artistique en chiffres : palette froide (béton, bleu nuit) qui vire au néon saturé en montant d'acte.
-- Couleurs en {r, g, b} 0-1 pour rester pur (le Builder les convertit en Color3).

export type RGB = { number }

export type ActPalette = {
	ground: RGB,
	building: { RGB },
	accent: RGB, -- néons, boutons, lumières
	fog: RGB,
	ambient: RGB,
	fogEnd: number,
	clockTime: number,
	material: string, -- matériau dominant des façades
}

local Palette = {}

Palette.Acts = {
	[1] = { ground = { 0.16, 0.16, 0.18 }, building = { { 0.36, 0.26, 0.22 }, { 0.3, 0.3, 0.33 }, { 0.42, 0.34, 0.3 } }, accent = { 0.95, 0.8, 0.35 }, fog = { 0.36, 0.38, 0.47 }, ambient = { 0.19, 0.2, 0.26 }, fogEnd = 700, clockTime = 19.5, material = "Brick" },
	[2] = { ground = { 0.2, 0.2, 0.22 }, building = { { 0.5, 0.45, 0.4 }, { 0.38, 0.4, 0.44 }, { 0.55, 0.5, 0.42 } }, accent = { 0.2, 0.9, 0.85 }, fog = { 0.4, 0.42, 0.52 }, ambient = { 0.22, 0.23, 0.3 }, fogEnd = 800, clockTime = 20, material = "Concrete" },
	[3] = { ground = { 0.22, 0.2, 0.18 }, building = { { 0.35, 0.33, 0.3 }, { 0.45, 0.4, 0.33 }, { 0.3, 0.3, 0.3 } }, accent = { 1, 0.45, 0.15 }, fog = { 0.5, 0.38, 0.3 }, ambient = { 0.3, 0.22, 0.18 }, fogEnd = 500, clockTime = 18.5, material = "Metal" },
	[4] = { ground = { 0.14, 0.15, 0.2 }, building = { { 0.45, 0.55, 0.7 }, { 0.3, 0.35, 0.5 }, { 0.6, 0.65, 0.78 } }, accent = { 0.9, 0.2, 0.75 }, fog = { 0.3, 0.2, 0.45 }, ambient = { 0.25, 0.18, 0.35 }, fogEnd = 900, clockTime = 21, material = "Glass" },
	[5] = { ground = { 0.1, 0.1, 0.12 }, building = { { 0.75, 0.65, 0.35 }, { 0.2, 0.2, 0.25 }, { 0.85, 0.75, 0.45 } }, accent = { 1, 0.85, 0.3 }, fog = { 0.15, 0.1, 0.25 }, ambient = { 0.32, 0.2, 0.4 }, fogEnd = 1200, clockTime = 23, material = "Marble" },
} :: { [number]: ActPalette }

Palette.Road = { 0.11, 0.11, 0.12 }
Palette.Sidewalk = { 0.42, 0.42, 0.44 }
Palette.Plot = { 0.24, 0.25, 0.28 }
Palette.PlotBorder = { 0.9, 0.8, 0.3 }
Palette.Conveyor = { 0.2, 0.2, 0.22 }
Palette.Collector = { 0.85, 0.7, 0.2 }
Palette.ButtonAvailable = { 0.2, 0.85, 0.4 }
Palette.ButtonLocked = { 0.35, 0.35, 0.38 }
Palette.ButtonOwned = { 0.2, 0.4, 0.9 }

-- Couleur d'une machine selon la catégorie de manifest (greybox)
Palette.Machine = {
	DROP = { 0.55, 0.6, 0.7 },
	UPG = { 0.85, 0.55, 0.2 },
	COLL = { 0.85, 0.7, 0.2 },
	CONV = { 0.2, 0.2, 0.22 },
	DECO = { 0.5, 0.5, 0.55 },
	CHAR = { 0.8, 0.7, 0.6 },
	LORE = { 0.95, 0.95, 0.85 },
	CITY = { 0.4, 0.4, 0.45 },
}

function Palette.forAct(act: number): ActPalette
	return Palette.Acts[math.clamp(act, 1, 5)]
end

-- Interpolation entre deux palettes (transition d'éclairage progressive côté client)
function Palette.lerpRGB(a: RGB, b: RGB, alpha: number): RGB
	return { a[1] + (b[1] - a[1]) * alpha, a[2] + (b[2] - a[2]) * alpha, a[3] + (b[3] - a[3]) * alpha }
end

return Palette
