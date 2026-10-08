--!nonstrict
--[[
	Lobby/Queue: the bottom-centre "WAITING FOR PLAYERS 1/2" panel shown while
	you stand on a match pad. Driven by the "Queue" remote:
	  {inQueue, mode, count, capacity, padName, waitTime, botFillIn?}
	INVITE opens Roblox's invite-friends prompt; LEAVE sends
	MatchAction {action = "leaveQueue"}.
]]

local Players = game:GetService("Players")
local SocialService = game:GetService("SocialService")

local Util = require(script.Parent.Util)
local Kit = Util.Kit

local Queue = {}

local ctx = nil
local holder, card, title, info, botLabel
local msg = nil -- last Queue message while queued
local receivedAt = 0 -- os.clock() when msg arrived (we count up between messages)
local inviting = false

function Queue.hide()
	msg = nil
	if holder then
		holder.Visible = false
	end
end

local function render()
	if not msg then
		return
	end
	local since = os.clock() - receivedAt
	local count = tonumber(msg.count) or 0
	local capacity = tonumber(msg.capacity) or 2
	if count >= capacity then
		title.Text = "STARTING..."
	else
		title.Text = string.format("WAITING FOR PLAYERS  %d/%d", count, capacity)
	end
	local mode = msg.mode == "Bot" and "PRACTICE VS BOT" or ("MODE: " .. tostring(msg.mode or "?"))
	info.Text = mode .. "     " .. Util.mmss((tonumber(msg.waitTime) or 0) + since)
	local botIn = tonumber(msg.botFillIn)
	if botIn then
		local left = math.ceil(botIn - since)
		botLabel.Text = left > 0 and ("Bot joins in " .. left .. "s") or "A bot is joining..."
		botLabel.Visible = true
	else
		botLabel.Visible = false
	end
end

function Queue.onQueue(m)
	if type(m) ~= "table" or not m.inQueue then
		Queue.hide()
		return
	end
	local wasHidden = msg == nil
	msg = m
	receivedAt = os.clock()
	holder.Visible = true
	if wasHidden then
		Kit.popIn(card)
	end
	render()
end

function Queue.tick()
	if msg then
		render()
	end
end

local function invite()
	if inviting then
		return
	end
	inviting = true
	task.spawn(function()
		local player = Players.LocalPlayer
		local ok, canInvite = pcall(function()
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if ok and canInvite then
			local ok2, err = pcall(function()
				SocialService:PromptGameInvite(player)
			end)
			if not ok2 then
				warn("[LobbyUI] invite prompt failed:", err)
				ctx.toast("Couldn't open invites right now.", Kit.C.red)
			end
		else
			ctx.toast("Invites aren't available right now.", Kit.C.red)
		end
		inviting = false
	end)
end

function Queue.build(gui, context)
	ctx = context
	holder = Util.group(gui, {
		name = "QueuePanel",
		size = UDim2.fromOffset(480, 156),
		position = UDim2.new(0.5, 0, 1, -14),
		anchor = Vector2.new(0.5, 1),
	})
	Util.autoScale(holder, 1280, 620)
	holder.Visible = false

	card = Util.box(holder, { name = "Card", color = Color3.new(1, 1, 1), corner = 18, stroke = 4 })
	card.Active = true
	Kit.gradient(card, Kit.C.panel2, Kit.C.panel)
	title = Kit.label(card, {
		text = "WAITING FOR PLAYERS",
		size = UDim2.new(1, -24, 0, 36),
		position = UDim2.new(0.5, 0, 0, 8),
		anchor = Vector2.new(0.5, 0),
		color = Kit.C.gold,
	})
	info = Kit.label(card, {
		text = "",
		size = UDim2.new(1, -24, 0, 22),
		position = UDim2.new(0.5, 0, 0, 46),
		anchor = Vector2.new(0.5, 0),
		color = Kit.C.sub,
		font = Kit.FontBody,
	})
	botLabel = Kit.label(card, {
		text = "",
		size = UDim2.new(1, -24, 0, 20),
		position = UDim2.new(0.5, 0, 0, 70),
		anchor = Vector2.new(0.5, 0),
		color = Kit.C.gem,
		font = Kit.FontBody,
	})
	local inviteBtn = Kit.button(card, {
		text = "INVITE",
		color = Kit.C.blue,
		size = UDim2.new(0.5, -18, 0, 52),
		position = UDim2.new(0, 12, 1, -10),
		anchor = Vector2.new(0, 1),
	})
	local leaveBtn = Kit.button(card, {
		text = "LEAVE",
		color = Kit.C.red,
		size = UDim2.new(0.5, -18, 0, 52),
		position = UDim2.new(1, -12, 1, -10),
		anchor = Vector2.new(1, 1),
	})
	Util.onClick(inviteBtn, invite)
	Util.onClick(leaveBtn, function()
		Util.matchAction({ action = "leaveQueue" })
		Queue.hide() -- the server confirms with inQueue = false
	end)
end

return Queue
