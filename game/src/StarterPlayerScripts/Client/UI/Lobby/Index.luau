--!nonstrict
--[[
	Lobby/Index: the INDEX panel — every fighter in the game.
	Owned fighters are in colour with their copy count, the rest are dimmed
	with a padlock. Tap a fighter to see its details: portrait, rarity, role,
	tagline, stat bars (compared with the best fighter in each stat) and both
	abilities.
]]

local Util = require(script.Parent.Util)
local Kit = Util.Kit
local Fighters = Util.Fighters

local Index = {
	title = "INDEX",
	color = Kit.C.blue,
	size = Vector2.new(820, 480),
}

local STATS = {
	{ key = "hp", label = "HP", color = Kit.C.green },
	{ key = "speed", label = "SPEED", color = Kit.C.blue },
	{ key = "size", label = "SIZE", color = Kit.C.purple },
	{ key = "contactDamage", label = "CONTACT DMG", color = Kit.C.red },
}

local gridView, countLabel, detailView, detailLeft, detailRight
local cells = {} -- [fighterId] = {overlay, copies, copiesText, name}
local maxStats = nil
local shownFighter = nil -- fighter in the detail view, or nil
local shownCount = 0 -- its copy count when we drew the detail view

local function ownedCount(id)
	local data = Util.data()
	local owned = data and data.owned
	return owned and tonumber(owned[id]) or 0
end

-- biggest value of each stat in the whole roster (the bars are relative to it)
local function getMaxStats()
	if maxStats then
		return maxStats
	end
	maxStats = {}
	for _, s in STATS do
		maxStats[s.key] = 1
	end
	for _, f in Fighters.List or {} do
		for _, s in STATS do
			local v = f.stats and tonumber(f.stats[s.key])
			if v and v > maxStats[s.key] then
				maxStats[s.key] = v
			end
		end
	end
	return maxStats
end

local function clear(frame)
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

----------------------------------------------------------------------
-- grid
----------------------------------------------------------------------

