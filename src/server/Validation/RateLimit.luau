--!strict
-- Per-player token bucket for request frequency. Pure (time passed in).

local RateLimit = {}
RateLimit.__index = RateLimit

export type Bucket = { tokens: number, at: number }
export type RateLimit = typeof(setmetatable({} :: { rate: number, burst: number, buckets: { [number]: Bucket }, dropped: { [number]: number } }, RateLimit))

function RateLimit.new(perSecond: number, burst: number): RateLimit
	return setmetatable({ rate = perSecond, burst = burst, buckets = {}, dropped = {} }, RateLimit)
end

function RateLimit.allow(self: RateLimit, uid: number, now: number): boolean
	local b = self.buckets[uid]
	if b == nil then
		b = { tokens = self.burst, at = now }
		self.buckets[uid] = b
	end
	local elapsed = now - b.at
	if elapsed > 0 then
		b.tokens = math.min(self.burst, b.tokens + elapsed * self.rate)
		b.at = now
	end
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	self.dropped[uid] = (self.dropped[uid] or 0) + 1
	return false
end

function RateLimit.forget(self: RateLimit, uid: number)
	self.buckets[uid] = nil
	self.dropped[uid] = nil
end

return RateLimit
