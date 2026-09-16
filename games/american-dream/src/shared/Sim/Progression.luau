--!strict
-- Étapes de l'entonnoir d'onboarding et repères de progression. Pur.
-- Les numéros sont stables : ils alimentent AnalyticsService (LogOnboardingFunnelStepEvent).

local Progression = {}

Progression.FUNNEL_NAME = "Onboarding"

Progression.Steps = {
	JOINED = 1,
	PLOT_CLAIMED = 2,
	FIRST_COLLECT = 3,
	FIRST_PURCHASE = 4,
	FIRST_UPGRADER = 5,
	ACT_2 = 6,
	FIRST_EMPLOYEE = 7,
	ACT_3 = 8,
	FIRST_BURNOUT = 9,
	FIRST_RENAISSANCE = 10,
	ACT_4 = 11,
	ACT_5 = 12,
	FIRST_OPA = 13,
}

Progression.StepNames = {
	[1] = "joined",
	[2] = "plot_claimed",
	[3] = "first_collect",
	[4] = "first_purchase",
	[5] = "first_upgrader",
	[6] = "act_2",
	[7] = "first_employee",
	[8] = "act_3",
	[9] = "first_burnout",
	[10] = "first_renaissance",
	[11] = "act_4",
	[12] = "act_5",
	[13] = "first_opa",
}

function Progression.stepForAct(act: number): number?
	if act == 2 then
		return Progression.Steps.ACT_2
	elseif act == 3 then
		return Progression.Steps.ACT_3
	elseif act == 4 then
		return Progression.Steps.ACT_4
	elseif act == 5 then
		return Progression.Steps.ACT_5
	end
	return nil
end

-- Le "sort" de la ville : slogan retourné à la Renaissance, par acte atteint
Progression.PROGRESSION_PATH = "Acts"

return Progression
