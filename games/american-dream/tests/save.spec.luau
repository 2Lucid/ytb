return function(t, loader)
	local SaveSchema = loader.shared("Sim.SaveSchema")
	local Economy = loader.shared("Config.Economy")

	t.describe("SaveSchema", function()
		t.it("fournit un gabarit valide", function()
			local data = SaveSchema.template()
			t.expect(data.version).toBe(SaveSchema.VERSION)
			t.expect(data.life).toBe(Economy.Life.max)
			t.expect(data.plot.owned.A1_UNLOCK).toBe(true)
		end)
		t.it("assainit des données corrompues", function()
			local data = SaveSchema.sanitize({ cash = -50, life = 999, plot = "cassé", renaissances = "abc", stats = nil })
			t.expect(data.cash).toBe(0)
			t.expect(data.life).toBe(Economy.Life.max)
			t.expect(data.renaissances).toBe(0)
			t.expect(data.plot.owned.A1_UNLOCK).toBe(true)
			t.expect(type(data.stats)).toBe("table")
			t.expect(type(data.journals)).toBe("table")
		end)
		t.it("migre depuis une version antérieure sans perte", function()
			local old = { version = 0, cash = 1234, plot = { owned = { A1_UNLOCK = true, A2_UNLOCK = true }, stored = 5, unpaidRent = 0 } }
			local data = SaveSchema.migrate(old)
			t.expect(data.version).toBe(SaveSchema.VERSION)
			t.expect(data.cash).toBe(1234)
			t.expect(data.plot.owned.A2_UNLOCK).toBe(true)
		end)
		t.it("assigne une variante A/B stable entre 1 et 5", function()
			local counts = {}
			for userId = 1, 5000 do
				local v = SaveSchema.layoutVariantFor(userId)
				t.expect(v).toBeBetween(1, 5)
				t.expect(SaveSchema.layoutVariantFor(userId)).toBe(v)
				counts[v] = (counts[v] or 0) + 1
			end
			for v = 1, 5 do
				t.expect(counts[v]).toBeBetween(700, 1300)
			end
		end)
	end)
end
