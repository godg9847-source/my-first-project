--!nonstrict
-- A7 Cursed School Courtyard — two Curse Puddles (radius 5) slow fighters by 25 %
-- while they are inside. At 20 s and 40 s a Cursed Orb appears in the centre:
-- the first fighter to touch it gains +25 ULT meter.
local G = {}

local ORB_TIMES = { 20, 40 }
local ORB_RADIUS = 1.6

function G.setup(b)
	local p = b.arenaData.puddles
	if not p or #p == 0 then
		p = { { x = -12, y = 12, r = 5 }, { x = 12, y = -12, r = 5 } }
	end
	b.gimmickState = { puddles = p, nextOrb = 1 }
	b.props = b.props or {}
end

function G.tick(b, _dt)
	local s = b.gimmickState
	for _, u in b.units do
		if u.alive then
			for _, p in s.puddles do
				local dx, dy = u.x - p.x, u.y - p.y
				if math.sqrt(dx * dx + dy * dy) < p.r then
					b:applyStatus(u, "slow", 0.15, { amount = 0.25 })
				end
			end
		end
	end
	-- the orb race
	if not s.orb and s.nextOrb <= #ORB_TIMES and b.time >= ORB_TIMES[s.nextOrb] then
		s.nextOrb += 1
		s.orb = { id = b:newId(), x = 0, y = 0, radius = ORB_RADIUS, visual = { shape = "ball", color = "#b26bff", light = true } }
		table.insert(b.props, s.orb)
		b:fx("banner", { text = "CURSED ORB!", color = "#b26bff" })
	end
	if s.orb then
		for _, u in b.units do
			if u.alive and not u.isMinion then
				local dx, dy = u.x - s.orb.x, u.y - s.orb.y
				if math.sqrt(dx * dx + dy * dy) < u.radius + s.orb.radius then
					if not u.ultReady then
						u.charge = math.min(100, u.charge + 25)
					end
					b:fx("burst", { x = s.orb.x, y = s.orb.y, radius = 6, color = "#b26bff", duration = 0.4 })
					b:fx("text", { x = u.x, y = u.y, text = "+25 ULT", color = "#d6a8ff", size = 1.1 })
					local idx = table.find(b.props, s.orb)
					if idx then
						table.remove(b.props, idx)
					end
					s.orb = nil
					break
				end
			end
		end
	end
end

return G
