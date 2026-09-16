--!strict
-- Seau à jetons par clé (joueur + remote). Pur : l'horloge est injectée.
-- Refuse quand le seau est vide ; se remplit à `refillPerSecond` jusqu'à `capacity`.

export type Bucket = { tokens: number, last: number }

export type RateLimiter = {
	allow: (self: RateLimiter, key: string, now: number) -> boolean,
	reset: (self: RateLimiter, key: string) -> (),
	prune: (self: RateLimiter, now: number, maxAge: number) -> number,
	capacity: number,
	refillPerSecond: number,
	buckets: { [string]: Bucket },
}

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(capacity: number, refillPerSecond: number): RateLimiter
	assert(capacity >= 1, "capacité >= 1")
	assert(refillPerSecond > 0, "recharge > 0")
	local self = setmetatable({
		capacity = capacity,
		refillPerSecond = refillPerSecond,
		buckets = {} :: { [string]: Bucket },
	}, RateLimiter)
	return (self :: any) :: RateLimiter
end

function RateLimiter.allow(self: RateLimiter, key: string, now: number): boolean
	local bucket = self.buckets[key]
	if bucket == nil then
		bucket = { tokens = self.capacity, last = now }
		self.buckets[key] = bucket
	end
	local elapsed = math.max(0, now - bucket.last)
	bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refillPerSecond)
	bucket.last = now
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter.reset(self: RateLimiter, key: string)
	self.buckets[key] = nil
end

function RateLimiter.prune(self: RateLimiter, now: number, maxAge: number): number
	local removed = 0
	for key, bucket in self.buckets do
		if now - bucket.last > maxAge then
			self.buckets[key] = nil
			removed += 1
		end
	end
	return removed
end

return RateLimiter
