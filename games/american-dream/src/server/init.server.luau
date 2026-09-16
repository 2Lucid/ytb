--!strict
-- Point d'entrée serveur : crée les remotes, initialise puis démarre les services dans l'ordre des dépendances.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

Remotes.create()

local Services = script.Services

-- L'ordre compte : chaque service ne dépend que de ceux qui le précèdent.
local ORDER = {
	"DataService",
	"TelemetryService",
	"WorldService",
	"PlotService",
	"EconomyService",
	"PurchaseService",
	"LifeService",
	"MarketEventService",
	"EmployeeService",
	"LeaderboardService",
	"LoreService",
	"OpaService",
	"MonetizationService",
	"SessionService",
}

type Service = { Init: () -> (), Start: () -> () }

local loaded: { { name: string, service: Service } } = {}
local started = os.clock()

for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), "service manquant : " .. name)
	local service = require(module) :: Service
	table.insert(loaded, { name = name, service = service })
end

for _, entry in loaded do
	local ok, err = pcall(entry.service.Init :: any)
	if not ok then
		error(string.format("[Boot] Init de %s a échoué : %s", entry.name, tostring(err)))
	end
end

for _, entry in loaded do
	local ok, err = pcall(entry.service.Start :: any)
	if not ok then
		error(string.format("[Boot] Start de %s a échoué : %s", entry.name, tostring(err)))
	end
end

print(string.format("[Boot] %d services démarrés en %.2fs", #loaded, os.clock() - started))
