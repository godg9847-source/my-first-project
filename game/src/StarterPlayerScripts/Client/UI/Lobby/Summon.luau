--!nonstrict
--[[
	Lobby/Summon: the SUMMON panel. One card per Config.Banners entry with drop
	rates, pity progress and x1 / x10 buttons.
	Buttons call RemoteFunction Summon:InvokeServer(bannerId, 1 or 10) and then
	play the Lobby/Reveal animation. Errors show as a toast.
]]

local Util = require(script.Parent.Util)
local Reveal = require(script.Parent.Reveal)
local Kit = Util.Kit
local Config = Util.Config

local Summon = {
	title = "SUMMON",
	color = Kit.C.gold,
	size = Vector2.new(820, 480),
}

local CARD_H = 392

local ctx = nil
local cards = {} -- {banner, pityLabel, pityBar, buttons = {}}
local busy = false

local function pctText(p)
	return string.format("%g%%", p)
end

local function priceText(banner, count)
	local cost = count == 10 and banner.cost10 or banner.cost
	return "x" .. count .. "\n" .. Kit.short(cost or 0) .. " " .. string.upper(banner.currency or "")
end

local function setBusy(v)
	busy = v
	for _, c in cards do
		for _, b in c.buttons do
			Util.styleButton(b, nil, nil, not v)
		end
	end
end

local function doSummon(banner, count)
	if busy then
		return
	end
	setBusy(true)
	task.spawn(function()
		local res = Util.invoke("Summon", banner.id, count)
		setBusy(false)
		if not res then
			ctx.toast("Summon failed, please try again.", Kit.C.red)
			return
		end
		if not res.ok then
			ctx.toast(tostring(res.error or "Summon failed."), Kit.C.red)
			return
		end
		-- (if a match started while we waited, skip the show: the fighters are in the Index)
		if type(res.results) == "table" and #res.results > 0 and not Util.State.inMatch then
			Reveal.play(res.results)
		end
	end)
end

----------------------------------------------------------------------
-- building
----------------------------------------------------------------------

local function buildOdds(card, banner, y)
	Kit.label(card, {
		text = "DROP RATES",
		size = UDim2.new(1, -24, 0, 22),
		position = UDim2.fromOffset(12, y),
		color = Kit.C.sub,
		font = Kit.FontBody,
	})
	y += 26
	for _, rarity in Config.RarityOrder do
		local pct = banner.odds and banner.odds[rarity]
		if pct and pct > 0 then
			local rc = Kit.rarityColor(rarity)
			local row = Util.box(card, {
				size = UDim2.new(1, -24, 0, 28),
				position = UDim2.fromOffset(12, y),
				color = Kit.C.stroke,
				transparency = 0.45,
				corner = 8,
			})
			Util.box(row, {
				size = UDim2.fromOffset(14, 14),
				position = UDim2.new(0, 10, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				color = rc,
				corner = 999,
			})
			Kit.label(row, {
				text = string.upper(rarity),
				color = rc,
				size = UDim2.new(0.6, -34, 1, -6),
				position = UDim2.new(0, 32, 0.5, 0),
				anchor = Vector2.new(0, 0.5),
				alignX = Enum.TextXAlignment.Left,
			})
			Kit.label(row, {
				text = pctText(pct),
				size = UDim2.new(0.4, -12, 1, -6),
				position = UDim2.new(1, -10, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				alignX = Enum.TextXAlignment.Right,
			})
			y += 32
		end
	end
	return y
end

local function buildCard(parent, banner, order, width)
	local color = Kit.hex(banner.color)
	local card = Util.box(parent, {
		name = tostring(banner.id),
		size = UDim2.fromOffset(width, CARD_H),
		color = Color3.new(1, 1, 1),
		corner = 16,
		stroke = 4,
		order = order,
	})
	Kit.gradient(card, color:Lerp(Kit.C.panel2, 0.6), Kit.C.panel)

	local head = Util.box(card, {
		size = UDim2.new(1, -16, 0, 48),
		position = UDim2.fromOffset(8, 8),
		color = Color3.new(1, 1, 1),
		corner = 12,
		stroke = 3,
	})
	Kit.gradient(head, color:Lerp(Color3.new(1, 1, 1), 0.25), color)
	Kit.label(head, {
		text = string.upper(banner.name or banner.id),
		size = UDim2.new(1, -16, 1, -12),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		strokeThickness = 3,
	})

	local c = { banner = banner, buttons = {} }
	local y = buildOdds(card, banner, 64)

	if banner.pity then
		c.pityLabel = Kit.label(card, {
			text = "",
			size = UDim2.new(1, -24, 0, 20),
			position = UDim2.fromOffset(12, y + 6),
			color = Kit.C.sub,
			font = Kit.FontBody,
		})
		c.pityBar = Util.bar(card, {
			size = UDim2.new(1, -24, 0, 22),
			position = UDim2.fromOffset(12, y + 30),
			color = Kit.rarityColor(banner.pity.rarity),
		})
	end

	local btnColor = banner.currency == "gems" and Kit.C.gem or Kit.C.gold
	for i, count in { 1, 10 } do
		local b = Kit.button(card, {
			text = priceText(banner, count),
			color = btnColor,
			size = UDim2.new(0.5, -18, 0, 70),
			position = i == 1 and UDim2.new(0, 12, 1, -12) or UDim2.new(1, -12, 1, -12),
			anchor = i == 1 and Vector2.new(0, 1) or Vector2.new(1, 1),
		})
		Util.styleButton(b, nil, btnColor, true)
		Util.onClick(b, function()
			doSummon(banner, count)
		end)
		table.insert(c.buttons, b)
	end
	table.insert(cards, c)
end

----------------------------------------------------------------------
-- panel interface (used by LobbyUI)
----------------------------------------------------------------------

function Summon.build(content, context)
	ctx = context
	local scroll = Kit.scroll(content, {})
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	scroll.CanvasSize = UDim2.new(0, 0, 0, CARD_H + 8)
	local list = Kit.list(scroll, Enum.FillDirection.Horizontal, 12)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	Kit.padding(scroll, 4)

	-- two banners share the width; more than two scroll sideways
	local n = math.max(1, #Config.Banners)
	local width = math.max(360, math.floor((796 - 8 - (n - 1) * 12) / n))
	for i, banner in Config.Banners do
		buildCard(scroll, banner, i, width)
	end
	Summon.update(Util.data())
end

function Summon.update(data)
	local pity = data and data.pity or {}
	for _, c in cards do
		local p = c.banner.pity
		if p and c.pityBar then
			local count = tonumber(pity[c.banner.id]) or 0
			local left = math.max(0, p.pulls - count)
			c.pityLabel.Text = string.format("%s+ GUARANTEED IN %d PULLS", string.upper(p.rarity), left)
			Util.setBar(c.pityBar, count / math.max(1, p.pulls), count .. " / " .. p.pulls)
		end
	end
end

return Summon
