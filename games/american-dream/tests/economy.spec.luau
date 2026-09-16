return function(t, loader)
	local Economy = loader.shared("Config.Economy")
	local PlotState = loader.shared("Sim.PlotState")
	local EconomyMath = loader.shared("Sim.EconomyMath")

	t.describe("Config/Economy", function()
		t.it("a 5 actes avec les coûts de la spec", function()
			t.expect(#Economy.Tiers).toBe(5)
			local costs = {}
			for _, tier in Economy.Tiers do
				table.insert(costs, tier.unlockCost)
			end
			t.expect(costs).toEqual({ 0, 500, 7500, 120000, 2500000 })
		end)
		t.it("garde un ratio coût/revenu d'environ x12 par acte", function()
			for act = 2, 4 do
				local ratio = Economy.Tiers[act + 1].unlockCost / Economy.Tiers[act].unlockCost
				t.expect(ratio).toBeBetween(10, 22)
			end
		end)
		t.it("accélère la cadence à chaque acte", function()
			for act = 2, 5 do
				t.expect(Economy.Tiers[act].dropInterval).toBeLessThan(Economy.Tiers[act - 1].dropInterval)
				t.expect(Economy.Tiers[act].dropValue).toBeGreaterThan(Economy.Tiers[act - 1].dropValue)
			end
		end)
		t.it("n'a pas de loyer en acte 1 et un loyer croissant ensuite", function()
			t.expect(Economy.Tiers[1].rentPerMinute).toBe(0)
			for act = 3, 5 do
				t.expect(Economy.Tiers[act].rentPerMinute).toBeGreaterThan(Economy.Tiers[act - 1].rentPerMinute)
			end
		end)
		t.it("calcule le multiplicateur de Renaissance 1 + 0.25n", function()
			t.expect(Economy.renaissanceMultiplier(0)).toBe(1)
			t.expect(Economy.renaissanceMultiplier(2)).toBe(1.5)
			t.expect(Economy.renaissanceMultiplier(-3)).toBe(1)
		end)
	end)

	t.describe("PlotState", function()
		t.it("génère un catalogue cohérent (prérequis existants, coûts > 0 sauf acte 1)", function()
			local catalog = PlotState.catalog()
			t.expect(#catalog).toBeGreaterThan(30)
			for _, item in catalog do
				for _, required in item.requires do
					t.expect(PlotState.item(required)).toBeTruthy()
				end
				if item.id ~= "A1_UNLOCK" then
					t.expect(item.cost).toBeGreaterThan(0)
				end
			end
		end)
		t.it("refuse un achat sans prérequis, sans argent, ou déjà possédé", function()
			local owned = { A1_UNLOCK = true }
			local ok, reason = PlotState.canBuy(owned, 1e9, "A2_DROPPER_2")
			t.expect(ok).toBe(false)
			t.expect(reason).toBe("shop.reason.requires")
			ok, reason = PlotState.canBuy(owned, 5, "A1_DROPPER_2")
			t.expect(ok).toBe(false)
			t.expect(reason).toBe("shop.reason.cost")
			ok, reason = PlotState.canBuy(owned, 10, "A1_UNLOCK")
			t.expect(ok).toBe(false)
			t.expect(reason).toBe("shop.reason.owned")
			ok = PlotState.canBuy(owned, 100, "A1_DROPPER_2")
			t.expect(ok).toBe(true)
		end)
		t.it("compte droppers, machines et employés", function()
			local owned = { A1_UNLOCK = true, A1_DROPPER_2 = true, A1_UPGRADER = true, A2_UNLOCK = true, A2_EMPLOYEE_1 = true }
			t.expect(PlotState.act(owned)).toBe(2)
			t.expect(PlotState.dropperCount(owned, 1)).toBe(2)
			t.expect(PlotState.dropperCount(owned, 3)).toBe(0)
			t.expect(PlotState.machineCount(owned, 1)).toBe(5)
			t.expect(PlotState.employeeCount(owned)).toBe(1)
		end)
		t.it("liste les achats disponibles triés par coût", function()
			local list = PlotState.available({ A1_UNLOCK = true })
			t.expect(#list).toBeGreaterThan(3)
			for i = 2, #list do
				t.expect(list[i].cost).toBeGreaterThanOrEqual(list[i - 1].cost)
			end
		end)
	end)

	t.describe("EconomyMath", function()
		t.it("calcule le revenu d'une ligne", function()
			local owned = { A1_UNLOCK = true }
			t.expect(EconomyMath.actIncomePerSecond(owned, 1)).toBeCloseTo(0.5)
			owned.A1_DROPPER_2 = true
			owned.A1_UPGRADER = true
			t.expect(EconomyMath.actIncomePerSecond(owned, 1)).toBeCloseTo(2)
			t.expect(EconomyMath.baseIncomePerSecond(owned)).toBeCloseTo(2)
		end)
		t.it("combine les multiplicateurs", function()
			t.expect(EconomyMath.globalMultiplier(0, false, 1)).toBe(1)
			t.expect(EconomyMath.globalMultiplier(2, true, 2)).toBe(6)
		end)
		t.it("garde le loyer sous 15 % du revenu théorique d'une base complète", function()
			for act = 2, 5 do
				local owned = {}
				for a = 1, act do
					owned["A" .. a .. "_UNLOCK"] = true
					owned["A" .. a .. "_DROPPER_2"] = true
					owned["A" .. a .. "_DROPPER_3"] = true
					owned["A" .. a .. "_DROPPER_4"] = true
					owned["A" .. a .. "_UPGRADER"] = true
				end
				local incomePerMinute = EconomyMath.baseIncomePerSecond(owned) * 60
				t.expect(EconomyMath.rentPerMinute(owned) / incomePerMinute).toBeLessThan(0.15)
			end
		end)
		t.it("plafonne le collecteur et garde un pack de cash équitable", function()
			local owned = { A1_UNLOCK = true }
			t.expect(EconomyMath.collectorCap(owned)).toBeGreaterThanOrEqual(50)
			t.expect(EconomyMath.cashPackAmount(owned, 5)).toBeGreaterThanOrEqual(100)
			local rich = { A1_UNLOCK = true, A2_UNLOCK = true, A3_UNLOCK = true }
			t.expect(EconomyMath.cashPackAmount(rich, 5)).toBeGreaterThan(EconomyMath.cashPackAmount(owned, 5))
		end)
		t.it("évalue la valeur nette", function()
			t.expect(EconomyMath.netWorth({ A1_UNLOCK = true, A2_UNLOCK = true }, 100)).toBe(600)
		end)
	end)
end
