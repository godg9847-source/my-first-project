--!nonstrict
--[[
	Lobby/Util: small helpers shared by the lobby screens (progress bars, icons,
	button states, safe remote calls, number formatting).
	The basic look (colours, buttons, panels) lives in UI/Kit — use Kit first.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Fighters = require(Shared:WaitForChild("Fighters"))
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.State)

local Util = {}
Util.Config = Config
Util.Fighters = Fighters
Util.Kit = Kit
Util.State = State

local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
Util.GREY = Color3.fromRGB(110, 106, 130)

-- the latest profile view, or nil before the first "Data" message
function Util.data()
	return State.data
end

----------------------------------------------------------------------
-- scaling
----------------------------------------------------------------------

-- Kit.autoScale scales by screen width. This also shrinks the frame on short
-- screens (phones held sideways) so `designH` design pixels always fit.
function Util.autoScale(gui, designW, designH)
	designW = designW or 1280
	designH = designH or 720
	local scale = Kit.autoScale(gui, designW)
	local cam = workspace.CurrentCamera
	local function fit()
		local vp = cam.ViewportSize
		local s = math.min(vp.X / designW, vp.Y / designH)
		scale.Scale = math.clamp(s, 0.5, 1.15)
	end
	fit()
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		task.defer(fit) -- runs after Kit's own width-only update
	end)
	return scale
end

----------------------------------------------------------------------
-- building blocks
----------------------------------------------------------------------

-- plain rounded frame. props: name, size, position, anchor, color, transparency,
-- corner (number or false), stroke (thickness), strokeColor, order, z
function Util.box(parent, props)
	local f = Instance.new("Frame")
	f.Name = props.name or "Box"
	f.Size = props.size or UDim2.fromScale(1, 1)
	f.Position = props.position or UDim2.new()
	f.AnchorPoint = props.anchor or Vector2.zero
	f.BackgroundColor3 = props.color or Kit.C.panel2
	f.BackgroundTransparency = props.transparency or 0
	f.BorderSizePixel = 0
	f.LayoutOrder = props.order or 0
	f.ZIndex = props.z or 1
	if props.corner ~= false then
		Kit.corner(f, props.corner or 12)
	end
	if props.stroke then
		Kit.stroke(f, props.stroke, props.strokeColor)
	end
	f.Parent = parent
	return f
end

-- an invisible frame used to group/position things
function Util.group(parent, props)
	local f = Instance.new("Frame")
	f.Name = props.name or "Group"
	f.BackgroundTransparency = 1
	f.Size = props.size or UDim2.fromScale(1, 1)
	f.Position = props.position or UDim2.new()
	f.AnchorPoint = props.anchor or Vector2.zero
	f.LayoutOrder = props.order or 0
	f.Parent = parent
	return f
end

-- stop a scaled label from getting huge
function Util.maxText(label, size)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = size
	c.Parent = label
	return label
end

