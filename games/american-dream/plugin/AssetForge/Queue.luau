--!strict
-- File d'attente respectant la limite de Cube 3D (5 générations par minute et par expérience).
-- Pur : l'horloge et l'attente sont injectées, donc testable hors Studio.

export type Queue = {
	limit: number,
	window: number,
	stamps: { number },
	-- Renvoie le nombre de secondes à attendre avant le prochain jeton (0 si libre)
	delayFor: (self: Queue, now: number) -> number,
	consume: (self: Queue, now: number) -> (),
}

local Queue = {}
Queue.__index = Queue

function Queue.new(limit: number, window: number?): Queue
	local self = setmetatable({ limit = limit, window = window or 60, stamps = {} :: { number } }, Queue)
	return (self :: any) :: Queue
end

local function prune(self: Queue, now: number)
	local cutoff = now - self.window
	local kept: { number } = {}
	for _, stamp in self.stamps do
		if stamp > cutoff then
			table.insert(kept, stamp)
		end
	end
	self.stamps = kept
end

function Queue.delayFor(self: Queue, now: number): number
	prune(self, now)
	if #self.stamps < self.limit then
		return 0
	end
	local oldest = math.huge
	for _, stamp in self.stamps do
		oldest = math.min(oldest, stamp)
	end
	-- +0.25 s de marge : la limite est appliquée côté serveur Roblox
	return math.max(0, oldest + self.window - now) + 0.25
end

function Queue.consume(self: Queue, now: number)
	prune(self, now)
	table.insert(self.stamps, now)
end

return Queue
