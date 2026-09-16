--!strict
-- Génère et construit la ville au démarrage du serveur. Précharge les meshes du registre avant.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Layout = require(ReplicatedStorage.Shared.WorldGen.Layout)
local World = require(ReplicatedStorage.Shared.Config.World)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local CityBuilder = require(script.Parent.Parent.Builder.CityBuilder)
local AssetCache = require(script.Parent.Parent.Builder.AssetCache)

local WorldService = {}

WorldService.Ready = Signal.new() :: Signal.Signal<>

local city: Layout.City? = nil
local root: Folder? = nil
local ready = false

function WorldService.Init()
	city = Layout.generate(World.SEED)
end

function WorldService.Start()
	local started = os.clock()
	AssetCache.preload()
	local generated = city
	assert(generated ~= nil, "ville non générée")
	root = CityBuilder.build(generated)
	ready = true
	print(string.format("[WorldService] ville construite en %.2fs (%d placements)", os.clock() - started, #generated.placements))
	WorldService.Ready:Fire()
end

function WorldService.city(): Layout.City
	local generated = city
	assert(generated ~= nil, "ville non générée")
	return generated
end

function WorldService.isReady(): boolean
	return ready
end

function WorldService.waitUntilReady()
	if ready then
		return
	end
	WorldService.Ready:Wait()
end

function WorldService.plotCFrame(index: number): CFrame
	local generated = WorldService.city()
	local plot = generated.plots[index]
	assert(plot ~= nil, "plot inconnu : " .. tostring(index))
	return CFrame.new(plot.x, 0, plot.z) * CFrame.Angles(0, math.rad(plot.yaw), 0)
end

function WorldService.citySpawnCFrame(): CFrame
	local spawn = WorldService.city().spawn
	return CFrame.new(spawn.x, 3, spawn.z)
end

function WorldService.cityFolder(): Folder?
	local folder = root or Workspace:FindFirstChild("City")
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

return WorldService
