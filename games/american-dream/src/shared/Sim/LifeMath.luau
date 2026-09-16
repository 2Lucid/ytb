--!strict
-- La jauge de Vie : elle descend quand la base grandit. Jamais expliquée au joueur au début.

local Economy = require(script.Parent.Parent.Config.Economy)
local PlotState = require(script.Parent.PlotState)
local Types = require(script.Parent.Parent.Types)

type ItemId = Types.ItemId

local LifeMath = {}

function LifeMath.drainPerMinute(owned: { [ItemId]: boolean }): number
	local drain = Economy.Life.baseDrainPerMinute
	for act = 1, Economy.maxAct() do
		local tier = Economy.tier(act)
		drain += PlotState.machineCount(owned, act) * tier.lifeDrainPerMachine
	end
	local employees = 0
	local employeeDrain = 0
	for id in owned do
		local item = PlotState.item(id)
		if item and item.kind == "employee" then
			employees += 1
			employeeDrain += Economy.tier(item.act).lifeDrainPerEmployee
		end
	end
	return drain + employeeDrain
end

function LifeMath.minutesToBurnout(life: number, owned: { [ItemId]: boolean }): number
	local drain = LifeMath.drainPerMinute(owned)
	if drain <= 0 then
		return math.huge
	end
	return life / drain
end

function LifeMath.isExhausted(life: number): boolean
	return life / Economy.Life.max < Economy.Life.exhaustedThreshold
end

function LifeMath.canExitVoluntarily(life: number, hasFastRenaissance: boolean): boolean
	if hasFastRenaissance then
		return true
	end
	return life / Economy.Life.max <= Economy.Life.voluntaryExitThreshold
end

-- Le burnout donne un multiplicateur seulement si l'acte 3 a été atteint dans cette vie
function LifeMath.renaissanceGrantsBonus(highestActThisLife: number): boolean
	return highestActThisLife >= Economy.Life.renaissanceMinAct
end

return LifeMath
