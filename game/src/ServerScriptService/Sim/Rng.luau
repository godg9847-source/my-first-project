--!strict
-- Small deterministic random number generator (xorshift32).
-- The battle simulation uses this instead of Roblox's Random so it can also run
-- outside Roblox in the headless test harness (game/tools/simtest).

local Rng = {}
Rng.__index = Rng

export type Rng = typeof(setmetatable({} :: { state: number }, Rng))

function Rng.new(seed: number?): Rng
	local s = math.floor(seed or 1) % 4294967296
	if s == 0 then
		s = 2463534242
	end
	return setmetatable({ state = s }, Rng)
end

-- Returns a float in [0, 1).
function Rng.next(self: Rng): number
	local x = self.state
	x = bit32.bxor(x, bit32.lshift(x, 13))
	x = bit32.bxor(x, bit32.rshift(x, 17))
	x = bit32.bxor(x, bit32.lshift(x, 5))
	self.state = x
	return x / 4294967296
end

-- Float in [a, b).
function Rng.range(self: Rng, a: number, b: number): number
	return a + (b - a) * self:next()
end

-- Integer in [a, b].
function Rng.int(self: Rng, a: number, b: number): number
	return a + math.floor(self:next() * (b - a + 1))
end

-- True with the given probability (0..1).
function Rng.chance(self: Rng, p: number): boolean
	return self:next() < p
end

function Rng.pick<T>(self: Rng, list: { T }): T
	return list[self:int(1, #list)]
end

return Rng
