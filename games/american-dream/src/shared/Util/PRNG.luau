--!strict
-- Générateur pseudo-aléatoire déterministe (xorshift32 avec mélange), identique dans Roblox et Lune.
-- Utilisé par la génération de monde : même graine = même ville, sur tous les serveurs et en test.

export type PRNG = {
	next: (self: PRNG) -> number, -- [0, 1)
	int: (self: PRNG, min: number, max: number) -> number, -- entier inclusif
	range: (self: PRNG, min: number, max: number) -> number, -- réel
	chance: (self: PRNG, probability: number) -> boolean,
	pick: <T>(self: PRNG, list: { T }) -> T,
	shuffle: <T>(self: PRNG, list: { T }) -> { T },
	fork: (self: PRNG, label: string) -> PRNG,
	state: number,
}

local PRNG = {}
PRNG.__index = PRNG

local function mix(seed: number): number
	-- hachage entier 32 bits pour éviter les graines corrélées
	local x = bit32.band(seed, 0xFFFFFFFF)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = bit32.band(x * 0x7feb352d, 0xFFFFFFFF)
	x = bit32.bxor(x, bit32.rshift(x, 15))
	x = bit32.band(x * 0x846ca68b, 0xFFFFFFFF)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	if x == 0 then
		x = 0x9E3779B9
	end
	return x
end

local function hashString(text: string): number
	local h = 2166136261
	for i = 1, #text do
		h = bit32.bxor(h, string.byte(text, i))
		h = bit32.band(h * 16777619, 0xFFFFFFFF)
	end
	return h
end

function PRNG.new(seed: number): PRNG
	local self = setmetatable({ state = mix(math.floor(seed)) }, PRNG)
	return (self :: any) :: PRNG
end

function PRNG.next(self: PRNG): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	x = bit32.band(x, 0xFFFFFFFF)
	self.state = x
	return x / 4294967296
end

function PRNG.int(self: PRNG, min: number, max: number): number
	if max < min then
		min, max = max, min
	end
	return min + math.floor(self:next() * (max - min + 1))
end

function PRNG.range(self: PRNG, min: number, max: number): number
	return min + self:next() * (max - min)
end

function PRNG.chance(self: PRNG, probability: number): boolean
	return self:next() < probability
end

function PRNG.pick<T>(self: PRNG, list: { T }): T
	assert(#list > 0, "PRNG:pick sur une liste vide")
	return list[self:int(1, #list)]
end

function PRNG.shuffle<T>(self: PRNG, list: { T }): { T }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = self:int(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

function PRNG.fork(self: PRNG, label: string): PRNG
	return PRNG.new(bit32.bxor(self.state, hashString(label)))
end

PRNG.hashString = hashString

return PRNG
