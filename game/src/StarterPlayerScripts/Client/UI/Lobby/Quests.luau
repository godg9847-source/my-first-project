--!nonstrict
--[[
	Lobby/Quests: the DAILY QUESTS tracker in the top-right corner.
	Tap the header to collapse/expand it. Each quest shows its text, a
	progress bar and a CLAIM button once it is complete
	(-> UIAction {action = "claimQuest", id}).
]]

local GuiService = game:GetService("GuiService")

local Util = require(script.Parent.Util)
local Kit = Util.Kit

local Quests = {}

local WIDTH = 300
local ROW_H = 74

local holder, header, badge, listFrame, emptyLabel
local expanded = true
local rows = {} -- reused row widgets, by index
local pending = {} -- [questId] = os.clock() when we pressed CLAIM

local function belowTopbar()
	local ok, inset = pcall(function()
		return (GuiService:GetGuiInset())
	end)
	local y = ok and inset and inset.Y or 36
	return math.max(y, 36) + 8
end

local function headerText()
	return expanded and "DAILY QUESTS  -" or "DAILY QUESTS  +"
end

function Quests.setExpanded(v)
	expanded = v
	listFrame.Visible = v
	Kit.setButtonText(header, headerText())
end

-- open the tracker (e.g. from the quest board in the lobby)
function Quests.expand()
	Quests.setExpanded(true)
	Kit.popIn(listFrame)
end

----------------------------------------------------------------------
-- rows
----------------------------------------------------------------------

local function makeRow(i)
	local row = Util.box(listFrame, {
		name = "Quest" .. i,
		size = UDim2.new(1, 0, 0, ROW_H),
		color = Kit.C.panel2,
		corner = 10,
		order = i,
	})
	local r = { frame = row }
	r.text = Kit.label(row, {
		text = "",
		size = UDim2.new(1, -16, 0, 28),
		position = UDim2.fromOffset(8, 4),
		alignX = Enum.TextXAlignment.Left,
		font = Kit.FontBody,
	})
	Util.maxText(r.text, 20)
	r.bar = Util.bar(row, {
		size = UDim2.new(1, -118, 0, 24),
		position = UDim2.new(0, 8, 1, -8),
		anchor = Vector2.new(0, 1),
		color = Kit.C.green,
	})
	-- right slot: reward text, or the CLAIM button, or "DONE"
	r.reward = Kit.label(row, {
		text = "",
		color = Kit.C.coin,
		size = UDim2.fromOffset(96, 34),
		position = UDim2.new(1, -8, 1, -4),
		anchor = Vector2.new(1, 1),
		font = Kit.FontBody,
	})
	Util.maxText(r.reward, 18)
	r.claim = Kit.button(row, {
		text = "CLAIM",
		color = Kit.C.green,
		size = UDim2.fromOffset(96, 38),
		position = UDim2.new(1, -8, 1, -4),
		anchor = Vector2.new(1, 1),
	})
	Util.styleButton(r.claim, "CLAIM", Kit.C.green, true)
	Util.onClick(r.claim, function()
		local id = r.questId
		if not id then
			return
		end
		pending[id] = os.clock()
		Util.styleButton(r.claim, "...", nil, false)
		Util.fire({ action = "claimQuest", id = id })
		-- if the server never answers, let the player try again
		task.delay(4, function()
			if pending[id] then
				pending[id] = nil
				Quests.update(Util.data())
			end
		end)
	end)
	rows[i] = r
	return r
end

local function fillRow(r, q)
	local goal = math.max(1, q.goal or 1)
	local progress = math.min(q.progress or 0, goal)
	local complete = progress >= goal
	r.questId = q.id
	r.text.Text = q.text or "?"
	Util.setBar(r.bar, progress / goal, tostring(progress) .. " / " .. tostring(goal), true)

	if q.claimed then
		r.claim.Visible = false
		r.reward.Visible = true
		r.reward.Text = "DONE"
		r.reward.TextColor3 = Kit.C.green
		r.frame.BackgroundTransparency = 0.4
	elseif complete then
		r.reward.Visible = false
		r.claim.Visible = true
		local waiting = pending[q.id] ~= nil
		Util.styleButton(r.claim, waiting and "..." or "CLAIM", nil, not waiting)
		r.frame.BackgroundTransparency = 0
	else
		r.claim.Visible = false
		r.reward.Visible = true
		r.reward.Text = "+" .. Util.rewardText(q.reward)
		r.reward.TextColor3 = (q.reward and q.reward.gems and not q.reward.coins) and Kit.C.gem or Kit.C.coin
		r.frame.BackgroundTransparency = 0
	end
end

----------------------------------------------------------------------
-- public
----------------------------------------------------------------------

function Quests.update(data)
	if not listFrame then
		return
	end
	local quests = data and data.quests or {}
	if type(quests) == "table" and quests.list then
		quests = quests.list -- tolerate the raw server shape too
	end
	local claimable = 0
	local count = 0
	for i, q in quests do
		count = i
		local r = rows[i] or makeRow(i)
		r.frame.Visible = true
		-- a fresh Data message answers our claim
		if q.claimed then
			pending[q.id] = nil
		end
		fillRow(r, q)
		if not q.claimed and (q.progress or 0) >= (q.goal or 1) then
			claimable += 1
		end
	end
	for i = count + 1, #rows do
		rows[i].frame.Visible = false
	end
	emptyLabel.Visible = count == 0
	emptyLabel.Text = data and "No quests today" or "Loading..."
	badge.Visible = claimable > 0
	Util.setBadge(badge, tostring(claimable))
end

function Quests.build(gui, _ctx)
	holder = Util.group(gui, {
		name = "QuestTracker",
		size = UDim2.fromOffset(WIDTH, 360),
		position = UDim2.new(1, -12, 0, belowTopbar()),
		anchor = Vector2.new(1, 0),
	})
	Util.autoScale(holder, 1280, 620)

	header = Kit.button(holder, {
		text = headerText(),
		color = Kit.C.purple,
		size = UDim2.new(1, 0, 0, 46),
	})
	badge = Util.badge(header, "0")
	Util.onClick(header, function()
		Quests.setExpanded(not expanded)
	end)

	listFrame = Util.box(holder, {
		name = "List",
		size = UDim2.new(1, 0, 0, 0),
		position = UDim2.fromOffset(0, 54),
		color = Kit.C.panel,
		transparency = 0.1,
		corner = 14,
		stroke = 3,
	})
	listFrame.AutomaticSize = Enum.AutomaticSize.Y
	Kit.padding(listFrame, 8)
	Kit.list(listFrame, Enum.FillDirection.Vertical, 6)
	emptyLabel = Kit.label(listFrame, {
		text = "Loading...",
		color = Kit.C.sub,
		size = UDim2.new(1, 0, 0, 30),
		font = Kit.FontBody,
		order = 999,
	})

	-- start collapsed on short (phone) screens so it doesn't cover the game
	-- (a viewport of ~1x1 means the camera isn't ready yet: assume a big screen)
	local vp = workspace.CurrentCamera.ViewportSize
	Quests.setExpanded(vp.Y < 10 or vp.Y >= 500)
	Quests.update(Util.data())
end

return Quests
