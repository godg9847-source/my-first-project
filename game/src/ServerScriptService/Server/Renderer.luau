--!nonstrict
--[[
	Renderer: shows a Battle (Sim/Battle.luau) in the 3D world.

	Every frame it moves fighter models and ability objects to match the
	simulation, and turns the battle's fx events into short visual effects.
	Effects that only matter for the camera/screen (shake, flash, banner,
	ultReady, damage numbers) are collected in `clientFx` so MatchService can
	send them to the players watching the arena.
]]

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local FighterModel = require(script.Parent.FighterModel)

local Renderer = {}
Renderer.__index = Renderer

local TEAM_COLORS = {
	[1] = Color3.fromRGB(70, 160, 255),
	[2] = Color3.fromRGB(255, 80, 80),
}
Renderer.TEAM_COLORS = TEAM_COLORS

-- Built-in Roblox sounds (rbxasset:// files ship with every Roblox install).
Renderer.SOUNDS = {
	hit = "rbxasset://sounds/collide.wav",
	slash = "rbxasset://sounds/swordslash.wav",
	lunge = "rbxasset://sounds/swordlunge.wav",
	boom = "rbxasset://sounds/collide.wav",
	ping = "rbxasset://sounds/electronicpingshort.wav",
	click = "rbxasset://sounds/clickfast.wav",
}

local hex = FighterModel.hex

local function material(name)
	if name and Enum.Material[name] then
		return Enum.Material[name]
	end
	return Enum.Material.Neon
end

--[[
	Renderer.new(battle, origin, parentFolder)
	  origin: Vector3 at the centre of the arena floor's top surface
]]
function Renderer.new(battle, origin, parent)
	local self = setmetatable({}, Renderer)
	self.battle = battle
	self.origin = origin
	self.folder = Instance.new("Folder")
	self.folder.Name = "BattleVisuals"
	self.folder.Parent = parent
	self.units = {} -- [unitId] = {model, root, ring, bar, ...}
	self.entities = {} -- [entityId] = part
	self.clientFx = {}
	self.dmgBudget = {}
	return self
end

function Renderer:world(x, y, height)
	return self.origin + Vector3.new(x, height or 0, y)
end

----------------------------------------------------------------------
-- units
----------------------------------------------------------------------

local function makeHealthBar(root, radius, team, name)
	local bb = Instance.new("BillboardGui")
	bb.Name = "HealthBar"
	bb.Size = UDim2.fromOffset(110, 26)
	bb.StudsOffsetWorldSpace = Vector3.new(0, radius + 2.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 12)
	nameLabel.Text = name or ""
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.3
	nameLabel.Parent = bb
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, 0, 0, 10)
	back.Position = UDim2.fromOffset(0, 14)
	back.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	back.BorderSizePixel = 0
	back.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = TEAM_COLORS[team] or Color3.new(0, 1, 0)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local c2 = corner:Clone()
	c2.Parent = fill
	local shield = Instance.new("Frame")
	shield.Name = "Shield"
	shield.Size = UDim2.fromScale(0, 1)
	shield.BackgroundColor3 = Color3.fromRGB(160, 220, 255)
	shield.BackgroundTransparency = 0.2
	shield.BorderSizePixel = 0
	shield.Parent = back
	bb.Parent = root
	return bb, fill, shield
end

function Renderer:createUnit(u)
	local model
	local teamColor = TEAM_COLORS[u.team]
	if u.isMinion and u.minionVisual and u.minionVisual.shape == "orb" then
		model = FighterModel.buildOrb(u.radius, u.minionVisual.color, teamColor)
	else
		local look = u.def and u.def.look or {}
		if u.isMinion and u.minionVisual and u.minionVisual.look then
			look = u.minionVisual.look
		end
		model = FighterModel.build(look, u.baseRadius, teamColor, u.def and u.def.name or "Fighter")
	end
	local root = model.PrimaryPart
	local ring = model:FindFirstChild("TeamRing")
	local displayName = u.isMinion and (u.name or "") or (u.def and u.def.name or "")
	local bar, fill, shield = makeHealthBar(root, u.baseRadius, u.team, displayName)
	if u.isMinion then
		bar.Size = UDim2.fromOffset(60, 16)
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "TeamRing" then
				d.Transparency = math.max(d.Transparency, (u.visual and u.visual.transparency) or 0.3)
			end
		end
	end
	model.Parent = self.folder
	local rec = {
		model = model,
		root = root,
		ring = ring,
		bar = bar,
		fill = fill,
		shield = shield,
		aura = root:FindFirstChild("AuraAttachment") and root.AuraAttachment:FindFirstChild("Aura"),
		glow = root:FindFirstChild("Glow"),
		scale = 1,
		lastHp = -1,
		yaw = math.atan2(u.vx, -u.vy),
		bob = math.random() * 10,
	}
	self.units[u.id] = rec
	return rec
