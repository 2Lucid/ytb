--!strict
-- Attribution de badges, idempotente et silencieuse si l'identifiant est à 0.

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.Services.DataService)

local Badges = {}

function Badges.award(player: Player, key: string)
	local id = Monetization.Badges[key] or 0
	local data = DataService.getData(player)
	if id == 0 or data == nil or data.badges[key] then
		return
	end
	task.spawn(function()
		local ok, result = pcall(function()
			return BadgeService:AwardBadgeAsync(player.UserId, id)
		end)
		if ok and result == true then
			data.badges[key] = true
			Remotes.getEvent("Notify"):FireClient(player, "notify.badge", {})
		elseif not ok then
			warn("[Badges] " .. key .. " : " .. tostring(result))
		end
	end)
end

return Badges
