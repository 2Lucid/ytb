return function(t, loader)
	local Strings = loader.shared("Strings")
	local PlotState = loader.shared("Sim.PlotState")
	local Lore = loader.shared("Config.Lore")
	local Monetization = loader.shared("Config.Monetization")

	t.describe("Strings", function()
		t.it("a une traduction FR et EN non vide pour chaque clé", function()
			local count = 0
			for _, entry in Strings.Table do
				count += 1
				t.expect(type(entry.fr) == "string" and #entry.fr > 0).toBe(true)
				t.expect(type(entry.en) == "string" and #entry.en > 0).toBe(true)
			end
			t.expect(count).toBeGreaterThan(150)
		end)
		t.it("substitue les paramètres et signale les clés inconnues", function()
			t.expect(Strings.get("hud.act", "fr", { act = 2, name = "Le Commerce" })).toBe("Acte 2 : Le Commerce")
			t.expect(Strings.get("hud.act", "en-us", { act = 2, name = "The Store" })).toBe("Act 2: The Store")
			t.expect(Strings.get("nope")).toBe("[nope]")
			t.expect(Strings.get("hud.act", "fr", {})).toBe("Acte {act} : {name}")
		end)
		t.it("couvre toutes les clés référencées par le catalogue, le lore et la boutique", function()
			for _, item in PlotState.catalog() do
				t.expect(Strings.has(item.nameKey)).toBe(true)
			end
			for index = 1, Lore.BILLBOARD_COUNT do
				for act = 1, 5 do
					t.expect(Strings.has(Lore.slogan(index, act))).toBe(true)
				end
			end
			for _, journal in Lore.Journals do
				t.expect(Strings.has(journal.titleKey)).toBe(true)
				t.expect(Strings.has(journal.bodyKey)).toBe(true)
			end
			for _, key in Lore.HOMELESS_LINES do
				t.expect(Strings.has(key)).toBe(true)
			end
			for _, key in Lore.RENAISSANCE_LINES do
				t.expect(Strings.has(key)).toBe(true)
			end
			for _, pass in Monetization.Gamepasses do
				t.expect(Strings.has(pass.nameKey)).toBe(true)
				t.expect(Strings.has(pass.descriptionKey)).toBe(true)
			end
			for _, product in Monetization.DevProducts do
				t.expect(Strings.has(product.nameKey)).toBe(true)
			end
			for _, key in { "shop.reason.unknown", "shop.reason.owned", "shop.reason.requires", "shop.reason.cost" } do
				t.expect(Strings.has(key)).toBe(true)
			end
		end)
	end)
end