end

function Renderer:updateUnit(u, rec, dt)
	if not rec.model.Parent then
		return
	end
	-- size changes (grow / shrink statuses)
	local scale = u.radius / u.baseRadius
	if math.abs(scale - rec.scale) > 0.02 then
		pcall(function()
			rec.model:ScaleTo(scale)
		end)
		rec.scale = scale
	end
	-- facing: turn smoothly toward the movement direction
	local speed = math.sqrt(u.vx * u.vx + u.vy * u.vy)
	if speed > 0.5 then
		local target = math.atan2(u.vx, -u.vy)
		local diff = (target - rec.yaw + math.pi) % (2 * math.pi) - math.pi
		rec.yaw += diff * math.min(1, dt * 12)
	end
	rec.bob += dt * 10
	local stunned = u.status.stun ~= nil
	local hop = stunned and 0 or math.abs(math.sin(rec.bob)) * 0.35
	local pos = self:world(u.x, u.radius + hop, u.y)
	local spin = stunned and CFrame.Angles(0, 0, math.sin(rec.bob * 2) * 0.3) or CFrame.identity
	rec.root.CFrame = CFrame.new(pos) * CFrame.Angles(0, -rec.yaw, 0) * spin
	if rec.ring then
		rec.ring.CFrame = CFrame.new(self:world(u.x, 0.12, u.y)) * CFrame.Angles(0, 0, math.rad(90))
	end
	-- health bar
	if u.hp ~= rec.lastHp then
		rec.lastHp = u.hp
		rec.fill.Size = UDim2.fromScale(math.clamp(u.hp / u.maxHp, 0, 1), 1)
	end
	local sh = u.status.shield
	rec.shield.Size = UDim2.fromScale(sh and math.clamp((sh.amount or 0) / u.maxHp, 0, 1) or 0, 1)
	-- aura: on while a visual aura or a buff is active
	local auraColor = u.visual.aura
	local buffed = u.status.empower or u.status.haste or u.status.invuln or u.status.unstoppable
	if rec.aura then
		rec.aura.Enabled = auraColor ~= nil or buffed ~= nil or u.ultReady
		if auraColor and rec.auraColor ~= auraColor then
			rec.auraColor = auraColor
			rec.aura.Color = ColorSequence.new(hex(auraColor))
			if rec.glow then
				rec.glow.Color = hex(auraColor)
			end
		end
	end
	if rec.glow then
		rec.glow.Enabled = auraColor ~= nil or u.ultReady
	end
	-- ghost / invisibility
	local wantT = u.visual.transparency or ((u.status.ghost or u.status.intangible) and 0.6) or nil
	if wantT ~= rec.transparency and not u.isMinion then
		rec.transparency = wantT
		-- (LocalTransparencyModifier doesn't replicate, so change Transparency itself)
		for _, d in rec.model:GetDescendants() do
			if d:IsA("BasePart") and d.Name ~= "TeamRing" then
				local base = d:GetAttribute("BaseT")
				if base == nil then
					base = d.Transparency
					d:SetAttribute("BaseT", base)
				end
				d.Transparency = wantT and math.max(base, wantT) or base
			end
		end
	end
	-- death
	if not u.alive and not rec.dead then
		rec.dead = true
		rec.bar.Enabled = false
		for _, d in rec.model:GetDescendants() do
			if d:IsA("BasePart") then
				TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			end
		end
	end
end

----------------------------------------------------------------------
-- entities
----------------------------------------------------------------------

local function basicPart(shape, color, mat, transparency)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Shape = shape
	p.Color = color
	p.Material = mat
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

function Renderer:createEntity(e)
	local v = e.visual or {}
	local shape = v.shape or "ball"
	if shape == "none" then
		return nil
	end
	local col = hex(v.color, Color3.new(1, 1, 1))
	local mat = material(v.material)
	local t = v.transparency or 0
	local p
	if shape == "ball" then
		p = basicPart(Enum.PartType.Ball, col, mat, t)
		local d = (v.size or e.radius * 2)
		p.Size = Vector3.one * d
	elseif shape == "block" then
		p = basicPart(Enum.PartType.Block, col, mat, t)
		local s = v.size or e.radius * 2
		p.Size = Vector3.new(s, v.height or s, s)
	elseif shape == "disc" or shape == "ring" then
		p = basicPart(Enum.PartType.Cylinder, col, mat, shape == "ring" and math.max(t, 0.55) or t)
		p.Size = Vector3.new(v.height or 0.25, e.radius * 2, e.radius * 2)
	elseif shape == "cylinder" then
		p = basicPart(Enum.PartType.Cylinder, col, mat, t)
		p.Size = Vector3.new(v.height or 5, e.radius * 2, e.radius * 2)
	elseif shape == "spike" then
		p = Instance.new("WedgePart")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Color = col
		p.Material = mat
		p.Transparency = t
		p.Size = Vector3.new(e.radius * 1.2, v.height or e.radius * 2.5, e.radius * 2)
	elseif shape == "beam" then
		p = basicPart(Enum.PartType.Block, col, mat, t)
		p.Size = Vector3.new(e.width or 2, v.height or 1.2, 1)
	else
		p = basicPart(Enum.PartType.Ball, col, mat, t)
		p.Size = Vector3.one * e.radius * 2
	end
	p.Name = e.kind or "Entity"
	if v.light ~= false and mat == Enum.Material.Neon then
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = math.clamp((e.radius or 1) * 4, 6, 24)
		l.Brightness = 1.2
		l.Parent = p
	end
	if v.trail then
		local a = Instance.new("Attachment")
		a.Parent = p
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(col)
		pe.LightEmission = 1
		pe.Size = NumberSequence.new((e.radius or 1) * 0.9, 0)
		pe.Lifetime = NumberRange.new(0.2, 0.35)
		pe.Speed = NumberRange.new(0)
		pe.Rate = 60
		pe.Parent = a
	end
	-- pop in
	local target = p.Size
	if shape ~= "beam" then
		p.Size = target * 0.3
		TweenService:Create(p, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Size = target }):Play()
	end
	p.Parent = self.folder
	return p
