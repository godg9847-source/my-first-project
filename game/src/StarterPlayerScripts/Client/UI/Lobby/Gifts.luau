--!nonstrict
--[[
	Lobby/Gifts: the GIFTS panel.
	  left:  DAILY LOGIN streak card   -> UIAction {action = "claimDaily"}
	         CODES box                 -> RemoteFunction RedeemCode(code)
	  right: PLAY TIME REWARDS (Config.OnlineRewards)
	                                   -> UIAction {action = "claimOnline", tier = i}
	Played time comes from data.online.seconds; the server adds 30 s at a time,
	so we count up locally in between.
	Opened with arg "codes" (Notify open = "Codes") it highlights the code box.
]]

local Util = require(script.Parent.Util)
local Kit = Util.Kit
local Config = Util.Config

local Gifts = {
	title = "GIFTS",
	color = Kit.C.pink,
	size = Vector2.new(780, 480),
}

local ctx = nil
local visible = false
local daily = {} -- daily card widgets
local codes = {} -- codes card widgets
local online = {} -- online card widgets
local tierRows = {}

-- online time tracking
local serverSeconds = nil -- last data.online.seconds we got
local secondsChangedAt = 0 -- os.clock() when it last changed
local pendingTier = {} -- [tier] = true while we wait for the server
local pendingDaily = false

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function card(parent, title, props)
	local c = Util.box(parent, {
		name = title,
		size = props.size,
		position = props.position,
		color = Kit.C.panel2,
		corner = 14,
		stroke = 3,
	})
	Kit.label(c, {
		text = title,
		size = UDim2.new(1, -20, 0, 28),
		position = UDim2.fromOffset(10, 6),
		alignX = Enum.TextXAlignment.Left,
		color = props.titleColor or Kit.C.gold,
		name = "Title",
	})
	return c
end

-- played seconds right now (server value + local count-up, max 29 s ahead)
local function playedSeconds()
	if not serverSeconds then
		return 0
	end
	return serverSeconds + math.min(29, os.clock() - secondsChangedAt)
end

local function dailyRewardText(r)
	if r.coins then
		return Kit.short(r.coins), Kit.C.coin
	elseif r.gems then
		return Kit.short(r.gems), Kit.C.gem
	elseif r.summon then
		return r.summon == "premium" and "PREMIUM" or "SUMMON", Kit.C.pink
	end
	return "?", Kit.C.text
end

----------------------------------------------------------------------
-- daily login card
----------------------------------------------------------------------

local function buildDaily(parent)
	local c = card(parent, "DAILY LOGIN", { size = UDim2.fromOffset(340, 196), position = UDim2.fromOffset(0, 0) })
	daily.streak = Kit.label(c, {
		text = "",
		size = UDim2.new(1, -20, 0, 20),
		position = UDim2.fromOffset(10, 34),
		alignX = Enum.TextXAlignment.Left,
		color = Kit.C.sub,
		font = Kit.FontBody,
	})
	local strip = Util.group(c, { size = UDim2.new(1, -16, 0, 60), position = UDim2.fromOffset(8, 60) })
	Kit.list(strip, Enum.FillDirection.Horizontal, 4)
	daily.days = {}
	local n = #Config.DailyRewards
	local w = math.floor((324 - (n - 1) * 4) / math.max(1, n))
	for i, reward in Config.DailyRewards do
		local d = Util.box(strip, { size = UDim2.fromOffset(w, 60), color = Kit.C.panel, corner = 8, order = i })
		local stroke = Kit.stroke(d, 2)
		Kit.label(d, {
			text = "DAY " .. i,
			size = UDim2.new(1, -4, 0, 18),
			position = UDim2.new(0.5, 0, 0, 4),
			anchor = Vector2.new(0.5, 0),
			color = Kit.C.sub,
			font = Kit.FontBody,
		})
		local text, color = dailyRewardText(reward)
		Kit.label(d, {
			text = text,
			color = color,
			size = UDim2.new(1, -6, 0, 30),
			position = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
		})
		daily.days[i] = { frame = d, stroke = stroke }
	end
	daily.button = Kit.button(c, {
		text = "LOADING",
		color = Kit.C.green,
		size = UDim2.new(1, -40, 0, 54),
		position = UDim2.new(0.5, 0, 1, -10),
		anchor = Vector2.new(0.5, 1),
	})
	Util.styleButton(daily.button, "LOADING", Kit.C.green, false)
	Util.onClick(daily.button, function()
		pendingDaily = true
		Util.styleButton(daily.button, "...", nil, false)
		Util.fire({ action = "claimDaily" })
		task.delay(4, function()
			if pendingDaily then
				pendingDaily = false
				Gifts.update(Util.data())
			end
		end)
	end)
