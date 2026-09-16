--!strict
-- Formes primitives colorées à la place des meshes absents. Le jeu est jouable avant le premier asset,
-- et chaque asset généré remplace silencieusement son greybox (voir AssetCache).

local Palette = require(game:GetService("ReplicatedStorage").Shared.WorldGen.Palette)

local Greybox = {}

local function color(rgb: { number }): Color3
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

Greybox.color = color

local function part(name: string, size: Vector3, rgb: { number }, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color(rgb)
	p.Material = material or Enum.Material.SmoothPlastic
	p.Shape = shape or Enum.PartType.Block
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

Greybox.part = part

local function categoryOf(id: string): string
	local category = string.match(id, "^MSH_A%d_(%u+)_") or string.match(id, "^MSH_(%u+)_") or "DECO"
	return category
end

-- Un modèle greybox pour un identifiant de manifest. Le PrimaryPart est la base au sol.
function Greybox.model(id: string, act: number): Model
	local category = categoryOf(id)
	local rgb = Palette.Machine[category] or Palette.Machine.DECO
	local accent = Palette.forAct(act).accent
	local model = Instance.new("Model")
	model.Name = id
	local base: Part
	if category == "DROP" then
		base = part("Base", Vector3.new(4, 5, 4), rgb, Enum.Material.Metal)
		local nozzle = part("Nozzle", Vector3.new(1.6, 1.2, 1.6), accent, Enum.Material.Neon, Enum.PartType.Cylinder)
		nozzle.CFrame = CFrame.new(0, 0.4, 2.4) * CFrame.Angles(0, 0, math.rad(90))
		nozzle.Parent = model
		local light = part("Light", Vector3.new(0.6, 0.6, 0.6), accent, Enum.Material.Neon)
		light.CFrame = CFrame.new(0, 2.2, 2.1)
		light.Parent = model
	elseif category == "UPG" then
		base = part("Base", Vector3.new(6, 0.6, 3), rgb, Enum.Material.Metal)
		local arch = part("Arch", Vector3.new(6, 5, 1), rgb, Enum.Material.Metal)
		arch.CFrame = CFrame.new(0, 3, 0)
		arch.Parent = model
		local ring = part("Ring", Vector3.new(4.6, 1.2, 4.6), accent, Enum.Material.Neon, Enum.PartType.Cylinder)
		ring.CFrame = CFrame.new(0, 3, 0) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = model
	elseif category == "COLL" then
		base = part("Base", Vector3.new(7, 5, 6), rgb, Enum.Material.Metal)
		local slot = part("Slot", Vector3.new(5, 0.4, 0.6), accent, Enum.Material.Neon)
		slot.CFrame = CFrame.new(0, 1.8, -3.1)
		slot.Parent = model
	elseif category == "CONV" then
		base = part("Base", Vector3.new(30, 0.8, 3), rgb, Enum.Material.DiamondPlate)
		for side = -1, 1, 2 do
			local rail = part("Rail", Vector3.new(30, 0.5, 0.3), Palette.Machine.DECO, Enum.Material.Metal)
			rail.CFrame = CFrame.new(0, 0.5, side * 1.5)
			rail.Parent = model
		end
	elseif category == "LORE" then
		base = part("Base", Vector3.new(1.5, 0.3, 1), Palette.Machine.LORE, Enum.Material.Fabric)
	elseif category == "GP" then
		base = part("Base", Vector3.new(1.2, 1.2, 1.2), accent, Enum.Material.Neon)
	elseif category == "CITY" then
		base = part("Base", Vector3.new(3, 3, 3), Palette.Machine.CITY, Enum.Material.Concrete)
	else
		base = part("Base", Vector3.new(3, 3, 3), rgb, Enum.Material.SmoothPlastic)
	end
	base.Parent = model
	model.PrimaryPart = base
	return model
end

-- Dimensionne un modèle greybox à une taille cible (les meshes réels passent par Model:ScaleTo)
function Greybox.fit(model: Model, target: Vector3)
	local current = model:GetExtentsSize()
	local largest = math.max(current.X, current.Y, current.Z)
	if largest <= 0 then
		return
	end
	local scale = math.max(target.X, target.Y, target.Z) / largest
	if math.abs(scale - 1) > 0.01 then
		model:ScaleTo(scale)
	end
end

return Greybox
