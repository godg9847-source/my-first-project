--!nonstrict
--[[
	Lobby/Shop: the SHOP panel — game passes (Config.GamePasses) and gem packs
	(Config.Products), each with its Robux price.
	Buying calls RemoteFunction BuyProduct:InvokeServer(key); the server opens
	Roblox's purchase prompt or answers with a message such as "Coming soon!".
]]

local Util = require(script.Parent.Util)
local Kit = Util.Kit
local Config = Util.Config

local Shop = {
	title = "SHOP",
	color = Kit.C.green,
	size = Vector2.new(800, 480),
}

local ctx = nil
local items = {} -- {key, kind = "pass"|"product", info, button}
local busy = false

-- dictionary -> list sorted by price (packs with a fighter first)
local function sorted(dict)
	local list = {}
	for key, info in dict do
		table.insert(list, { key = key, info = info })
	end
	table.sort(list, function(a, b)
		local fa, fb = a.info.fighter and 0 or 1, b.info.fighter and 0 or 1
		if fa ~= fb then
			return fa < fb
		end
		if (a.info.price or 0) ~= (b.info.price or 0) then
			return (a.info.price or 0) < (b.info.price or 0)
		end
		return a.key < b.key
	end)
	return list
end

local function isOwned(item, data)
	if not data then
		return false
	end
	if item.kind == "pass" then
		return data.passes ~= nil and data.passes[item.key] == true
	end
	return item.info.oncePerPlayer == true and data.flags ~= nil and data.flags["bought_" .. item.key] == true
end

local function refresh()
	local data = Util.data()
	for _, item in items do
		if isOwned(item, data) then
			Util.styleButton(item.button, "OWNED", nil, false)
		else
			Util.styleButton(item.button, "R$ " .. tostring(item.info.price or "?"), nil, not busy)
		end
	end
end

local function buy(item)
	if busy then
		return
	end
	busy = true
	refresh()
	Util.styleButton(item.button, "...", nil, false)
	task.spawn(function()
		local res = Util.invoke("BuyProduct", item.key)
		busy = false
		refresh()
		if not res then
			ctx.toast("The shop isn't available right now.", Kit.C.red)
		elseif type(res.message) == "string" and res.message ~= "" then
			ctx.toast(res.message, res.ok and Kit.C.green or Kit.C.red)
		end
	end)
end

----------------------------------------------------------------------
-- cards
----------------------------------------------------------------------

local function section(parent, text, order)
	Kit.label(parent, {
		text = text,
		color = Kit.C.gold,
		size = UDim2.new(1, -8, 0, 32),
		alignX = Enum.TextXAlignment.Left,
		order = order,
	})
end

-- a frame with a grid layout whose height fits `count` cells
local function gridFrame(parent, count, cell, cols, order)
	local rows = math.max(1, math.ceil(count / cols))
	local f = Util.group(parent, { size = UDim2.new(1, -8, 0, rows * (cell.Y + 12)), order = order })
	local g = Kit.grid(f, UDim2.fromOffset(cell.X, cell.Y), 12)
	g.HorizontalAlignment = Enum.HorizontalAlignment.Left
	return f
end

local function buyButton(parent, item)
	local b = Kit.button(parent, {
		text = "",
		color = Kit.C.green,
		size = UDim2.new(1, -24, 0, 46),
		position = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
	})
	Util.styleButton(b, "R$ " .. tostring(item.info.price or "?"), Kit.C.green, true)
	Util.onClick(b, function()
		buy(item)
	end)
	item.button = b
	table.insert(items, item)
end

local function passCard(parent, key, info, order)
	local c = Util.box(parent, { name = key, color = Color3.new(1, 1, 1), corner = 14, stroke = 3, order = order })
	Kit.gradient(c, Kit.C.gold:Lerp(Kit.C.panel2, 0.6), Kit.C.panel)
	Kit.label(c, {
		text = string.upper(info.name or key),
		color = Kit.C.gold,
		size = UDim2.new(1, -16, 0, 32),
		position = UDim2.new(0.5, 0, 0, 8),
		anchor = Vector2.new(0.5, 0),
		strokeThickness = 3,
	})
	local desc = Kit.label(c, {
		text = info.desc or "",
		color = Kit.C.sub,
		size = UDim2.new(1, -20, 0, 54),
		position = UDim2.new(0.5, 0, 0, 42),
		anchor = Vector2.new(0.5, 0),
		font = Kit.FontBody,
		stroke = false,
	})
	Util.maxText(desc, 18)
	buyButton(c, { key = key, kind = "pass", info = info })
end

local function productCard(parent, key, info, order)
	local c = Util.box(parent, { name = key, color = Color3.new(1, 1, 1), corner = 14, stroke = 3, order = order })
	Kit.gradient(c, Kit.C.gem:Lerp(Kit.C.panel2, 0.65), Kit.C.panel)
	Util.gemIcon(c, 46, UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
	local title, sub
	if info.fighter then
		local f = Util.fighter(info.fighter)
		title = key == "StarterPack" and "STARTER PACK" or string.upper(key)
		sub = Kit.short(info.gems or 0) .. " GEMS + " .. string.upper(f and f.name or info.fighter)
	else
		title = Kit.short(info.gems or 0) .. " GEMS"
		sub = info.oncePerPlayer and "One time only" or ""
	end
	Kit.label(c, {
		text = title,
		color = info.fighter and Kit.C.gold or Kit.C.gem,
		size = UDim2.new(1, -12, 0, 30),
		position = UDim2.new(0.5, 0, 0, 58),
		anchor = Vector2.new(0.5, 0),
		strokeThickness = 3,
	})
	Kit.label(c, {
		text = sub,
		color = Kit.C.sub,
		size = UDim2.new(1, -12, 0, 34),
		position = UDim2.new(0.5, 0, 0, 90),
		anchor = Vector2.new(0.5, 0),
		font = Kit.FontBody,
	})
	buyButton(c, { key = key, kind = "product", info = info })
end

----------------------------------------------------------------------
-- panel interface (used by LobbyUI)
----------------------------------------------------------------------

function Shop.build(content, context)
	ctx = context
	local scroll = Kit.scroll(content, {})
	Kit.padding(scroll, 6)
	local list = Kit.list(scroll, Enum.FillDirection.Vertical, 8)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local passes = sorted(Config.GamePasses or {})
	section(scroll, "GAME PASSES", 1)
	local passGrid = gridFrame(scroll, #passes, Vector2.new(236, 160), 3, 2)
	for i, p in passes do
		passCard(passGrid, p.key, p.info, i)
	end

	local products = sorted(Config.Products or {})
	section(scroll, "GEMS & PACKS", 3)
	local productGrid = gridFrame(scroll, #products, Vector2.new(176, 180), 4, 4)
	for i, p in products do
		productCard(productGrid, p.key, p.info, i)
	end
	refresh()
end

function Shop.update(_data)
	if ctx then
		refresh()
	end
end

return Shop
