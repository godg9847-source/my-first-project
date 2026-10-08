--!nonstrict
--[[
	Match/Cards: fighter cards used by the match screens.

	  Cards.big(parent, fighter, order)          270x380 pick card (TextButton)
	      returns card, scale (UIScale), stroke (UIStroke)
	  Cards.mini(parent, fighter, order, size)   compact card (TextButton) for the Hero Pick list
	      and the reveal; everything inside is sized in scale so any size works
	  Cards.chip(parent, fighter, richText, color)  300x40 strip: portrait + one line of rich text
	  Cards.badge(card, text, color)             small tag on the top edge of a card ("COUNTER!")
]]

local Match = script.Parent
local Util = require(Match:WaitForChild("Util"))
local Kit = Util.Kit

local Cards = {}

local WHITE = Util.WHITE

local function hover(button, scale)
	button.MouseEnter:Connect(function()
		Kit.tween(scale, 0.12, { Scale = 1.05 })
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(scale, 0.12, { Scale = 1 })
	end)
end

local function cardBase(parent, f, order, size, strokePx)
	local rc = Kit.rarityColor(f.rarity)
	local card = Instance.new("TextButton")
	card.Name = "Card_" .. tostring(f.id)
	card.AutoButtonColor = false
	card.Text = ""
	card.Size = size
	card.BackgroundColor3 = WHITE
	card.LayoutOrder = order or 0
	Kit.corner(card, 18)
	local stroke = Kit.stroke(card, strokePx, rc)
	Kit.gradient(card, Kit.C.panel2, Kit.C.bg)
	local scale = Instance.new("UIScale")
	scale.Parent = card
	hover(card, scale)
	card.Parent = parent
	return card, scale, stroke, rc
end

-- coloured strip with the rarity name
local function rarityRibbon(card, f, rc, height)
	local ribbon = Instance.new("Frame")
	ribbon.Name = "Rarity"
	ribbon.Size = UDim2.new(1, -16, 0, height)
	ribbon.Position = UDim2.fromOffset(8, 8)
	ribbon.BackgroundColor3 = rc
	ribbon.BorderSizePixel = 0
	Kit.corner(ribbon, 10)
	ribbon.Parent = card
	Kit.label(ribbon, {
		text = string.upper(tostring(f.rarity or "")),
		size = UDim2.new(1, -8, 1, -6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
end

-- "SKILL: Energy Wave" + trigger + short description
local function abilityBlock(card, tag, a, y, extra)
	local box = Instance.new("Frame")
	box.Name = tag
	box.Size = UDim2.new(1, -16, 0, 58)
	box.Position = UDim2.fromOffset(8, y)
	box.BackgroundColor3 = Kit.C.stroke
	box.BackgroundTransparency = 0.35
	Kit.corner(box, 10)
	box.Parent = card
	local title = Kit.label(box, {
		text = tag .. ": " .. Util.escape(a.name) .. (extra ~= "" and (" " .. Util.rich("(" .. extra .. ")", Kit.C.sub)) or ""),
		size = UDim2.new(1, -12, 0, 22),
		position = UDim2.fromOffset(6, 3),
		color = a.color,
		alignX = Enum.TextXAlignment.Left,
	})
	title.RichText = true
	local desc = Kit.label(box, {
		text = a.description,
		size = UDim2.new(1, -12, 0, 30),
		position = UDim2.fromOffset(6, 26),
		color = Kit.C.sub,
		font = Kit.FontBody,
		scaled = false,
		textSize = 12,
		alignX = Enum.TextXAlignment.Left,
		alignY = Enum.TextYAlignment.Top,
		stroke = false,
	})
	desc.TextTruncate = Enum.TextTruncate.AtEnd
end

-- three pills: HP, SPD, DMG
local function statRow(card, f, y)
	local row = Instance.new("Frame")
	row.Name = "Stats"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -16, 0, 28)
	row.Position = UDim2.fromOffset(8, y)
	row.Parent = card
	local list = Kit.list(row, Enum.FillDirection.Horizontal, 6)
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	local st = f.stats or {}
	local pills = {
		{ "HP", st.hp, Kit.C.green },
		{ "SPD", st.speed, Kit.C.gem },
		{ "DMG", st.contactDamage, Kit.C.red },
	}
	for i, p in pills do
		local pill = Instance.new("Frame")
		pill.Size = UDim2.fromOffset(78, 26)
		pill.BackgroundColor3 = p[3]:Lerp(Util.BLACK, 0.55)
		pill.LayoutOrder = i
		Kit.corner(pill, 13)
		pill.Parent = row
		Kit.label(pill, {
			text = p[1] .. " " .. Util.num(p[2]),
			size = UDim2.new(1, -10, 1, -6),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			color = p[3]:Lerp(WHITE, 0.4),
			font = Kit.FontBody,
		})
	end
end

-- the big pick card (270 x 380)
function Cards.big(parent, f, order)
	local card, scale, stroke, rc = cardBase(parent, f, order, UDim2.fromOffset(270, 380), 5)
	rarityRibbon(card, f, rc, 30)

	-- soft glow behind the portrait
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0)
	glow.Position = UDim2.new(0.5, 0, 0, 42)
	glow.Size = UDim2.fromOffset(122, 122)
	glow.BackgroundColor3 = rc
	glow.BackgroundTransparency = 0.6
	Kit.corner(glow, 999)
	glow.Parent = card
	local portrait = Kit.portrait(card, f, UDim2.fromOffset(102, 102))
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 52)
	portrait.ZIndex = 2

	Kit.label(card, {
		name = "FighterName",
		text = tostring(f.name),
		size = UDim2.new(1, -16, 0, 32),
		position = UDim2.fromOffset(8, 160),
		strokeThickness = 3,
		z = 2,
	})
	Kit.label(card, {
		name = "Role",
		text = string.upper(tostring(f.role or "")),
		size = UDim2.new(1, -16, 0, 18),
		position = UDim2.fromOffset(8, 193),
		color = Util.roleColor(f.role):Lerp(WHITE, 0.25),
		font = Kit.FontBody,
	})
	local a1 = Util.ability(f, 1)
	abilityBlock(card, "SKILL", a1, 214, Util.triggerText(a1))
	abilityBlock(card, "ULT", Util.ability(f, 2), 276, "")
	statRow(card, f, 342)
	return card, scale, stroke
