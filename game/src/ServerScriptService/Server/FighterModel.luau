--!nonstrict
--[[
	FighterModel: builds the chibi "ball" version of a fighter out of plain parts.

	A fighter is a sphere (the face/body) with eyes, an outfit band, a hair style
	and accessories, all welded to an anchored root part. The Renderer moves the
	root every frame and the welded parts follow.

	Look spec (from Shared/Fighters.luau):
	  look = {
	    skin = "#f5cfa6", outfit = "#ff7a00", outfit2 = "#1f3fbf",
	    hair = "#111111", hairStyle = "spiky", eyes = "#1b1b1b",
	    aura = "#ffd93b", accessories = { "headband" }, accessoryColor = "#3355ff",
	  }
	Hair styles: spiky, wild, messy, short, long, twintails, ponytail, slick, bowl, bun, bald
	Accessories: headband, forehead_protector, strawhat, blindfold, glasses, scarf, cape,
	  horns, chainsaw, mask_half, eyepatch, earrings, hairclip, goggles, crown, hood,
	  bandana, sword, cat_ears, scar, gloves (ignored if unknown)
	Front of the model is -Z (the LookVector), so it faces the way it rolls.
]]

local FighterModel = {}

local function hex(c, fallback)
	if typeof(c) == "Color3" then
		return c
	end
	if type(c) ~= "string" then
		return fallback or Color3.new(1, 1, 1)
	end
	local ok, col = pcall(Color3.fromHex, c)
	if ok then
		return col
	end
	return fallback or Color3.new(1, 1, 1)
end
FighterModel.hex = hex

