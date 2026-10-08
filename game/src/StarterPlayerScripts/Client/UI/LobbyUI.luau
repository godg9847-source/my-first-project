--!nonstrict
--[[
	LobbyUI: everything you see in the lobby.
	  HUD     (Lobby/Hud)     coins, gems, level/XP, x2 boost, GIFTS + side buttons
	  Quests  (Lobby/Quests)  daily quest tracker, top-right
	  Queue   (Lobby/Queue)   "WAITING FOR PLAYERS" panel while on a match pad
	  Toasts  (Lobby/Toasts)  messages from the "Notify" remote (also shown in matches)
	  Panels: Summon, Index, Shop, Settings, Gifts (one open at a time)

	The HUD and panels hide while State.inMatch is true.
	Open a panel from anywhere with State.open("Summon") (or Notify {open = "Summon"}).
	Names: "Summon", "Index", "Shop", "Settings", "Gifts", "Codes", "Quests".
]]

local Client = script.Parent.Parent
local State = require(Client.State)
local Kit = require(script.Parent.Kit)

local Lobby = script.Parent:WaitForChild("Lobby")
local Util = require(Lobby.Util)
local Toasts = require(Lobby.Toasts)
local Hud = require(Lobby.Hud)
local Quests = require(Lobby.Quests)
local Queue = require(Lobby.Queue)
local Reveal = require(Lobby.Reveal)

local Remotes = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Remotes"))

-- panel modules: each has title, color, size, build(content, ctx) and
-- optional update(data), onOpen(arg), onClose(), tick()
local PANELS = {
	Summon = require(Lobby.Summon),
	Index = require(Lobby.Index),
	Shop = require(Lobby.Shop),
	Settings = require(Lobby.Settings),
	Gifts = require(Lobby.Gifts),
}

local LobbyUI = {}

local hudGui, panelGui
local shells = {} -- [name] = {name, mod, holder, frame}
local current = nil -- shell of the open panel
local pendingOpen = nil -- {name, arg, time} asked for during a match
local started = false

-- run a module function without letting one error break the whole UI
local function safe(fn, ...)
	if not fn then
		return
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[LobbyUI] " .. tostring(err))
	end
end

----------------------------------------------------------------------
-- opening / closing panels
----------------------------------------------------------------------

function LobbyUI.close()
	local s = current
	if not s then
		return
	end
	current = nil
	State.openScreen = nil
	s.holder.Visible = false
	safe(s.mod.onClose)
end

function LobbyUI.open(name, arg)
	if type(name) ~= "string" then
		return
	end
	if State.inMatch then
		pendingOpen = { name = name, arg = arg, time = os.clock() }
		return
	end
	if name == "Quests" then
		Quests.expand()
		return
	end
	if name == "Codes" then
		name, arg = "Gifts", "codes"
	end
	local s = shells[name]
	if not s then
		warn("[LobbyUI] unknown screen: " .. name)
		return
	end
	if current ~= s then
		LobbyUI.close()
		current = s
		State.openScreen = name
		s.holder.Visible = true
		Kit.popIn(s.frame)
	end
	safe(s.mod.onOpen, arg)
end

-- side buttons: tap once to open, again to close
function LobbyUI.toggle(name)
	if current and current.name == name then
		LobbyUI.close()
	else
		LobbyUI.open(name)
	end
end

----------------------------------------------------------------------
-- building
----------------------------------------------------------------------

-- a centred, auto-scaled Kit.panel holding one panel module
local function makeShell(name, mod, ctx)
	local w, h = mod.size.X, mod.size.Y
	local holder = Util.group(panelGui, {
		name = name .. "Panel",
		size = UDim2.fromOffset(w, h),
		position = UDim2.new(0.5, 0, 0.5, 16),
		anchor = Vector2.new(0.5, 0.5),
	})
	holder.Visible = false
	Util.autoScale(holder, 1280, h + 110)
	local frame, content, closeBtn = Kit.panel(holder, {
		name = "Panel",
		title = mod.title,
		titleColor = mod.color,
		size = UDim2.fromScale(1, 1),
	})
	frame.Active = true -- don't let clicks fall through to the world
	if closeBtn then
		Util.onClick(closeBtn, LobbyUI.close)
	end
	safe(mod.build, content, ctx)
	shells[name] = { name = name, mod = mod, holder = holder, frame = frame }
end

local function onData(data)
	if not data then
		return
	end
	safe(Hud.update, data)
	safe(Quests.update, data)
	for _, mod in PANELS do
		safe(mod.update, data)
	end
end

local function onMatchChanged(inMatch)
	hudGui.Enabled = not inMatch
	panelGui.Enabled = not inMatch
	if inMatch then
		LobbyUI.close()
		Reveal.cancel()
		Queue.hide()
		return
	end
	safe(Hud.onLobby)
	-- a screen someone asked for right as the match ended
	local p = pendingOpen
	pendingOpen = nil
	if p and os.clock() - p.time < 3 then
		LobbyUI.open(p.name, p.arg)
	end
end

local function onNotify(msg)
	if type(msg) == "string" then
		Toasts.show(msg)
		return
	end
	if type(msg) ~= "table" then
		return
	end
	if type(msg.text) == "string" and msg.text ~= "" then
		Toasts.show(msg.text, msg.color)
	end
	if type(msg.open) == "string" then
		LobbyUI.open(msg.open)
	end
end

-- one loop drives every timer (x2 boost, play time, queue clock)
local function startTicker()
	task.spawn(function()
		while true do
			task.wait(0.25)
			safe(Hud.tick)
			safe(Queue.tick)
			for _, mod in PANELS do
				safe(mod.tick)
			end
		end
	end)
end

function LobbyUI.init()
	if started then
		return
	end
	started = true

	Toasts.build()
	hudGui = Kit.screen("AvA_LobbyHud", 5)
	panelGui = Kit.screen("AvA_LobbyPanels", 10)

	local ctx = {
		open = LobbyUI.open,
		close = LobbyUI.close,
		toggle = LobbyUI.toggle,
		toast = Toasts.show,
	}
	Hud.build(hudGui, ctx)
	Quests.build(hudGui, ctx)
	Queue.build(hudGui, ctx)
	for name, mod in PANELS do
		makeShell(name, mod, ctx)
	end

	-- State events (data may already be here, or arrive later)
	State.Changed:Connect(onData)
	State.MatchChanged:Connect(onMatchChanged)
	State.OpenRequested:Connect(LobbyUI.open)
	if State.data then
		onData(State.data)
	end
	onMatchChanged(State.inMatch)

	-- server messages
	Remotes.event("Notify").OnClientEvent:Connect(onNotify)
	Remotes.event("Queue").OnClientEvent:Connect(function(msg)
		if not State.inMatch then
			safe(Queue.onQueue, msg)
		elseif type(msg) == "table" and not msg.inQueue then
			Queue.hide()
		end
	end)

	startTicker()
end

return LobbyUI
