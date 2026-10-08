--!nonstrict
-- A5 Shadow Gate Dungeon — two blue portals in the middle of the west and east
-- walls. A fighter or projectile that enters one comes out of the other with the
-- same velocity. Beams don't pass through.
local G = {}

local COOLDOWN = 0.6

function G.setup(b)
	local p = b.arenaData.portals
	if not p or #p < 2 then
		local r = 3
		p = { { x = -b.halfX, y = 0, r = r }, { x = b.halfX, y = 0, r = r } }
	end
	b.gimmickState = { portals = p, cool = {} }
end

local function tryPort(b, s, obj, objR)
	local key = obj
	if (s.cool[key] or -1) > b.time then
		return
	end
	for i, p in s.portals do
		local dx, dy = obj.x - p.x, obj.y - p.y
		if math.sqrt(dx * dx + dy * dy) < p.r + objR then
			local other = s.portals[3 - i]
			local sp = math.sqrt(obj.vx * obj.vx + obj.vy * obj.vy)
			if sp < 0.1 then
				return
			end
			local nx, ny = obj.vx / sp, obj.vy / sp
			b:fx("burst", { x = obj.x, y = obj.y, radius = 3, color = "#3b82f6", duration = 0.25 })
			obj.x = other.x + nx * (other.r + objR + 0.5)
			obj.y = other.y + ny * (other.r + objR + 0.5)
			if obj.radius then
				b:clampInside(obj, objR)
			end
			b:fx("burst", { x = obj.x, y = obj.y, radius = 3, color = "#3b82f6", duration = 0.25 })
			s.cool[key] = b.time + COOLDOWN
			return
		end
	end
end

function G.tick(b, _dt)
	local s = b.gimmickState
	for _, u in b.units do
		if u.alive then
			tryPort(b, s, u, u.radius)
		end
	end
	for _, e in b.entities do
		if not e.dead and e.shape == "circle" and (e.vx ~= 0 or e.vy ~= 0) then
			tryPort(b, s, e, e.radius)
		end
	end
end

return G
