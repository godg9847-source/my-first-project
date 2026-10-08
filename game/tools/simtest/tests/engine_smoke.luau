-- Smoke test for the engine with two made-up fighters.
local Battle = require(Root.ServerScriptService.Sim.Battle)

local fighters = {
	a = { id = "a", stats = { hp = 1000, speed = 35, size = 6, contactDamage = 30, mass = 1 },
		role = "Blaster", ability1 = { name = "Zap", trigger = "timer", cooldown = 4 }, ability2 = { name = "Big Zap" }, look = { aura = "#ffff00" } },
	b = { id = "b", stats = { hp = 1000, speed = 38, size = 5, contactDamage = 34, mass = 0.8 },
		role = "Brawler", ability1 = { name = "Puddle", trigger = "contact", cooldown = 3 }, ability2 = { name = "Dash" }, look = { aura = "#00ffff" } },
}
local mods = {
	a = {
		ability1 = function(b, u)
			local t = b:nearestEnemy(u)
			if t then
				local dx, dy = b:dirTo(u, t)
				b:shoot(u, dx, dy, { speed = 50, damage = 90, radius = 1 })
			end
		end,
		ability2 = function(b, u)
			b:blast(u, u.x, u.y, 14, 260, { knockback = 90, status = { "stun", 1 } })
		end,
	},
	b = {
		setup = function(b, u)
			b:hook(u, "onWallHit", function(bb, uu)
				bb:zone(uu, uu.x, uu.y, 3, { damage = 10, duration = 2, persistent = true })
			end)
		end,
		ability1 = function(b, u)
			b:zone(u, u.x, u.y, 6, { damage = 25, duration = 3, status = { "slow", 1, { amount = 0.4 } } })
		end,
		ability2 = function(b, u)
			local t = b:nearestEnemy(u)
			if t then
				local dx, dy = b:dirTo(u, t)
				b:dash(u, dx, dy, 110, 0.4, { damage = 220, knockback = 90 })
				b:applyStatus(u, "lifesteal", 3, { amount = 0.5 })
			end
		end,
	},
}

local wins, totalTime, errors = { 0, 0 }, 0, 0
for seed = 1, 200 do
	local battle = Battle.new({ fighters = fighters, abilities = function(id) return mods[id] end, seed = seed })
	battle:addUnit({ team = 1, fighterId = "a", x = 0, y = -14, dirX = 0.3, dirY = 1 })
	battle:addUnit({ team = 2, fighterId = "b", x = 0, y = 14, dirX = -0.2, dirY = -1 })
	battle:start()
	local steps = 0
	while not battle.result and steps < 60 * 180 do
		battle:step(1 / 60)
		battle:flushFx()
		steps += 1
	end
	assert(battle.result, "battle never ended")
	if battle.result.winnerTeam then wins[battle.result.winnerTeam] += 1 end
	totalTime += battle.result.time
	errors += #battle.errors
end
print(string.format("200 fights: team1 %d / team2 %d, avg round %.1fs, ability errors %d", wins[1], wins[2], totalTime / 200, errors))
