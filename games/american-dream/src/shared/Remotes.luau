--!strict
-- Registre unique des remotes. Le serveur les crée (Remotes.create), le client les attend (Remotes.get).
-- Aucun remote ne transporte de montant venant du client : le client envoie des intentions, le serveur décide.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Definition = { name: string, class: "RemoteEvent" | "UnreliableRemoteEvent" | "RemoteFunction" }

local Remotes = {}

Remotes.Definitions = {
	-- serveur -> client
	{ name = "HudUpdate", class = "RemoteEvent" },
	{ name = "Notify", class = "RemoteEvent" },
	{ name = "MarketChanged", class = "RemoteEvent" },
	{ name = "LeaderboardChanged", class = "RemoteEvent" },
	{ name = "PlotChanged", class = "RemoteEvent" },
	{ name = "LifeEvent", class = "RemoteEvent" },
	{ name = "OpaEvent", class = "RemoteEvent" },
	{ name = "LoreEvent", class = "RemoteEvent" },
	{ name = "ShopState", class = "RemoteEvent" },
	{ name = "DropPulse", class = "UnreliableRemoteEvent" },
	-- client -> serveur
	{ name = "RequestState", class = "RemoteEvent" },
	{ name = "Purchase", class = "RemoteEvent" },
	{ name = "Collect", class = "RemoteEvent" },
	{ name = "ExitDoor", class = "RemoteEvent" },
	{ name = "OpaAttack", class = "RemoteEvent" },
	{ name = "OpaBuyback", class = "RemoteEvent" },
	{ name = "ReadJournal", class = "RemoteEvent" },
	{ name = "SetSetting", class = "RemoteEvent" },
	{ name = "PromptPurchase", class = "RemoteEvent" },
	{ name = "ClientEvent", class = "RemoteEvent" },
} :: { Definition }

local FOLDER_NAME = "Remotes"

local function folder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end
	if RunService:IsServer() then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = ReplicatedStorage
		return created
	end
	local waited = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	assert(waited:IsA("Folder"), "Remotes doit être un Folder")
	return waited
end

-- Serveur : crée tous les remotes manquants
function Remotes.create()
	assert(RunService:IsServer(), "Remotes.create est réservé au serveur")
	local parent = folder()
	for _, definition in Remotes.Definitions do
		if parent:FindFirstChild(definition.name) == nil then
			local remote = Instance.new(definition.class)
			remote.Name = definition.name
			remote.Parent = parent
		end
	end
end

function Remotes.getEvent(name: string): RemoteEvent
	local remote = folder():WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteEvent"), "RemoteEvent introuvable : " .. name)
	return remote
end

function Remotes.getUnreliable(name: string): UnreliableRemoteEvent
	local remote = folder():WaitForChild(name, 30)
	assert(remote and remote:IsA("UnreliableRemoteEvent"), "UnreliableRemoteEvent introuvable : " .. name)
	return remote
end

function Remotes.getFunction(name: string): RemoteFunction
	local remote = folder():WaitForChild(name, 30)
	assert(remote and remote:IsA("RemoteFunction"), "RemoteFunction introuvable : " .. name)
	return remote
end

return Remotes
