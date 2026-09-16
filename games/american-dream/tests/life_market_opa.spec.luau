return function(t, loader)
	local Economy = loader.shared("Config.Economy")
	local LifeMath = loader.shared("Sim.LifeMath")
	local MarketModel = loader.shared("Sim.MarketModel")
	local OpaRules = loader.shared("Sim.OpaRules")
	local PRNG = loader.shared("Util.PRNG")

	local function fullBase(act)
		local owned = {}
		for a = 1, act do
			owned["A" .. a .. "_UNLOCK"] = true
			owned["A" .. a .. "_DROPPER_2"] = true
			owned["A" .. a .. "_DROPPER_3"] = true
			owned["A" .. a .. "_DROPPER_4"] = true
			owned["A" .. a .. "_UPGRADER"] = true
		end
		return owned
	end

	t.describe("LifeMath", function()
		t.it("ne peut pas mener au burnout en actes 1-2 en moins de 3 heures", function()
			local owned = fullBase(2)
			owned.A2_EMPLOYEE_1 = true
			t.expect(LifeMath.minutesToBurnout(Economy.Life.max, owned)).toBeGreaterThan(180)
		end)
		t.it("mène au burnout en 40 à 120 minutes avec une base complète d'acte 4", function()
			local owned = fullBase(4)
			owned.A2_EMPLOYEE_1 = true
			owned.A3_EMPLOYEE_1 = true
			owned.A3_EMPLOYEE_2 = true
			owned.A4_EMPLOYEE_1 = true
			t.expect(LifeMath.minutesToBurnout(Economy.Life.max, owned)).toBeBetween(40, 120)
		end)
		t.it("draine plus vite quand la base grandit", function()
			t.expect(LifeMath.drainPerMinute(fullBase(3))).toBeGreaterThan(LifeMath.drainPerMinute(fullBase(2)))
			t.expect(LifeMath.drainPerMinute(fullBase(5))).toBeGreaterThan(LifeMath.drainPerMinute(fullBase(4)))
		end)
		t.it("détecte l'épuisement et la sortie volontaire", function()
			t.expect(LifeMath.isExhausted(24)).toBe(true)
			t.expect(LifeMath.isExhausted(26)).toBe(false)
			t.expect(LifeMath.canExitVoluntarily(80, false)).toBe(false)
			t.expect(LifeMath.canExitVoluntarily(80, true)).toBe(true)
			t.expect(LifeMath.canExitVoluntarily(20, false)).toBe(true)
			t.expect(LifeMath.renaissanceGrantsBonus(2)).toBe(false)
			t.expect(LifeMath.renaissanceGrantsBonus(3)).toBe(true)
		end)
	end)

	t.describe("MarketModel", function()
		t.it("planifie un événement entre 8 et 10 minutes puis le termine", function()
			local rng = PRNG.new(5)
			local state = MarketModel.initial(0, rng)
			t.expect(state.nextAt).toBeBetween(480, 600)
			local booms, crashes = 0, 0
			local now = 0
			for _ = 1, 40 do
				now = state.nextAt
				local event
				state, event = MarketModel.step(state, now, rng)
				if event == "boom" then
					booms += 1
					t.expect(state.multiplier).toBe(2)
				elseif event == "crash" then
					crashes += 1
					t.expect(state.multiplier).toBe(0.5)
				end
				local ended
				state, ended = MarketModel.step(state, state.endsAt, rng)
				t.expect(ended).toBe("end")
				t.expect(state.multiplier).toBe(1)
			end
			t.expect(booms + crashes).toBe(40)
			t.expect(booms).toBeBetween(8, 32)
		end)
		t.it("ne change rien avant l'échéance", function()
			local rng = PRNG.new(1)
			local state = MarketModel.initial(100, rng)
			local same, event = MarketModel.step(state, 101, rng)
			t.expect(event).toBeNil()
			t.expect(same).toBe(state)
		end)
	end)

	t.describe("OpaRules", function()
		local attacker = { userId = 1, act = 5, cash = 10000000 }
		local target = { userId = 2, act = 5, cash = 50000000 }
		t.it("autorise une OPA valide et calcule le coût", function()
			local ok, reason, cost = OpaRules.canAttack(attacker, target, 0, 0, nil)
			t.expect(ok).toBe(true)
			t.expect(reason).toBe("")
			t.expect(cost).toBe(1000000)
		end)
		t.it("refuse hors acte 5, sur soi-même, en cooldown, cible occupée ou sans argent", function()
			local ok, reason = OpaRules.canAttack({ userId = 1, act = 4, cash = 1e9 }, target, 0, 0, nil)
			t.expect(ok).toBe(false)
			t.expect(reason).toBe("opa.reason.act")
			ok, reason = OpaRules.canAttack(attacker, attacker, 0, 0, nil)
			t.expect(reason).toBe("opa.reason.self")
			ok, reason = OpaRules.canAttack(attacker, target, 10, 20, nil)
			t.expect(reason).toBe("opa.reason.cooldown")
			local active = OpaRules.start(attacker, target, 0, 1000000)
			ok, reason = OpaRules.canAttack(attacker, target, 10, 0, active)
			t.expect(reason).toBe("opa.reason.target_busy")
			ok, reason = OpaRules.canAttack({ userId = 1, act = 5, cash = 10 }, target, 0, 0, nil)
			t.expect(reason).toBe("opa.reason.cost")
		end)
		t.it("siphonne 5 % pendant 2 minutes puis plus rien", function()
			local state = OpaRules.start(attacker, target, 0, 1000000)
			t.expect(state.endsAt).toBe(120)
			local mine, theirs = OpaRules.split(1000, state, 60)
			t.expect(mine).toBe(50)
			t.expect(theirs).toBe(950)
			mine, theirs = OpaRules.split(1000, state, 121)
			t.expect(mine).toBe(0)
			t.expect(theirs).toBe(1000)
			t.expect(OpaRules.buybackCost(state)).toBe(1000000)
		end)
	end)
end
