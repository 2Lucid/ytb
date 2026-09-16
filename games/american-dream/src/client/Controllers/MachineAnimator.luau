--!strict
-- Toutes les animations d'objets : rouleaux de tapis, pistons, bras, néons, fumée, bandeau boursier,
-- pulsation des boutons. 100 % scriptées (TweenService + CFrame), aucun asset d'animation requis.
-- Tout tourne côté client : zéro réplication, zéro coût serveur.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Palette = require(ReplicatedStorage.Shared.WorldGen.Palette)

local MachineAnimator = {}

local animated: { [Instance]: (dt: number, clock: number) -> () } = {}
local connections: { RBXScriptConnection } = {}
local MAX_DISTANCE = 220

-- Libère toutes les connexions (utilisé au rechargement du personnage ou en test)
local function disconnectAll()
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	table.clear(animated)
end

local function color(rgb: { number }): Color3
	return Color3.new(rgb[1], rgb[2], rgb[3])
end

local function actOf(instance: Instance): number
	local act = instance:GetAttribute("Act")
	return type(act) == "number" and act or 1
end

-- Tapis : les rails défilent (décalage de texture simulé par oscillation des rails)
local function animateConveyor(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local rails: { BasePart } = {}
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Rail" then
			table.insert(rails, child)
		end
	end
	local base = model.PrimaryPart
	if base == nil then
		return
	end
	local origins: { CFrame } = {}
	for index, rail in rails do
		origins[index] = rail.CFrame
	end
	local speed = 6
	animated[model] = function(_dt: number, clock: number)
		local offset = (clock * speed) % 2 - 1
		for index, rail in rails do
			rail.CFrame = origins[index] * CFrame.new(offset, 0, 0)
		end
	end
end

-- Dropper : la buse pulse et la lumière clignote à chaque cycle
local function animateDropper(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local light = model:FindFirstChild("Light")
	local nozzle = model:FindFirstChild("Nozzle")
	if light == nil and nozzle == nil then
		return
	end
	local accent = color(Palette.forAct(actOf(model)).accent)
	local nozzleOrigin = nozzle and nozzle:IsA("BasePart") and nozzle.CFrame or nil
	animated[model] = function(_dt: number, clock: number)
		local phase = (clock * 1.4) % 1
		if light and light:IsA("BasePart") then
			light.Color = accent:Lerp(Color3.new(1, 1, 1), phase < 0.15 and 1 - phase / 0.15 or 0)
		end
		if nozzle and nozzle:IsA("BasePart") and nozzleOrigin then
			nozzle.CFrame = nozzleOrigin * CFrame.new(0, 0, phase < 0.2 and -0.3 * (1 - phase / 0.2) or 0)
		end
	end
end

-- Améliorateur : l'anneau tourne et pulse
local function animateUpgrader(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local ring = model:FindFirstChild("Ring")
	if ring == nil or not ring:IsA("BasePart") then
		return
	end
	local origin = ring.CFrame
	animated[model] = function(_dt: number, clock: number)
		ring.CFrame = origin * CFrame.Angles(math.rad(clock * 90), 0, 0)
		ring.Transparency = 0.15 + 0.15 * math.sin(clock * 3)
	end
end

-- Collecteur : la fente respire quand il y a du cash en attente
local function animateCollector(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local slot = model:FindFirstChild("Slot")
	if slot == nil or not slot:IsA("BasePart") then
		return
	end
	local plot = model:FindFirstAncestorOfClass("Model")
	animated[model] = function(_dt: number, clock: number)
		local stored = plot and plot:GetAttribute("Stored")
		local active = type(stored) == "number" and stored > 0
		slot.Transparency = active and (0.1 + 0.25 * math.sin(clock * 5)) or 0.7
	end
end

-- Bouton d'achat : pulse quand il est abordable
local function animateButton(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local origin = part.Size
	animated[part] = function(_dt: number, clock: number)
		if part:GetAttribute("State") == "available" then
			local scale = 1 + 0.06 * math.sin(clock * 4)
			part.Size = Vector3.new(origin.X * scale, origin.Y, origin.Z * scale)
		elseif part.Size ~= origin then
			part.Size = origin
		end
	end
end

-- Cheminée : fumée qui monte, plus dense selon l'acte du quartier
local function animateChimney(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local base = model.PrimaryPart
	if base == nil or base:FindFirstChildOfClass("ParticleEmitter") then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, base.Size.Y / 2, 0)
	attachment.Parent = base
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Smoke"
	emitter.Rate = 6
	emitter.Lifetime = NumberRange.new(4, 7)
	emitter.Speed = NumberRange.new(4, 7)
	emitter.SpreadAngle = Vector2.new(12, 12)
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 14) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	emitter.Color = ColorSequence.new(Color3.fromRGB(90, 85, 80), Color3.fromRGB(140, 130, 120))
	emitter.LightEmission = 0
	emitter.Parent = attachment
end

-- Néons et bandeaux de tours : scintillement irrégulier
local function animateNeon(instance: Instance)
	local part: BasePart? = nil
	if instance:IsA("BasePart") then
		part = instance
	elseif instance:IsA("Model") then
		part = instance:FindFirstChild("Band") :: BasePart? or instance.PrimaryPart
	end
	if part == nil then
		return
	end
	local target = part
	local accent = color(Palette.forAct(actOf(instance)).accent)
	local seed = math.random() * 10
	animated[instance] = function(_dt: number, clock: number)
		local flicker = math.sin((clock + seed) * 2.2) * math.sin((clock + seed) * 7.3)
		target.Color = accent:Lerp(Color3.new(0.1, 0.1, 0.12), math.clamp(0.25 - flicker * 0.3, 0, 0.6))
	end
end

-- Bandeau boursier : texte défilant autour du plot
local function animateTicker(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local labels: { TextLabel } = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("TextLabel") and descendant.Name == "Text" then
			table.insert(labels, descendant)
		end
	end
	if #labels == 0 then
		return
	end
	animated[model] = function(_dt: number, clock: number)
		local text = model:GetAttribute("Ticker")
		if type(text) ~= "string" or #text == 0 then
			return
		end
		local width = 48
		local padded = text .. "   "
		local offset = math.floor(clock * 6) % #padded
		local scrolled = string.sub(padded, offset + 1) .. string.sub(padded, 1, offset)
		local visible = string.sub(string.rep(scrolled, 3), 1, width)
		for _, label in labels do
			label.Text = visible
		end
	end
end

-- Feu tricolore : cycle vert / orange / rouge
local function animateTrafficLight(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local pole = model.PrimaryPart
	if pole == nil then
		return
	end
	local lamp = model:FindFirstChild("Lamp")
	if lamp == nil then
		local created = Instance.new("Part")
		created.Name = "Lamp"
		created.Size = Vector3.new(1, 2.4, 1)
		created.Anchored = true
		created.CanCollide = false
		created.CanQuery = false
		created.Material = Enum.Material.Neon
		created.CFrame = pole.CFrame * CFrame.new(0, pole.Size.Y / 2 - 1.5, 0)
		created.Parent = model
		lamp = created
	end
	local target = lamp :: BasePart
	local seed = math.random() * 12
	animated[model] = function(_dt: number, clock: number)
		local phase = ((clock + seed) % 12) / 12
		if phase < 0.45 then
			target.Color = Color3.fromRGB(60, 210, 110)
		elseif phase < 0.55 then
			target.Color = Color3.fromRGB(245, 180, 60)
		else
			target.Color = Color3.fromRGB(230, 70, 60)
		end
	end
end

-- Journaux et collectibles : flottement et rotation lente
local function animateJournal(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local base = model.PrimaryPart
	if base == nil then
		return
	end
	local origin = base.CFrame
	animated[model] = function(_dt: number, clock: number)
		base.CFrame = origin * CFrame.new(0, math.sin(clock * 1.5) * 0.3, 0) * CFrame.Angles(0, clock * 0.8, 0)
	end
end

-- Totem de Vie : hauteur et couleur suivent l'attribut Life du plot
local function animateLifeTotem(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local base = model.PrimaryPart
	local plot = model:FindFirstAncestorOfClass("Model")
	if base == nil or plot == nil then
		return
	end
	local fullSize = base.Size
	local origin = base.CFrame
	animated[model] = function(_dt: number, _clock: number)
		local life = plot:GetAttribute("Life")
		if type(life) ~= "number" then
			return
		end
		local ratio = math.clamp(life / 100, 0.02, 1)
		base.Size = Vector3.new(fullSize.X, fullSize.Y * ratio, fullSize.Z)
		base.CFrame = origin * CFrame.new(0, -(fullSize.Y - base.Size.Y) / 2, 0)
		base.Color = ratio < 0.25 and Color3.fromRGB(230, 90, 70) or Color3.fromRGB(90, 210, 160)
	end
end

local HANDLERS: { [string]: (Instance) -> () } = {
	Conveyor = animateConveyor,
	Dropper = animateDropper,
	Upgrader = animateUpgrader,
	Collector = animateCollector,
	PurchaseButton = animateButton,
	Chimney = animateChimney,
	Neon = animateNeon,
	NeonTower = animateNeon,
	Ticker = animateTicker,
	TrafficLight = animateTrafficLight,
	Journal = animateJournal,
	LifeTotem = animateLifeTotem,
}

function MachineAnimator.Init() end

function MachineAnimator.Start()
	for tag, handler in HANDLERS do
		for _, instance in CollectionService:GetTagged(tag) do
			task.spawn(handler, instance)
		end
		table.insert(connections, CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
			task.spawn(handler, instance)
		end))
		table.insert(connections, CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
			animated[instance] = nil
		end))
	end
	-- Une seule boucle pour toutes les animations, avec coupure à distance (60 FPS mobile)
	local clock = 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		local character = Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local origin = root and root:IsA("BasePart") and root.Position or Vector3.zero
		for instance, update in animated do
			if instance.Parent == nil then
				animated[instance] = nil
				continue
			end
			local pivot: Vector3? = nil
			if instance:IsA("BasePart") then
				pivot = instance.Position
			elseif instance:IsA("Model") then
				local primary = instance.PrimaryPart
				pivot = primary and primary.Position or nil
			end
			if pivot and (pivot - origin).Magnitude > MAX_DISTANCE then
				continue
			end
			update(dt, clock)
		end
	end)
end

-- Fait tomber un objet visuel du dropper vers le collecteur (purement décoratif)
MachineAnimator.disconnectAll = disconnectAll

function MachineAnimator.spawnDrop(from: CFrame, to: CFrame, travelTime: number, dropColor: Color3): Part
	local drop = Instance.new("Part")
	drop.Name = "Drop"
	drop.Size = Vector3.new(1.2, 1.2, 1.2)
	drop.Color = dropColor
	drop.Material = Enum.Material.SmoothPlastic
	drop.Anchored = true
	drop.CanCollide = false
	drop.CanQuery = false
	drop.CanTouch = false
	drop.CastShadow = false
	drop.CFrame = from
	drop.Parent = Workspace
	local tween = TweenService:Create(drop, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), { CFrame = to })
	tween:Play()
	tween.Completed:Once(function()
		local shrink = TweenService:Create(drop, TweenInfo.new(0.2), { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
		shrink:Play()
		shrink.Completed:Once(function()
			drop:Destroy()
		end)
	end)
	return drop
end

return MachineAnimator
