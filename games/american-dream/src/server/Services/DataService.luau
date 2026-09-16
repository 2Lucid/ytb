--!strict
-- Sauvegarde : ProfileStore (verrouillage de session, sauvegarde périodique et à la déconnexion).
-- Le reste du serveur ne touche jamais DataStoreService directement.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileStore = require(script.Parent.Parent.Vendor.ProfileStore)
local SaveSchema = require(ReplicatedStorage.Shared.Sim.SaveSchema)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Types = require(ReplicatedStorage.Shared.Types)

type PlayerData = Types.PlayerData

export type Profile = {
	Data: PlayerData,
	IsActive: (self: Profile) -> boolean,
	Reconcile: (self: Profile) -> (),
	EndSession: (self: Profile) -> (),
	AddUserId: (self: Profile, userId: number) -> (),
	Save: (self: Profile) -> (),
	OnSessionEnd: { Connect: (self: any, fn: () -> ()) -> any },
}

local DataService = {}

DataService.ProfileLoaded = Signal.new() :: Signal.Signal<Player, Profile>
DataService.ProfileReleased = Signal.new() :: Signal.Signal<Player>

local profiles: { [Player]: Profile } = {}
local store: any = nil
local usingMock = false

local function dataStoresAvailable(): boolean
	if not RunService:IsStudio() then
		return true
	end
	local ok = pcall(function()
		DataStoreService:GetDataStore("__probe"):GetAsync("probe")
	end)
	return ok
end

local function onPlayerAdded(player: Player)
	if store == nil then
		return
	end
	local profile = store:StartSessionAsync("Player_" .. player.UserId, {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if profile == nil then
		player:Kick("Impossible de charger tes données. Réessaie dans une minute.")
		return
	end
	profile:AddUserId(player.UserId)
	profile:Reconcile()
	SaveSchema.migrate(profile.Data)
	local data = profile.Data
	if data.layoutVariant == 0 then
		data.layoutVariant = SaveSchema.layoutVariantFor(player.UserId)
	end
	data.stats.sessions += 1
	local now = os.time()
	if data.stats.firstJoin == 0 then
		data.stats.firstJoin = now
	end
	data.stats.lastJoin = now
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		DataService.ProfileReleased:Fire(player)
		if player.Parent == Players then
			player:Kick("Session de données terminée ailleurs.")
		end
	end)
	if player.Parent ~= Players then
		profile:EndSession()
		return
	end
	profiles[player] = profile
	DataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile:EndSession()
	end
end

function DataService.Init()
	usingMock = not dataStoresAvailable()
	local base = ProfileStore.New(SaveSchema.STORE_NAME, SaveSchema.template())
	store = usingMock and base.Mock or base
	if usingMock then
		warn("[DataService] DataStores indisponibles : mode Mock (rien n'est sauvegardé)")
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

function DataService.get(player: Player): Profile?
	return profiles[player]
end

function DataService.getData(player: Player): PlayerData?
	local profile = profiles[player]
	if profile then
		return profile.Data
	end
	return nil
end

-- Attend le profil (au plus `timeout` secondes)
function DataService.waitFor(player: Player, timeout: number?): Profile?
	local deadline = os.clock() + (timeout or 20)
	while os.clock() < deadline do
		local profile = profiles[player]
		if profile then
			return profile
		end
		if player.Parent ~= Players then
			return nil
		end
		task.wait(0.1)
	end
	return nil
end

function DataService.isMock(): boolean
	return usingMock
end

function DataService.players(): { Player }
	local list = {}
	for player in profiles do
		table.insert(list, player)
	end
	return list
end

return DataService
