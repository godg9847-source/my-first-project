--!nonstrict
-- A4 Pirate Ship Deck — "Big Wave": first at 12 s, then every 15 s. A 2 s bell
-- warning shows which way the deck will tilt; then for 3 s every fighter drifts
-- toward port or starboard (+18 studs/s²). Seeded, so both sides get the same waves.
local G = {}

local FIRST, EVERY, WARN, TILT, DRIFT = 12, 15, 2, 3, 18

function G.setup(b)
	b.gimmickState = { nextWave = FIRST, warned = false, dir = 1, tiltUntil = -1 }
end

function G.tick(b, dt)
	local s = b.gimmickState
	if not s.warned and b.time >= s.nextWave - WARN then
		s.warned = true
		s.dir = b:chance(0.5) and 1 or -1
		b:fx("banner", { text = s.dir > 0 and "BIG WAVE!  >>>" or "<<<  BIG WAVE!", color = "#5ec8ff" })
		b:fx("sound", { name = "ping", x = 0, y = 0 })
	end
	if b.time >= s.nextWave then
		s.tiltUntil = b.time + TILT
		s.nextWave += EVERY
		s.warned = false
		b:fx("flash", { color = "#3aa0ff", duration = 0.3 })
		b:fx("shake", { power = 0.4, duration = 0.5 })
	end
	if b.time < s.tiltUntil then
		for _, u in b.units do
			if u.alive and b:canMove(u) then
				u.vy += s.dir * DRIFT * dt
			end
		end
	end
end

return G
