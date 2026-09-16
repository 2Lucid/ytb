--!strict
-- Résolution des assets par identifiant de manifest. Fallback silencieux : 0 -> greybox.

local AssetIds = require(script.Parent.Generated.AssetIds)

local AssetRegistry = {}

function AssetRegistry.mesh(id: string): number
	return AssetIds.meshes[id] or 0
end

function AssetRegistry.image(id: string): number
	return AssetIds.images[id] or 0
end

function AssetRegistry.audio(id: string): number
	return AssetIds.audio[id] or 0
end

function AssetRegistry.animation(id: string): number
	return AssetIds.animations[id] or 0
end

function AssetRegistry.contentId(assetId: number): string
	return "rbxassetid://" .. tostring(assetId)
end

function AssetRegistry.hasMesh(id: string): boolean
	return AssetRegistry.mesh(id) > 0
end

return AssetRegistry
