--!nonstrict
--[[
	Lobby/Hud: the always-visible lobby buttons and counters.
	  * top-centre: coins, gems (+ button opens the shop), level badge + XP bar,
	    and a "x2 COINS mm:ss" pill while a boost is active
	  * top-left:   GIFTS button (red dot when something can be claimed)
	  * left side:  SUMMON / INDEX / SHOP / SETTINGS buttons
	  * a "LEVEL UP!" banner when data.level goes up
]]

local GuiService = game:GetService("GuiService")

local Util = require(script.Parent.Util)
local Kit = Util.Kit
local Config = Util.Config
local State = Util.State

local Hud = {}

local ctx = nil
local ui = {} -- references to the labels/bars we update
local lastLevel = nil -- level from the previous Data message
local pendingLevel = nil -- level-up that happened during a match (shown back in the lobby)
local x2Until = 0
local xpVersion = 0

-- y position just under Roblox's own top bar buttons
local function belowTopbar()
	local ok, inset = pcall(function()
		return (GuiService:GetGuiInset())
	end)
	local y = ok and inset and inset.Y or 36
	return math.max(y, 36) + 8
end

----------------------------------------------------------------------
-- top-centre bar
----------------------------------------------------------------------

local function pill(parent, width, order)
	local p = Util.box(parent, {
		name = "Pill",
		size = UDim2.fromOffset(width, 48),
		color = Color3.new(1, 1, 1),
		corner = 999,
		stroke = 3,
		order = order,
	})
	Kit.gradient(p, Kit.C.panel2, Kit.C.panel)
	return p
end

