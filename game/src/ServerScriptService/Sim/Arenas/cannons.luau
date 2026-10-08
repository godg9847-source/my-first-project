--!nonstrict
-- A6 Titan Wall District — "Cannon Barrage": first at 10 s, then every 14 s.
-- Three circles (radius 5) glow for 1.5 s, then each deals 60 damage and 60
-- knockback. Arena damage is capped at 120 per fighter per round. The three
-- spots are mirrored (p, -p and the centre) so neither side is favoured.
local G = {}

local FIRST, EVERY, WARN, RADIUS, DAMAGE, KNOCK = 10, 14, 1.5, 5, 60, 60

function G.setup(b)
	b.gimmickState = { nextShot = FIRST, dealt = {} }
end

local function fire(b, spots)
	local s = b.gimmickState
	for _, p in spots do
		b:fx("burst", { x = p.x, y = p.y, radius = RADIUS, color = "#ff9b3d", duration = 0.4 })
		for _, u in b:unitsInRadius(p.x, p.y, RADIUS, nil, nil) do
			if not b.overtime then
				local done = s.dealt[u.id] or 0
				local amount = math.min(DAMAGE, b.cfg.GimmickRoundCap - done)
				if amount > 0 then
					s.dealt[u.id] = done + amount
					b:damage(nil, u, amount, { big = true })
				end
				if u.alive then
					b:knockback(u, u.x - p.x, u.y - p.y, KNOCK)
				end
			end
		end
	end
	b:fx("shake", { power = 0.6, duration = 0.35 })
	b:fx("sound", { name = "boom", x = 0, y = 0 })
end

function G.tick(b, _dt)
	local s = b.gimmickState
	if b.time >= s.nextShot - WARN and not s.pending then
		local x, y = b:randomPoint(7)
		local spots = { { x = x, y = y }, { x = -x, y = -y }, { x = 0, y = 0 } }
		s.pending = spots
		for _, p in spots do
			b:telegraph(p.x, p.y, RADIUS, WARN, { color = "#ff6a00" })
		end
		b:fx("banner", { text = "CANNON BARRAGE!", color = "#ff9b3d" })
	end
	if s.pending and b.time >= s.nextShot then
		fire(b, s.pending)
		s.pending = nil
		s.nextShot += EVERY
	end
end

return G
