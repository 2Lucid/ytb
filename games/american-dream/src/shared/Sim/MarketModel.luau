--!strict
-- Événements de marché : boom (x2) ou krach (/2), annoncés à tout le serveur. Pur, horloge injectée.

local Economy = require(script.Parent.Parent.Config.Economy)
local PRNG = require(script.Parent.Parent.Util.PRNG)
local Types = require(script.Parent.Parent.Types)

type MarketState = Types.MarketState

local MarketModel = {}

function MarketModel.initial(now: number, rng: PRNG.PRNG): MarketState
	return {
		kind = "none",
		multiplier = 1,
		endsAt = 0,
		nextAt = now + rng:range(Economy.Market.minInterval, Economy.Market.maxInterval),
	}
end

-- Fait avancer l'état. Renvoie (nouvelÉtat, événementDéclenché?) où l'événement vaut "boom", "crash", "end" ou nil.
function MarketModel.step(state: MarketState, now: number, rng: PRNG.PRNG): (MarketState, string?)
	if state.kind ~= "none" then
		if now >= state.endsAt then
			return {
				kind = "none",
				multiplier = 1,
				endsAt = 0,
				nextAt = now + rng:range(Economy.Market.minInterval, Economy.Market.maxInterval),
			}, "end"
		end
		return state, nil
	end
	if now >= state.nextAt then
		local market = Economy.Market
		if rng:chance(market.boomProbability) then
			return { kind = "boom", multiplier = market.boomMultiplier, endsAt = now + market.boomDuration, nextAt = 0 }, "boom"
		end
		return { kind = "crash", multiplier = market.crashMultiplier, endsAt = now + market.crashDuration, nextAt = 0 }, "crash"
	end
	return state, nil
end

return MarketModel