end

function Renderer:placeEntity(e, p)
	local v = e.visual or {}
	local shape = v.shape or "ball"
	local h = v.y or 0
	if shape == "beam" or e.shape == "segment" then
		local a = self:world(e.x, h + 1, e.y)
		local b = self:world(e.x2 or e.x, h + 1, e.y2 or e.y)
		local len = (b - a).Magnitude
		if len < 0.05 then
			len = 0.05
		end
		p.Size = Vector3.new(e.width or p.Size.X, p.Size.Y, len)
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
	elseif shape == "disc" or shape == "ring" then
		p.CFrame = CFrame.new(self:world(e.x, h + 0.15, e.y)) * CFrame.Angles(0, 0, math.rad(90))
		local d = e.radius * 2
		if math.abs(p.Size.Y - d) > 0.05 then
			p.Size = Vector3.new(p.Size.X, d, d)
		end
	elseif shape == "cylinder" then
		p.CFrame = CFrame.new(self:world(e.x, h + p.Size.X / 2, e.y)) * CFrame.Angles(0, 0, math.rad(90))
	elseif shape == "spike" then
		local dir = Vector3.new(e.vx, 0, e.vy)
		local pos = self:world(e.x, h + p.Size.Y / 2, e.y)
		if dir.Magnitude > 0.1 then
			p.CFrame = CFrame.lookAt(pos, pos + dir)
		else
			p.CFrame = CFrame.new(pos)
		end
	else
		local y = h + (v.height and v.height / 2 or (p.Size.Y / 2 + 0.3))
		p.CFrame = CFrame.new(self:world(e.x, y, e.y))
	end
end

----------------------------------------------------------------------
-- one-shot effects
----------------------------------------------------------------------

function Renderer:burst(x, y, radius, color, duration)
	local p = basicPart(Enum.PartType.Ball, hex(color, Color3.new(1, 1, 1)), Enum.Material.Neon, 0.25)
	p.Size = Vector3.one * 0.5
	p.CFrame = CFrame.new(self:world(x, 1, y))
	p.Parent = self.folder
	local d = duration or 0.35
	TweenService:Create(p, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.one * math.max(radius * 2, 1),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, d + 0.05)
