--!strict
-- Règles de l'OPA (acte 5) : PvP doux, tout est notifié et rachetable.

local Economy = require(script.Parent.Parent.Config.Economy)
local EconomyMath = require(script.Parent.EconomyMath)
local Types = require(script.Parent.Parent.Types)

type ItemId = Types.ItemId
type OpaState = Types.OpaState

local OpaRules = {}

export type Party = {
	userId: number,
	act: number,
	cash: number,
}

-- Renvoie (ok, cléDeRaison, coût)
function OpaRules.canAttack(attacker: Party, target: Party, now: number, attackerCooldownUntil: number, targetActive: OpaState?): (boolean, string, number)
	local cost = EconomyMath.opaCost(target.cash)
	if attacker.userId == target.userId then
		return false, "opa.reason.self", cost
	end
	if attacker.act < Economy.Opa.requiredAct then
		return false, "opa.reason.act", cost
	end
	if target.act < Economy.Opa.requiredAct then
		return false, "opa.reason.target_act", cost
	end
	if now < attackerCooldownUntil then
		return false, "opa.reason.cooldown", cost
	end
	if targetActive ~= nil and now < targetActive.endsAt then
		return false, "opa.reason.target_busy", cost
	end
	if attacker.cash < cost then
		return false, "opa.reason.cost", cost
	end
	return true, "", cost
end

function OpaRules.start(attacker: Party, target: Party, now: number, cost: number): OpaState
	return {
		attackerUserId = attacker.userId,
		targetUserId = target.userId,
		endsAt = now + Economy.Opa.duration,
		ratio = Economy.Opa.siphonRatio,
		cost = cost,
	}
end

function OpaRules.buybackCost(state: OpaState): number
	return math.floor(state.cost * Economy.Opa.buybackRatio)
end

-- Part siphonnée d'un gain : (pourL'attaquant, pourLaCible)
function OpaRules.split(amount: number, state: OpaState?, now: number): (number, number)
	if state == nil or now >= state.endsAt then
		return 0, amount
	end
	local siphoned = math.floor(amount * state.ratio)
	return siphoned, amount - siphoned
end

return OpaRules
