-- Chargeur de modules "à la Roblox" pour Lune : reconstruit l'arbre src/ comme un DataModel virtuel
-- (script.Parent, FindFirstChild, WaitForChild, game:GetService("ReplicatedStorage").Shared...)
-- et exécute chaque ModuleScript avec `luau.load` en injectant `script`, `require`, `game`, `task`.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")

local Loader = {}

local Node = {}
Node.__index = function(self, key)
	local method = rawget(Node, key)
	if method ~= nil then
		return method
	end
	local children = rawget(self, "_children")
	local child = children[key]
	if child ~= nil then
		return child
	end
	error(string.format("%s n'est pas un enfant valide de %s", tostring(key), rawget(self, "_full")), 2)
end

function Node:FindFirstChild(name)
	return rawget(self, "_children")[name]
end

function Node:WaitForChild(name)
	local child = rawget(self, "_children")[name]
	if child == nil then
		error(string.format("WaitForChild(%s) : introuvable sous %s", tostring(name), rawget(self, "_full")), 2)
	end
	return child
end

function Node:GetChildren()
	local list = {}
	for _, child in rawget(self, "_children") do
		table.insert(list, child)
	end
	return list
end

function Node:GetDescendants()
	local list = {}
	for _, child in rawget(self, "_children") do
		table.insert(list, child)
		for _, d in child:GetDescendants() do
			table.insert(list, d)
		end
	end
	return list
end

function Node:IsA(className)
	return rawget(self, "ClassName") == className or className == "Instance"
end

function Node:GetAttribute()
	return nil
end

function Node:GetFullName()
	return rawget(self, "_full")
end

local function newNode(name, className, parent, file)
	local node = setmetatable({}, Node)
	rawset(node, "Name", name)
	rawset(node, "ClassName", className)
	rawset(node, "Parent", parent)
	rawset(node, "_children", {})
	rawset(node, "_file", file)
	rawset(node, "_full", parent and (rawget(parent, "_full") .. "." .. name) or name)
	if parent then
		rawget(parent, "_children")[name] = node
	end
	return node
end

local function stripExt(name)
	return (name:gsub("%.server%.luau$", ""):gsub("%.client%.luau$", ""):gsub("%.luau$", ""):gsub("%.lua$", ""))
end

-- Construit récursivement un dossier en Folder/ModuleScript (init.luau -> le dossier devient le module)
local function buildDir(dir, name, parent)
	local initPath = dir .. "/init.luau"
	local node
	if fs.isFile(initPath) then
		node = newNode(name, "ModuleScript", parent, initPath)
	else
		node = newNode(name, "Folder", parent, nil)
	end
	for _, entry in fs.readDir(dir) do
		local path = dir .. "/" .. entry
		if fs.isDir(path) then
			buildDir(path, entry, node)
		elseif entry:match("%.luau$") and entry ~= "init.luau" and not entry:match("%.spec%.luau$") then
			local className = "ModuleScript"
			if entry:match("%.server%.luau$") then
				className = "Script"
			elseif entry:match("%.client%.luau$") then
				className = "LocalScript"
			end
			newNode(stripExt(entry), className, node, path)
		end
	end
	return node
end

local cache = {}
local services = {}
local game = {}

function game:GetService(name)
	local service = services[name]
	if service == nil then
		error("service non simulé dans les tests : " .. tostring(name), 2)
	end
	return service
end

function game:IsLoaded()
	return true
end

local function vrequire(target)
	if type(target) == "string" then
		return require(target)
	end
	local file = rawget(target, "_file")
	if file == nil then
		error("require sur un non-module : " .. tostring(rawget(target, "_full")), 2)
	end
	if cache[file] ~= nil then
		return cache[file].value
	end
	local source = fs.readFile(file)
	local chunk = luau.load(source, {
		debugName = rawget(target, "_full"),
		environment = { script = target, require = vrequire, game = game, task = task, tick = os.clock },
		injectGlobals = true,
	})
	local value = chunk()
	cache[file] = { value = value }
	return value
end

-- Racine du jeu (dossier games/american-dream)
function Loader.setup(root)
	root = root or "."
	local replicatedStorage = newNode("ReplicatedStorage", "ReplicatedStorage", nil, nil)
	buildDir(root .. "/src/shared", "Shared", replicatedStorage)
	newNode("Remotes", "Folder", replicatedStorage, nil)
	newNode("Assets", "Folder", replicatedStorage, nil)
	local serverScriptService = newNode("ServerScriptService", "ServerScriptService", nil, nil)
	buildDir(root .. "/src/server", "Server", serverScriptService)
	services.ReplicatedStorage = replicatedStorage
	services.ServerScriptService = serverScriptService
	Loader.ReplicatedStorage = replicatedStorage
	Loader.Shared = replicatedStorage.Shared
	Loader.Server = serverScriptService.Server
	return Loader
end

-- Charge un module par chemin pointé sous Shared, ex : "Sim.EconomyMath"
function Loader.shared(path)
	local node = Loader.Shared
	for part in string.gmatch(path, "[^%.]+") do
		node = node:WaitForChild(part)
	end
	return vrequire(node)
end

function Loader.server(path)
	local node = Loader.Server
	for part in string.gmatch(path, "[^%.]+") do
		node = node:WaitForChild(part)
	end
	return vrequire(node)
end

Loader.require = vrequire
Loader.game = game

return Loader