end

local function updateDaily(data)
	local d = data and data.daily
	if not d then
		daily.streak.Text = "Loading..."
		Util.styleButton(daily.button, "LOADING", nil, false)
		return
	end
	local n = #Config.DailyRewards
	local streak = tonumber(d.streak) or 0
	-- which day of the 7-day cycle is next (if you can claim) or was claimed today
	-- (the client can't tell if you missed a day; the server resets the streak then)
	local current
	if d.canClaim then
		current = (streak % n) + 1
	else
		current = ((math.max(1, streak) - 1) % n) + 1
	end
	daily.streak.Text = "STREAK: " .. streak .. (streak == 1 and " DAY" or " DAYS")
	for i, box in daily.days do
		local done = i < current or (i == current and not d.canClaim)
		box.frame.BackgroundColor3 = done and Kit.C.green:Lerp(Kit.C.panel, 0.45) or Kit.C.panel
		box.stroke.Color = (i == current) and Kit.C.gold or Kit.C.stroke
		box.stroke.Thickness = (i == current) and 3 or 2
	end
	if d.canClaim and pendingDaily then
		Util.styleButton(daily.button, "...", nil, false) -- waiting for the server
	elseif d.canClaim then
		Util.styleButton(daily.button, "CLAIM DAY " .. current, nil, true)
	else
		pendingDaily = false
		Util.styleButton(daily.button, "COME BACK TOMORROW", nil, false)
	end
end

----------------------------------------------------------------------
-- codes card
----------------------------------------------------------------------

local function redeem()
	if codes.busy then
		return
	end
	local code = (codes.box.Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if code == "" then
		codes.result.TextColor3 = Kit.C.red
		codes.result.Text = "Type a code first."
		return
	end
	codes.busy = true
	Util.styleButton(codes.button, "...", nil, false)
	codes.result.TextColor3 = Kit.C.sub
	codes.result.Text = "Checking..."
	task.spawn(function()
		local res = Util.invoke("RedeemCode", code)
		codes.busy = false
		Util.styleButton(codes.button, "REDEEM", nil, true)
		if not res then
			codes.result.TextColor3 = Kit.C.red
			codes.result.Text = "Something went wrong, try again."
			return
		end
		codes.result.TextColor3 = res.ok and Kit.C.green or Kit.C.red
		codes.result.Text = tostring(res.message or (res.ok and "Redeemed!" or "Invalid code."))
		if res.ok then
			codes.box.Text = ""
		end
	end)
end

local function buildCodes(parent)
	local c = card(parent, "CODES", { size = UDim2.fromOffset(340, 196), position = UDim2.fromOffset(0, 208) })
	codes.card = c
	codes.stroke = c:FindFirstChildOfClass("UIStroke")
	Kit.label(c, {
		text = "Enter a code for free rewards!",
		size = UDim2.new(1, -20, 0, 20),
		position = UDim2.fromOffset(10, 34),
		alignX = Enum.TextXAlignment.Left,
		color = Kit.C.sub,
		font = Kit.FontBody,
	})
	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.Size = UDim2.new(1, -144, 0, 52)
	box.Position = UDim2.fromOffset(10, 62)
	box.BackgroundColor3 = Kit.C.bg
	box.TextColor3 = Kit.C.text
	box.PlaceholderText = "Enter code here"
	box.PlaceholderColor3 = Kit.C.sub
	box.Font = Kit.FontBody
	box.Text = ""
	box.TextScaled = true
	box.ClearTextOnFocus = false
	Kit.corner(box, 10)
	Kit.stroke(box, 3)
	Kit.padding(box, 10)
	Util.maxText(box, 24)
	box.Parent = c
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			redeem()
		end
	end)
	codes.box = box
	codes.button = Kit.button(c, {
		text = "REDEEM",
		color = Kit.C.green,
		size = UDim2.fromOffset(120, 52),
		position = UDim2.new(1, -10, 0, 62),
		anchor = Vector2.new(1, 0),
	})
	Util.styleButton(codes.button, "REDEEM", Kit.C.green, true)
	Util.onClick(codes.button, redeem)
	codes.result = Kit.label(c, {
		text = "",
		size = UDim2.new(1, -20, 0, 64),
		position = UDim2.fromOffset(10, 122),
		color = Kit.C.sub,
		font = Kit.FontBody,
	})
	Util.maxText(codes.result, 20)
end

-- flash the codes card so the player sees where to type
local function highlightCodes()
	if not codes.stroke then
		return
	end
	codes.stroke.Color = Kit.C.gold
	codes.stroke.Thickness = 5
	task.delay(1.2, function()
		Kit.tween(codes.stroke, 0.4, { Color = Kit.C.stroke, Thickness = 3 })
	end)
end

----------------------------------------------------------------------
-- online-time rewards
----------------------------------------------------------------------

local function tierRewardText(tier)
	local text = Util.rewardText(tier)
	if tier.boostChance then
		text ..= string.format(" (%d%% x2 boost)", math.floor(tier.boostChance * 100 + 0.5))
	end
	return text
end

local function buildTierRow(list, i, tier)
	local row = Util.box(list, { name = "Tier" .. i, size = UDim2.new(1, -12, 0, 62), color = Kit.C.panel, corner = 10, order = i })
	local timeBox = Util.box(row, {
		size = UDim2.fromOffset(64, 48),
		position = UDim2.new(0, 7, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = Kit.C.purple,
		corner = 10,
		stroke = 2,
	})
	Kit.label(timeBox, {
		text = tier.minutes .. "\nMIN",
		size = UDim2.new(1, -6, 1, -6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	local reward = Kit.label(row, {
		text = tierRewardText(tier),
		color = tier.gems and Kit.C.gem or Kit.C.coin,
		size = UDim2.new(1, -196, 0, 24),
		position = UDim2.fromOffset(80, 6),
		alignX = Enum.TextXAlignment.Left,
		font = Kit.FontBody,
	})
	Util.maxText(reward, 18)
	local bar = Util.bar(row, {
		size = UDim2.new(1, -196, 0, 20),
		position = UDim2.new(0, 80, 1, -8),
		anchor = Vector2.new(0, 1),
		color = Kit.C.gold,
	})
	local btn = Kit.button(row, {
		text = "",
		color = Kit.C.green,
		size = UDim2.fromOffset(100, 46),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
	})
	Util.styleButton(btn, "--:--", Kit.C.green, false)
	Util.onClick(btn, function()
		pendingTier[i] = true
		Util.styleButton(btn, "...", nil, false)
		Util.fire({ action = "claimOnline", tier = i })
		task.delay(4, function()
			pendingTier[i] = nil
		end)
	end)
	tierRows[i] = { bar = bar, button = btn, need = tier.minutes * 60 }
end

local function buildOnline(parent)
	local c = card(parent, "PLAY TIME REWARDS", {
		size = UDim2.new(1, -352, 1, 0),
		position = UDim2.fromOffset(352, 0),
	})
	online.played = Kit.label(c, {
		text = "",
		size = UDim2.new(1, -20, 0, 20),
		position = UDim2.fromOffset(10, 34),
		alignX = Enum.TextXAlignment.Left,
		color = Kit.C.sub,
		font = Kit.FontBody,
	})
	local list = Kit.scroll(c, { size = UDim2.new(1, -8, 1, -66), position = UDim2.fromOffset(4, 60) })
	local layout = Kit.list(list, Enum.FillDirection.Vertical, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i, tier in Config.OnlineRewards do
		buildTierRow(list, i, tier)
	end
end

-- refresh timers/buttons (every tick while open, and on new data)
local function renderOnline()
	local data = Util.data()
	local onlineData = data and data.online
	local played = playedSeconds()
	online.played.Text = "Played today: " .. Util.mmss(played)
	for i, row in tierRows do
		local claimed = Util.tierClaimed(onlineData, i)
		local ready = (serverSeconds or 0) >= row.need
		Util.setBar(row.bar, played / row.need)
		if claimed then
			pendingTier[i] = nil
			Util.styleButton(row.button, "CLAIMED", nil, false)
		elseif pendingTier[i] then
			Util.styleButton(row.button, "...", nil, false)
		elseif ready then
			Util.styleButton(row.button, "CLAIM", nil, true)
		elseif not data then
			Util.styleButton(row.button, "--:--", nil, false)
		else
			local left = row.need - played
			Util.styleButton(row.button, left > 0 and Util.mmss(left) or "SOON", nil, false)
		end
	end
end

----------------------------------------------------------------------
-- panel interface (used by LobbyUI)
----------------------------------------------------------------------

function Gifts.build(content, context)
	ctx = context
	buildDaily(content)
	buildCodes(content)
	buildOnline(content)
	Gifts.update(Util.data())
end

function Gifts.update(data)
	if not ctx then
		return
	end
	local s = data and data.online and tonumber(data.online.seconds)
	if s and s ~= serverSeconds then
		serverSeconds = s
		secondsChangedAt = os.clock()
	end
	updateDaily(data)
	renderOnline()
end

function Gifts.onOpen(arg)
	visible = true
	renderOnline()
	if arg == "codes" then
		highlightCodes()
	end
end

function Gifts.onClose()
	visible = false
end

function Gifts.tick()
	if visible then
		renderOnline()
	end
end

return Gifts
