--!strict
-- Garde des remotes : validation de types, rate limiting par joueur et par remote, journalisation.
-- Aucun handler serveur n'est connecté à un RemoteEvent sans passer ici.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RateLimiter = require(ReplicatedStorage.Shared.Util.RateLimiter)

local RemoteGuard = {}

export type Validator = (...any) -> boolean
export type Handler = (player: Player, ...any) -> ()

local limiters: { [string]: RateLimiter.RateLimiter } = {}
local violations: { [number]: number } = {}

RemoteGuard.MAX_VIOLATIONS_BEFORE_KICK = 200

-- Validateurs composables
function RemoteGuard.isString(maxLength: number?): Validator
	return function(value: any): boolean
		return type(value) == "string" and #value <= (maxLength or 64)
	end
end

function RemoteGuard.isInteger(min: number?, max: number?): Validator
	return function(value: any): boolean
		if type(value) ~= "number" or value ~= value or value % 1 ~= 0 then
			return false
		end
		if min and value < min then
			return false
		end
		if max and value > max then
			return false
		end
		return true
	end
end

function RemoteGuard.isNumber(min: number?, max: number?): Validator
	return function(value: any): boolean
		if type(value) ~= "number" or value ~= value then
			return false
		end
		if min and value < min then
			return false
		end
		if max and value > max then
			return false
		end
		return true
	end
end

function RemoteGuard.isBoolean(): Validator
	return function(value: any): boolean
		return type(value) == "boolean"
	end
end

function RemoteGuard.oneOf(options: { string }): Validator
	return function(value: any): boolean
		return type(value) == "string" and table.find(options, value) ~= nil
	end
end

function RemoteGuard.optional(inner: Validator): Validator
	return function(value: any): boolean
		return value == nil or inner(value)
	end
end

local function registerViolation(player: Player, remoteName: string, reason: string)
	local count = (violations[player.UserId] or 0) + 1
	violations[player.UserId] = count
	if count % 20 == 1 then
		warn(string.format("[RemoteGuard] %s (%d) refusé sur %s : %s (total %d)", player.Name, player.UserId, remoteName, reason, count))
	end
	if count >= RemoteGuard.MAX_VIOLATIONS_BEFORE_KICK then
		player:Kick("Trop de requêtes invalides.")
	end
end

-- Connecte un handler protégé. `perSecond` = rythme accepté, `burst` = pic toléré.
function RemoteGuard.connect(remote: RemoteEvent, validators: { Validator }, perSecond: number, burst: number, handler: Handler): RBXScriptConnection
	local name = remote.Name
	local limiter = RateLimiter.new(burst, perSecond)
	limiters[name] = limiter
	return remote.OnServerEvent:Connect(function(player: Player, ...: any)
		if not limiter:allow(tostring(player.UserId), os.clock()) then
			registerViolation(player, name, "rate limit")
			return
		end
		local count = select("#", ...)
		if count > #validators then
			registerViolation(player, name, "trop d'arguments")
			return
		end
		local args = { ... }
		for index, validator in validators do
			if not validator(args[index]) then
				registerViolation(player, name, "argument " .. index .. " invalide")
				return
			end
		end
		local ok, err = pcall(handler :: any, player, ...)
		if not ok then
			warn(string.format("[RemoteGuard] erreur dans le handler %s : %s", name, tostring(err)))
		end
	end)
end

function RemoteGuard.violations(player: Player): number
	return violations[player.UserId] or 0
end

Players.PlayerRemoving:Connect(function(player: Player)
	violations[player.UserId] = nil
	for _, limiter in limiters do
		limiter:reset(tostring(player.UserId))
	end
end)

return RemoteGuard
