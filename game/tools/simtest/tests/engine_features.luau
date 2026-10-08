-- Engine feature tests: every Ability 1 trigger fires, statuses behave, gimmicks run,
-- overtime ends rounds, Tag Out works, CC Guard and the heal cap hold.
local Battle = require(Root.ServerScriptService.Sim.Battle)
local Arenas = Root.ServerScriptService.Sim.Arenas

local failures = 0
local function check(cond, msg)
	if not cond then
		failures += 1
		print("FAIL: " .. msg)
	end
end

local function fighter(id, trigger, cd, extra)
	local f = {
		id = id,
		name = id,
		role = (extra and extra.role) or "Brawler",
		stats = { hp = 1000, speed = 35, size = 6, contactDamage = 30, mass = 1, chargeMult = 1 },
		look = { aura = "#ffffff" },
		ability1 = { name = id .. " A1", trigger = trigger, cooldown = cd, radius = 12 },
		ability2 = { name = id .. " A2", duration = 2 },
	}
	return f
end

local casts = {}
local mod = {
	ability1 = function(b, u, ctx)
		casts[u.fighterId] = (casts[u.fighterId] or 0) + 1
		if u.fighterId == "contact" then
			assert(ctx.target, "contact ctx.target missing")
		elseif u.fighterId == "prox" then
			assert(ctx.target, "proximity ctx.target missing")
		elseif u.fighterId == "wall" then
			assert(ctx.nx and ctx.ny, "wall ctx normal missing")
		elseif u.fighterId == "hurt" then
			assert(ctx.source, "hurt ctx.source missing")
		end
		local t = b:nearestEnemy(u)
		if t then
			b:damage(u, t, 20)
		end
	end,
	ability2 = function(b, u)
		casts[u.fighterId .. "_ult"] = (casts[u.fighterId .. "_ult"] or 0) + 1
	end,
}

local fighters = {
	timer = fighter("timer", "timer", 4),
	wall = fighter("wall", "wall", 2),
	contact = fighter("contact", "contact", 1.5),
	prox = fighter("prox", "proximity", 3),
	charge = fighter("charge", "charge", 3),
	hurt = fighter("hurt", "hurt", 3),
	guard = fighter("guard", "timer", 5, { role = "Guardian" }),
	blaster = fighter("blaster", "timer", 5, { role = "Blaster" }),
}

local function newBattle(seed, extra)
	extra = extra or {}
	return Battle.new({
		fighters = fighters,
		abilities = function()
			return mod
		end,
		seed = seed,
		halfX = extra.halfX,
		halfY = extra.halfY,
		obstacles = extra.obstacles,
		gimmick = extra.gimmick,
		arenaData = extra.arenaData,
	})
end

local function run(b, seconds)
	local steps = 0
	while not b.result and steps < seconds * 60 do
		b:step(1 / 60)
		b:flushFx()
		steps += 1
	end
end

-- 1) every trigger fires
local ids = { "timer", "wall", "contact", "prox", "charge", "hurt" }
for i, id in ids do
	for seed = 1, 3 do
		local b = newBattle(seed * 10 + i)
		b:addUnit({ team = 1, fighterId = id, x = 0, y = -14, dirX = 0.3, dirY = 1, ownerId = 1 })
		b:addUnit({ team = 2, fighterId = "timer", x = 0, y = 14, dirX = -0.2, dirY = -1, ownerId = 2 })
		b:start()
		run(b, 40)
		check(#b.errors == 0, id .. " produced errors: " .. tostring(b.errors[1]))
	end
	check((casts[id] or 0) > 0, "trigger '" .. id .. "' never fired")
	check((casts[id .. "_ult"] or 0) > 0, "ultimate never fired for " .. id)
end

-- 2) overtime ends every round by 75 s
do
	local b = newBattle(5)
	local u1 = b:addUnit({ team = 1, fighterId = "timer", x = 0, y = -14, dirX = 1, dirY = 0.2, ownerId = 1 })
	local u2 = b:addUnit({ team = 2, fighterId = "timer", x = 0, y = 14, dirX = -1, dirY = 0.2, ownerId = 2 })
	u1.status.invuln = { untilT = 1e9 } -- can't die → must be decided by time
	u2.status.invuln = { untilT = 1e9 }
	b:start()
	run(b, 90)
	check(b.result ~= nil, "round did not end")
	check(b.result and b.result.reason == "time", "expected time decision, got " .. tostring(b.result and b.result.reason))
	check(b.halfX < 24, "arena did not collapse")
end

