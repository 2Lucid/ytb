--!strict
-- Contrôle qualité du lot : ce qui manque, ce qui n'a pas de texture, ce qui est trop lourd,
-- ce qui sort du gabarit. Renvoie des lignes de tableau lisibles. Pur : testable hors Studio.

local Quality = {}

export type Entry = {
	id: string,
	kind: string,
	category: string,
	scale: { number }?,
	maxTriangles: number?,
	hero: boolean?,
}

export type Record = { status: string, assetId: number, reason: string, triangles: number, textured: boolean, at: number }

export type Issue = { id: string, severity: string, problem: string, detail: string }

-- Limite dure de Roblox par MeshPart, et budget que l'on s'impose pour tenir 60 FPS sur mobile.
Quality.HARD_TRIANGLE_LIMIT = 10000
Quality.HERO_BUDGET = 5000
Quality.PROP_BUDGET = 2000

function Quality.audit(entries: { Entry }, records: { [string]: Record }): { Issue }
	local issues: { Issue } = {}
	local function add(id: string, severity: string, problem: string, detail: string)
		table.insert(issues, { id = id, severity = severity, problem = problem, detail = detail })
	end
	for _, entry in entries do
		if entry.kind ~= "mesh" and entry.kind ~= "character" then
			continue
		end
		local record = records[entry.id]
		if record == nil or record.status == "pending" then
			add(entry.id, "info", "jamais généré", "relancer le lot")
			continue
		end
		if record.status == "failed" then
			add(entry.id, "erreur", "génération échouée", record.reason)
			continue
		end
		if record.assetId <= 0 then
			add(entry.id, "erreur", "aucun identifiant d'asset", "la publication n'a pas abouti")
		end
		if not record.textured then
			add(entry.id, "avertissement", "aucune texture", "vérifier EditableImage / EditableMesh dans Game Settings > Security")
		end
		local budget = entry.hero == true and Quality.HERO_BUDGET or Quality.PROP_BUDGET
		if record.triangles > Quality.HARD_TRIANGLE_LIMIT then
			add(entry.id, "erreur", "au-dessus de la limite Roblox", string.format("%d triangles (max %d)", record.triangles, Quality.HARD_TRIANGLE_LIMIT))
		elseif record.triangles > budget then
			add(entry.id, "avertissement", "au-dessus du budget", string.format("%d triangles (budget %d)", record.triangles, budget))
		elseif record.triangles > 0 and record.triangles < 20 then
			add(entry.id, "avertissement", "géométrie quasi vide", string.format("%d triangles", record.triangles))
		end
	end
	table.sort(issues, function(a, b)
		if a.severity ~= b.severity then
			return a.severity < b.severity
		end
		return a.id < b.id
	end)
	return issues
end

function Quality.summary(entries: { Entry }, records: { [string]: Record }): string
	local total, done, failed, pending = 0, 0, 0, 0
	local triangles = 0
	for _, entry in entries do
		if entry.kind ~= "mesh" and entry.kind ~= "character" then
			continue
		end
		total += 1
		local record = records[entry.id]
		if record == nil or record.status == "pending" then
			pending += 1
		elseif record.status == "done" then
			done += 1
			triangles += record.triangles
		else
			failed += 1
		end
	end
	return string.format("%d/%d générés, %d échecs, %d en attente, %d triangles au total", done, total, failed, pending, triangles)
end

return Quality