local function makeCell(parent, f, order)
	local rc = Kit.rarityColor(f.rarity)
	local b = Instance.new("TextButton")
	b.Name = tostring(f.id)
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = Color3.new(1, 1, 1)
	b.LayoutOrder = order
	Kit.corner(b, 12)
	Kit.stroke(b, 3, rc)
	Kit.gradient(b, rc:Lerp(Kit.C.panel2, 0.45), Kit.C.panel)
	b.Parent = parent

	local portrait = Kit.portrait(b, f, UDim2.fromOffset(70, 70))
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 10)
	local name = Kit.label(b, {
		text = f.name or f.id,
		size = UDim2.new(1, -10, 0, 22),
		position = UDim2.new(0.5, 0, 0, 86),
		anchor = Vector2.new(0.5, 0),
	})
	Kit.label(b, {
		text = string.upper(f.rarity or ""),
		color = rc,
		size = UDim2.new(1, -10, 0, 16),
		position = UDim2.new(0.5, 0, 0, 110),
		anchor = Vector2.new(0.5, 0),
		font = Kit.FontBody,
	})
	local copies = Util.box(b, {
		name = "Copies",
		size = UDim2.fromOffset(40, 24),
		position = UDim2.new(1, -4, 0, 4),
		anchor = Vector2.new(1, 0),
		color = Kit.C.gold,
		corner = 999,
		stroke = 2,
		z = 3,
	})
	local copiesText = Kit.label(copies, {
		text = "x1",
		size = UDim2.new(1, -6, 1, -4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		z = 4,
	})
	-- dark cover + padlock for fighters you don't own yet
	local overlay = Util.box(b, { name = "Locked", color = Kit.C.stroke, transparency = 0.4, corner = 12, z = 2 })
	Util.lockIcon(overlay, 34, UDim2.new(0.5, 0, 0, 28), Vector2.new(0.5, 0))

	b.Activated:Connect(function()
		Index.showDetail(f)
	end)
	cells[f.id] = { overlay = overlay, copies = copies, copiesText = copiesText, name = name }
end

local function refreshCells()
	local total, have = 0, 0
	for _, f in Util.sortedFighters() do
		total += 1
		local n = ownedCount(f.id)
		local c = cells[f.id]
		if c then
			c.overlay.Visible = n <= 0
			c.copies.Visible = n > 0
			c.copiesText.Text = "x" .. n
			c.name.TextColor3 = n > 0 and Kit.C.text or Kit.C.sub
		end
		if n > 0 then
			have += 1
		end
	end
	countLabel.Text = string.format("COLLECTED %d / %d", have, total)
end

local function buildGrid(content)
	gridView = Util.group(content, { name = "Grid" })
	countLabel = Kit.label(gridView, {
		text = "COLLECTED 0 / 0",
		color = Kit.C.gold,
		size = UDim2.new(0.5, 0, 0, 32),
		alignX = Enum.TextXAlignment.Left,
	})
	Kit.label(gridView, {
		text = "Tap a fighter for details",
		color = Kit.C.sub,
		size = UDim2.new(0.5, 0, 0, 22),
		position = UDim2.new(1, 0, 0, 6),
		anchor = Vector2.new(1, 0),
		alignX = Enum.TextXAlignment.Right,
		font = Kit.FontBody,
	})
	local scroll = Kit.scroll(gridView, { size = UDim2.new(1, 0, 1, -40), position = UDim2.fromOffset(0, 40) })
	Kit.grid(scroll, UDim2.fromOffset(118, 136), 10)
	Kit.padding(scroll, 6)
	for i, f in Util.sortedFighters() do
		makeCell(scroll, f, i)
	end
end

----------------------------------------------------------------------
-- detail view
----------------------------------------------------------------------

local function statRow(parent, def, value, order)
	local row = Util.group(parent, { size = UDim2.new(1, -8, 0, 28), order = order })
	Kit.label(row, {
		text = def.label,
		size = UDim2.new(0, 130, 1, -4),
		position = UDim2.new(0, 0, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		alignX = Enum.TextXAlignment.Left,
		font = Kit.FontBody,
	})
	local bar = Util.bar(row, {
		size = UDim2.new(1, -210, 0, 20),
		position = UDim2.new(0, 136, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = def.color,
	})
	Util.setBar(bar, (value or 0) / getMaxStats()[def.key], nil)
	Kit.label(row, {
		text = value and tostring(value) or "-",
		size = UDim2.new(0, 64, 1, -4),
		position = UDim2.new(1, 0, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		alignX = Enum.TextXAlignment.Right,
	})
end

local function abilityCard(parent, title, ability, extra, order)
	ability = ability or {}
	local accent = Kit.hex(ability.color or "#ffffff")
	local c = Util.box(parent, { size = UDim2.new(1, -8, 0, 104), color = Kit.C.panel2, corner = 12, stroke = 3, order = order })
	Util.box(c, { size = UDim2.new(0, 8, 1, -16), position = UDim2.new(0, 8, 0.5, 0), anchor = Vector2.new(0, 0.5), color = accent, corner = 4 })
	Kit.label(c, {
		text = title .. ": " .. string.upper(ability.name or "?"),
		color = accent:Lerp(Color3.new(1, 1, 1), 0.3),
		size = UDim2.new(1, -130, 0, 28),
		position = UDim2.fromOffset(24, 6),
		alignX = Enum.TextXAlignment.Left,
	})
	if extra then
		Kit.label(c, {
			text = extra,
			color = Kit.C.sub,
			size = UDim2.fromOffset(100, 24),
			position = UDim2.new(1, -10, 0, 8),
			anchor = Vector2.new(1, 0),
			alignX = Enum.TextXAlignment.Right,
			font = Kit.FontBody,
		})
	end
	local desc = Kit.label(c, {
		text = ability.description or "",
		color = Kit.C.text,
		size = UDim2.new(1, -36, 1, -44),
		position = UDim2.fromOffset(24, 38),
		alignX = Enum.TextXAlignment.Left,
		alignY = Enum.TextYAlignment.Top,
		font = Kit.FontBody,
		stroke = false,
	})
	Util.maxText(desc, 18)
end

local function fillLeft(f)
	local rc = Kit.rarityColor(f.rarity)
	local portrait = Kit.portrait(detailLeft, f, UDim2.fromOffset(130, 130))
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 14)
	Kit.label(detailLeft, {
		text = f.name or f.id,
		size = UDim2.new(1, -16, 0, 34),
		position = UDim2.new(0.5, 0, 0, 152),
		anchor = Vector2.new(0.5, 0),
	})
	local pill = Util.box(detailLeft, {
		size = UDim2.fromOffset(150, 28),
		position = UDim2.new(0.5, 0, 0, 190),
		anchor = Vector2.new(0.5, 0),
		color = rc,
		corner = 999,
		stroke = 2,
	})
	Kit.label(pill, {
		text = string.upper(f.rarity or ""),
		size = UDim2.new(1, -10, 1, -6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	Kit.label(detailLeft, {
		text = "ROLE: " .. string.upper(f.role or "?"),
		color = Kit.C.gold,
		size = UDim2.new(1, -16, 0, 22),
		position = UDim2.new(0.5, 0, 0, 224),
		anchor = Vector2.new(0.5, 0),
		font = Kit.FontBody,
	})
	local tagline = Kit.label(detailLeft, {
		text = f.tagline or "",
		color = Kit.C.sub,
		size = UDim2.new(1, -20, 0, 56),
		position = UDim2.new(0.5, 0, 0, 250),
		anchor = Vector2.new(0.5, 0),
		font = Kit.FontBody,
		stroke = false,
	})
	Util.maxText(tagline, 18)
	local n = ownedCount(f.id)
	Kit.label(detailLeft, {
		text = n > 0 and ("OWNED  x" .. n) or "NOT OWNED - SUMMON IT!",
		color = n > 0 and Kit.C.green or Kit.C.red,
		size = UDim2.new(1, -16, 0, 26),
		position = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
	})
end

local function fillRight(f)
	Kit.label(detailRight, {
		text = "STATS",
		color = Kit.C.gold,
		size = UDim2.new(1, -8, 0, 26),
		alignX = Enum.TextXAlignment.Left,
		order = 1,
	})
	for i, def in STATS do
		statRow(detailRight, def, f.stats and tonumber(f.stats[def.key]), 1 + i)
	end
	local a1 = f.ability1 or {}
	local cd = a1.cooldown and ("COOLDOWN " .. tostring(a1.cooldown) .. "s") or nil
	abilityCard(detailRight, "ABILITY", a1, cd, 10)
	abilityCard(detailRight, "ULTIMATE", f.ability2, "ULT METER", 11)
end

-- (re)draw the detail page contents
local function renderDetail(f)
	shownFighter = f
	shownCount = ownedCount(f.id)
	clear(detailLeft)
	clear(detailRight)
	fillLeft(f)
	fillRight(f)
end

-- open the detail page of one fighter
function Index.showDetail(f)
	if not f then
		return
	end
	renderDetail(f)
	detailRight.CanvasPosition = Vector2.zero
	gridView.Visible = false
	detailView.Visible = true
	Kit.popIn(detailView)
end

local function showGrid()
	shownFighter = nil
	detailView.Visible = false
	gridView.Visible = true
end

local function buildDetail(content)
	detailView = Util.group(content, { name = "Detail" })
	detailView.Visible = false
	local back = Kit.button(detailView, {
		text = "BACK",
		color = Util.GREY,
		size = UDim2.fromOffset(120, 40),
	})
	Util.onClick(back, showGrid)
	detailLeft = Util.box(detailView, {
		name = "Left",
		size = UDim2.new(0, 250, 1, -48),
		position = UDim2.fromOffset(0, 48),
		color = Kit.C.panel2,
		corner = 14,
		stroke = 3,
	})
	detailRight = Kit.scroll(detailView, { size = UDim2.new(1, -264, 1, 0), position = UDim2.fromOffset(264, 0) })
	Kit.padding(detailRight, 4)
	local list = Kit.list(detailRight, Enum.FillDirection.Vertical, 6)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left
end

----------------------------------------------------------------------
-- panel interface (used by LobbyUI)
----------------------------------------------------------------------

function Index.build(content, _ctx)
	buildGrid(content)
	buildDetail(content)
	refreshCells()
end

function Index.update(_data)
	if not countLabel then
		return
	end
	refreshCells()
	-- redraw the open detail page only if its copy count changed
	if shownFighter and detailView.Visible and ownedCount(shownFighter.id) ~= shownCount then
		renderDetail(shownFighter)
	end
end

-- arg may be a fighter id to jump straight to its details
function Index.onOpen(arg)
	refreshCells()
	local f = Util.fighter(arg)
	if f then
		Index.showDetail(f)
	else
		showGrid()
	end
end

return Index
