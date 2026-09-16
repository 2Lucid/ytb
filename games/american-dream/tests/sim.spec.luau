-- Simulation d'une session parfaite : les temps par acte doivent rester dans la fourchette cible.
return function(t, loader)
	local Bot = loader.shared("Sim.Bot")
	local Economy = loader.shared("Config.Economy")

	t.describe("Simulation (bot glouton)", function()
		local options = Bot.defaultOptions()
		local timeline = Bot.run(options)
		local minutes = {}
		for act = 1, Economy.maxAct() do
			local at = timeline.actReachedAt[act]
			minutes[act] = at and at / 60 or nil
		end
		print(string.format(
			"  sim : acte2 %.1f min, acte3 %.1f min, acte4 %.1f min, acte5 %s min, burnout %s min, loyer payé %d",
			minutes[2] or -1, minutes[3] or -1, minutes[4] or -1,
			minutes[5] and string.format("%.1f", minutes[5]) or "jamais",
			timeline.burnoutAt and string.format("%.1f", timeline.burnoutAt / 60) or "jamais",
			timeline.totalRentPaid
		))

		t.it("atteint l'acte 2 en 1.5 à 4 minutes (tuto déguisé)", function()
			t.expect(minutes[2]).toBeBetween(1.5, 4)
		end)
		t.it("atteint l'acte 3 en 6 à 14 minutes cumulées", function()
			t.expect(minutes[3]).toBeBetween(6, 14)
		end)
		t.it("atteint l'acte 4 en 18 à 40 minutes cumulées", function()
			t.expect(minutes[4]).toBeBetween(18, 40)
		end)
		t.it("subit son premier burnout entre 45 et 110 minutes, après l'acte 3", function()
			t.expect(timeline.burnoutAt).toBeTruthy()
			t.expect(timeline.burnoutAt / 60).toBeBetween(45, 110)
			t.expect(timeline.burnoutAt).toBeGreaterThan(timeline.actReachedAt[3])
		end)
		t.it("atteint l'acte 5 avec des renaissances (le prestige accélère)", function()
			local fast = Bot.defaultOptions()
			fast.renaissances = 3
			fast.stopAtBurnout = false
			local run = Bot.run(fast)
			t.expect(run.actReachedAt[5]).toBeTruthy()
			t.expect(run.actReachedAt[5] / 60).toBeLessThan(150)
		end)
	end)
end