local function pillNumber(p, leftPad, rightPad)
	return Kit.label(p, {
		text = "...",
		size = UDim2.new(1, -(leftPad + rightPad), 1, -14),
		position = UDim2.new(0, leftPad, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		name = "Amount",
	})
end

local function buildTopBar(gui)
	local bar = Util.group(gui, {
		name = "TopBar",
		size = UDim2.fromOffset(620, 100),
		position = UDim2.new(0.5, 0, 0, 6),
		anchor = Vector2.new(0.5, 0),
	})
	Util.autoScale(bar, 1280, 620)

	local row = Util.group(bar, { name = "Row", size = UDim2.new(1, 0, 0, 56) })
	local list = Kit.list(row, Enum.FillDirection.Horizontal, 10)
	list.VerticalAlignment = Enum.VerticalAlignment.Center

	-- coins
	ui.coinPill = pill(row, 190, 1)
	Util.coinIcon(ui.coinPill, 34, UDim2.new(0, 8, 0.5, 0), Vector2.new(0, 0.5))
	ui.coins = pillNumber(ui.coinPill, 48, 14)

	-- gems (+ opens the shop)
	ui.gemPill = pill(row, 180, 2)
	Util.gemIcon(ui.gemPill, 36, UDim2.new(0, 6, 0.5, 0), Vector2.new(0, 0.5))
	ui.gems = pillNumber(ui.gemPill, 46, 48)
	local plus = Kit.button(ui.gemPill, {
		text = "+",
		color = Kit.C.green,
		size = UDim2.fromOffset(36, 36),
		position = UDim2.new(1, -6, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
		corner = 999,
	})
	Util.onClick(plus, function()
		ctx.open("Shop")
	end)

	-- level badge + xp bar
	ui.levelPill = pill(row, 230, 3)
	local badge = Util.box(ui.levelPill, {
		name = "LevelBadge",
		size = UDim2.fromOffset(56, 56),
		position = UDim2.new(0, -6, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Color3.new(1, 1, 1),
		corner = 999,
		stroke = 3,
		z = 2,
	})
	Kit.gradient(badge, Kit.C.purple:Lerp(Color3.new(1, 1, 1), 0.3), Kit.C.purple)
	Kit.label(badge, { text = "LV", size = UDim2.new(1, 0, 0.32, 0), position = UDim2.fromScale(0, 0.08), font = Kit.FontBody, z = 3 })
	ui.level = Kit.label(badge, { text = "1", size = UDim2.new(0.8, 0, 0.5, 0), position = UDim2.fromScale(0.1, 0.38), z = 3 })
	ui.xpBar = Util.bar(ui.levelPill, {
		size = UDim2.new(1, -66, 0, 24),
		position = UDim2.new(0, 56, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Kit.C.purple,
	})
	Util.setBar(ui.xpBar, 0, "0 / 0 XP")

	-- x2 coins boost pill (hidden until a boost is active)
	ui.x2 = Util.box(bar, {
		name = "X2Pill",
		size = UDim2.fromOffset(190, 32),
		position = UDim2.new(0.5, 0, 0, 62),
		anchor = Vector2.new(0.5, 0),
		color = Color3.new(1, 1, 1),
		corner = 999,
		stroke = 3,
	})
	Kit.gradient(ui.x2, Kit.C.gold:Lerp(Color3.new(1, 1, 1), 0.3), Kit.C.gold)
	ui.x2Text = Kit.label(ui.x2, {
		text = "x2 COINS",
		size = UDim2.new(1, -16, 1, -8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	ui.x2.Visible = false
end

----------------------------------------------------------------------
-- buttons
----------------------------------------------------------------------

local function buildGiftButton(gui)
	local holder = Util.group(gui, {
		name = "GiftButton",
		size = UDim2.fromOffset(150, 62),
		position = UDim2.new(0, 12, 0, belowTopbar()),
	})
	Util.autoScale(holder, 1280, 620)
	local btn = Kit.button(holder, { text = "GIFTS", color = Kit.C.pink, size = UDim2.fromScale(1, 1) })
	ui.giftBadge = Util.badge(btn, "!")
	Util.onClick(btn, function()
		ctx.toggle("Gifts")
	end)
end

local SIDE_BUTTONS = {
	{ name = "Summon", text = "SUMMON", color = Kit.C.gold },
	{ name = "Index", text = "INDEX", color = Kit.C.blue },
	{ name = "Shop", text = "SHOP", color = Kit.C.green },
	{ name = "Settings", text = "SETTINGS", color = Color3.fromRGB(120, 112, 160) },
}

local function buildSideButtons(gui)
	local h = #SIDE_BUTTONS * 62 + (#SIDE_BUTTONS - 1) * 10
	local holder = Util.group(gui, {
		name = "SideButtons",
		size = UDim2.fromOffset(150, h),
		position = UDim2.new(0, 12, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
	})
	Util.autoScale(holder, 1280, 620)
	Kit.list(holder, Enum.FillDirection.Vertical, 10)
	for i, def in SIDE_BUTTONS do
		local b = Kit.button(holder, { text = def.text, color = def.color, size = UDim2.fromOffset(150, 62), order = i })
		Util.onClick(b, function()
			ctx.toggle(def.name)
		end)
	end
end

----------------------------------------------------------------------
-- level-up banner
----------------------------------------------------------------------

local function buildBannerLayer(gui)
	ui.bannerLayer = Util.group(gui, {
		name = "LevelUpLayer",
		size = UDim2.fromOffset(480, 120),
		position = UDim2.fromScale(0.5, 0.3),
		anchor = Vector2.new(0.5, 0.5),
	})
	Util.autoScale(ui.bannerLayer, 1280, 620)
end

local function showLevelBanner(level)
	local b = Util.box(ui.bannerLayer, {
		name = "LevelUp",
		size = UDim2.fromOffset(440, 100),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Color3.new(1, 1, 1),
		corner = 18,
		stroke = 4,
	})
	Kit.gradient(b, Kit.C.gold:Lerp(Color3.new(1, 1, 1), 0.35), Kit.C.gold)
	Kit.label(b, {
		text = "LEVEL UP!",
		size = UDim2.new(1, -24, 0, 52),
		position = UDim2.new(0.5, 0, 0, 6),
		anchor = Vector2.new(0.5, 0),
		strokeThickness = 3,
	})
	Kit.label(b, {
		text = "You reached level " .. tostring(level) .. "!",
		size = UDim2.new(1, -24, 0, 28),
		position = UDim2.new(0.5, 0, 1, -8),
		anchor = Vector2.new(0.5, 1),
		font = Kit.FontBody,
	})
	Kit.popIn(b)
	task.delay(2.8, function()
		if b.Parent then
			Kit.tween(b, 0.4, { Position = UDim2.new(0.5, 0, 0.5, -60) })
			Util.fadeOut(b, 0.4)
			task.wait(0.45)
			b:Destroy()
		end
	end)
end

local function onLevelUp(level)
	if State.inMatch then
		pendingLevel = level -- the lobby HUD is hidden; show it when we're back
	else
		showLevelBanner(level)
	end
end

----------------------------------------------------------------------
-- updates
----------------------------------------------------------------------

-- true when a daily reward or an online-time reward can be claimed
function Hud.hasGift(data)
	if not data then
		return false
	end
	if data.daily and data.daily.canClaim then
		return true
	end
	local online = data.online
	if online then
		for i, tier in Config.OnlineRewards do
			if (online.seconds or 0) >= tier.minutes * 60 and not Util.tierClaimed(online, i) then
				return true
			end
		end
	end
	return false
end

local function updateXp(data)
	local frac = (data.xp or 0) / math.max(1, data.xpNeeded or 1)
	local text = Kit.short(data.xp or 0) .. " / " .. Kit.short(data.xpNeeded or 0) .. " XP"
	xpVersion += 1
	local myVersion = xpVersion
	if lastLevel and data.level and data.level > lastLevel then
		-- fill the bar up, then start again from 0 for the new level
		Util.setBar(ui.xpBar, 1, text, true)
		task.delay(0.4, function()
			if myVersion == xpVersion then
				Util.setBar(ui.xpBar, 0)
				Util.setBar(ui.xpBar, frac, nil, true)
			end
		end)
	else
		Util.setBar(ui.xpBar, frac, text, lastLevel ~= nil)
	end
end

local function updateX2()
	local left = (x2Until or 0) - os.time()
	ui.x2.Visible = left > 0
	if left > 0 then
		ui.x2Text.Text = "x2 COINS " .. Util.mmss(left)
	end
end

function Hud.update(data)
	if not data then
		return
	end
	if Util.countTo(ui.coins, data.coins or 0, Kit.short) then
		Util.pulse(ui.coinPill)
	end
	if Util.countTo(ui.gems, data.gems or 0, Kit.short) then
		Util.pulse(ui.gemPill)
	end
	ui.level.Text = tostring(data.level or 1)
	updateXp(data)
	if lastLevel and data.level and data.level > lastLevel then
		onLevelUp(data.level)
	end
	lastLevel = data.level
	x2Until = tonumber(data.x2Until) or 0
	updateX2()
	ui.giftBadge.Visible = Hud.hasGift(data)
end

-- called every 0.25 s
function Hud.tick()
	updateX2()
end

-- called when we come back to the lobby after a match
function Hud.onLobby()
	if pendingLevel then
		local level = pendingLevel
		pendingLevel = nil
		task.delay(0.5, showLevelBanner, level)
	end
end

function Hud.build(gui, context)
	ctx = context
	buildTopBar(gui)
	buildGiftButton(gui)
	buildSideButtons(gui)
	buildBannerLayer(gui)
end

return Hud
