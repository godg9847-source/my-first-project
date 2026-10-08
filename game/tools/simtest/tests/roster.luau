--[[
	Roster test: fights fighters against each other headlessly and reports
	win rates, round lengths, ultimate counts, damage mix and ability errors.

	  simtest src tools/simtest/tests/roster.luau [ids|all] [fightsPerPair] [arena] [format]
	    ids     comma list of fighter ids to test against everyone (default all)
	    fights  fights per ordered pair (default 20)
	    arena   "neutral" (48x48), "pillars" (bamboo grove), "rect" (52x44), "mix" (default neutral)
	    format  "text" (default) or "json"

	ULT policy ("smart"): tap when an enemy is within 16 studs or below 30 % HP,
	otherwise let it auto-fire. Aims: toward the enemy spawn ± 60 degrees.
]]

local Battle = require(Root.ServerScriptService.Sim.Battle)
local Fighters = require(Root.ReplicatedStorage.Shared.Fighters)
local AbilFolder = Root.ServerScriptService.Sim.Abilities

local cache = {}
local function loadAb(id)
	if cache[id] == nil then
		local m = AbilFolder:FindFirstChild(id)
		if m then
			local ok, res = pcall(require, m)
			if ok then
				cache[id] = res
			else
				print("LOAD ERROR " .. id .. ": " .. tostring(res))
				cache[id] = false
			end
		else
			cache[id] = false
		end
	end
	return cache[id] or nil
end

local which = ARGS[1] or "all"
local N = tonumber(ARGS[2]) or 20
local arenaKind = ARGS[3] or "neutral"
local format = ARGS[4] or "text"

local all = {}
for _, f in Fighters.List do
	table.insert(all, f.id)
end
local testIds = {}
if which == "all" then
	testIds = all
else
	for id in string.gmatch(which, "[^,]+") do
		table.insert(testIds, id)
	end
end

local arenas = {
	neutral = { halfX = 24, halfY = 24, obstacles = {} },
	pillars = { halfX = 24, halfY = 24, obstacles = { { x = 11, y = 11, r = 2.5 }, { x = -11, y = 11, r = 2.5 }, { x = 11, y = -11, r = 2.5 }, { x = -11, y = -11, r = 2.5 } } },
	rect = { halfX = 26, halfY = 22, obstacles = {} },
}

local stats = {} -- [id] = {...}
local function S(id)
	stats[id] = stats[id] or { wins = 0, fights = 0, time = 0, ults = 0, focused = 0, a1 = 0, contact = 0, ability = 0, dealt = 0, errors = {}, otRounds = 0, vs = {} }
	return stats[id]
end
local allTimes = {}
local seed = 1000

local function fight(a, b, k)
	seed += 1
	local ak = arenaKind
	if ak == "mix" then
		ak = ({ "neutral", "pillars", "rect" })[seed % 3 + 1]
	end
	local ar = arenas[ak] or arenas.neutral
	local battle = Battle.new({ fighters = Fighters.ById, abilities = loadAb, seed = seed, halfX = ar.halfX, halfY = ar.halfY, obstacles = ar.obstacles })
	local rng = battle.rng
	local function aim(y)
		local base = y < 0 and math.pi / 2 or -math.pi / 2
		local ang = base + math.rad(rng:range(-60, 60))
		return math.cos(ang), math.sin(ang)
	end
	local dx1, dy1 = aim(-14)
	local dx2, dy2 = aim(14)
	local u1 = battle:addUnit({ team = 1, fighterId = a, x = 0, y = -14, dirX = dx1, dirY = dy1, ownerId = 1 })
	local u2 = battle:addUnit({ team = 2, fighterId = b, x = 0, y = 14, dirX = dx2, dirY = dy2, ownerId = 2 })
	battle:start()
	local steps = 0
	while not battle.result and steps < 60 * 120 do
		battle:step(1 / 60)
		battle:flushFx()
		for _, u in { u1, u2 } do
			if u.alive and u.ultReady then
				local t, d = battle:nearestEnemy(u)
				if t and (d < 16 or t.hp / t.maxHp < 0.3) then
					battle:requestUlt(u.ownerId)
				end
			end
		end
		steps += 1
	end
	local r = battle.result
	local sa, sb = S(a), S(b)
	sa.fights += 1
	sb.fights += 1
	local winner = r and r.winnerTeam
	if r and r.doubleKO then
		winner = nil
	end
	if winner == 1 then
		sa.wins += 1
	elseif winner == 2 then
		sb.wins += 1
	else
		sa.wins += 0.5
		sb.wins += 0.5
	end
	sa.vs[b] = sa.vs[b] or { w = 0, n = 0 }
	sa.vs[b].n += 1
	sa.vs[b].w += (winner == 1 and 1 or (winner == nil and 0.5 or 0))
	local t = r and r.time or 120
	table.insert(allTimes, t)
	for _, pair in { { u1, sa }, { u2, sb } } do
		local u, s = pair[1], pair[2]
		s.time += t
		s.ults += u.stats.casts2
		s.focused += u.stats.focused
		s.a1 += u.stats.casts1
		s.contact += u.stats.contact
		s.ability += u.stats.ability
		s.dealt += u.stats.damageDealt
		if battle.overtime then
			s.otRounds += 1
		end
	end
	for _, e in battle.errors do
		local id = string.match(e, "^%[([%w_]+)%]") or "?"
		local s = S(id)
		if #s.errors < 5 then
			table.insert(s.errors, e)
		end
	end
