--!strict
-- Formatage des nombres pour l'affichage (1.2K, 3.4M, 5.6B) et des durées.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi" }

function Format.money(amount: number): string
	if amount ~= amount then
		return "0"
	end
	local sign = amount < 0 and "-" or ""
	local value = math.abs(amount)
	if value < 1000 then
		return sign .. tostring(math.floor(value + 0.5))
	end
	local index = 1
	while value >= 1000 and index < #SUFFIXES do
		value /= 1000
		index += 1
	end
	local text: string
	if value >= 100 then
		text = string.format("%d", math.floor(value + 0.5))
	elseif value >= 10 then
		text = string.format("%.1f", value)
	else
		text = string.format("%.2f", value)
	end
	-- retire les zéros inutiles : 1.50 -> 1.5, 2.00 -> 2
	text = text:gsub("%.?0+$", "")
	return sign .. text .. SUFFIXES[index]
end

function Format.duration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	local minutes = seconds // 60
	local remaining = seconds % 60
	if minutes >= 60 then
		local hours = minutes // 60
		return string.format("%dh%02d", hours, minutes % 60)
	end
	return string.format("%d:%02d", minutes, remaining)
end

function Format.percent(ratio: number): string
	return string.format("%d%%", math.floor(math.clamp(ratio, 0, 1) * 100 + 0.5))
end

return Format