-- 3) Tag Out keeps HP %
do
	local b = newBattle(6)
	local u1 = b:addUnit({ team = 1, fighterId = "timer", x = 0, y = -14, ownerId = 1 })
	b:addUnit({ team = 2, fighterId = "timer", x = 0, y = 14, ownerId = 2 })
	b:start()
	u1.hp = 500
	local nu = b:replaceUnit(u1, "wall")
	check(math.abs(nu.hp - 500) < 1, "Tag Out HP % not kept")
	check(nu.fighterId == "wall" and nu.alive, "Tag Out unit wrong")
	run(b, 5)
	check(#b.errors == 0, "errors after tag out")
end

-- 4) CC Guard and Guardian CC reduction
do
	local b = newBattle(7)
	local g = b:addUnit({ team = 1, fighterId = "guard", x = 0, y = -14, ownerId = 1 })
	local e = b:addUnit({ team = 2, fighterId = "timer", x = 0, y = 14, ownerId = 2 })
	b:start()
	b:applyStatus(g, "stun", 1.0)
	check(math.abs((g.status.stun.untilT - b.time) - 0.75) < 0.01, "Guardian stun not reduced 25%")
	b:applyStatus(e, "stun", 1.4)
	run(b, 1.6)
	check(e.ccImmuneUntil > b.time - 0.2 or e.ccAccum > 0, "CC accumulation not tracked")
	for _ = 1, 4 do
		b:applyStatus(e, "stun", 0.8)
		run(b, 0.85)
	end
	check(e.ccImmuneUntil > 0, "CC Guard never triggered")
end

-- 5) heal cap 30 %
do
	local b = newBattle(8)
	local u = b:addUnit({ team = 1, fighterId = "timer", x = 0, y = -14, ownerId = 1 })
	b:addUnit({ team = 2, fighterId = "timer", x = 0, y = 14, ownerId = 2 })
	b:start()
	u.hp = 100
	local total = 0
	for _ = 1, 10 do
		total += b:heal(u, 100, true)
	end
	check(math.abs(total - 300) < 1, "heal cap expected 300, got " .. total)
end

-- 6) role edge: Brawler deals +12 % to Blaster
do
	local b = newBattle(9)
	local br = b:addUnit({ team = 1, fighterId = "timer", x = 0, y = -14, ownerId = 1 })
	local bl = b:addUnit({ team = 2, fighterId = "blaster", x = 0, y = 14, ownerId = 2 })
	b:start()
	local d = b:damage(br, bl, 100, { silent = true })
	check(math.abs(d - 112) < 0.01, "role edge expected 112, got " .. d)
end

-- 7) gimmicks run cleanly
for _, g in { "waves", "portals", "cannons", "puddles" } do
	local gm = require(Arenas[g])
	for seed = 1, 3 do
		local b = newBattle(100 + seed, { gimmick = gm, obstacles = { { x = 0, y = 0, r = 3 } } })
		b:addUnit({ team = 1, fighterId = "wall", x = 0, y = -14, dirX = 0.5, dirY = 1, ownerId = 1 })
		b:addUnit({ team = 2, fighterId = "contact", x = 0, y = 14, dirX = -0.5, dirY = -1, ownerId = 2 })
		b:start()
		run(b, 50)
		check(#b.errors == 0, g .. " gimmick errors: " .. tostring(b.errors[1]))
	end
end

-- 8) projectiles, beams, zones, summons, dash don't error
do
	local fx = {
		ability1 = function(b, u)
			local t = b:nearestEnemy(u)
			if not t then
				return
			end
			local dx, dy = b:dirTo(u, t)
			b:shoot(u, dx, dy, { speed = 70, damage = 40, homing = t, turnRate = 200 })
			b:beam(u, dx, dy, { damage = 30, width = 3 })
			b:zone(u, t.x, t.y, 6, { damage = 10, duration = 3, persistent = true })
			b:summon(u, { hp = 120, size = 3, speed = 30, contactDamage = 15, ttl = 6 })
		end,
		ability2 = function(b, u)
			local t = b:nearestEnemy(u)
			if t then
				local dx, dy = b:dirTo(u, t)
				b:beam(u, dx, dy, { damage = 40, duration = 1.5, tick = 0.25, track = t, width = 4 })
				b:dash(u, dx, dy, 110, 0.3, { damage = 60, knockback = 90 })
			end
		end,
	}
	local b = Battle.new({ fighters = fighters, abilities = function()
		return fx
	end, seed = 11 })
	b:addUnit({ team = 1, fighterId = "timer", x = 0, y = -14, dirX = 0.2, dirY = 1, ownerId = 1 })
	b:addUnit({ team = 2, fighterId = "timer", x = 0, y = 14, dirX = -0.2, dirY = -1, ownerId = 2 })
	b:start()
	run(b, 80)
	check(#b.errors == 0, "spawner errors: " .. tostring(b.errors[1]))
	check(b.result ~= nil, "spawner battle did not end")
end

print(failures == 0 and "ENGINE FEATURES: ALL PASSED" or ("ENGINE FEATURES: " .. failures .. " FAILED"))
