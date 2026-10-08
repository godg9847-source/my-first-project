--!nonstrict
--[[
	Battle: the fight simulation for one arena round (design framework §4, §5, §7, §8.4).

	This module is PURE LUAU: it never touches Roblox instances. It only keeps
	numbers (positions, HP, timers) and pushes "fx" events into a queue. The
	Renderer (Server/Renderer.luau) turns that state into parts every frame.
	Because of that, the exact same code also runs in the headless test harness
	(game/tools/simtest), which plays thousands of fights to catch bugs and to
	measure balance.

	Coordinates are 2D studs on the arena floor: x goes right (world X), y goes
	"down the screen" (world Z). (0, 0) is the arena centre; walls sit at
	x = ±halfX and y = ±halfY.

	Ability modules (Sim/Abilities/<FighterId>.luau) are documented in
	game/docs/ABILITY_API.md. The engine decides WHEN Ability 1 fires (from the
	fighter's trigger data) and when the Ultimate fires (tap or auto-fire);
	the module only decides WHAT happens.
]]

local Rng = require(script.Parent.Rng)

local Battle = {}
Battle.__index = Battle

local DEFAULTS = {
	TickRate = 60,
	HalfX = 24, -- standard 1v1 arena is 48 x 48 studs
	HalfY = 24,
	ContactCooldown = 0.4, -- per pair
	CruiseAccel = 150, -- studs/s² used to ease back to cruise speed
	WallJitterDegrees = 3,
	MinExitAngle = 15, -- degrees away from a wall after a bounce
	FirstCastDelay = 1.5, -- Ability 1 can first trigger this long after FIGHT
	UltPerDamage = 1 / 15, -- meter points per point of damage dealt
	UltPerDamageTaken = 1 / 15,
	UltPerSecond = 2.0,
	UltWindow = 6.0, -- tap window; auto-fires when it runs out
	FocusBonus = 0.10, -- tapped ULT: +10 % damage/heal/shield
	HeavyHitSpeed = 1.4, -- contact ×1.5 when moving at ≥ 1.4 × cruise
	HeavyHitMult = 1.5,
	SlamPower = 80, -- knockback ≥ this, then a wall within 0.4 s = Wall Slam
	SlamWindow = 0.4,
	SlamDamage = 30,
	RivalPullAfter = 5.0, -- no enemy collision for this long → fighters steer together
	RivalPullStart = 10, -- degrees/s, +5 each second, up to 30
	RivalPullRamp = 5,
	RivalPullMax = 30,
	CCGuardThreshold = 1.5, -- seconds of hard CC (decaying window ≈ 6 s) before immunity
	CCGuardImmunity = 3.0,
	GuardianCCMult = 0.75,
	HealCap = 0.30, -- of max HP per round
	RoleEdge = 0.12,
	SlowFloor = 0.5, -- speed never drops below 50 %
	MaxObjectsPerFighter = 14,
	MaxEntities = 200,
	RoundTime = 60, -- Overtime (Arena Collapse) starts
	CollapseSpeed = 1.0, -- studs/s per side
	CollapseMinHalf = 9, -- 48 → 18
	OvertimeDps = { 15, 30, 45 }, -- for seconds 60-65, 65-70, 70-75
	HardEnd = 75, -- decided by HP % at this time
	GimmickEventCap = 60,
	GimmickRoundCap = 120,
}

local HARD_CC = { stun = true, freeze = true, root = true }
local BLOCKS_CAST = { stun = true, freeze = true, silence = true }
local NO_MOVE = { stun = true, freeze = true, root = true }

-- Role Edge: attacker role → roles it deals +12 % to
local ROLE_EDGE = {
	Brawler = { Blaster = true },
	Blaster = { Trickster = true },
	Trickster = { Brawler = true },
	Controller = { Assassin = true },
	Assassin = { Guardian = true },
	Guardian = { Controller = true },
}
Battle.ROLE_EDGE = ROLE_EDGE

----------------------------------------------------------------------
-- small math helpers (shared with abilities through battle.math)
----------------------------------------------------------------------

local function len(x, y)
	return math.sqrt(x * x + y * y)
end

local function norm(x, y)
	local l = len(x, y)
	if l < 1e-6 then
		return 1, 0
	end
	return x / l, y / l
end

local function rotate(x, y, degrees)
	local a = math.rad(degrees)
	local c, s = math.cos(a), math.sin(a)
	return x * c - y * s, x * s + y * c
end

local function clamp(v, a, b)
	if v < a then
		return a
	elseif v > b then
		return b
	end
	return v
end

-- distance from point (px,py) to segment (ax,ay)-(bx,by)
local function segDist(px, py, ax, ay, bx, by)
	local dx, dy = bx - ax, by - ay
	local l2 = dx * dx + dy * dy
	local t = 0
	if l2 > 1e-9 then
		t = clamp(((px - ax) * dx + (py - ay) * dy) / l2, 0, 1)
	end
	return len(px - (ax + t * dx), py - (ay + t * dy))
end

Battle.math = { len = len, norm = norm, rotate = rotate, clamp = clamp, segDist = segDist }

----------------------------------------------------------------------
-- construction
----------------------------------------------------------------------

--[[
	opts = {
		fighters  = { [id] = def },          -- Shared/Fighters.luau .ById
		abilities = function(id) -> module | nil,
		gimmick   = module | nil,             -- Sim/Arenas/<name>.luau (setup/tick)
		config    = { ...overrides of DEFAULTS },
		seed      = number,
		halfX, halfY = numbers,               -- play-area half sizes (default 24 x 24)
		obstacles = { {x, y, r}, ... },       -- round pillars
		arenaData = { portals = {...}, puddles = {...} } -- extra map data for gimmicks
		finalClash = bool,                    -- Overtime damage from second 0
	}
]]
function Battle.new(opts)
	local cfg = table.clone(DEFAULTS)
	for k, v in pairs(opts.config or {}) do
		cfg[k] = v
	end
	local self = setmetatable({}, Battle)
	self.cfg = cfg
	self.halfX = opts.halfX or opts.half or cfg.HalfX
	self.halfY = opts.halfY or opts.half or cfg.HalfY
	self.baseHalfX, self.baseHalfY = self.halfX, self.halfY
	self.half = math.min(self.halfX, self.halfY)
	self.obstacles = opts.obstacles or {}
	self.arenaData = opts.arenaData or {}
	self.fighters = opts.fighters
	self.loadAbilities = opts.abilities
	self.gimmick = opts.gimmick
	self.finalClash = opts.finalClash or false
	self.rng = Rng.new(opts.seed or 1)
	self.time = 0
	self.units = {}
	self.entities = {}
	self.timers = {}
	self.fxQueue = {}
	self.nextId = 0
	self.result = nil
	self.overtime = false
	self.started = false
	self.lastEnemyContact = 0
	self.errors = {} -- ability errors are caught and recorded here instead of crashing the round
	self.gimmickState = {}
	self.props = {} -- visual-only objects created by arena gimmicks ({id, x, y, radius, visual})
	return self
end

function Battle:newId()
	self.nextId += 1
	return self.nextId
end

----------------------------------------------------------------------
-- randomness (seeded — never use math.random in the simulation)
----------------------------------------------------------------------

function Battle:rand()
	return self.rng:next()
end

function Battle:randRange(a, b)
	return self.rng:range(a, b)
end

function Battle:randInt(a, b)
	return self.rng:int(a, b)
end

function Battle:chance(p)
	return self.rng:chance(p)
end

function Battle:randomDir()
	local a = self.rng:range(0, math.pi * 2)
	return math.cos(a), math.sin(a)
end

-- random point inside the arena, at least `margin` studs from the walls
function Battle:randomPoint(margin)
	local m = margin or 4
	return self.rng:range(-self.halfX + m, self.halfX - m), self.rng:range(-self.halfY + m, self.halfY - m)
end

----------------------------------------------------------------------
-- fx: purely visual events for the renderer (the test harness ignores them)
----------------------------------------------------------------------

--[[
	Known fx kinds (see Server/Renderer.luau):
	  burst     {x, y, radius, color, duration}          expanding glowing sphere
	  ring      {x, y, radius, color, duration}          expanding flat ring
	  line      {x, y, x2, y2, width, color, duration}   flash line (slash, laser flash)
	  telegraph {x, y, radius, duration, team}           ground warning disc
	  text      {x, y, text, color, size}                floating text
	  callout   {unitId, text, slot, color}              ability name above a fighter
	  dmg       {unitId, x, y, amount, dmgKind, big}     damage number
	  banner    {text, color}                            big centre text for viewers
	  shake     {power, duration}                        camera shake for viewers
	  flash     {color, duration}                        screen tint for viewers
	  sound     {name, x, y}                             one of Renderer.SOUNDS
	  ultReady  {unitId, ownerId}
]]
function Battle:fx(kind, data)
	data = data or {}
	data.kind = kind
	data.t = self.time
	table.insert(self.fxQueue, data)
end

function Battle:flushFx()
	local q = self.fxQueue
	self.fxQueue = {}
	return q
end

-- ground warning circle in the owner's team colour (visual only)
function Battle:telegraph(x, y, radius, seconds, opts)
	opts = opts or {}
	self:fx("telegraph", { x = x, y = y, radius = radius, duration = seconds, team = opts.team, color = opts.color })
end

----------------------------------------------------------------------
-- units
----------------------------------------------------------------------

local function newHooks()
	return { onWallHit = {}, onCollide = {}, onDamaged = {}, onDealDamage = {}, onTick = {}, onDeath = {}, onAbility = {} }
end

local function triggerOf(def)
	local a1 = def.ability1 or {}
	return {
		trigger = a1.trigger or "timer",
		cooldown = a1.cooldown or 5,
		radius = a1.radius or 10,
		readyAt = 0, -- set at start()
		progress = 0, -- charge-up progress (seconds)
	}
end

--[[
	info = { team = 1|2, fighterId = "goku", x, y, dirX, dirY, ownerId = userId or 0 }
]]
function Battle:addUnit(info)
	local def = self.fighters[info.fighterId]
	assert(def, "unknown fighter " .. tostring(info.fighterId))
	local st = def.stats
	local dx, dy = norm(info.dirX or 1, info.dirY or 0)
	local unit = {
		id = self:newId(),
		team = info.team,
		ownerId = info.ownerId or 0,
		fighterId = info.fighterId,
		def = def,
		role = def.role,
		x = info.x or 0,
		y = info.y or 0,
		vx = dx * st.speed,
		vy = dy * st.speed,
		baseRadius = st.size / 2,
		radius = st.size / 2,
		baseMass = st.mass or 1,
		mass = st.mass or 1,
		baseSpeed = st.speed,
		hp = st.hp,
		maxHp = st.hp,
		contactDamage = st.contactDamage,
		chargeMult = st.chargeMult or 1,
		alive = true,
		isMinion = false,
		status = {},
		hooks = newHooks(),
		mem = {}, -- free scratch space for ability modules
		a1 = triggerOf(def),
		charge = 0,
		ultReady = false,
		ultWindowLeft = 0,
		ultRequested = false,
		ultActiveUntil = -1,
		instantUlt = info.instantUlt or false,
		lastHit = {}, -- [otherId] = time of last contact damage
		dash = nil,
		ccAccum = 0,
		ccImmuneUntil = -1,
		healed = 0,
		visual = {}, -- renderer hints (aura colour, scale, transparency...)
		stats = { damageDealt = 0, damageTaken = 0, casts1 = 0, casts2 = 0, focused = 0, contact = 0, ability = 0 },
	}
	table.insert(self.units, unit)
	local mod = self.loadAbilities and self.loadAbilities(info.fighterId)
	unit.ability = mod
	if mod and mod.setup then
		self:safeCall("setup", unit, mod.setup, self, unit)
	end
	return unit
end

--[[
	Spawn a temporary helper unit (clone, shadow soldier, summon...).
	spec = { hp, size, speed, contactDamage, ttl, look = "<fighterId>" or nil,
	         visual = {color=..., shape="orb"|nil, transparency}, mass, x, y, dirX, dirY, name,
	         damageMult (clones deal 40 %), keepAfterOwner }
	Minions bounce, collide and deal contact damage like fighters, but they do not
	count for winning the round, have no abilities, and vanish after ttl seconds.
	Max 3 alive per owner (the oldest is removed).
]]
function Battle:summon(owner, spec)
	local mine = {}
	for _, u in self.units do
		if u.isMinion and u.owner == owner and u.alive then
			table.insert(mine, u)
		end
	end
	if #mine >= 3 then
		self:kill(mine[1], nil)
	end
	local dx, dy = spec.dirX, spec.dirY
	if not dx then
		dx, dy = self:randomDir()
	end
	dx, dy = norm(dx, dy)
	local speed = spec.speed or owner.baseSpeed
	local size = spec.size or owner.baseRadius * 1.4
	local unit = {
		id = self:newId(),
		team = owner.team,
		ownerId = owner.ownerId,
		fighterId = spec.look or owner.fighterId,
		def = owner.def,
		role = owner.role,
		x = spec.x or owner.x,
		y = spec.y or owner.y,
		vx = dx * speed,
		vy = dy * speed,
		baseRadius = size / 2,
		radius = size / 2,
		baseMass = spec.mass or 0.6,
		mass = spec.mass or 0.6,
		baseSpeed = speed,
		hp = spec.hp or 150,
		maxHp = spec.hp or 150,
		contactDamage = spec.contactDamage or 15,
		damageMult = spec.damageMult,
		chargeMult = 0,
		alive = true,
		isMinion = true,
		owner = owner,
		ttl = spec.ttl or 8,
		keepAfterOwner = spec.keepAfterOwner,
		name = spec.name,
		status = {},
		hooks = newHooks(),
		mem = {},
		a1 = { trigger = "none", cooldown = math.huge, readyAt = math.huge, progress = 0 },
		charge = 0,
		ultReady = false,
		ultWindowLeft = 0,
		ultActiveUntil = -1,
		lastHit = {},
		ccAccum = 0,
		ccImmuneUntil = -1,
		healed = 0,
		visual = spec.visual or { transparency = 0.35 },
		minionVisual = spec.visual,
		stats = { damageDealt = 0, damageTaken = 0, casts1 = 0, casts2 = 0, focused = 0, contact = 0, ability = 0 },
	}
	self:clampInside(unit)
	table.insert(self.units, unit)
	self:fx("burst", { x = unit.x, y = unit.y, radius = unit.radius * 2, color = (spec.visual and spec.visual.color) or "#ffffff", duration = 0.3 })
	return unit
end

-- Mid-fight swap (Tag Out): replace a fighter with another one, keeping HP %, meter, position and heading.
function Battle:replaceUnit(old, newFighterId)
	local pct = clamp(old.hp / old.maxHp, 0.01, 1)
	local u = self:addUnit({
		team = old.team,
		fighterId = newFighterId,
		x = old.x,
		y = old.y,
		dirX = old.vx,
		dirY = old.vy,
		ownerId = old.ownerId,
		instantUlt = old.instantUlt,
	})
	u.hp = math.max(1, u.maxHp * pct)
	u.charge = old.charge
	u.ultReady = old.ultReady
	u.ultWindowLeft = old.ultWindowLeft
	u.a1.readyAt = self.time + 1.5 -- Ability 1 restarts
	if u.a1.trigger == "timer" then
		u.a1.readyAt = self.time + 1.5
	end
	old.alive = false
	old.replaced = true
	local idx = table.find(self.units, old)
	if idx then
		table.remove(self.units, idx)
	end
	-- entities owned by the old fighter keep working but now credit the new one
	for _, e in self.entities do
		if e.owner == old then
			e.owner = u
		end
	end
	self:fx("burst", { x = u.x, y = u.y, radius = u.radius * 3, color = "#ffffff", duration = 0.4 })
	self:fx("banner", { text = "TAG OUT!", color = "#ffffff" })
	return u
end

----------------------------------------------------------------------
-- queries
----------------------------------------------------------------------

function Battle:enemiesOf(unit, includeMinions)
	local out = {}
	for _, u in self.units do
		if u.alive and u.team ~= unit.team and (includeMinions or not u.isMinion) then
			table.insert(out, u)
		end
	end
	return out
end

function Battle:alliesOf(unit, includeSelf)
	local out = {}
	for _, u in self.units do
		if u.alive and u.team == unit.team and (includeSelf or u ~= unit) and not u.isMinion then
			table.insert(out, u)
		end
	end
	return out
end

-- nearest living enemy fighter (falls back to minions if no fighter is left)
function Battle:nearestEnemy(unit, minionsToo)
	local best, bestD = nil, math.huge
	for _, u in self.units do
		if u.alive and u.team ~= unit.team and (minionsToo or not u.isMinion) and not u.status.intangible then
			local d = len(u.x - unit.x, u.y - unit.y)
			if d < bestD then
				best, bestD = u, d
			end
		end
	end
	if not best and not minionsToo then
		return self:nearestEnemy(unit, true)
	end
	return best, bestD
end

-- living units whose circle overlaps the circle (x, y, r). filter: "enemy" / "ally" / nil, relative to `of`
function Battle:unitsInRadius(x, y, r, of, filter)
	local out = {}
	for _, u in self.units do
		if u.alive and len(u.x - x, u.y - y) <= r + u.radius then
			local ok = true
			if of and filter == "enemy" then
				ok = u.team ~= of.team
			elseif of and filter == "ally" then
				ok = u.team == of.team
			end
			if ok then
				table.insert(out, u)
			end
		end
	end
	return out
end

-- living units touched by the segment (x1,y1)-(x2,y2) of the given width
function Battle:unitsOnLine(x1, y1, x2, y2, width, of, filter)
	local out = {}
	for _, u in self.units do
		if u.alive and segDist(u.x, u.y, x1, y1, x2, y2) <= width / 2 + u.radius then
			local ok = true
			if of and filter == "enemy" then
				ok = u.team ~= of.team
			elseif of and filter == "ally" then
				ok = u.team == of.team
			end
			if ok then
				table.insert(out, u)
			end
		end
	end
	return out
end

function Battle:dirTo(from, to)
	return norm(to.x - from.x, to.y - from.y)
end

function Battle:distance(a, b)
	return len(a.x - b.x, a.y - b.y)
end

function Battle:hpPercent(unit)
	return unit.hp / unit.maxHp
end

-- where a ray from (x, y) in direction (dx, dy) hits the arena wall
function Battle:rayToWall(x, y, dx, dy)
	local hx, hy = self.halfX, self.halfY
	local t = math.huge
	if dx > 1e-6 then
		t = math.min(t, (hx - x) / dx)
	elseif dx < -1e-6 then
		t = math.min(t, (-hx - x) / dx)
	end
	if dy > 1e-6 then
		t = math.min(t, (hy - y) / dy)
	elseif dy < -1e-6 then
		t = math.min(t, (-hy - y) / dy)
	end
	if t == math.huge or t < 0 then
		t = 0
	end
	return x + dx * t, y + dy * t, t
end

function Battle:clampInside(obj, margin)
	local m = margin or obj.radius or 0
	obj.x = clamp(obj.x, -self.halfX + m, self.halfX - m)
	obj.y = clamp(obj.y, -self.halfY + m, self.halfY - m)
end

----------------------------------------------------------------------
-- timers
----------------------------------------------------------------------

-- run fn after `seconds` (sim time). Skipped if `owner` died. Returns a handle with .cancel()
function Battle:after(seconds, fn, owner)
	local t = { at = self.time + seconds, fn = fn, owner = owner, alive = true }
	function t.cancel()
		t.alive = false
	end
	table.insert(self.timers, t)
	return t
end

-- run fn(i) `count` times, every `interval` seconds (first call after `interval`, or immediately if startNow)
function Battle:every(interval, count, fn, owner, startNow)
	local i = 0
	local handle = { alive = true }
	function handle.cancel()
		handle.alive = false
	end
	local function tick()
		if not handle.alive or (owner and not owner.alive) then
			return
		end
		i += 1
		fn(i)
		if i < count then
			self:after(interval, tick, owner)
		end
	end
	if startNow then
		tick()
	else
		self:after(interval, tick, owner)
	end
	return handle
end

----------------------------------------------------------------------
-- hooks
----------------------------------------------------------------------

--[[
	Register a callback on a unit event. duration (optional) removes it after that many seconds.
	  onWallHit(battle, unit, nx, ny)          -- wall or pillar; (nx, ny) points back into the arena
	  onCollide(battle, unit, other)           -- other may be an ally or enemy
	  onDamaged(battle, unit, amount, source)  -- after damage applied
	  onDealDamage(battle, unit, target, amount, kind)
	  onTick(battle, unit, dt)
	  onDeath(battle, unit, killer)            -- set unit.hp > 0 inside to cancel the KO
	  onAbility(battle, unit, slot)
]]
function Battle:hook(unit, event, fn, duration)
	local list = unit.hooks[event]
	assert(list, "unknown hook " .. tostring(event))
	local entry = { fn = fn, untilT = duration and (self.time + duration) or math.huge }
	table.insert(list, entry)
	return entry
end

function Battle:fire(unit, event, ...)
	local list = unit.hooks[event]
	if not list or #list == 0 then
		return
	end
	local i = 1
	while i <= #list do
		local e = list[i]
		if self.time > e.untilT or e.dead then
			table.remove(list, i)
		else
			self:safeCall(event, unit, e.fn, self, unit, ...)
			i += 1
		end
	end
end

function Battle:safeCall(where, unit, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		local msg = string.format("[%s] %s: %s", unit and unit.fighterId or "?", where, tostring(err))
		table.insert(self.errors, msg)
		if #self.errors <= 10 then
			warn(msg)
		end
	end
	return ok
end

----------------------------------------------------------------------
-- status effects (ABILITY_API.md lists them all)
----------------------------------------------------------------------

function Battle:applyStatus(target, name, duration, params)
	if not target or not target.alive or duration <= 0 then
		return false
	end
	params = params or {}
	local now = self.time
	if name == "intangible" then
		duration = math.min(duration, 1.5)
	end
	if HARD_CC[name] then
		if target.status.invuln or target.status.intangible or target.status.unstoppable or now < target.ccImmuneUntil then
			self:fx("text", { x = target.x, y = target.y, text = "IMMUNE", color = "#dddddd", size = 0.8 })
			return false
		end
		if target.role == "Guardian" then
			duration *= self.cfg.GuardianCCMult
		end
		-- a stun interrupts a charge-up: lose half of the progress
		if name ~= "root" and target.a1 then
			target.a1.progress *= 0.5
		end
	end
	if name == "slow" and params.amount then
		params.amount = math.min(params.amount, 1 - self.cfg.SlowFloor)
	end
	if name == "lifesteal" and params.amount then
		params.amount = math.min(params.amount, 0.3)
	end
	if name == "shield" and params.amount and target.status.focus then
		params.amount *= 1 + self.cfg.FocusBonus
	end
	local cur = target.status[name]
	local untilT = now + duration
	if cur then
		cur.untilT = math.max(cur.untilT, untilT)
		for _, k in { "amount", "dps", "perHit" } do
			if params[k] and (cur[k] == nil or params[k] > cur[k]) then
				cur[k] = params[k]
				cur.source = params.source or cur.source
			end
		end
		if params.cap then
			cur.cap = params.cap
		end
	else
		local s = table.clone(params)
		s.untilT = untilT
		s.start = now
		target.status[name] = s
	end
	local labels = {
		stun = { "STUNNED", "#facc15" },
		freeze = { "FROZEN", "#67e8f9" },
		root = { "BOUND", "#b45309" },
		silence = { "SILENCED", "#7c3aed" },
	}
	if labels[name] then
		self:fx("text", { x = target.x, y = target.y, text = labels[name][1], color = labels[name][2], size = 0.9 })
	end
	if name == "grow" or name == "giant" then
		self:updateSize(target)
	end
	return true
end

function Battle:removeStatus(target, name)
	local s = target.status[name]
	if s then
		target.status[name] = nil
		if name == "grow" or name == "giant" then
			self:updateSize(target)
		end
	end
end

function Battle:hasStatus(target, name)
	return target.status[name] ~= nil
end

function Battle:cleanse(target)
	for _, n in { "stun", "freeze", "root", "silence", "slow", "burn", "poison", "bleed", "vulnerable" } do
		self:removeStatus(target, n)
	end
end

function Battle:updateSize(unit)
	local m = 1
	local g = unit.status.giant or unit.status.grow
	if g then
		m = g.amount or 1.4
	end
	unit.radius = unit.baseRadius * m
	unit.mass = unit.baseMass * ((unit.status.giant and m) or 1)
	self:clampInside(unit)
end

local function speedMult(unit)
	local m = 1
	local s = unit.status
	if s.slow then
		m *= (1 - clamp(s.slow.amount or 0.3, 0, 0.5))
	end
	if s.haste then
		m *= (1 + (s.haste.amount or 0.3))
	end
	if unit.speedMult then
		m *= unit.speedMult
	end
	return m
end
Battle.speedMult = speedMult

function Battle:canMove(unit)
	local s = unit.status
	return not (s.stun or s.freeze or s.root)
end

function Battle:canCast(unit)
	local s = unit.status
	return unit.alive and not (s.stun or s.freeze or s.silence)
end

function Battle:isHardCC(unit)
	local s = unit.status
	return s.stun ~= nil or s.freeze ~= nil or s.root ~= nil
end

----------------------------------------------------------------------
-- meters
----------------------------------------------------------------------

function Battle:addCharge(unit, amount)
	if unit.isMinion or not unit.alive then
		return
	end
	if self.time < unit.ultActiveUntil then
		return
	end
	if unit.ultReady then
		return
	end
	unit.charge = clamp(unit.charge + amount * (unit.chargeMult or 1), 0, 100)
end

function Battle:drainUlt(target, amount)
	if target.ultReady then
		return
	end
	target.charge = math.max(0, target.charge - amount)
	self:fx("text", { x = target.x, y = target.y, text = "-" .. math.floor(amount) .. " ULT", color = "#d946ef", size = 0.8 })
end

function Battle:isFocused(unit)
	return unit.status.focus ~= nil
end

----------------------------------------------------------------------
-- damage & healing
----------------------------------------------------------------------

--[[
	damage(source, target, amount, opts)
	  source: unit or nil (arena/overtime). Minion damage is credited to its owner for meters.
	  opts.kind: "ability" (default) | "contact" | "dot" | "true" (ignores shield & bonuses) | "reflect"
	  opts.noCharge, opts.silent, opts.big (yellow number)
	Returns the damage actually dealt.
]]
function Battle:damage(source, target, amount, opts)
	if not target or not target.alive or not amount or amount <= 0 then
		return 0
	end
	opts = opts or {}
	local kind = opts.kind or "ability"
	local attacker = source
	if attacker and attacker.isMinion and attacker.owner then
		attacker = attacker.owner
	end
	if target.status.invuln or target.status.intangible then
		if not opts.silent then
			self:fx("text", { x = target.x, y = target.y, text = "BLOCK", color = "#ffffff", size = 0.7 })
		end
		return 0
	end
	local dmg = amount
	if kind ~= "true" then
		local bonus = 0
		if source and source.status.empower then
			bonus += source.status.empower.amount or 0.25
		end
		if source and source.status.focus then
			bonus += self.cfg.FocusBonus
		end
		if target.status.vulnerable then
			bonus += target.status.vulnerable.amount or 0.2
		end
		if target.status.freeze then
			bonus += 0.15
		end
		dmg *= (1 + bonus)
		local srcRole = attacker and attacker.role
		if srcRole and target.role and ROLE_EDGE[srcRole] and ROLE_EDGE[srcRole][target.role] then
			dmg *= (1 + self.cfg.RoleEdge)
		end
		if source and source.damageMult then
			dmg *= source.damageMult
		end
		if target.damageTakenMult then
			dmg *= target.damageTakenMult
		end
		if target.status.shield then
			local sh = target.status.shield
			local absorbed = math.min(sh.amount or 0, dmg)
			sh.amount = (sh.amount or 0) - absorbed
			dmg -= absorbed
			if sh.amount <= 0 then
				self:removeStatus(target, "shield")
				self:fx("burst", { x = target.x, y = target.y, radius = target.radius * 2.2, color = "#fde68a", duration = 0.25 })
			end
		end
	end
	if dmg <= 0 then
		return 0
	end
	target.hp -= dmg
	target.stats.damageTaken += dmg
	target.lastAttacker = attacker
	if attacker and attacker ~= target then
		attacker.stats.damageDealt += dmg
		if kind == "contact" then
			attacker.stats.contact += dmg
		else
			attacker.stats.ability += dmg
		end
	end
	if not opts.noCharge then
		if attacker and attacker ~= target and not attacker.isMinion and attacker.team ~= target.team then
			local per = self.cfg.UltPerDamage * (target.isMinion and 0.5 or 1)
			self:addCharge(attacker, dmg * per)
		end
		if not target.isMinion then
			self:addCharge(target, dmg * self.cfg.UltPerDamageTaken)
		end
	end
	if attacker and attacker ~= target and attacker.status.lifesteal and kind ~= "dot" and kind ~= "reflect" then
		self:heal(attacker, dmg * (attacker.status.lifesteal.amount or 0.2), true)
	end
	if source and source ~= target and target.status.reflect and kind ~= "reflect" and kind ~= "dot" then
		local r = target.status.reflect
		local cap = r.cap or 300
		r.reflected = r.reflected or 0
		local back = math.min(dmg * (r.amount or 1), cap - r.reflected)
		if back > 0 then
			r.reflected += back
			self:damage(target, attacker or source, back, { kind = "reflect", noCharge = true, big = true })
		end
	end
	if not opts.silent then
		self:fx("dmg", { unitId = target.id, x = target.x, y = target.y, amount = dmg, dmgKind = kind, big = opts.big })
	end
	if attacker and attacker ~= target then
		self:fire(attacker, "onDealDamage", target, dmg, kind)
	end
	-- Ability 1 "hurt" trigger
	if target.a1 and target.a1.trigger == "hurt" and source and source ~= target then
		self:tryTrigger(target, { source = attacker or source, amount = dmg })
	end
	self:fire(target, "onDamaged", dmg, attacker)
	if target.hp <= 0 then
		self:kill(target, attacker)
	end
	return dmg
end

-- damage = a % of the target's max HP
function Battle:damagePercent(source, target, percent, opts)
	return self:damage(source, target, target.maxHp * percent / 100, opts)
end

-- KO the target if its HP is below `percent` % (Execute, ULT only, ≤ 12)
function Battle:execute(source, target, percent)
	if target and target.alive and not target.isMinion and target.hp / target.maxHp * 100 < math.min(percent, 12) then
		self:fx("text", { x = target.x, y = target.y, text = "EXECUTED!", color = "#ff3b3b", size = 1.4 })
		self:kill(target, source)
		return true
	end
	return false
end

function Battle:heal(unit, amount, silent)
	if not unit.alive or amount <= 0 or unit.isMinion then
		return 0
	end
	if unit.status.focus then
		amount *= 1 + self.cfg.FocusBonus
	end
	if unit.status.poison then
		amount *= 0.7
	end
	local capLeft = unit.maxHp * self.cfg.HealCap - unit.healed
	amount = math.min(amount, capLeft)
	if amount <= 0 then
		return 0
	end
	local before = unit.hp
	unit.hp = math.min(unit.maxHp, unit.hp + amount)
	local healed = unit.hp - before
	unit.healed += healed
	if healed >= 1 and not silent then
		self:fx("dmg", { unitId = unit.id, x = unit.x, y = unit.y, amount = healed, dmgKind = "heal" })
	end
	return healed
end

function Battle:kill(unit, killer)
	if not unit.alive then
		return
	end
	unit.hp = 0
	self:fire(unit, "onDeath", killer)
	if unit.hp > 0 then
		return -- a passive cancelled the KO
	end
	unit.alive = false
	unit.diedAt = self.time
	self:fx("burst", { x = unit.x, y = unit.y, radius = unit.radius * 3, color = unit.isMinion and "#dddddd" or "#ff5a3c", duration = 0.45 })
	if not unit.isMinion then
		self:fx("shake", { power = 0.6, duration = 0.35 })
	end
end

----------------------------------------------------------------------
-- movement helpers for abilities
----------------------------------------------------------------------

-- push a unit away along (dx, dy). power ≈ studs/second (std 70, range 40-110), divided by mass
function Battle:knockback(target, dx, dy, power, source)
	if not target.alive or target.status.unstoppable or target.status.intangible then
		return
	end
	dx, dy = norm(dx, dy)
	local m = target.mass or 1
	target.vx += dx * power / m
	target.vy += dy * power / m
	if power >= self.cfg.SlamPower then
		target.slam = { untilT = self.time + self.cfg.SlamWindow, source = source }
	end
end

-- pull a unit toward a point
function Battle:pull(target, x, y, power, source)
	self:knockback(target, x - target.x, y - target.y, power, source)
	if target.slam then
		target.slam = nil -- pulls never slam
	end
end

--[[
	dash(unit, dirX, dirY, speed, duration, opts)
	The unit flies straight at `speed` (≤ 120) for `duration`, bouncing off walls.
	opts.damage / knockback / status = {name, secs, params} / onHit(battle, unit, target) per enemy touched (once each)
	opts.pierce: pass through enemies instead of bouncing; opts.stopOnWall
]]
function Battle:dash(unit, dx, dy, speed, duration, opts)
	if not unit.alive then
		return
	end
	dx, dy = norm(dx, dy)
	speed = math.min(speed, 120)
	unit.dash = { dx = dx, dy = dy, speed = speed, untilT = self.time + duration, hit = {}, opts = opts or {} }
	unit.vx, unit.vy = dx * speed, dy * speed
end

function Battle:teleport(unit, x, y)
	self:fx("burst", { x = unit.x, y = unit.y, radius = unit.radius * 1.6, color = "#ffffff", duration = 0.3 })
	unit.x, unit.y = x, y
	self:clampInside(unit)
	self:fx("burst", { x = unit.x, y = unit.y, radius = unit.radius * 1.6, color = "#ffffff", duration = 0.2 })
end

function Battle:setDirection(unit, dx, dy)
	dx, dy = norm(dx, dy)
	local s = math.max(len(unit.vx, unit.vy), unit.baseSpeed * speedMult(unit))
	unit.vx, unit.vy = dx * s, dy * s
end

-- visual hint for the renderer, e.g. battle:setVisual(unit, {aura="#ffd23f", scale=1.2}, 5)
function Battle:setVisual(unit, visual, duration)
	for k, v in visual do
		unit.visual[k] = v
	end
	if duration then
		self:after(duration, function()
			for k in visual do
				unit.visual[k] = nil
			end
		end)
	end
end

----------------------------------------------------------------------
-- entities (projectiles, zones, beams, traps, walls...)
----------------------------------------------------------------------

--[[
	spawn(spec) -> entity. Fields (all optional except owner):
	  owner, kind, x, y, vx, vy, radius
	  shape        "circle" (default) or "segment" (x,y -> x2,y2 with width)
	  ttl          seconds to live
	  hits         "enemies" (default) | "allies" | "all" | "none"
	  damage       damage on touch; tick = re-hit interval (zones); once (default for projectiles)
	  pierce       projectiles keep flying after a hit
	  wall         "bounce" | "die" (default when moving) | "stop" | "ignore"; maxBounces
	  onHit(battle, e, target), onUpdate(battle, e, dt), onExpire(battle, e), onWall(battle, e)
	  follow (unit, offsetX/offsetY), bindToOwner
	  homing (unit), turnRate (degrees/s)
	  status {name, secs, params}, knockback (power)
	  blocksProjectiles, persistent (counts toward the 4-hazard cap)
	  visual {shape="ball"|"block"|"disc"|"ring"|"beam"|"cylinder"|"spike"|"none", color, size, height, transparency, light, trail}
]]
function Battle:spawn(spec)
	assert(spec.owner, "entity needs an owner")
	local owner = spec.owner
	-- per-fighter object cap (14) and persistent hazard cap (4): drop the oldest
	local mine, persistent = {}, {}
	for _, e in self.entities do
		if not e.dead and e.owner == owner then
			table.insert(mine, e)
			if e.persistent then
				table.insert(persistent, e)
			end
		end
	end
	if spec.persistent and #persistent >= 4 then
		self:destroy(persistent[1])
	end
	if #mine >= self.cfg.MaxObjectsPerFighter then
		self:destroy(mine[1])
	end
	if #self.entities >= self.cfg.MaxEntities then
		local old = table.remove(self.entities, 1)
		old.dead = true
	end
	local e = spec
	e.id = self:newId()
	e.team = spec.team or owner.team
	e.x = e.x or owner.x
	e.y = e.y or owner.y
	e.vx = e.vx or 0
	e.vy = e.vy or 0
	e.radius = e.radius or 1
	e.shape = e.shape or "circle"
	e.hits = e.hits or "enemies"
	e.born = self.time
	e.hitLog = {}
	e.bounces = 0
	if e.once == nil then
		e.once = (e.tick == nil)
	end
	if e.wall == nil then
		e.wall = ((e.vx ~= 0 or e.vy ~= 0) and "die") or "ignore"
	end
	e.visual = e.visual or { shape = "ball", color = "#ffffff" }
	table.insert(self.entities, e)
	return e
end

function Battle:destroy(e)
	if e.dead then
		return
	end
	e.dead = true
	if e.onExpire then
		self:safeCall("onExpire", e.owner, e.onExpire, self, e)
	end
end

local function entityTouches(e, u)
	if e.shape == "segment" then
		return segDist(u.x, u.y, e.x, e.y, e.x2 or e.x, e.y2 or e.y) <= (e.width or 1) / 2 + u.radius
	end
	return len(u.x - e.x, u.y - e.y) <= e.radius + u.radius
end

function Battle:entityTargets(e, u)
	if not u.alive then
		return false
	end
	if u.status.intangible and (e.vx ~= 0 or e.vy ~= 0) then
		return false -- projectiles pass through intangible units
	end
	if e.hits == "none" then
		return false
	elseif e.hits == "enemies" then
		return u.team ~= e.team
	elseif e.hits == "allies" then
		return u.team == e.team
	end
	return true
end

function Battle:updateEntity(e, dt)
	if e.ttl and self.time - e.born >= e.ttl then
		self:destroy(e)
		return
	end
	if e.bindToOwner and not e.owner.alive then
		self:destroy(e)
		return
	end
	if e.follow then
		if not e.follow.alive then
			self:destroy(e)
			return
		end
		local fx, fy = e.follow.x + (e.offsetX or 0), e.follow.y + (e.offsetY or 0)
		if e.shape == "segment" then
			local dx, dy = fx - e.x, fy - e.y
			e.x2 = (e.x2 or e.x) + dx
			e.y2 = (e.y2 or e.y) + dy
		end
		e.x, e.y = fx, fy
	end
	if e.homing and e.homing.alive then
		local tx, ty = norm(e.homing.x - e.x, e.homing.y - e.y)
		local sp = len(e.vx, e.vy)
		local cx, cy = norm(e.vx, e.vy)
		local turn = math.rad(e.turnRate or 180) * dt
		local ang = math.atan2(cx * ty - cy * tx, cx * tx + cy * ty)
		ang = clamp(ang, -turn, turn)
		local c, s = math.cos(ang), math.sin(ang)
		e.vx, e.vy = (cx * c - cy * s) * sp, (cx * s + cy * c) * sp
	end
	if e.onUpdate then
		self:safeCall("entity.onUpdate", e.owner, e.onUpdate, self, e, dt)
		if e.dead then
			return
		end
	end
	if e.vx ~= 0 or e.vy ~= 0 then
		e.x += e.vx * dt
		e.y += e.vy * dt
		if e.shape == "segment" and e.x2 then
			e.x2 += e.vx * dt
			e.y2 += e.vy * dt
		end
		local r = (e.shape == "circle") and e.radius or 0
		local hx, hy = self.halfX - r, self.halfY - r
		local hitWall = false
		if e.x > hx or e.x < -hx then
			hitWall = true
			if e.wall == "bounce" then
				e.vx = -e.vx
			end
			e.x = clamp(e.x, -hx, hx)
		end
		if e.y > hy or e.y < -hy then
			hitWall = true
			if e.wall == "bounce" then
				e.vy = -e.vy
			end
			e.y = clamp(e.y, -hy, hy)
		end
		-- pillars
		if e.shape == "circle" then
			for _, o in self.obstacles do
				local d = len(e.x - o.x, e.y - o.y)
				if d < o.r + e.radius then
					hitWall = true
					local nx, ny = norm(e.x - o.x, e.y - o.y)
					e.x, e.y = o.x + nx * (o.r + e.radius), o.y + ny * (o.r + e.radius)
					if e.wall == "bounce" then
						local dot = e.vx * nx + e.vy * ny
						e.vx, e.vy = e.vx - 2 * dot * nx, e.vy - 2 * dot * ny
					end
				end
			end
		end
		if hitWall then
			e.bounces += 1
			if e.onWall then
				self:safeCall("entity.onWall", e.owner, e.onWall, self, e)
			end
			if e.wall == "die" or (e.maxBounces and e.bounces > e.maxBounces) then
				self:destroy(e)
				return
			elseif e.wall == "stop" then
				e.vx, e.vy = 0, 0
			end
		end
	end
	if e.blocksProjectiles then
		for _, o in self.entities do
			if not o.dead and o ~= e and o.team ~= e.team and (o.vx ~= 0 or o.vy ~= 0) and o.shape == "circle" and entityTouches(e, o) then
				self:destroy(o)
				self:fx("burst", { x = o.x, y = o.y, radius = 1.5, color = "#ffffff", duration = 0.15 })
			end
		end
	end
	for _, u in self.units do
		if not e.dead and self:entityTargets(e, u) and entityTouches(e, u) then
			local last = e.hitLog[u.id]
			local ready
			if e.once then
				ready = last == nil
			else
				ready = last == nil or (self.time - last) >= e.tick
			end
			if ready then
				e.hitLog[u.id] = self.time
				if e.damage and e.damage > 0 then
					self:damage(e.owner, u, e.damage, { kind = e.damageKind or "ability", big = e.big })
				end
				if e.status and u.alive then
					self:applyStatus(u, e.status[1], e.status[2], e.status[3])
				end
				if e.knockback and u.alive then
					local kx, ky = u.x - e.x, u.y - e.y
					if e.shape == "segment" or (e.vx ~= 0 or e.vy ~= 0) then
						if e.vx ~= 0 or e.vy ~= 0 then
							kx, ky = e.vx, e.vy
						end
					end
					self:knockback(u, kx, ky, e.knockback, e.owner)
				end
				if e.onHit then
					self:safeCall("entity.onHit", e.owner, e.onHit, self, e, u)
				end
				if (e.vx ~= 0 or e.vy ~= 0) and not e.pierce and e.shape == "circle" and e.hits ~= "allies" then
					self:destroy(e)
				end
			end
		end
	end
end

----------------------------------------------------------------------
-- convenience spawners used by most abilities
----------------------------------------------------------------------

-- straight projectile from the unit toward (dx, dy)
function Battle:shoot(unit, dx, dy, spec)
	dx, dy = norm(dx, dy)
	spec = spec or {}
	local speed = clamp(spec.speed or 60, 20, 120)
	spec.owner = unit
	spec.kind = spec.kind or "projectile"
	spec.x = spec.x or (unit.x + dx * (unit.radius + 0.5))
	spec.y = spec.y or (unit.y + dy * (unit.radius + 0.5))
	spec.vx, spec.vy = dx * speed, dy * speed
	spec.radius = spec.radius or 1
	spec.ttl = spec.ttl or 3
	spec.visual = spec.visual or { shape = "ball", color = "#ffffff", trail = true }
	return self:spawn(spec)
end

-- instant circular blast. Returns the list of enemies hit.
function Battle:blast(unit, x, y, radius, damage, spec)
	spec = spec or {}
	local targets = self:unitsInRadius(x, y, radius, unit, spec.filter or "enemy")
	self:fx("burst", { x = x, y = y, radius = radius, color = spec.color or "#ffffff", duration = spec.duration or 0.35 })
	for _, t in targets do
		if damage and damage > 0 then
			self:damage(unit, t, damage, { kind = spec.kind or "ability", big = spec.big })
		end
		if t.alive and spec.status then
			self:applyStatus(t, spec.status[1], spec.status[2], spec.status[3])
		end
		if t.alive and spec.knockback then
			self:knockback(t, t.x - x, t.y - y, spec.knockback, unit)
		end
		if spec.onHit then
			self:safeCall("blast.onHit", unit, spec.onHit, t)
		end
	end
	return targets
end

-- beam/line from the unit in direction (dx, dy). length nil = to the wall.
-- With spec.duration it lingers (ticking every spec.tick) and can track the target (spec.track = unit, spec.trackRate deg/s ≤ 45)
function Battle:beam(unit, dx, dy, spec)
	spec = spec or {}
	dx, dy = norm(dx, dy)
	local width = spec.width or 3
	local function endpoint(ox, oy, ddx, ddy)
		if spec.length then
			return ox + ddx * spec.length, oy + ddy * spec.length
		end
		local wx, wy = self:rayToWall(ox, oy, ddx, ddy)
		return wx, wy
	end
	if spec.duration and spec.duration > 0 then
		local x2, y2 = endpoint(unit.x, unit.y, dx, dy)
		local e = self:spawn({
			owner = unit,
			kind = "beam",
			shape = "segment",
			x = unit.x,
			y = unit.y,
			x2 = x2,
			y2 = y2,
			width = width,
			ttl = spec.duration,
			damage = spec.damage,
			tick = spec.tick or 0.25,
			status = spec.status,
			knockback = spec.knockback,
			onHit = spec.onHit,
			big = spec.big,
			visual = { shape = "beam", color = spec.color or "#ffffff", transparency = 0.1, light = true, height = spec.height },
		})
		e.dirX, e.dirY = dx, dy
		e.onUpdate = function(b, ent, dt)
			if not unit.alive then
				b:destroy(ent)
				return
			end
			-- tracking (≤ 45°/s by the rules)
			if spec.track and spec.track.alive then
				local tx, ty = norm(spec.track.x - unit.x, spec.track.y - unit.y)
				local ang = math.atan2(ent.dirX * ty - ent.dirY * tx, ent.dirX * tx + ent.dirY * ty)
				local maxT = math.rad(math.min(spec.trackRate or 45, 45)) * dt
				ang = clamp(ang, -maxT, maxT)
				ent.dirX, ent.dirY = rotate(ent.dirX, ent.dirY, math.deg(ang))
			end
			ent.x, ent.y = unit.x, unit.y
			ent.x2, ent.y2 = endpoint(unit.x, unit.y, ent.dirX, ent.dirY)
		end
		return e
	end
	local x2, y2 = endpoint(unit.x, unit.y, dx, dy)
	self:fx("line", { x = unit.x, y = unit.y, x2 = x2, y2 = y2, width = width, color = spec.color or "#ffffff", duration = 0.3 })
	local hit = self:unitsOnLine(unit.x, unit.y, x2, y2, width, unit, "enemy")
	for _, t in hit do
		if spec.damage then
			self:damage(unit, t, spec.damage, { big = spec.big })
		end
		if t.alive and spec.status then
			self:applyStatus(t, spec.status[1], spec.status[2], spec.status[3])
		end
		if t.alive and spec.knockback then
			self:knockback(t, dx, dy, spec.knockback, unit)
		end
		if spec.onHit then
			self:safeCall("beam.onHit", unit, spec.onHit, t)
		end
	end
	return hit
end

-- lingering circular area
function Battle:zone(unit, x, y, radius, spec)
	spec = spec or {}
	return self:spawn({
		owner = unit,
		kind = "zone",
		x = x,
		y = y,
		radius = radius,
		ttl = spec.duration or 3,
		damage = spec.damage,
		tick = spec.tick or 0.5,
		hits = spec.hits or "enemies",
		status = spec.status,
		onHit = spec.onHit,
		follow = spec.follow,
		bindToOwner = spec.bindToOwner,
		persistent = spec.persistent,
		visual = spec.visual or { shape = "disc", color = spec.color or "#ff3b3b", transparency = 0.45 },
	})
end

----------------------------------------------------------------------
-- abilities
----------------------------------------------------------------------

function Battle:cast(unit, slot, ctx)
	local mod = unit.ability
	local fn = mod and (slot == 1 and mod.ability1 or mod.ability2)
	local adef = slot == 1 and unit.def.ability1 or unit.def.ability2
	if adef then
		self:fx("callout", { unitId = unit.id, x = unit.x, y = unit.y, text = adef.name, slot = slot, color = adef.color or (unit.def.look and unit.def.look.aura) })
	end
	if slot == 1 then
		unit.stats.casts1 += 1
	else
		unit.stats.casts2 += 1
		self:fx("banner", { text = string.upper(adef and adef.name or "ULTIMATE") .. "!", color = adef and adef.color or "#ffffff", ownerId = unit.ownerId })
		self:fx("shake", { power = 0.45, duration = 0.3 })
	end
	if fn then
		self:safeCall("ability" .. slot, unit, fn, self, unit, ctx or {})
	end
	self:fire(unit, "onAbility", slot)
end

-- Ability 1 trigger check (wall / contact / proximity / hurt call this; timer & charge tick in step)
function Battle:tryTrigger(unit, ctx)
	local a1 = unit.a1
	if not a1 or unit.isMinion or not unit.alive or not self.started then
		return false
	end
	if self.time < a1.readyAt or not self:canCast(unit) then
		return false
	end
	a1.readyAt = self.time + a1.cooldown
	self:cast(unit, 1, ctx)
	return true
end

-- the player tapped ULT
function Battle:requestUlt(ownerId)
	for _, u in self.units do
		if u.alive and not u.isMinion and u.ownerId == ownerId and u.ultReady then
			u.ultRequested = true
			return true
		end
	end
	return false
end

function Battle:fireUlt(u, tapped)
	u.ultReady = false
	u.ultRequested = false
	u.charge = 0
	local dur = (u.def.ability2 and u.def.ability2.duration) or 0
	u.ultActiveUntil = self.time + math.max(dur, 0.5)
	if tapped then
		u.stats.focused += 1
		self:applyStatus(u, "focus", math.max(dur, 1.5) + 0.5, {})
		self:fx("text", { x = u.x, y = u.y, text = "FOCUSED!", color = "#ffe066", size = 1.1 })
	end
	self:cast(u, 2)
end

-- allow abilities to refund / change cooldowns
function Battle:setCooldown(unit, seconds)
	unit.a1.readyAt = self.time + seconds
	if unit.a1.trigger == "charge" then
		unit.a1.progress = 0
	end
end

----------------------------------------------------------------------
-- the main step
----------------------------------------------------------------------

function Battle:start()
	self.started = true
	for _, u in self.units do
		if not u.isMinion then
			u.a1.readyAt = self.cfg.FirstCastDelay + self.time
		end
	end
	if self.gimmick and self.gimmick.setup then
		self:safeCall("gimmick.setup", nil, self.gimmick.setup, self)
	end
end

local function reflectOffWall(self, u, nx, ny)
	local cfg = self.cfg
	-- jitter and minimum exit angle (15°)
	local jitter = self.rng:range(-cfg.WallJitterDegrees, cfg.WallJitterDegrees)
	u.vx, u.vy = rotate(u.vx, u.vy, jitter)
	local sp = len(u.vx, u.vy)
	local minC = math.sin(math.rad(cfg.MinExitAngle)) * sp
	-- component along the wall normal must be at least minC and pointing inward
	local along = u.vx * nx + u.vy * ny
	if along < minC then
		local add = minC - along
		u.vx += nx * add
		u.vy += ny * add
		local s2 = len(u.vx, u.vy)
		u.vx, u.vy = u.vx / s2 * sp, u.vy / s2 * sp
	end
end

function Battle:onUnitWall(u, nx, ny)
	-- Wall Slam
	if u.slam and self.time <= u.slam.untilT then
		local src = u.slam.source
		u.slam = nil
		if src and src.stats then
			src.stats.slams = (src.stats.slams or 0) + 1
		end
		self:damage(src, u, self.cfg.SlamDamage, { big = true })
		self:fx("text", { x = u.x, y = u.y, text = "SLAM!", color = "#ffb020", size = 1.3 })
		self:fx("shake", { power = 0.5, duration = 0.2 })
	end
	-- Bleed
	local b = u.status.bleed
	if b and b.perHit then
		self:damage(b.source, u, b.perHit, { kind = "dot" })
	end
	if u.a1.trigger == "wall" then
		self:tryTrigger(u, { nx = nx, ny = ny })
	end
	self:fire(u, "onWallHit", nx, ny)
	if u.dash and u.dash.opts.stopOnWall then
		u.dash.untilT = self.time
	end
end

function Battle:step(dt)
	if self.result then
		return
	end
	self.time += dt
	local cfg = self.cfg
	local now = self.time

	-- timers
	if #self.timers > 0 then
		local due, keep = {}, {}
		for _, t in self.timers do
			if t.alive and now >= t.at then
				table.insert(due, t)
			elseif t.alive then
				table.insert(keep, t)
			end
		end
		self.timers = keep
		for _, t in due do
			if not t.owner or t.owner.alive then
				self:safeCall("timer", t.owner, t.fn)
			end
		end
	end

	-- overtime / arena collapse
	local otStart = self.finalClash and 0 or cfg.RoundTime
	if not self.overtime and now >= otStart then
		self.overtime = true
		self.overtimeStart = now
		self:fx("banner", { text = "ARENA COLLAPSE!", color = "#ff4d4d" })
		self:fx("flash", { color = "#ff3030", duration = 0.35 })
	end
	if self.overtime then
		local secs = now - self.overtimeStart
		local shrink = math.min(secs * cfg.CollapseSpeed, math.max(0, self.baseHalfX - cfg.CollapseMinHalf))
		local shrinkY = math.min(secs * cfg.CollapseSpeed, math.max(0, self.baseHalfY - cfg.CollapseMinHalf))
		self.halfX = self.baseHalfX - shrink
		self.halfY = self.baseHalfY - shrinkY
		self.half = math.min(self.halfX, self.halfY)
		local dps = cfg.OvertimeDps[math.min(#cfg.OvertimeDps, math.floor(secs / 5) + 1)]
		for _, u in self.units do
			if u.alive and not u.isMinion then
				u.otAcc = (u.otAcc or 0) + dps * dt
				if u.otAcc >= 1 then
					local whole = math.floor(u.otAcc)
					u.otAcc -= whole
					self:damage(nil, u, whole, { kind = "true", silent = true, noCharge = true })
				end
			end
		end
	elseif self.gimmick and self.gimmick.tick then
		self:safeCall("gimmick.tick", nil, self.gimmick.tick, self, dt)
	end

	-- per-unit: statuses, DoTs, CC Guard, abilities, ultimate
	for _, u in self.units do
		if u.alive then
			for name, s in u.status do
				if now >= s.untilT then
					self:removeStatus(u, name)
				end
			end
			for _, dotName in { "burn", "poison" } do
				local s = u.status[dotName]
				if s and s.dps and u.alive then
					s.acc = (s.acc or 0) + s.dps * dt
					if s.acc >= 1 then
						local whole = math.floor(s.acc)
						s.acc -= whole
						self:damage(s.source, u, whole, { kind = "dot", silent = true })
					end
				end
			end
			-- CC Guard
			if self:isHardCC(u) then
				u.ccAccum += dt
				if u.ccAccum >= cfg.CCGuardThreshold then
					u.ccAccum = 0
					u.ccImmuneUntil = now + cfg.CCGuardImmunity
					for _, n in { "stun", "freeze", "root" } do
						self:removeStatus(u, n)
					end
					self:fx("ring", { x = u.x, y = u.y, radius = u.radius * 2.5, color = "#ffffff", duration = 0.5 })
					self:fx("text", { x = u.x, y = u.y, text = "CC GUARD", color = "#ffffff", size = 0.8 })
				end
			else
				u.ccAccum = math.max(0, u.ccAccum - dt * cfg.CCGuardThreshold / 6)
			end
			if u.isMinion then
				u.ttl -= dt
				if u.ttl <= 0 or (u.owner and not u.owner.alive and not u.keepAfterOwner) then
					self:kill(u, nil)
				end
			elseif u.alive and self.started then
				-- Ability 1: timer, charge-up and proximity triggers
				local a1 = u.a1
				if u.ability and u.ability.ability1 then
					if a1.trigger == "timer" then
						if now >= a1.readyAt and self:canCast(u) then
							a1.readyAt = now + a1.cooldown
							self:cast(u, 1, {})
						end
					elseif a1.trigger == "charge" then
						if now >= a1.readyAt and self:canCast(u) then
							a1.progress += dt
							if a1.progress >= a1.cooldown then
								a1.progress = 0
								a1.readyAt = now + 0.3
								self:cast(u, 1, {})
							end
						end
					elseif a1.trigger == "proximity" then
						if now >= a1.readyAt and self:canCast(u) then
							local t, d = self:nearestEnemy(u)
							if t and d - t.radius - u.radius <= a1.radius then
								a1.readyAt = now + a1.cooldown
								self:cast(u, 1, { target = t })
							end
						end
					end
				end
				-- Ability 2: the ultimate meter and the 6 s tap window
				if not u.ultReady then
					self:addCharge(u, cfg.UltPerSecond * dt)
					if u.charge >= 100 then
						u.ultReady = true
						u.ultWindowLeft = cfg.UltWindow
						u.ultRequested = false
						self:fx("ultReady", { unitId = u.id, ownerId = u.ownerId })
					end
				else
					if self:canCast(u) and not self:isHardCC(u) then
						if u.instantUlt then
							self:fireUlt(u, false)
						elseif u.ultRequested then
							self:fireUlt(u, true)
						else
							u.ultWindowLeft -= dt
							if u.ultWindowLeft <= 0 then
								self:fireUlt(u, false)
							end
						end
					end
				end
			end
			if u.alive then
				self:fire(u, "onTick", dt)
			end
		end
	end

	-- Rival Pull: steer fighters together after 5 s without an enemy collision
	local sinceContact = now - self.lastEnemyContact
	local pullRate = 0
	if sinceContact >= cfg.RivalPullAfter then
		pullRate = math.min(cfg.RivalPullMax, cfg.RivalPullStart + cfg.RivalPullRamp * (sinceContact - cfg.RivalPullAfter))
	end

	-- movement
	for _, u in self.units do
		if u.alive then
			local moving = self:canMove(u)
			if u.dash and now >= u.dash.untilT then
				u.dash = nil
			end
			if moving then
				local sp = len(u.vx, u.vy)
				if u.dash then
					local dx, dy = norm(u.vx, u.vy)
					u.vx, u.vy = dx * u.dash.speed, dy * u.dash.speed
				else
					local target = u.baseSpeed * speedMult(u)
					if sp < 0.5 then
						local rx, ry = self:randomDir()
						u.vx, u.vy = rx * target, ry * target
					else
						local newSp
						if sp > target then
							newSp = math.max(target, sp - cfg.CruiseAccel * dt)
						else
							newSp = math.min(target, sp + cfg.CruiseAccel * dt * 4)
						end
						u.vx, u.vy = u.vx / sp * newSp, u.vy / sp * newSp
					end
					if pullRate > 0 and not u.isMinion then
						local t = self:nearestEnemy(u)
						if t then
							local tx, ty = norm(t.x - u.x, t.y - u.y)
							local cx, cy = norm(u.vx, u.vy)
							local ang = math.atan2(cx * ty - cy * tx, cx * tx + cy * ty)
							local maxT = math.rad(pullRate) * dt
							ang = clamp(ang, -maxT, maxT)
							u.vx, u.vy = rotate(u.vx, u.vy, math.deg(ang))
						end
					end
				end
				u.x += u.vx * dt
				u.y += u.vy * dt
			end
			-- walls
			local r = u.radius
			local nx, ny = 0, 0
			if u.x > self.halfX - r then
				u.x = self.halfX - r
				u.vx = -math.abs(u.vx)
				nx = -1
			elseif u.x < -self.halfX + r then
				u.x = -self.halfX + r
				u.vx = math.abs(u.vx)
				nx = 1
			end
			if u.y > self.halfY - r then
				u.y = self.halfY - r
				u.vy = -math.abs(u.vy)
				ny = -1
			elseif u.y < -self.halfY + r then
				u.y = -self.halfY + r
				u.vy = math.abs(u.vy)
				ny = 1
			end
			-- pillars
			for _, o in self.obstacles do
				local d = len(u.x - o.x, u.y - o.y)
				if d < o.r + r then
					local ox, oy = norm(u.x - o.x, u.y - o.y)
					u.x, u.y = o.x + ox * (o.r + r), o.y + oy * (o.r + r)
					local dot = u.vx * ox + u.vy * oy
					if dot < 0 then
						u.vx, u.vy = u.vx - 2 * dot * ox, u.vy - 2 * dot * oy
					end
					nx, ny = ox, oy
				end
			end
			if nx ~= 0 or ny ~= 0 then
				local nl = len(nx, ny)
				nx, ny = nx / nl, ny / nl
				if moving and not u.dash then
					reflectOffWall(self, u, nx, ny)
				end
				self:onUnitWall(u, nx, ny)
			end
		end
	end

	-- unit vs unit collisions
	local units = self.units
	for i = 1, #units do
		local a = units[i]
		if a.alive and not a.status.ghost and not a.status.intangible then
			for j = i + 1, #units do
				local b = units[j]
				if b.alive and not b.status.ghost and not b.status.intangible then
					local dx, dy = b.x - a.x, b.y - a.y
					local d = len(dx, dy)
					local minD = a.radius + b.radius
					if d < minD then
						self:resolveCollision(a, b, dx, dy, d, minD)
					end
				end
			end
		end
	end

	-- entities
	local i = 1
	while i <= #self.entities do
		local e = self.entities[i]
		if not e.dead then
			self:updateEntity(e, dt)
		end
		if e.dead then
			table.remove(self.entities, i)
		else
			i += 1
		end
	end

	-- forget dead minions after a moment (the renderer fades them)
	local k = 1
	while k <= #self.units do
		local u = self.units[k]
		if u.isMinion and not u.alive and now - (u.diedAt or 0) > 0.5 then
			table.remove(self.units, k)
		else
			k += 1
		end
	end

	self:checkEnd()
end

function Battle:resolveCollision(a, b, dx, dy, d, minD)
	local nx, ny
	if d < 1e-6 then
		nx, ny = self:randomDir()
	else
		nx, ny = dx / d, dy / d
	end
	local ma = self:canMove(a) and (a.mass or 1) or 1e6
	local mb = self:canMove(b) and (b.mass or 1) or 1e6
	-- push apart
	local overlap = minD - d
	local total = ma + mb
	a.x -= nx * overlap * (mb / total)
	a.y -= ny * overlap * (mb / total)
	b.x += nx * overlap * (ma / total)
	b.y += ny * overlap * (ma / total)
	self:clampInside(a)
	self:clampInside(b)
	-- speeds at impact (for Heavy Hit)
	local spA, spB = len(a.vx, a.vy), len(b.vx, b.vy)
	-- elastic bounce along the normal (restitution 1)
	local rv = (b.vx - a.vx) * nx + (b.vy - a.vy) * ny
	if rv < 0 then
		local jImp = -2 * rv / (1 / ma + 1 / mb)
		a.vx -= jImp * nx / ma
		a.vy -= jImp * ny / ma
		b.vx += jImp * nx / mb
		b.vy += jImp * ny / mb
	end
	if a.dash and a.dash.opts.pierce then
		a.vx, a.vy = a.dash.dx * a.dash.speed, a.dash.dy * a.dash.speed
	end
	if b.dash and b.dash.opts.pierce then
		b.vx, b.vy = b.dash.dx * b.dash.speed, b.dash.dy * b.dash.speed
	end
	if a.team ~= b.team then
		self.lastEnemyContact = self.time
		self:contact(a, b, spA)
		self:contact(b, a, spB)
		-- Bleed ticks on collisions too
		for _, u in { a, b } do
			local bl = u.status.bleed
			if bl and bl.perHit and u.alive then
				self:damage(bl.source, u, bl.perHit, { kind = "dot" })
			end
		end
		if a.a1 and a.a1.trigger == "contact" then
			self:tryTrigger(a, { target = b })
		end
		if b.a1 and b.a1.trigger == "contact" then
			self:tryTrigger(b, { target = a })
		end
		self:fx("spark", { x = (a.x + b.x) / 2, y = (a.y + b.y) / 2 })
	end
	self:fire(a, "onCollide", b)
	self:fire(b, "onCollide", a)
end

-- contact damage from `src` to `dst`
function Battle:contact(src, dst, impactSpeed)
	if not src.alive or not dst.alive or src.status.stun or src.status.freeze then
		return
	end
	local now = self.time
	if src.dash then
		local d = src.dash
		if not d.hit[dst.id] then
			d.hit[dst.id] = true
			if d.opts.damage then
				self:damage(src, dst, d.opts.damage)
			end
			if dst.alive and d.opts.knockback then
				self:knockback(dst, d.dx, d.dy, d.opts.knockback, src)
			end
			if dst.alive and d.opts.status then
				self:applyStatus(dst, d.opts.status[1], d.opts.status[2], d.opts.status[3])
			end
			if d.opts.onHit then
				self:safeCall("dash.onHit", src, d.opts.onHit, self, src, dst)
			end
		end
	end
	local last = src.lastHit[dst.id]
	if last and now - last < self.cfg.ContactCooldown then
		return
	end
	src.lastHit[dst.id] = now
	local dmg = (src.contactDamage or 0) + (src.contactBonus or 0)
	if src.contactMult then
		dmg *= src.contactMult
	end
	local heavy = (impactSpeed or 0) >= self.cfg.HeavyHitSpeed * src.baseSpeed
	if heavy then
		dmg *= self.cfg.HeavyHitMult
	end
	if dmg > 0 then
		self:damage(src, dst, dmg, { kind = "contact", big = heavy })
	end
end

function Battle:teamAlive(team)
	for _, u in self.units do
		if u.alive and not u.isMinion and u.team == team then
			return true
		end
	end
	return false
end

local function teamTotals(self, team)
	local hp, maxHp, dealt = 0, 0, 0
	for _, u in self.units do
		if not u.isMinion and u.team == team then
			hp += math.max(0, u.hp)
			maxHp += u.maxHp
			dealt += u.stats.damageDealt
		end
	end
	return (maxHp > 0 and hp / maxHp or 0), dealt
end

function Battle:finish(winner, reason)
	local winnerUnit
	for _, u in self.units do
		if u.team == winner and not u.isMinion then
			if not winnerUnit or (u.alive and not winnerUnit.alive) then
				winnerUnit = u
			end
		end
	end
	self.result = { winnerTeam = winner, loserTeam = winner and (3 - winner) or nil, winnerUnit = winnerUnit, time = self.time, reason = reason }
end

function Battle:checkEnd()
	if self.result then
		return
	end
	local alive1, alive2 = self:teamAlive(1), self:teamAlive(2)
	if alive1 and alive2 then
		if self.time >= self.cfg.HardEnd + (self.finalClash and -self.cfg.RoundTime or 0) then
			local p1, d1 = teamTotals(self, 1)
			local p2, d2 = teamTotals(self, 2)
			local winner
			if math.abs(p1 - p2) > 1e-4 then
				winner = p1 > p2 and 1 or 2
			elseif d1 ~= d2 then
				winner = d1 > d2 and 1 or 2
			else
				winner = self.rng:int(1, 2)
				self:fx("banner", { text = "FATE DECIDES!", color = "#ffffff" })
			end
			-- the loser's fighters are KO'd for the Finisher
			for _, u in self.units do
				if u.team ~= winner and u.alive and not u.isMinion then
					u.hp = 0
					u.alive = false
					u.diedAt = self.time
				end
			end
			self:finish(winner, "time")
		end
		return
	end
	if alive1 and not alive2 then
		self:finish(1, "ko")
	elseif alive2 and not alive1 then
		self:finish(2, "ko")
	else
		self.result = { doubleKO = true, time = self.time, reason = "doubleKO" }
	end
end

-- compact state for the client HUD
function Battle:snapshot()
	local out = {}
	for _, u in self.units do
		if not u.isMinion then
			local a1 = u.a1
			local cdLeft, cdMax = 0, a1.cooldown
			if a1.trigger == "charge" then
				cdLeft = math.max(0, a1.cooldown - a1.progress)
			else
				cdLeft = math.max(0, a1.readyAt - self.time)
			end
			local statuses = {}
			for name in u.status do
				table.insert(statuses, name)
			end
			table.insert(out, {
				id = u.id,
				team = u.team,
				ownerId = u.ownerId,
				fighterId = u.fighterId,
				hp = math.max(0, math.floor(u.hp + 0.5)),
				maxHp = u.maxHp,
				charge = math.floor(u.charge),
				ultReady = u.ultReady,
				ultWindow = u.ultReady and u.ultWindowLeft or 0,
				cd1 = cdLeft,
				cd1Max = cdMax,
				trigger = a1.trigger,
				alive = u.alive,
				statuses = statuses,
			})
		end
	end
	return { time = self.time, overtime = self.overtime, halfX = self.halfX, halfY = self.halfY, units = out }
end

return Battle