local function newPart(model, root, name, shape, size, localCf, color, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape or Enum.PartType.Block
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	if props then
		for k, v in props do
			p[k] = v
		end
	end
	p.CFrame = root.CFrame * localCf
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

local function wedge(model, root, name, size, localCf, color, material)
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	p.CFrame = root.CFrame * localCf
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder
local BLOCK = Enum.PartType.Block

-- a point on the sphere surface for given yaw (degrees, 0 = front) and pitch (degrees, 90 = top)
local function onSphere(R, yaw, pitch, out)
	local y = math.rad(yaw)
	local p = math.rad(pitch)
	local r = R * (out or 1)
	return Vector3.new(math.sin(y) * math.cos(p) * r, math.sin(p) * r, -math.cos(y) * math.cos(p) * r)
end

-- CFrame at a sphere point, with the part's +Y axis pointing outward
local function outward(R, yaw, pitch, out)
	local pos = onSphere(R, yaw, pitch, out)
	local up = pos.Unit
	local right = up:Cross(Vector3.new(0, 0, -1))
	if right.Magnitude < 1e-3 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	local back = right:Cross(up)
	return CFrame.fromMatrix(pos, right, up, back)
end

local HAIR = {}

local function cap(m, root, R, col, scale, lift, back)
	return newPart(m, root, "HairCap", BALL, Vector3.one * R * 2 * (scale or 0.98),
		CFrame.new(0, R * (lift or 0.36), R * (back or 0.24)), col)
end

function HAIR.short(m, root, R, col)
	cap(m, root, R, col)
end

function HAIR.slick(m, root, R, col)
	cap(m, root, R, col, 1.0, 0.33, 0.3)
	newPart(m, root, "Fringe", BALL, Vector3.new(R * 1.1, R * 0.45, R * 0.6), CFrame.new(R * 0.35, R * 0.62, -R * 0.55) * CFrame.Angles(0, 0, math.rad(-15)), col)
end

function HAIR.spiky(m, root, R, col, big)
	cap(m, root, R, col)
	local n = big and 7 or 9
	local len = big and 1.15 or 0.85
	for i = 1, n do
		local yaw = (i - 1) / n * 360 + 20
		local pitch = big and 40 or 50
		local cf = outward(R, yaw, pitch, 0.95) * CFrame.new(0, R * len * 0.45, 0) * CFrame.Angles(math.rad(big and -25 or -12), 0, 0)
		wedge(m, root, "Spike" .. i, Vector3.new(R * 0.32, R * len, R * 0.5), cf, col)
	end
	-- top spikes
	for i = 1, 3 do
		local cf = outward(R, i * 120, 75, 0.95) * CFrame.new(0, R * len * 0.4, 0)
		wedge(m, root, "TopSpike" .. i, Vector3.new(R * 0.3, R * len * 0.9, R * 0.45), cf, col)
	end
end

function HAIR.wild(m, root, R, col)
	HAIR.spiky(m, root, R, col, true)
end

function HAIR.messy(m, root, R, col)
	cap(m, root, R, col)
	for i = 1, 8 do
		local yaw = (i - 1) * 45 + 10
		local pos = onSphere(R, yaw, 48 + (i % 2) * 18, 0.92)
		newPart(m, root, "Tuft" .. i, BALL, Vector3.one * R * 0.62, CFrame.new(pos), col)
	end
end

function HAIR.long(m, root, R, col)
	cap(m, root, R, col)
	newPart(m, root, "BackHair", BLOCK, Vector3.new(R * 1.7, R * 1.5, R * 0.5), CFrame.new(0, -R * 0.1, R * 0.82), col)
	newPart(m, root, "SideL", BLOCK, Vector3.new(R * 0.35, R * 1.2, R * 0.6), CFrame.new(-R * 0.9, -R * 0.1, -R * 0.1), col)
	newPart(m, root, "SideR", BLOCK, Vector3.new(R * 0.35, R * 1.2, R * 0.6), CFrame.new(R * 0.9, -R * 0.1, -R * 0.1), col)
end

function HAIR.twintails(m, root, R, col)
	cap(m, root, R, col)
	for _, s in { -1, 1 } do
		newPart(m, root, "Tail", CYL, Vector3.new(R * 1.5, R * 0.45, R * 0.45),
			CFrame.new(s * R * 1.0, -R * 0.15, R * 0.35) * CFrame.Angles(0, 0, math.rad(90 + s * 15)), col)
		newPart(m, root, "TailTie", BALL, Vector3.one * R * 0.28, CFrame.new(s * R * 0.92, R * 0.55, R * 0.3), Color3.fromRGB(230, 60, 60))
	end
end

function HAIR.ponytail(m, root, R, col)
	cap(m, root, R, col)
	newPart(m, root, "Ponytail", CYL, Vector3.new(R * 1.2, R * 0.42, R * 0.42), CFrame.new(0, R * 0.05, R * 1.1) * CFrame.Angles(0, 0, math.rad(80)), col)
end

function HAIR.bun(m, root, R, col)
	cap(m, root, R, col)
	newPart(m, root, "Bun", BALL, Vector3.one * R * 0.7, CFrame.new(0, R * 0.85, R * 0.65), col)
end

function HAIR.bowl(m, root, R, col)
	cap(m, root, R, col, 1.02, 0.3, 0.12)
	newPart(m, root, "BowlFringe", CYL, Vector3.new(R * 0.18, R * 1.75, R * 1.75), CFrame.new(0, R * 0.42, -R * 0.12) * CFrame.Angles(0, 0, math.rad(90)), col)
end

function HAIR.bald(m, root, R, _col)
	newPart(m, root, "Shine", BALL, Vector3.one * R * 0.3, CFrame.new(-R * 0.3, R * 0.85, -R * 0.3), Color3.new(1, 1, 1), Enum.Material.Neon, { Transparency = 0.35 })
end

local ACC = {}

function ACC.headband(m, root, R, col)
	newPart(m, root, "Headband", CYL, Vector3.new(R * 0.28, R * 2.06, R * 2.06), CFrame.new(0, R * 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)), col)
end

function ACC.forehead_protector(m, root, R, col)
	ACC.headband(m, root, R, col)
	newPart(m, root, "Plate", BLOCK, Vector3.new(R * 0.8, R * 0.32, R * 0.12), outward(R, 0, 24, 1.03), Color3.fromRGB(200, 205, 215), Enum.Material.Metal)
end

function ACC.strawhat(m, root, R, _col)
	local straw = Color3.fromRGB(236, 200, 110)
	newPart(m, root, "Brim", CYL, Vector3.new(R * 0.12, R * 2.9, R * 2.9), CFrame.new(0, R * 0.78, R * 0.1) * CFrame.Angles(0, 0, math.rad(90)), straw, Enum.Material.Fabric)
	newPart(m, root, "Crown", CYL, Vector3.new(R * 0.65, R * 1.55, R * 1.55), CFrame.new(0, R * 1.05, R * 0.1) * CFrame.Angles(0, 0, math.rad(90)), straw, Enum.Material.Fabric)
	newPart(m, root, "Ribbon", CYL, Vector3.new(R * 0.2, R * 1.58, R * 1.58), CFrame.new(0, R * 0.88, R * 0.1) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 30, 30))