end

-- compact card; size defaults to 150 x 190. Layout uses scale so it fits any size.
function Cards.mini(parent, f, order, size)
	local card, scale, stroke, rc = cardBase(parent, f, order, size or UDim2.fromOffset(150, 190), 4)
	local holder = Instance.new("Frame")
	holder.Name = "PortraitHolder"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.fromScale(0.5, 0.06)
	holder.Size = UDim2.fromScale(0.62, 0.45)
	holder.Parent = card
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = holder
	local portrait = Kit.portrait(holder, f, UDim2.fromScale(1, 1))
	portrait.Name = "Portrait"
	Kit.label(card, {
		name = "FighterName",
		text = tostring(f.name),
		size = UDim2.fromScale(0.92, 0.17),
		position = UDim2.fromScale(0.04, 0.53),
		strokeThickness = 2,
	})
	Kit.label(card, {
		name = "Rarity",
		text = string.upper(tostring(f.rarity or "")),
		size = UDim2.fromScale(0.9, 0.11),
		position = UDim2.fromScale(0.05, 0.71),
		color = rc,
		font = Kit.FontBody,
	})
	Kit.label(card, {
		name = "Role",
		text = string.upper(tostring(f.role or "")),
		size = UDim2.fromScale(0.9, 0.1),
		position = UDim2.fromScale(0.05, 0.84),
		color = Kit.C.sub,
		font = Kit.FontBody,
	})
	return card, scale, stroke
end

-- one-line strip with a portrait, tinted in a team colour
function Cards.chip(parent, f, richText, color)
	local chip = Instance.new("Frame")
	chip.Name = "Chip"
	chip.Size = UDim2.fromOffset(300, 40)
	chip.BackgroundColor3 = WHITE
	Kit.corner(chip, 20)
	Kit.stroke(chip, 3)
	Kit.gradient(chip, color, color:Lerp(Util.BLACK, 0.45))
	local p = Kit.portrait(chip, f, UDim2.fromOffset(30, 30))
	p.AnchorPoint = Vector2.new(0, 0.5)
	p.Position = UDim2.new(0, 6, 0.5, 0)
	local label = Kit.label(chip, {
		name = "Text",
		text = richText,
		size = UDim2.new(1, -52, 1, -12),
		position = UDim2.new(0, 44, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		alignX = Enum.TextXAlignment.Left,
		font = Kit.FontBody,
	})
	label.RichText = true
	chip.Parent = parent
	Util.pop(chip, 0.4)
	return chip
end

-- small tag sitting on the top edge of a card
function Cards.badge(card, text, color)
	local old = card:FindFirstChild("Badge")
	if old then
		old:Destroy()
	end
	local b = Instance.new("Frame")
	b.Name = "Badge"
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = UDim2.fromScale(0.5, 0)
	b.Size = UDim2.fromOffset(170, 32)
	b.BackgroundColor3 = color
	b.ZIndex = 30
	Kit.corner(b, 16)
	Kit.stroke(b, 3)
	Kit.label(b, {
		text = text,
		size = UDim2.new(1, -12, 1, -6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		z = 31,
	})
	b.Parent = card
	Util.pop(b, 0.3)
	return b
end

-- dark cover on a card (used for "not chosen")
function Cards.dim(card, on)
	local d = card:FindFirstChild("Dim")
	if on and not d then
		d = Instance.new("Frame")
		d.Name = "Dim"
		d.Size = UDim2.fromScale(1, 1)
		d.BackgroundColor3 = Util.BLACK
		d.BackgroundTransparency = 1
		d.ZIndex = 25
		Kit.corner(d, 18)
		d.Parent = card
		Kit.tween(d, 0.2, { BackgroundTransparency = 0.5 })
	elseif not on and d then
		d:Destroy()
	end
end

return Cards
