return function(t, loader)
	local Layout = loader.shared("WorldGen.Layout")
	local PlotLayout = loader.shared("WorldGen.PlotLayout")
	local Layouts = loader.shared("Config.Layouts")
	local World = loader.shared("Config.World")
	local Lore = loader.shared("Config.Lore")
	local PlotState = loader.shared("Sim.PlotState")

	t.describe("WorldGen.Layout (ville)", function()
		local city = Layout.generate()
		print(string.format("  ville : %d studs, %d placements (%d immeubles, %d props, %d panneaux, %d journaux)",
			city.size, #city.placements, city.counts.building or 0, city.counts.prop or 0, #city.billboards, #city.journals))
		t.it("est déterministe", function()
			local again = Layout.generate()
			t.expect(#again.placements).toBe(#city.placements)
			for index, p in city.placements do
				local q = again.placements[index]
				t.expect(q.id).toBe(p.id)
				t.expect(q.x).toBe(p.x)
				t.expect(q.z).toBe(p.z)
			end
			local other = Layout.generate(1)
			t.expect(other.placements[#other.placements].x == city.placements[#city.placements].x and #other.placements == #city.placements).toBe(false)
		end)
		t.it("a 6 plots, 12 panneaux et un journal par entrée de lore", function()
			t.expect(#city.plots).toBe(World.PLOTS)
			t.expect(#city.billboards).toBe(World.BILLBOARDS)
			t.expect(#city.journals).toBe(#Lore.Journals)
		end)
		t.it("garde tout dans l'emprise de la ville", function()
			local half = city.size / 2 + 1
			for _, p in city.placements do
				t.expect(math.abs(p.x)).toBeLessThanOrEqual(half)
				t.expect(math.abs(p.z)).toBeLessThanOrEqual(half)
				t.expect(p.sy).toBeGreaterThan(0)
			end
		end)
		t.it("éloigne les actes du centre (ruelle au centre, holding au bord)", function()
			local maxDist = {}
			local minDist = {}
			for _, p in city.placements do
				if p.kind == "building" then
					local d = math.max(math.abs(p.x), math.abs(p.z))
					maxDist[p.act] = math.max(maxDist[p.act] or 0, d)
					minDist[p.act] = math.min(minDist[p.act] or math.huge, d)
				end
			end
			t.expect(minDist[2]).toBeLessThan(minDist[3])
			t.expect(minDist[2]).toBeLessThan(minDist[5])
			t.expect(maxDist[5]).toBeGreaterThan(maxDist[2])
		end)
		t.it("ne fait pas se chevaucher les plots et laisse un immeuble par module", function()
			for a = 1, #city.plots do
				for b = a + 1, #city.plots do
					local dx = math.abs(city.plots[a].x - city.plots[b].x)
					local dz = math.abs(city.plots[a].z - city.plots[b].z)
					t.expect(math.max(dx, dz)).toBeGreaterThanOrEqual(Layouts.PLOT_SIZE)
				end
			end
			t.expect(city.counts.building).toBeBetween(150, 600)
		end)
	end)

	t.describe("WorldGen.PlotLayout (plot)", function()
		for variant = 1, #Layouts.Variants do
			local spec = PlotLayout.build(variant)
			t.it("variante " .. variant .. " reste dans le plot et sans chevauchement", function()
				local half = spec.size / 2
				local points = PlotLayout.machinePoints(spec)
				for _, p in points do
					t.expect(math.abs(p.x)).toBeLessThanOrEqual(half)
					t.expect(math.abs(p.z)).toBeLessThanOrEqual(half)
				end
				for a = 1, #points do
					for b = a + 1, #points do
						local d = math.sqrt((points[a].x - points[b].x) ^ 2 + (points[a].z - points[b].z) ^ 2)
						t.expect(d).toBeGreaterThanOrEqual(2)
					end
				end
				for _, item in PlotState.catalog() do
					if not (item.kind == "unlock" and item.act == 1) then
						local b = spec.buttons[item.id]
						t.expect(b).toBeTruthy()
						t.expect(math.abs(b.x)).toBeLessThanOrEqual(half)
						t.expect(math.abs(b.z)).toBeLessThanOrEqual(half)
					end
				end
			end)
		end
		t.it("place les 5 lignes d'actes et 4 droppers par ligne", function()
			local spec = PlotLayout.build(1)
			t.expect(#spec.lines).toBe(5)
			for _, line in spec.lines do
				t.expect(#line.droppers).toBe(4)
				t.expect(line.conveyorEnd.x).toBeGreaterThan(line.conveyorStart.x)
			end
		end)
	end)
end