end

function ACC.blindfold(m, root, R, col)
	newPart(m, root, "Blindfold", CYL, Vector3.new(R * 0.42, R * 2.08, R * 2.08), CFrame.new(0, R * 0.14, 0) * CFrame.Angles(0, 0, math.rad(90)), col or Color3.fromRGB(20, 20, 24))
end

function ACC.glasses(m, root, R, col)
	for _, s in { -1, 1 } do
		newPart(m, root, "Lens", CYL, Vector3.new(R * 0.06, R * 0.42, R * 0.42), CFrame.new(s * R * 0.32, R * 0.12, -R * 0.98) * CFrame.Angles(0, math.rad(90), 0), col or Color3.fromRGB(30, 30, 30), Enum.Material.Glass, { Transparency = 0.4 })
	end
end

function ACC.goggles(m, root, R, col)
	ACC.headband(m, root, R, Color3.fromRGB(60, 60, 60))
	for _, s in { -1, 1 } do
		newPart(m, root, "Goggle", CYL, Vector3.new(R * 0.2, R * 0.5, R * 0.5), CFrame.new(s * R * 0.3, R * 0.62, -R * 0.82) * CFrame.Angles(0, math.rad(90), math.rad(20)), col or Color3.fromRGB(255, 170, 40), Enum.Material.Glass)
	end
end

function ACC.scarf(m, root, R, col)
	newPart(m, root, "Scarf", CYL, Vector3.new(R * 0.4, R * 2.1, R * 2.1), CFrame.new(0, -R * 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)), col)
	newPart(m, root, "ScarfTail", BLOCK, Vector3.new(R * 0.35, R * 0.9, R * 0.12), CFrame.new(R * 0.3, -R * 0.75, R * 0.95) * CFrame.Angles(math.rad(20), 0, math.rad(10)), col)
end

function ACC.cape(m, root, R, col)
	newPart(m, root, "Cape", BLOCK, Vector3.new(R * 1.6, R * 1.4, R * 0.12), CFrame.new(0, -R * 0.25, R * 1.0) * CFrame.Angles(math.rad(-12), 0, 0), col)
end

function ACC.horns(m, root, R, col)
	for _, s in { -1, 1 } do
		wedge(m, root, "Horn", Vector3.new(R * 0.22, R * 0.7, R * 0.35), outward(R, s * 35, 62, 1.0) * CFrame.new(0, R * 0.3, 0), col or Color3.fromRGB(240, 240, 230))
	end
end

function ACC.chainsaw(m, root, R, _col)
	local metal = Color3.fromRGB(190, 190, 195)
	local orange = Color3.fromRGB(255, 120, 30)
	newPart(m, root, "SawBody", BLOCK, Vector3.new(R * 0.45, R * 0.55, R * 0.5), CFrame.new(0, R * 0.98, -R * 0.35), orange)
	newPart(m, root, "SawBlade", BLOCK, Vector3.new(R * 0.18, R * 0.35, R * 1.3), CFrame.new(0, R * 1.05, -R * 1.1), metal, Enum.Material.Metal)
	for _, s in { -1, 1 } do
		newPart(m, root, "ArmSaw", BLOCK, Vector3.new(R * 1.0, R * 0.16, R * 0.3), CFrame.new(s * R * 1.25, -R * 0.1, -R * 0.2), metal, Enum.Material.Metal)
	end
end

function ACC.mask_half(m, root, R, col)
	newPart(m, root, "Mask", BLOCK, Vector3.new(R * 0.9, R * 0.55, R * 0.14), CFrame.new(-R * 0.2, -R * 0.28, -R * 0.94), col or Color3.fromRGB(25, 25, 25))
	newPart(m, root, "MaskTeeth", BLOCK, Vector3.new(R * 0.7, R * 0.08, R * 0.05), CFrame.new(-R * 0.2, -R * 0.3, -R * 1.02), Color3.new(1, 1, 1))
end

