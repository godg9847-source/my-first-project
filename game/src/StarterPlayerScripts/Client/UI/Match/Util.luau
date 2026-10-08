--!nonstrict
--[[
	Match/Util: small helpers shared by the match screens in UI/Match/.
	The basic look (colours, fonts, buttons, panels) lives in UI/Kit — use Kit first.

	  Util.fighter(id)          fighter data, never nil (unknown ids get a placeholder)
	  Util.ability(f, slot)     {name, description, cooldown, trigger, color} of Ability 1 / the Ultimate
	  Util.triggerText(a)       "EVERY 5s", "ON WALL HIT", ... for Ability 1
	  Util.ownedIds()           ids the player may Hero Pick (owned + loaners), best rarity first
	  Util.roleBeats(a, b)      true when role a has the edge over role b (Config.Roles)
	  Util.roleColor(role)      colour of a role
	  Util.teamColor(team)      Kit.C.team1 / Kit.C.team2
	  Util.setting(key, def)    the player's setting (State.data.settings), or def
	  Util.send(t)              fire MatchAction to the server
	  Util.now()                server time (same clock as the endsAt fields)
	  Util.bag()                collects connections / instances / functions; bag:clean() removes all
	  Util.button(...)          Kit.button whose click is ignored while disabled
	  Util.setEnabled(b, on)    grey a Util.button out / back in
	  Util.setFill(grad, f)     hard-edged fill made with a UIGradient (works with round corners)
	  Util.fillFrame(...)       a frame + UIGradient ready for Util.setFill
	  Util.bar(...)             simple horizontal bar (returns background, fill)
	  Util.heart(...)           heart icon made of 3 frames (no image assets)
	  Util.stage(gui)           full-screen frame laid out in 1280x720 "design pixels"
	  Util.setText(l, text)     only touches the label when the text changed
	  Util.rich(text, color)    rich-text colour tag (escapes the text)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Fighters = require(Shared:WaitForChild("Fighters"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local UI = script.Parent.Parent
local Kit = require(UI:WaitForChild("Kit"))
local State = require(UI.Parent:WaitForChild("State"))

local Util = {}

Util.DESIGN_W = 1280
Util.DESIGN_H = 720
Util.GREY = Color3.fromRGB(100, 96, 122)
Util.HEART = Color3.fromRGB(255, 64, 104)
Util.HEART_LOST = Color3.fromRGB(60, 56, 82)
Util.WHITE = Color3.new(1, 1, 1)
Util.BLACK = Color3.new(0, 0, 0)

local WHITE, BLACK = Util.WHITE, Util.BLACK

----------------------------------------------------------------------
-- fighters
----------------------------------------------------------------------

local function placeholder(id)
	return {
		id = tostring(id),
		name = tostring(id or "???"),
		rarity = "Rare",
		role = "",
		tagline = "",
		stats = { hp = 100, speed = 20, size = 5, contactDamage = 5, mass = 1 },
		look = {},
		ability1 = { name = "Skill", description = "", cooldown = 5, color = "#7fd6ff" },
		ability2 = { name = "Ultimate", description = "", color = "#ffd34d" },
	}
end

-- fighter data for an id; never nil so screens can't crash on a bad id
function Util.fighter(id)
	local f = (type(id) == "string") and Fighters.get(id) or nil
	return f or placeholder(id)
end

-- slot 1 = Ability 1 (automatic), slot 2 = Ultimate (tap)
function Util.ability(f, slot)
	local a = (slot == 1 and f.ability1 or f.ability2) or {}
	return {
		name = a.name or (slot == 1 and "Skill" or "Ultimate"),
		description = a.description or "",
		cooldown = tonumber(a.cooldown),
		trigger = a.trigger or "timer",
		color = Kit.hex(a.color or (slot == 1 and "#7fd6ff" or "#ffd34d")),
	}
end

-- 6 -> "6", 6.25 -> "6.3"
function Util.num(n)
	n = tonumber(n) or 0
	return tostring(math.floor(n * 10 + 0.5) / 10)
end

-- short text telling WHEN Ability 1 fires (see docs/ABILITY_API.md)
function Util.triggerText(a)
	local t = a.trigger
	if t == "wall" then
		return "ON WALL HIT"
	elseif t == "contact" then
		return "ON HIT"
	elseif t == "proximity" then
		return "WHEN CLOSE"
	elseif t == "hurt" then
		return "WHEN HURT"
	elseif t == "charge" then
		return "CHARGES " .. Util.num(a.cooldown) .. "s"
	end
	return a.cooldown and ("EVERY " .. Util.num(a.cooldown) .. "s") or ""
end

local function rarityOrder(f)
	local r = Config.Rarities[f.rarity]
	return r and r.order or 0
end

-- every fighter the player may Hero Pick, best rarity first
function Util.ownedIds()
	local ids, seen = {}, {}
	local owned = State.data and State.data.owned
	if type(owned) == "table" then
		for id, copies in owned do
			if type(copies) == "number" and copies >= 1 and Fighters.get(id) then
				table.insert(ids, id)
				seen[id] = true
			end
		end
	end
	-- the server lends the starter fighters when you own fewer than 3
	if #ids < (Config.Match.OptionsPerRound or 3) then
		for _, id in Config.StarterFighters do
			if not seen[id] and Fighters.get(id) then
				table.insert(ids, id)
				seen[id] = true
			end
		end
	end
	table.sort(ids, function(a, b)
		local fa, fb = Util.fighter(a), Util.fighter(b)
		local ra, rb = rarityOrder(fa), rarityOrder(fb)
		if ra ~= rb then
			return ra > rb
		end
		return tostring(fa.name) < tostring(fb.name)
	end)
	return ids
end

-- does role A have the counter-pick edge over role B?
function Util.roleBeats(roleA, roleB)
	local r = Config.Roles and Config.Roles[roleA]
	return r ~= nil and type(r.beats) == "table" and table.find(r.beats, roleB) ~= nil
end

function Util.roleColor(role)
	local r = Config.Roles and Config.Roles[role]
	return Kit.hex(r and r.color or "#c9c6e0")
end

----------------------------------------------------------------------
-- match helpers
----------------------------------------------------------------------

function Util.teamColor(team)
	return team == 2 and Kit.C.team2 or Kit.C.team1
end

function Util.setting(key, default)
	local s = State.data and State.data.settings
	if type(s) == "table" and s[key] ~= nil then
		return s[key]
	end
	return default
end

function Util.gemsInProfile()
	return State.data and tonumber(State.data.gems)
end

function Util.send(action)
	Remotes.event("MatchAction"):FireServer(action)
end

function Util.now()
	return workspace:GetServerTimeNow()
end

----------------------------------------------------------------------
-- cleanup bag: everything added is removed by bag:clean()
----------------------------------------------------------------------

local Bag = {}
Bag.__index = Bag

function Util.bag()
	return setmetatable({ items = {} }, Bag)
end

-- add a connection, an Instance, a function or a table with :Destroy(). Returns it.
function Bag:add(item)
	table.insert(self.items, item)
	return item
end

local function cleanOne(item)
	local t = typeof(item)
	if t == "RBXScriptConnection" then
		item:Disconnect()
	elseif t == "Instance" then
		item:Destroy()
	elseif t == "function" then
		item()
	elseif t == "table" and item.Destroy then
		item:Destroy()
	end
end

-- newest first, so things are undone in reverse order
function Bag:clean()
	local items = self.items
	self.items = {}
	for i = #items, 1, -1 do
		local ok, err = pcall(cleanOne, items[i])
		if not ok then
			warn("[MatchUI] cleanup error:", err)
		end
	end
end

----------------------------------------------------------------------
-- text
----------------------------------------------------------------------

function Util.setText(label, text)
	if label.Text ~= text then
		label.Text = text
	end
end

function Util.escape(s)
	s = tostring(s or "")
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	return s
end

-- '<font color="#rrggbb">text</font>' for labels with RichText = true
function Util.rich(text, color)
	return string.format('<font color="#%s">%s</font>', color:ToHex(), Util.escape(text))
end

----------------------------------------------------------------------
-- buttons
----------------------------------------------------------------------

-- Kit.button + onClick that does nothing while the button is disabled
function Util.button(parent, props, onClick)
	local b = Kit.button(parent, props)
	b:SetAttribute("BaseColor", props.color or Kit.C.blue)
	if onClick then
		b.Activated:Connect(function()
			if not b:GetAttribute("Disabled") then
				onClick()
			end
		end)
	end
	return b
end

-- recolour a Kit.button the same way Kit builds it
local function paint(b, color)
	b.BackgroundColor3 = color
	local g = b:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.15))
	end
end

function Util.setEnabled(b, on)
	if (not b:GetAttribute("Disabled")) == on then
		return -- no change
	end
	b:SetAttribute("Disabled", not on)
	paint(b, on and (b:GetAttribute("BaseColor") or Kit.C.blue) or Util.GREY)
	local label = b:FindFirstChild("Text")
	if label then
		label.TextTransparency = on and 0 or 0.3
	end
end

function Util.setColor(b, color)
	b:SetAttribute("BaseColor", color)
	if not b:GetAttribute("Disabled") then
		paint(b, color)
	end
end

----------------------------------------------------------------------
-- fills and bars
----------------------------------------------------------------------

-- show only the first `frac` (0..1) of the gradient's parent, with a hard edge.
-- Rotation 0 = fills left->right, 270 = bottom->top, 90 = top->bottom.
function Util.setFill(gradient, frac)
	frac = math.clamp(tonumber(frac) or 0, 0, 1)
	if frac <= 0.002 then
		gradient.Transparency = NumberSequence.new(1)
	elseif frac >= 0.998 then
		gradient.Transparency = NumberSequence.new(0)
	else
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(frac, 0),
			NumberSequenceKeypoint.new(frac + 0.001, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
end

-- a frame covering its parent whose visible part is set with Util.setFill
function Util.fillFrame(parent, color, rotation, cornerPx, z)
	local f = Instance.new("Frame")
	f.Name = "Fill"
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = z or 1
	if cornerPx then
		Kit.corner(f, cornerPx)
	end
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 0
	g.Parent = f
	Util.setFill(g, 0)
	f.Parent = parent
	return f, g
end

-- horizontal bar. props: size, position, anchor, color, corner, z. Returns background, fill.
-- Set the value with fill.Size = UDim2.fromScale(frac, 1).
function Util.bar(parent, props)
	local bg = Instance.new("Frame")
	bg.Name = props.name or "Bar"
	bg.Size = props.size or UDim2.fromOffset(200, 14)
	bg.Position = props.position or UDim2.new()
	bg.AnchorPoint = props.anchor or Vector2.zero
	bg.BackgroundColor3 = Kit.C.stroke
	bg.BorderSizePixel = 0
	bg.ZIndex = props.z or 1
	Kit.corner(bg, props.corner or 8)
	Kit.stroke(bg, 2)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = props.color or Kit.C.green
	fill.BorderSizePixel = 0
	fill.ZIndex = 2
	Kit.corner(fill, props.corner or 8)
	fill.Parent = bg
	bg.Parent = parent
	return bg, fill
end

-- timer colour: green, then gold, then red for the last seconds
function Util.timerColor(secondsLeft)
	if secondsLeft <= 3 then
		return Kit.C.red
	elseif secondsLeft <= 7 then
		return Kit.C.gold
	end
	return Kit.C.green
end

----------------------------------------------------------------------
-- heart icon
----------------------------------------------------------------------

-- two circles + a square turned 45 degrees = a heart
local function heartShape(parent, color, scale, z)
	local g = Instance.new("Frame")
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.Size = UDim2.fromScale(scale, scale)
	g.ZIndex = z
	local function piece(x, y, round, rotation)
		local p = Instance.new("Frame")
		p.BorderSizePixel = 0
		p.BackgroundColor3 = color
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.fromScale(x, y)
		p.Size = UDim2.fromScale(0.52, 0.52)
		p.Rotation = rotation or 0
		p.ZIndex = z
		if round then
			Kit.corner(p, 999)
		end
		p.Parent = g
	end
	piece(0.3, 0.36, true)
	piece(0.7, 0.36, true)
	piece(0.5, 0.56, false, 45)
	g.Parent = parent
	return g
end

-- returns { frame, inner, scale (UIScale), setColor(color) }
function Util.heart(parent, px, color)
	local box = Instance.new("Frame")
	box.Name = "Heart"
	box.BackgroundTransparency = 1
	box.Size = UDim2.fromOffset(px, px)
	-- inner frame is centred so the UIScale grows the heart from its middle
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.BackgroundTransparency = 1
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.fromScale(0.5, 0.5)
	inner.Size = UDim2.fromScale(1, 1)
	inner.Parent = box
	local scale = Instance.new("UIScale")
	scale.Parent = inner
	local outline = heartShape(inner, Kit.C.stroke, 1.22, 1)
	outline.Name = "Outline"
	local fill = heartShape(inner, color or Util.HEART, 1, 2)
	fill.Name = "Fill"
	local shine = Instance.new("Frame")
	shine.Name = "Shine"
	shine.BackgroundColor3 = WHITE
	shine.BackgroundTransparency = 0.3
	shine.BorderSizePixel = 0
	shine.Size = UDim2.fromScale(0.16, 0.16)
	shine.Position = UDim2.fromScale(0.2, 0.22)
	shine.ZIndex = 3
	Kit.corner(shine, 999)
	shine.Parent = inner
	box.Parent = parent

	local heart = { frame = box, inner = inner, scale = scale }
	function heart.setColor(c)
		for _, p in fill:GetChildren() do
			if p:IsA("GuiObject") then
				p.BackgroundColor3 = c
			end
		end
	end
	function heart.setShine(on)
		shine.Visible = on
	end
	return heart
end

----------------------------------------------------------------------
-- stage: scaled full-screen root frame
----------------------------------------------------------------------

--[[
	Kit.autoScale only looks at the screen WIDTH. Phones held sideways are very
	wide but short, so a width-only scale would push buttons off the bottom.
	The stage picks the scale that keeps 1280x720 design pixels visible on any
	screen, then grows itself to fill the rest. Children are laid out in design
	pixels and anchored to the edges/centre of the stage.
]]
function Util.stage(gui)
	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	-- top-left anchor: the UIScale then grows the frame from the screen corner
	stage.AnchorPoint = Vector2.zero
	stage.Position = UDim2.new()
	stage.Size = UDim2.fromOffset(Util.DESIGN_W, Util.DESIGN_H)
	local scale = Instance.new("UIScale")
	scale.Parent = stage
	local function fit()
		local size = gui.AbsoluteSize
		if size.X < 10 or size.Y < 10 then
			return
		end
		local s = math.clamp(math.min(size.X / Util.DESIGN_W, size.Y / Util.DESIGN_H), 0.4, 1.4)
		scale.Scale = s
		stage.Size = UDim2.fromOffset(math.floor(size.X / s), math.floor(size.Y / s))
	end
	stage.Parent = gui
	fit()
	local conn = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	return stage, conn
end

-- a transparent frame that fills its parent (used as a screen/layer)
function Util.layer(parent, name, z)
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

-- tween a label's text (and its outline) to transparent
function Util.fadeText(label, t)
	Kit.tween(label, t, { TextTransparency = 1 })
	local st = label:FindFirstChildOfClass("UIStroke")
	if st then
		Kit.tween(st, t, { Transparency = 1 })
	end
end

-- pop a GuiObject in with a bouncy scale (adds a UIScale if it has none)
function Util.pop(gui, from, t)
	local scale = gui:FindFirstChildOfClass("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Parent = gui
	end
	scale.Scale = from or 0.5
	Kit.tween(scale, t or 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	return scale
end

Util.Config = Config
Util.Kit = Kit
Util.State = State

return Util
