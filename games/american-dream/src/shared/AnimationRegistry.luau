--!strict
-- Nom d'animation -> assetId. Fallback silencieux : une animation absente ne joue rien et ne casse rien.
-- Les animations de machines n'existent pas ici : ce sont des tweens (voir client/Controllers/MachineAnimator).

local AssetRegistry = require(script.Parent.AssetRegistry)

local AnimationRegistry = {}

AnimationRegistry.Names = {
	-- PNJ
	"ANM_NPC_WorkerLift",
	"ANM_NPC_WorkerIdle",
	"ANM_NPC_ClerkScan",
	"ANM_NPC_OfficeType",
	"ANM_NPC_ExecPhone",
	"ANM_NPC_InvestorNod",
	"ANM_NPC_Patrol",
	-- Joueur
	"ANM_PLR_CountCash",
	"ANM_PLR_CheckWatch",
	"ANM_PLR_Handshake",
	"ANM_PLR_Celebrate",
	"ANM_PLR_Exhausted",
	"ANM_PLR_Collapse",
	"ANM_PLR_WakeUp",
}

function AnimationRegistry.id(name: string): number
	return AssetRegistry.animation(name)
end

-- Renvoie une Animation prête à charger, ou nil si l'asset n'existe pas encore
function AnimationRegistry.instance(name: string): Animation?
	local id = AnimationRegistry.id(name)
	if id <= 0 then
		return nil
	end
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = AssetRegistry.contentId(id)
	return animation
end

return AnimationRegistry