function ACC.eyepatch(m, root, R, col)
	newPart(m, root, "Eyepatch", CYL, Vector3.new(R * 0.08, R * 0.45, R * 0.45), CFrame.new(R * 0.32, R * 0.12, -R * 1.0) * CFrame.Angles(0, math.rad(90), 0), col or Color3.fromRGB(20, 20, 20))
end

function ACC.earrings(m, root, R, col)
	for _, s in { -1, 1 } do
		newPart(m, root, "Earring", BALL, Vector3.one * R * 0.18, CFrame.new(s * R * 0.98, -R * 0.15, 0), col or Color3.fromRGB(255, 215, 80), Enum.Material.Neon)
	end
end

function ACC.hairclip(m, root, R, col)
	newPart(m, root, "Clip", BLOCK, Vector3.new(R * 0.4, R * 0.12, R * 0.12), CFrame.new(R * 0.55, R * 0.62, -R * 0.62) * CFrame.Angles(0, 0, math.rad(30)), col or Color3.fromRGB(255, 80, 120))
end

function ACC.crown(m, root, R, col)
	local gold = col or Color3.fromRGB(255, 205, 60)
	for i = 1, 5 do
		wedge(m, root, "CrownSpike" .. i, Vector3.new(R * 0.18, R * 0.4, R * 0.25), outward(R, i * 72, 70, 1.02) * CFrame.new(0, R * 0.2, 0), gold)
	end
end

function ACC.hood(m, root, R, col)
	newPart(m, root, "Hood", BALL, Vector3.one * R * 2.15, CFrame.new(0, R * 0.25, R * 0.3), col)
end

function ACC.bandana(m, root, R, col)
	newPart(m, root, "Bandana", CYL, Vector3.new(R * 0.35, R * 2.04, R * 2.04), CFrame.new(0, -R * 0.35, 0) * CFrame.Angles(0, 0, math.rad(90)), col)
end