end

for _, a in testIds do
	for _, b in all do
		if a ~= b then
			for k = 1, N do
				fight(a, b, k)
				if which ~= "all" then
					fight(b, a, k) -- both sides when testing a subset
				end
			end
		end
	end
end

table.sort(allTimes)
local median = allTimes[math.max(1, math.floor(#allTimes / 2))] or 0
local p10 = allTimes[math.max(1, math.floor(#allTimes * 0.1))] or 0
local p90 = allTimes[math.max(1, math.floor(#allTimes * 0.9))] or 0

local function pct(x)
	return math.floor(x * 1000 + 0.5) / 10
end

if format == "json" then
	local parts = {}
	for id, s in stats do
		if s.fights > 0 then
			local vs = {}
			for o, v in s.vs do
				table.insert(vs, string.format('"%s":%.3f', o, v.w / v.n))
			end
			table.insert(parts, string.format(
				'"%s":{"winRate":%.4f,"fights":%d,"avgRound":%.2f,"ultsPerRound":%.3f,"focused":%.3f,"a1PerRound":%.3f,"contactShare":%.3f,"overtime":%.3f,"errors":%d,"vs":{%s}}',
				id, s.wins / s.fights, s.fights, s.time / s.fights, s.ults / s.fights, s.focused / s.fights, s.a1 / s.fights,
				(s.dealt > 0 and s.contact / s.dealt or 0), s.otRounds / s.fights, #s.errors, table.concat(vs, ",")))
		end
	end
	print(string.format('{"median":%.2f,"p10":%.2f,"p90":%.2f,"fighters":{%s}}', median, p10, p90, table.concat(parts, ",")))
else
	print(string.format("rounds: median %.1fs  p10 %.1fs  p90 %.1fs  (%d fights)", median, p10, p90, #allTimes))
	local rows = {}
	for id, s in stats do
		if s.fights > 0 then
			table.insert(rows, { id = id, s = s })
		end
	end
	table.sort(rows, function(x, y)
		return x.s.wins / x.s.fights > y.s.wins / y.s.fights
	end)
	print(string.format("%-10s %6s %6s %6s %6s %6s %6s %5s", "fighter", "win%", "round", "ult/r", "a1/r", "cont%", "OT%", "errs"))
	for _, row in rows do
		local s = row.s
		print(string.format("%-10s %6.1f %6.1f %6.2f %6.1f %6.1f %6.1f %5d", row.id, pct(s.wins / s.fights), s.time / s.fights,
			s.ults / s.fights, s.a1 / s.fights, pct(s.dealt > 0 and s.contact / s.dealt or 0), pct(s.otRounds / s.fights), #s.errors))
		for _, e in s.errors do
			print("    ! " .. e)
		end
	end
end
