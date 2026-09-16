--!strict
-- Point d'entrée client : attend les remotes, puis initialise et démarre les contrôleurs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Remotes", 30)
ReplicatedStorage:WaitForChild("Shared", 30)

local Controllers = script.Controllers

local ORDER = {
	"UIController",
	"LightingController",
	"BillboardController",
	"MachineAnimator",
	"DropVisualController",
	"SoundController",
	"CharacterController",
}

type Controller = { Init: () -> (), Start: () -> () }

local loaded: { { name: string, controller: Controller } } = {}

for _, name in ORDER do
	local module = Controllers:FindFirstChild(name)
	assert(module and module:IsA("ModuleScript"), "contrôleur manquant : " .. name)
	table.insert(loaded, { name = name, controller = require(module) :: Controller })
end

for _, entry in loaded do
	local ok, err = pcall(entry.controller.Init :: any)
	if not ok then
		warn(string.format("[Client] Init de %s a échoué : %s", entry.name, tostring(err)))
	end
end

for _, entry in loaded do
	local ok, err = pcall(entry.controller.Start :: any)
	if not ok then
		warn(string.format("[Client] Start de %s a échoué : %s", entry.name, tostring(err)))
	end
end

print(string.format("[Client] %d contrôleurs démarrés", #loaded))
