--!strict
-- PNJ sur rig R15 standard (Players:CreateHumanoidModelFromDescriptionAsync) : les animations
-- text-to-anim R15 s'appliquent sans retouche. Les accessoires viennent plus tard par HumanoidDescription.
-- Repli : une silhouette greybox si la création du rig échoue (Studio hors ligne, par exemple).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Greybox = require(script.Parent.Greybox)
local Strings = require(ReplicatedStorage.Shared.Strings)

local NpcBuilder = {}

export type Kind = "CHAR_Worker" | "CHAR_Clerk" | "CHAR_OfficeWorker" | "CHAR_Executive" | "CHAR_Investor" | "CHAR_Homeless" | "CHAR_Mascot" | "CHAR_Vendor"

type Look = { head: Color3, torso: Color3, arms: Color3, legs: Color3 }

local LOOKS: { [string]: Look } = {
	CHAR_Worker = { head = Color3.fromRGB(234, 184, 146), torso = Color3.fromRGB(40, 70, 140), arms = Color3.fromRGB(40, 70, 140), legs = Color3.fromRGB(35, 45, 80) },
	CHAR_Clerk = { head = Color3.fromRGB(214, 170, 140), torso = Color3.fromRGB(60, 140, 90), arms = Color3.fromRGB(230, 230, 230), legs = Color3.fromRGB(40, 40, 50) },
	CHAR_Vendor = { head = Color3.fromRGB(224, 180, 150), torso = Color3.fromRGB(220, 200, 90), arms = Color3.fromRGB(224, 180, 150), legs = Color3.fromRGB(70, 60, 50) },
	CHAR_OfficeWorker = { head = Color3.fromRGB(230, 190, 160), torso = Color3.fromRGB(235, 235, 240), arms = Color3.fromRGB(235, 235, 240), legs = Color3.fromRGB(50, 50, 60) },
	CHAR_Executive = { head = Color3.fromRGB(220, 180, 150), torso = Color3.fromRGB(25, 25, 30), arms = Color3.fromRGB(25, 25, 30), legs = Color3.fromRGB(25, 25, 30) },
	CHAR_Investor = { head = Color3.fromRGB(230, 200, 180), torso = Color3.fromRGB(60, 50, 45), arms = Color3.fromRGB(60, 50, 45), legs = Color3.fromRGB(45, 40, 38) },
	CHAR_Homeless = { head = Color3.fromRGB(200, 165, 140), torso = Color3.fromRGB(90, 70, 50), arms = Color3.fromRGB(90, 70, 50), legs = Color3.fromRGB(60, 55, 50) },
	CHAR_Mascot = { head = Color3.fromRGB(120, 200, 90), torso = Color3.fromRGB(120, 200, 90), arms = Color3.fromRGB(120, 200, 90), legs = Color3.fromRGB(120, 200, 90) },
}

local function description(kind: string): HumanoidDescription
	local look = LOOKS[kind] or LOOKS.CHAR_Worker
	local d = Instance.new("HumanoidDescription")
	d.HeadColor = look.head
	d.TorsoColor = look.torso
	d.LeftArmColor = look.arms
	d.RightArmColor = look.arms
	d.LeftLegColor = look.legs
	d.RightLegColor = look.legs
	d.HeightScale = 1
	return d
end

local function fallback(kind: string, cframe: CFrame): Model
	local model = Instance.new("Model")
	model.Name = kind
	local look = LOOKS[kind] or LOOKS.CHAR_Worker
	local body = Greybox.part("Body", Vector3.new(2, 4, 1), { look.torso.R, look.torso.G, look.torso.B })
	body.CFrame = cframe * CFrame.new(0, 2, 0)
	body.Parent = model
	local head = Greybox.part("Head", Vector3.new(1.2, 1.2, 1.2), { look.head.R, look.head.G, look.head.B }, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	head.CFrame = cframe * CFrame.new(0, 4.6, 0)
	head.Parent = model
	model.PrimaryPart = body
	return model
end

-- Crée un PNJ ancré à la position donnée. displayNameKey = clé Strings du nom affiché.
function NpcBuilder.create(kind: string, cframe: CFrame, displayNameKey: string, locale: string?): Model
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescriptionAsync(description(kind), Enum.HumanoidRigType.R15)
	end)
	local model: Model
	if ok and typeof(result) == "Instance" and result:IsA("Model") then
		model = result
		model.Name = kind
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.DisplayName = Strings.get(displayNameKey, locale)
			humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			humanoid.NameDisplayDistance = 40
			humanoid.WalkSpeed = 0
			humanoid.JumpPower = 0
			if humanoid:FindFirstChildOfClass("Animator") == nil then
				local animator = Instance.new("Animator")
				animator.Parent = humanoid
			end
		end
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
			end
		end
		model:PivotTo(cframe * CFrame.new(0, 3, 0))
	else
		if not ok then
			warn("[NpcBuilder] rig R15 indisponible, greybox utilisé : " .. tostring(result))
		end
		model = fallback(kind, cframe)
	end
	model:SetAttribute("NpcKind", kind)
	CollectionService:AddTag(model, "Npc")
	return model
end

return NpcBuilder
