--!nonstrict
--[[
	Lobby/Settings: the SETTINGS panel — music / sound effects toggles
	(-> UIAction {action = "setSetting", key, value}), your match stats and
	the game version.
]]

local Util = require(script.Parent.Util)
local Kit = Util.Kit
local Config = Util.Config

local Settings = {
	title = "SETTINGS",
	color = Color3.fromRGB(120, 112, 160),
	size = Vector2.new(500, 420),
}

local TOGGLES = {
	{ key = "music", text = "MUSIC" },
	{ key = "sfx", text = "SOUND EFFECTS" },
}

local STATS = {
	{ key = "wins", text = "WINS" },
	{ key = "losses", text = "LOSSES" },
	{ key = "matches", text = "MATCHES" },
	{ key = "bestStreak", text = "BEST STREAK" },
}

local toggleButtons = {} -- [key] = button
local statLabels = {} -- [key] = label
local pending = {} -- [key] = {value, time} until the server confirms

-- current value of a setting (our unconfirmed click wins for 2 seconds)
local function settingValue(key)
	local p = pending[key]
	if p and os.clock() - p.time < 2 then
		return p.value
	end
	local data = Util.data()
	local s = data and data.settings
	if s and s[key] ~= nil then
		return s[key] == true
	end
	return true -- default: on
end

local function refresh()
	for key, btn in toggleButtons do
		local on = settingValue(key)
		Util.styleButton(btn, on and "ON" or "OFF", on and Kit.C.green or Util.GREY, true)
	end
	local data = Util.data()
	local stats = data and data.stats or {}
	for key, label in statLabels do
		label.Text = tostring(stats[key] or 0)
	end
end

local function toggleRow(parent, def, order)
	local row = Util.box(parent, { size = UDim2.new(1, 0, 0, 60), color = Kit.C.panel2, corner = 12, order = order })
	Kit.label(row, {
		text = def.text,
		size = UDim2.new(1, -170, 1, -20),
		position = UDim2.new(0, 14, 0.5, 0),
		anchor = Vector2.new(0, 0.5),
		alignX = Enum.TextXAlignment.Left,
	})
	local btn = Kit.button(row, {
		text = "ON",
		color = Kit.C.green,
		size = UDim2.fromOffset(130, 46),
		position = UDim2.new(1, -8, 0.5, 0),
		anchor = Vector2.new(1, 0.5),
	})
	Util.onClick(btn, function()
		local value = not settingValue(def.key)
		pending[def.key] = { value = value, time = os.clock() }
		Util.fire({ action = "setSetting", key = def.key, value = value })
		refresh()
	end)
	toggleButtons[def.key] = btn
end

local function statsBlock(parent, order)
	local f = Util.group(parent, { size = UDim2.new(1, 0, 0, 132), order = order })
	Kit.grid(f, UDim2.new(0.5, -6, 0, 60), 8)
	for i, def in STATS do
		local box = Util.box(f, { color = Kit.C.panel2, corner = 10, order = i })
		Kit.label(box, {
			text = def.text,
			color = Kit.C.sub,
			size = UDim2.new(1, -10, 0, 20),
			position = UDim2.new(0.5, 0, 0, 6),
			anchor = Vector2.new(0.5, 0),
			font = Kit.FontBody,
		})
		statLabels[def.key] = Kit.label(box, {
			text = "0",
			color = Kit.C.gold,
			size = UDim2.new(1, -10, 0, 28),
			position = UDim2.new(0.5, 0, 1, -4),
			anchor = Vector2.new(0.5, 1),
		})
	end
end

----------------------------------------------------------------------
-- panel interface (used by LobbyUI)
----------------------------------------------------------------------

function Settings.build(content, _ctx)
	Kit.list(content, Enum.FillDirection.Vertical, 8)
	for i, def in TOGGLES do
		toggleRow(content, def, i)
	end
	Kit.label(content, {
		text = "YOUR STATS",
		color = Kit.C.gold,
		size = UDim2.new(1, 0, 0, 26),
		alignX = Enum.TextXAlignment.Left,
		order = 10,
	})
	statsBlock(content, 11)
	Kit.label(content, {
		text = (Config.GameName or "") .. "  -  Version " .. tostring(Config.Version or "?"),
		color = Kit.C.sub,
		size = UDim2.new(1, 0, 0, 20),
		font = Kit.FontBody,
		order = 20,
	})
	refresh()
end

function Settings.update(data)
	if not data then
		return
	end
	-- the server has answered: forget clicks it has confirmed
	for key, p in pending do
		if data.settings and data.settings[key] == p.value then
			pending[key] = nil
		end
	end
	refresh()
end

function Settings.onOpen()
	refresh()
end

return Settings