function ACC.sword(m, root, R, col)
	newPart(m, root, "Blade", BLOCK, Vector3.new(R * 0.14, R * 2.2, R * 0.35), CFrame.new(R * 0.7, R * 0.3, R * 0.95) * CFrame.Angles(0, 0, math.rad(-35)), col or Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
	newPart(m, root, "Hilt", BLOCK, Vector3.new(R * 0.5, R * 0.12, R * 0.18), CFrame.new(R * 0.15, -R * 0.45, R * 0.95) * CFrame.Angles(0, 0, math.rad(-35)), Color3.fromRGB(90, 60, 30))
end

function ACC.cat_ears(m, root, R, col)
	for _, s in { -1, 1 } do
		wedge(m, root, "Ear", Vector3.new(R * 0.15, R * 0.5, R * 0.45), outward(R, s * 30, 65, 0.98) * CFrame.new(0, R * 0.2, 0), col)
	end
end

function ACC.scar(m, root, R, col)
	newPart(m, root, "Scar", BLOCK, Vector3.new(R * 0.08, R * 0.45, R * 0.05), CFrame.new(R * 0.3, -R * 0.15, -R * 1.0) * CFrame.Angles(0, 0, math.rad(20)), col or Color3.fromRGB(150, 60, 60))
end

function ACC.gloves(m, root, R, col)
	for _, s in { -1, 1 } do
		newPart(m, root, "Fist", BALL, Vector3.one * R * 0.55, CFrame.new(s * R * 1.1, -R * 0.35, -R * 0.35), col or Color3.fromRGB(230, 40, 40))
	end
end

--[[
	build(look, radius, teamColor) -> Model (PrimaryPart = "Root", anchored)
]]
function FighterModel.build(look, radius, teamColor, name)
	look = look or {}
	local R = radius
	local m = Instance.new("Model")
	m.Name = name or "Fighter"

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = BALL
	root.Size = Vector3.one * R * 2
	root.Color = hex(look.skin, Color3.fromRGB(245, 207, 166))
	root.Material = Enum.Material.SmoothPlastic
	root.TopSurface = Enum.SurfaceType.Smooth
	root.BottomSurface = Enum.SurfaceType.Smooth
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = true
	root.CFrame = CFrame.new(0, 500, 0)
	root.Parent = m
	m.PrimaryPart = root

	-- outfit band (lower half) and trim
	local outfit = hex(look.outfit, Color3.fromRGB(60, 60, 70))
	newPart(m, root, "Outfit", CYL, Vector3.new(R * 0.9, R * 2.04, R * 2.04), CFrame.new(0, -R * 0.55, 0) * CFrame.Angles(0, 0, math.rad(90)), outfit)
	newPart(m, root, "OutfitBottom", BALL, Vector3.one * R * 1.7, CFrame.new(0, -R * 0.3, 0), outfit)
	if look.outfit2 then
		newPart(m, root, "Trim", CYL, Vector3.new(R * 0.16, R * 2.07, R * 2.07), CFrame.new(0, -R * 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)), hex(look.outfit2))
	end

	-- eyes (skipped by blindfold)
	local blind = false
	for _, a in look.accessories or {} do
		if a == "blindfold" then
			blind = true
		end
	end
	if not blind then
		local iris = hex(look.eyes, Color3.fromRGB(25, 25, 30))
		for _, s in { -1, 1 } do
			newPart(m, root, "EyeWhite", BALL, Vector3.new(R * 0.36, R * 0.46, R * 0.2), CFrame.new(s * R * 0.32, R * 0.1, -R * 0.9), Color3.new(1, 1, 1))
			newPart(m, root, "Iris", BALL, Vector3.new(R * 0.26, R * 0.34, R * 0.14), CFrame.new(s * R * 0.32, R * 0.08, -R * 0.97), iris)
			newPart(m, root, "Shine", BALL, Vector3.one * R * 0.09, CFrame.new(s * R * 0.32 - R * 0.05, R * 0.17, -R * 1.03), Color3.new(1, 1, 1), Enum.Material.Neon)
		end
	end
	-- small mouth
	newPart(m, root, "Mouth", BLOCK, Vector3.new(R * 0.22, R * 0.05, R * 0.05), CFrame.new(0, -R * 0.2, -R * 0.98), Color3.fromRGB(90, 40, 40))

	-- hair
	local style = HAIR[look.hairStyle or "short"] or HAIR.short
	style(m, root, R, hex(look.hair, Color3.fromRGB(30, 30, 30)))

	-- accessories
	local accCol = look.accessoryColor and hex(look.accessoryColor) or nil
	for _, a in look.accessories or {} do
		local fn = ACC[a]
		if fn then
			fn(m, root, R, accCol)
		end
	end

	-- team ring on the floor (not welded, positioned by the renderer)
	local ring = Instance.new("Part")
	ring.Name = "TeamRing"
	ring.Shape = CYL
	ring.Size = Vector3.new(0.2, R * 2.5, R * 2.5)
	ring.Color = teamColor or Color3.fromRGB(80, 170, 255)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.35
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Parent = m

	-- aura particles (renderer turns them on/off)
	local att = Instance.new("Attachment")
	att.Name = "AuraAttachment"
	att.Parent = root
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "Aura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(hex(look.aura, Color3.new(1, 1, 1)))
	aura.LightEmission = 0.8
	aura.Size = NumberSequence.new(R * 0.5, 0)
	aura.Transparency = NumberSequence.new(0.2, 1)
	aura.Lifetime = NumberRange.new(0.4, 0.8)
	aura.Speed = NumberRange.new(2, 5)
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Rate = 40
	aura.Enabled = false
	aura.Parent = att

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = hex(look.aura, Color3.new(1, 1, 1))
	light.Range = R * 5
	light.Brightness = 1.2
	light.Enabled = false
	light.Parent = root

	return m
end

-- simple glowing orb for minions/summons that don't copy a fighter look
function FighterModel.buildOrb(radius, color, teamColor)
	local m = Instance.new("Model")
	m.Name = "Summon"
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Shape = BALL
	root.Size = Vector3.one * radius * 2
	root.Color = hex(color, Color3.new(1, 1, 1))
	root.Material = Enum.Material.Neon
	root.Transparency = 0.15
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Parent = m
	m.PrimaryPart = root
	local ring = Instance.new("Part")
	ring.Name = "TeamRing"
	ring.Shape = CYL
	ring.Size = Vector3.new(0.2, radius * 2.3, radius * 2.3)
	ring.Color = teamColor or Color3.fromRGB(80, 170, 255)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.5
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Parent = m
	return m
end

return FighterModel