end

function Renderer:ring(x, y, radius, color, duration)
	local p = basicPart(Enum.PartType.Cylinder, hex(color, Color3.new(1, 1, 1)), Enum.Material.Neon, 0.3)
	p.Size = Vector3.new(0.2, 1, 1)
	p.CFrame = CFrame.new(self:world(x, 0.3, y)) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = self.folder
	local d = duration or 0.4
	TweenService:Create(p, TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	Debris:AddItem(p, d + 0.05)
end

function Renderer:line(x, y, x2, y2, width, color, duration)
	local a = self:world(x, 1, y)
	local b = self:world(x2, 1, y2)
	local len = math.max((b - a).Magnitude, 0.1)
	local p = basicPart(Enum.PartType.Block, hex(color, Color3.new(1, 1, 1)), Enum.Material.Neon, 0.1)
	p.Size = Vector3.new(width or 1, 1, len)
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
	p.Parent = self.folder
	local d = duration or 0.25
	TweenService:Create(p, TweenInfo.new(d), { Transparency = 1, Size = Vector3.new(0.1, 0.2, len) }):Play()
	Debris:AddItem(p, d + 0.05)
end

function Renderer:floatText(x, y, text, color, size, rise)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(self:world(x, 4, y))
	anchor.Parent = self.folder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(220 * (size or 1), 46 * (size or 1))
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.Parent = anchor
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextScaled = true
	label.Font = Enum.Font.FredokaOne
	label.TextColor3 = hex(color, Color3.new(1, 1, 1))
	label.TextStrokeTransparency = 0
	label.Parent = bb
	TweenService:Create(bb, TweenInfo.new(0.9, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(0, rise or 4, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1)
end

function Renderer:playSound(name, x, y)
	local id = Renderer.SOUNDS[name]
	if not id then
		return
	end
	local anchor = Instance.new("Attachment")
	anchor.WorldPosition = self:world(x or 0, 2, y or 0)
	anchor.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.5
	s.RollOffMaxDistance = 220
	s.Parent = anchor
	s:Play()
	Debris:AddItem(anchor, 3)
end

function Renderer:handleFx(fx)
	local b = self.battle
	local k = fx.kind
	if k == "burst" then
		self:burst(fx.x, fx.y, fx.radius or 3, fx.color, fx.duration)
	elseif k == "ring" then
		self:ring(fx.x, fx.y, fx.radius or 6, fx.color, fx.duration)
	elseif k == "line" then
		self:line(fx.x, fx.y, fx.x2, fx.y2, fx.width, fx.color, fx.duration)
	elseif k == "text" then
		self:floatText(fx.x, fx.y, fx.text, fx.color, fx.size or 1)
	elseif k == "callout" then
		local u
		for _, unit in b.units do
			if unit.id == fx.unitId then
				u = unit
			end
		end
		if u then
			self:floatText(u.x, u.y, fx.text, fx.color or "#ffffff", fx.slot == 2 and 1.6 or 1.2, 6)
			if fx.slot == 2 then
				self:ring(u.x, u.y, 10, fx.color or "#ffffff", 0.5)
			end
		end
		table.insert(self.clientFx, fx)
	elseif k == "telegraph" then
		local col = fx.color or (fx.team and (fx.team == 1 and "#38bdf8" or "#f43f5e")) or "#f43f5e"
		local p = basicPart(Enum.PartType.Cylinder, hex(col), Enum.Material.Neon, 0.6)
		p.Size = Vector3.new(0.12, (fx.radius or 4) * 2, (fx.radius or 4) * 2)
		p.CFrame = CFrame.new(self:world(fx.x, 0.12, fx.y)) * CFrame.Angles(0, 0, math.rad(90))
		p.Parent = self.folder
		TweenService:Create(p, TweenInfo.new(fx.duration or 1, Enum.EasingStyle.Linear), { Transparency = 0.35 }):Play()
		Debris:AddItem(p, (fx.duration or 1) + 0.05)
	elseif k == "dmg" then
		-- damage numbers: limit how many we create per unit per second
		local now = os.clock()
		local key = fx.unitId or 0
		local budget = self.dmgBudget[key]
		if not budget or now - budget.t > 0.15 then
			self.dmgBudget[key] = { t = now }
			local heal = fx.dmgKind == "heal"
			local amount = math.floor(fx.amount + 0.5)
			if amount >= 1 then
				local col = "#ffffff"
				if heal then
					col = "#4ade80"
				elseif fx.dmgKind == "dot" then
					col = "#c084fc"
				elseif fx.big then
					col = "#ffd34d"
				end
				self:floatText(fx.x + math.random(-10, 10) / 10, fx.y, (heal and "+" or "-") .. amount, col, fx.big and 0.95 or 0.7, 3)
			end
		end
	elseif k == "spark" then
		self:burst(fx.x, fx.y, 1.6, "#fff6c2", 0.15)
		self:playSound("hit", fx.x, fx.y)
	elseif k == "sound" then
		self:playSound(fx.name, fx.x, fx.y)
	elseif k == "shake" or k == "flash" or k == "banner" or k == "ultReady" then
		table.insert(self.clientFx, fx)
	end
end

----------------------------------------------------------------------
-- main frame update
----------------------------------------------------------------------

function Renderer:frame(dt)
	local b = self.battle
	-- units
	local seen = {}
	for _, u in b.units do
		seen[u.id] = true
		local rec = self.units[u.id] or self:createUnit(u)
		self:updateUnit(u, rec, dt)
	end
	for id, rec in self.units do
		if not seen[id] then
			rec.model:Destroy()
			self.units[id] = nil
		end
	end
	-- entities
	local live = {}
	for _, e in b.entities do
		live[e.id] = true
		local p = self.entities[e.id]
		if p == nil then
			p = self:createEntity(e) or false
			self.entities[e.id] = p
		end
		if p then
			self:placeEntity(e, p)
		end
	end
	for id, p in self.entities do
		if type(id) == "number" and not live[id] then
			if p then
				TweenService:Create(p, TweenInfo.new(0.15), { Transparency = 1 }):Play()
				Debris:AddItem(p, 0.2)
			end
			self.entities[id] = nil
		end
	end
	-- gimmick props (cursed orb, ...)
	local liveProps = {}
	for _, pr in b.props or {} do
		liveProps[pr.id] = true
		local p = self.entities["prop" .. pr.id]
		if p == nil then
			p = self:createEntity(pr) or false
			self.entities["prop" .. pr.id] = p
		end
		if p then
			p.CFrame = CFrame.new(self:world(pr.x, 1.5 + math.sin(os.clock() * 3) * 0.4, pr.y))
		end
	end
	for key, p in self.entities do
		if type(key) == "string" and key:sub(1, 4) == "prop" and not liveProps[tonumber(key:sub(5))] then
			if p then
				p:Destroy()
			end
			self.entities[key] = nil
		end
	end
	-- Arena Collapse: glowing red walls closing in during overtime
	if b.overtime then
		if not self.collapse then
			self.collapse = {}
			for i = 1, 4 do
				local w = basicPart(Enum.PartType.Block, Color3.fromRGB(255, 60, 60), Enum.Material.ForceField, 0.2)
				w.Name = "CollapseWall"
				w.Parent = self.folder
				self.collapse[i] = w
			end
		end
		local hx, hy = b.halfX, b.halfY
		local h = 5
		local walls = {
			{ CFrame.new(self:world(hx + 0.5, h / 2, 0)), Vector3.new(1, h, hy * 2 + 2) },
			{ CFrame.new(self:world(-hx - 0.5, h / 2, 0)), Vector3.new(1, h, hy * 2 + 2) },
			{ CFrame.new(self:world(0, h / 2, hy + 0.5)), Vector3.new(hx * 2 + 2, h, 1) },
			{ CFrame.new(self:world(0, h / 2, -hy - 0.5)), Vector3.new(hx * 2 + 2, h, 1) },
		}
		for i, w in walls do
			self.collapse[i].CFrame = w[1]
			self.collapse[i].Size = w[2]
		end
	end
	-- fx
	for _, fx in b:flushFx() do
		local ok, err = pcall(self.handleFx, self, fx)
		if not ok then
			warn("[Renderer] fx error:", err)
		end
	end
end

function Renderer:takeClientFx()
	local q = self.clientFx
	self.clientFx = {}
	return q
end

function Renderer:getUnitModel(unitId)
	local rec = self.units[unitId]
	return rec and rec.model
end

function Renderer:destroy()
	self.folder:Destroy()
	self.units = {}
	self.entities = {}
end

return Renderer
