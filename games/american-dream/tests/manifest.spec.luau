-- Vérifie que chaque identifiant d'asset utilisé par le code existe dans le manifest,
-- et que le manifest reste cohérent (identifiants uniques, prompts non vides, échelles valides).
return function(t, loader)
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")

	local manifest = serde.decode("json", fs.readFile("assets/manifest.json"))
	local ids: { [string]: any } = {}
	for _, asset in manifest.assets do
		ids[asset.id] = asset
	end

	local Machines = loader.shared("Config.Machines")
	local AnimationRegistry = loader.shared("AnimationRegistry")

	t.describe("Manifest d'assets", function()
		t.it("a des identifiants uniques et des prompts non vides", function()
			local count = 0
			local seen: { [string]: boolean } = {}
			for _, asset in manifest.assets do
				count += 1
				t.expect(seen[asset.id]).toBeFalsy()
				seen[asset.id] = true
				t.expect(#asset.prompt).toBeGreaterThan(10)
				t.expect(#asset.id).toBeGreaterThan(4)
			end
			t.expect(count).toBeGreaterThan(150)
		end)

		t.it("impose le préfixe de style à chaque prompt de mesh", function()
			for _, asset in manifest.assets do
				if asset.kind == "mesh" or asset.kind == "character" then
					t.expect(string.find(asset.prompt, manifest.style, 1, true) ~= nil).toBe(true)
				end
			end
		end)

		t.it("n'utilise que des schémas Cube 3D valides et des échelles positives", function()
			for _, asset in manifest.assets do
				if asset.kind ~= "mesh" then
					continue
				end
				t.expect(asset.schema == "Body1" or asset.schema == "Car5").toBe(true)
				t.expect(#asset.scale).toBe(3)
				for _, value in asset.scale do
					t.expect(value).toBeGreaterThan(0)
				end
				t.expect(asset.maxTriangles).toBeLessThanOrEqual(10000)
			end
		end)

		t.it("génère les personnages sur rig R15 (sinon aucune animation ne s'applique)", function()
			local characters = 0
			for _, asset in manifest.assets do
				if asset.kind == "character" then
					characters += 1
					t.expect(asset.schema).toBe("R15")
				end
			end
			t.expect(characters).toBe(8)
		end)

		t.it("couvre toutes les machines référencées par Config/Machines", function()
			for act = 1, 5 do
				local machines = Machines.forAct(act)
				for _, key in { "dropper", "upgrader", "collector", "conveyor", "product", "employee" } do
					local id = machines[key]
					t.expect(ids[id] ~= nil).toBe(true)
				end
				for _, id in machines.decor do
					t.expect(ids[id] ~= nil).toBe(true)
				end
			end
			for _, id in Machines.Gameplay do
				t.expect(ids[id] ~= nil).toBe(true)
			end
		end)

		t.it("couvre toutes les animations du registre", function()
			for _, name in AnimationRegistry.Names do
				t.expect(ids[name] ~= nil).toBe(true)
				t.expect(ids[name].rig).toBe("R15")
			end
		end)

		t.it("marque en retouche manuelle les trois animations qui portent l'émotion", function()
			local polished = {}
			for _, asset in manifest.assets do
				if asset.kind == "animation" and asset.manualPolish then
					table.insert(polished, asset.id)
				end
			end
			table.sort(polished)
			t.expect(polished).toEqual({ "ANM_PLR_Collapse", "ANM_PLR_Exhausted", "ANM_PLR_WakeUp" })
		end)

		t.it("garde une poignée d'assets héros, pas la moitié du lot", function()
			local heroes = 0
			for _, asset in manifest.assets do
				if asset.hero then
					heroes += 1
				end
			end
			t.expect(heroes).toBeBetween(8, 25)
		end)
	end)
end
