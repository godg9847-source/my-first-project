--!nonstrict
--[[
	Lobby/Toasts: short messages stacked at the top-centre of the screen.
	They slide in, stay ~3 seconds and fade out. Shown in the lobby AND in
	matches (e.g. "Not enough gems!"), so they live in their own ScreenGui.

	Toasts.show("Hello", "#ffd34d")   -- colour may be a hex string or a Color3
]]

local Util = require(script.Parent.Util)
local Kit = Util.Kit

local Toasts = {}

local SHOW_TIME = 3 -- seconds on screen
local MAX_TOASTS = 4 -- older ones are removed when more arrive

local holder = nil
local active = {} -- toast frames, oldest first
local order = 0

function Toasts.build()
	local gui = Kit.screen("AvA_Toasts", 60)
	holder = Util.group(gui, {
		name = "Toasts",
		size = UDim2.fromOffset(560, 320),
		anchor = Vector2.new(0.5, 0),
	})
	local list = Kit.list(holder, Enum.FillDirection.Vertical, 6)
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	-- sit just below the coin bar; the gap grows/shrinks with the UI scale
	local scale = Util.autoScale(holder, 1280, 620)
	local function place()
		holder.Position = UDim2.new(0.5, 0, 0, math.floor(8 + 104 * scale.Scale))
	end
	place()
	scale:GetPropertyChangedSignal("Scale"):Connect(place)
end

local function remove(slot)
	local i = table.find(active, slot)
	if i then
		table.remove(active, i)
	end
	slot:Destroy()
end

function Toasts.show(text, color)
	if not holder or type(text) ~= "string" or text == "" then
		return
	end
	local c = Kit.hex(color or "#ffffff")
	order += 1

	-- the slot is placed by the list layout; the card inside it slides in
	local slot = Util.group(holder, { name = "Toast", size = UDim2.fromOffset(540, 50), order = order })
	local card = Util.box(slot, {
		size = UDim2.fromScale(1, 1),
		position = UDim2.new(0.5, 0, 0, -24),
		anchor = Vector2.new(0.5, 0),
		color = Kit.C.bg,
		transparency = 0.08,
		corner = 14,
		stroke = 3,
	})
	Util.box(card, {
		name = "Accent",
		size = UDim2.new(0, 8, 1, -14),
		position = UDim2.new(0, 8, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		color = c,
		corner = 4,
	})
	local label = Kit.label(card, {
		text = text,
		color = c,
		size = UDim2.new(1, -40, 1, -12),
		position = UDim2.new(0, 26, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
	})
	Util.maxText(label, 24)
	Kit.popIn(card)
	Kit.tween(card, 0.25, { Position = UDim2.new(0.5, 0, 0, 0) }, Enum.EasingStyle.Back)

	table.insert(active, slot)
	while #active > MAX_TOASTS do
		remove(active[1])
	end

	task.delay(SHOW_TIME, function()
		if slot.Parent then
			Util.fadeOut(slot, 0.35)
			task.wait(0.4)
			remove(slot)
		end
	end)
end

return Toasts