-- progress bar. Returns {frame, fill, text}; change it with Util.setBar.
function Util.bar(parent, props)
	local bg = Util.box(parent, {
		name = props.name or "Bar",
		size = props.size,
		position = props.position,
		anchor = props.anchor,
		color = props.bg or Kit.C.stroke,
		corner = props.corner or 8,
		order = props.order,
	})
	local fill = Util.box(bg, {
		name = "Fill",
		size = UDim2.fromScale(0, 1),
		color = props.color or Kit.C.green,
		corner = props.corner or 8,
	})
	Kit.gradient(fill, WHITE, Color3.fromRGB(190, 190, 190))
	local text = Kit.label(bg, {
		text = "",
		size = UDim2.new(1, -8, 1, -4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		name = "Text",
		z = 2,
	})
	return { frame = bg, fill = fill, text = text }
end

-- frac 0..1; text optional; animate = smooth slide
function Util.setBar(bar, frac, text, animate)
	frac = math.clamp(frac or 0, 0, 1)
	local size = UDim2.fromScale(frac, 1)
	bar.fill.Visible = frac > 0.001
	if animate then
		Kit.tween(bar.fill, 0.35, { Size = size })
	else
		bar.fill.Size = size
	end
	if text then
		bar.text.Text = text
	end
end

-- recolour a Kit.button (or any frame that has Kit's gradient)
function Util.paint(gui, color)
	gui.BackgroundColor3 = color
	local g = gui:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(color:Lerp(WHITE, 0.2), color:Lerp(BLACK, 0.15))
	end
end

-- one call to set a Kit.button's text, colour and enabled state.
-- Pass nil for text/color to keep the current ones.
function Util.styleButton(btn, text, color, enabled)
	if text then
		Kit.setButtonText(btn, text)
	end
	if color then
		btn:SetAttribute("BaseColor", color)
	end
	enabled = enabled ~= false
	btn:SetAttribute("Disabled", not enabled)
	local base = btn:GetAttribute("BaseColor") or btn.BackgroundColor3
	Util.paint(btn, enabled and base or Util.GREY)
end

-- connect a click that is ignored while the button is disabled
function Util.onClick(btn, fn)
	return btn.Activated:Connect(function()
		if btn:GetAttribute("Disabled") then
			return
		end
		fn()
	end)
end

-- little red notification dot in a button's top-right corner
function Util.badge(parent, text)
	local b = Util.box(parent, {
		name = "Badge",
		size = UDim2.fromOffset(28, 28),
		position = UDim2.new(1, 8, 0, -8),
		anchor = Vector2.new(1, 0),
		color = Kit.C.red,
		corner = 999,
		stroke = 2,
		z = 5,
	})
	Kit.label(b, {
		text = text or "!",
		size = UDim2.new(1, -6, 1, -6),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		name = "Text",
		z = 6,
	})
	b.Visible = false
	return b
end

function Util.setBadge(badge, text)
	local l = badge:FindFirstChild("Text")
	if l then
		l.Text = text
	end
end

-- quick "bump" animation (e.g. when coins go up)
function Util.pulse(gui)
	local s = gui:FindFirstChild("Pulse")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "Pulse"
		s.Parent = gui
	end
	s.Scale = 1.15
	Kit.tween(s, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
end

-- fade a gui and everything inside it to invisible
function Util.fadeOut(gui, t)
	local info = TweenInfo.new(t or 0.3)
	local function fade(o)
		if o:IsA("GuiObject") and o.BackgroundTransparency < 1 then
			TweenService:Create(o, info, { BackgroundTransparency = 1 }):Play()
		end
		if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
			TweenService:Create(o, info, { TextTransparency = 1 }):Play()
		end
		if o:IsA("UIStroke") then
			TweenService:Create(o, info, { Transparency = 1 }):Play()
		end
	end
	fade(gui)
	for _, d in gui:GetDescendants() do
		fade(d)
	end
end

----------------------------------------------------------------------
-- icons drawn with frames (no image assets)
----------------------------------------------------------------------

function Util.coinIcon(parent, size, position, anchor)
	local c = Util.box(parent, {
		name = "CoinIcon",
		size = UDim2.fromOffset(size, size),
		position = position,
		anchor = anchor,
		color = Kit.C.coin,
		corner = 999,
		stroke = 2,
	})
	Util.box(c, {
		size = UDim2.fromScale(0.5, 0.5),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Kit.C.gold:Lerp(BLACK, 0.2),
		corner = 999,
	})
	return c
end

function Util.gemIcon(parent, size, position, anchor)
	local holder = Util.group(parent, {
		name = "GemIcon",
		size = UDim2.fromOffset(size, size),
		position = position,
		anchor = anchor,
	})
	local g = Util.box(holder, {
		size = UDim2.fromScale(0.68, 0.68),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = WHITE,
		corner = 4,
		stroke = 2,
	})
	g.Rotation = 45
	Kit.gradient(g, Kit.C.gem:Lerp(WHITE, 0.5), Kit.C.gem)
	return holder
end

-- padlock: a ring (shackle) and a box (body)
function Util.lockIcon(parent, size, position, anchor)
	local holder = Util.group(parent, {
		name = "Lock",
		size = UDim2.fromOffset(size, size),
		position = position,
		anchor = anchor,
	})
	local shackle = Util.box(holder, {
		size = UDim2.fromScale(0.56, 0.6),
		position = UDim2.fromScale(0.5, 0.04),
		anchor = Vector2.new(0.5, 0),
		transparency = 1,
		corner = 999,
	})
	Kit.stroke(shackle, math.max(2, math.floor(size * 0.1)), Color3.fromRGB(200, 200, 215))
	local body = Util.box(holder, {
		size = UDim2.fromScale(0.82, 0.52),
		position = UDim2.fromScale(0.5, 1),
		anchor = Vector2.new(0.5, 1),
		color = Color3.fromRGB(200, 200, 215),
		corner = 5,
		stroke = 2,
		z = 2,
	})
	Util.box(body, {
		size = UDim2.fromScale(0.14, 0.4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		color = Kit.C.stroke,
		corner = 3,
		z = 3,
	})
	return holder
end

----------------------------------------------------------------------
-- animated numbers
----------------------------------------------------------------------

local counters = {} -- [label] = {nv = NumberValue, tween = Tween?}

-- show `target` in `label` as format(n). Counts up smoothly when the number
-- grows, jumps straight down when it shrinks. Returns true if it grew.
function Util.countTo(label, target, format)
	target = target or 0
	local st = counters[label]
	if not st then
		local nv = Instance.new("NumberValue")
		nv.Value = target
		st = { nv = nv }
		nv.Changed:Connect(function(v)
			label.Text = format(v)
		end)
		counters[label] = st
		label.Text = format(target)
		return false
	end
	if st.tween then
		st.tween:Cancel()
		st.tween = nil
	end
	local grew = target > st.nv.Value
	if grew then
		st.tween = TweenService:Create(st.nv, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = target })
		st.tween:Play()
	else
		st.nv.Value = target
	end
	return grew
end

----------------------------------------------------------------------
-- remotes
----------------------------------------------------------------------

-- UIAction (claim rewards, settings ...)
function Util.fire(msg)
	Remotes.event("UIAction"):FireServer(msg)
end

-- MatchAction (leaveQueue ...)
function Util.matchAction(msg)
	Remotes.event("MatchAction"):FireServer(msg)
end

-- call a RemoteFunction safely. Returns the server's table, or nil on failure.
function Util.invoke(name, ...)
	local args = table.pack(...)
	local ok, res = pcall(function()
		return Remotes.func(name):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		warn("[LobbyUI] " .. name .. " failed:", res)
		return nil
	end
	if type(res) ~= "table" then
		return nil
	end
	return res
end

----------------------------------------------------------------------
-- game data helpers
----------------------------------------------------------------------

-- 75 -> "1:15", 3700 -> "1:01:40"
function Util.mmss(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local h = seconds // 3600
	if h > 0 then
		return string.format("%d:%02d:%02d", h, (seconds % 3600) // 60, seconds % 60)
	end
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Util.banner(id)
	for _, b in Config.Banners do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- {coins = 100, gems = 5} -> "100 COINS + 5 GEMS"
function Util.rewardText(reward)
	if type(reward) ~= "table" then
		return ""
	end
	local parts = {}
	if reward.coins then
		table.insert(parts, Kit.short(reward.coins) .. " COINS")
	end
	if reward.gems then
		table.insert(parts, Kit.short(reward.gems) .. " GEMS")
	end
	if reward.summon then
		local b = Util.banner(reward.summon)
		table.insert(parts, "FREE " .. string.upper(b and b.name or "SUMMON"))
	end
	return table.concat(parts, " + ")
end

-- has online-reward tier i been claimed today? (server uses "t1", "t2", ... keys)
function Util.tierClaimed(online, i)
	local c = online and online.claimed
	if type(c) ~= "table" then
		return false
	end
	return c["t" .. i] == true or c[i] == true or c[tostring(i)] == true
end

function Util.fighter(id)
	if type(id) ~= "string" then
		return nil
	end
	return Fighters.get(id)
end

local function rarityOrder(r)
	local info = Config.Rarities[r]
	return info and info.order or 0
end
Util.rarityOrder = rarityOrder

-- every fighter, sorted by rarity (Rare first) then by roster order
local sortedCache = nil
function Util.sortedFighters()
	if sortedCache then
		return sortedCache
	end
	local list = table.clone(Fighters.List or {})
	table.sort(list, function(a, b)
		local ra, rb = rarityOrder(a.rarity), rarityOrder(b.rarity)
		if ra ~= rb then
			return ra < rb
		end
		local oa, ob = a.order or 0, b.order or 0
		if oa ~= ob then
			return oa < ob
		end
		return tostring(a.id) < tostring(b.id)
	end)
	sortedCache = list
	return list
end

return Util
