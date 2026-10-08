--!nonstrict
--[[
	RewardService: daily quests + Daily Chest, online-time rewards, the 7-day
	login streak, level rewards, index rewards, codes and the group reward
	(framework §10.3, §10.6-10.8).
	DataStores can't save tables with gaps in numeric keys, so claimed tiers are
	stored with string keys ("t1", "i5", ...).
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local RewardService = {}

local DataService, ShopService

local function notify(player, text, color)
	Remotes.event("Notify"):FireClient(player, { text = text, color = color or "#7dff8a" })
end

-- reward = {coins?, gems?, tagTickets?, summon? = bannerId, summons? = n, fighterOf? = rarity, title?}
local function grant(player, reward, _why)
	local parts = {}
	DataService.grantSimple(player, reward)
	if reward.coins then
		table.insert(parts, "+" .. reward.coins .. " coins")
	end
	if reward.gems then
		table.insert(parts, "+" .. reward.gems .. " gems")
	end
	if reward.tagTickets then
		table.insert(parts, "+" .. reward.tagTickets .. " Tag Ticket")
	end
	if reward.title then
		table.insert(parts, 'title "' .. reward.title .. '"')
	end
	if reward.summon and ShopService then
		local n = reward.summons or 1
		ShopService.freeSummon(player, reward.summon, n)
		table.insert(parts, n .. "x free " .. reward.summon .. " summon")
	end
	if reward.fighterOf and ShopService then
		ShopService.giveUnowned(player, reward.fighterOf)
		table.insert(parts, "a new " .. reward.fighterOf .. " fighter")
	end
	return table.concat(parts, ", ")
end
RewardService.grant = grant

----------------------------------------------------------------------
-- daily quests + chest
----------------------------------------------------------------------

local function rollQuests(profile, player)
	local day = DataService.today()
	if profile.quests.day == day then
		return
	end
	local pool = table.clone(Config.QuestPool)
	local rng = Random.new(day * 7919 + (profile.firstJoin or 0) % 100000)
	local count = Config.QuestsPerDay
	if player and DataService.passes(player).ExtraQuest then
		count += 1
	end
	local list = {}
	for _ = 1, math.min(count, #pool) do
		local q = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(list, { id = q.id, type = q.type, text = q.text, goal = q.goal, reward = Config.QuestReward, progress = 0, claimed = false })
	end
	profile.quests = { day = day, list = list, chestClaimed = false }
end

local function chestReady(player)
	local p = DataService.getProfile(player)
	if not p or p.quests.chestClaimed then
		return false
	end
	for _, q in p.quests.list do
		if not q.claimed then
			return false
		end
	end
	return #p.quests.list > 0
end

function RewardService.progress(player, questType, amount)
	local p = DataService.getProfile(player)
	if not p then
		return
	end
	rollQuests(p, player)
	local changed = false
	for _, q in p.quests.list do
		if q.type == questType and q.progress < q.goal then
			q.progress = math.min(q.goal, q.progress + (amount or 1))
			changed = true
			if q.progress >= q.goal then
				notify(player, "Quest complete: " .. q.text .. "! Claim it in Quests.", "#ffd34d")
			end
		end
	end
	if changed then
		DataService.push(player)
	end
end

local function claimQuest(player, id)
	local p = DataService.getProfile(player)
	if not p then
		return
	end
	rollQuests(p, player)
	for _, q in p.quests.list do
		if q.id == id and not q.claimed and q.progress >= q.goal then
			q.claimed = true
			notify(player, "Quest reward: " .. grant(player, q.reward, "quest"))
			DataService.push(player)
			return
		end
	end
end

local function claimChest(player)
	if not chestReady(player) then
		return
	end
	local p = DataService.getProfile(player)
	p.quests.chestClaimed = true
	notify(player, "DAILY CHEST: " .. grant(player, Config.DailyChest, "chest"), "#ffd34d")
	DataService.push(player)
end

----------------------------------------------------------------------
-- online-time rewards
----------------------------------------------------------------------

local function resetOnline(p)
	local day = DataService.today()
	if p.online.day ~= day then
		p.online = { day = day, seconds = 0, claimed = {} }
	end
end

local function claimOnline(player, tier)
	local p = DataService.getProfile(player)
	local info = Config.OnlineRewards[tier]
	if not p or not info then
		return
	end
	resetOnline(p)
	local k = "t" .. tier
	if p.online.claimed[k] then
		return
	end
	if p.online.seconds < info.minutes * 60 then
		notify(player, "Keep playing to unlock this reward!", "#ff6b6b")
		return
	end
	p.online.claimed[k] = true
	local txt = grant(player, info, "online")
	if Random.new():NextNumber() < Config.BoostChance then
		p.x2Until = math.max(p.x2Until, os.time()) + Config.BoostMinutes * 60
		txt ..= " and a x2 COINS boost for " .. Config.BoostMinutes .. " minutes!"
	end
	notify(player, "Online reward: " .. txt)
	DataService.push(player)
end

----------------------------------------------------------------------
-- 7-day login streak (missing 1 day keeps the streak, missing 2 resets it)
----------------------------------------------------------------------

local function claimDaily(player)
	local p = DataService.getProfile(player)
	if not p then
		return
	end
	local day = DataService.today()
	if p.daily.lastDay == day then
		return
	end
	local gap = day - p.daily.lastDay
	if p.daily.lastDay >= 0 and gap <= 2 then
		p.daily.streak += 1
	else
		p.daily.streak = 1
	end
	p.daily.lastDay = day
	local idx = ((p.daily.streak - 1) % #Config.DailyRewards) + 1
	local reward = Config.DailyRewards[idx]
	if idx == 7 and p.daily.streak == 7 then
		reward = { fighterOf = "Rare" } -- first cycle: a Rare you don't own
	end
	notify(player, "Day " .. p.daily.streak .. " login reward: " .. grant(player, reward, "daily"))
	DataService.push(player)
end

----------------------------------------------------------------------
-- index rewards
----------------------------------------------------------------------

local function claimIndex(player, count)
	local p = DataService.getProfile(player)
	if not p then
		return
	end
	for _, r in Config.IndexRewards do
		if r.count == count then
			local k = "i" .. count
			if p.indexClaimed[k] or DataService.indexCount(player) < count then
				return
			end
			p.indexClaimed[k] = true
			notify(player, "Index reward: " .. grant(player, r, "index"), "#ffd34d")
			DataService.push(player)
			return
		end
	end
end

----------------------------------------------------------------------
-- level rewards
----------------------------------------------------------------------

local function onLevelUp(player, level)
	task.defer(function()
		notify(player, "LEVEL UP! You reached level " .. level .. "!", "#ffd34d")
		local r = Config.LevelRewards[level] or (level > 10 and Config.LevelRewardDefault) or nil
		if r then
			grant(player, r, "level")
		end
		if level % 5 == 0 then
			grant(player, Config.EveryFifthLevel, "level5")
		end
		for feature, need in Config.Unlocks do
			if need == level then
				notify(player, feature .. " unlocked!", "#7dd3fc")
			end
		end
	end)
end

----------------------------------------------------------------------
-- codes (not case-sensitive)
----------------------------------------------------------------------

local function redeem(player, code)
	if type(code) ~= "string" then
		return { ok = false, message = "Type a code first." }
	end
	local p = DataService.getProfile(player)
	if not p then
		return { ok = false, message = "Still loading, try again." }
	end
	code = string.upper((code:gsub("%s", "")))
	local reward = Config.Codes[code]
	if not reward then
		return { ok = false, message = "That code doesn't exist (or expired)." }
	end
	if p.codes[code] then
		return { ok = false, message = "You already used this code." }
	end
	p.codes[code] = true
	local txt = grant(player, reward, "code")
	DataService.push(player)
	return { ok = true, message = "Redeemed! " .. txt }
end

----------------------------------------------------------------------
-- group reward (+ 5 % match coins for members)
----------------------------------------------------------------------

local function checkGroup(player)
	if Config.GroupId == 0 then
		return
	end
	local p = DataService.getProfile(player)
	if not p then
		return
	end
	local ok, inGroup = pcall(function()
		return player:IsInGroup(Config.GroupId)
	end)
	p.flags.groupMember = ok and inGroup or false
	if p.flags.groupMember and not p.flags.groupReward then
		p.flags.groupReward = true
		notify(player, "Thanks for joining the group! " .. grant(player, { summon = "featured", title = "Clan Member" }, "group"), "#ffd34d")
	end
	DataService.push(player)
end

----------------------------------------------------------------------
-- init
----------------------------------------------------------------------

function RewardService.init(deps)
	DataService = deps.DataService
	ShopService = deps.ShopService
	DataService.chestReady = chestReady
	DataService.onLevelUp = onLevelUp

	DataService.Loaded:Connect(function(player, profile)
		rollQuests(profile, player)
		resetOnline(profile)
		task.delay(3, checkGroup, player)
	end)

	Remotes.event("UIAction").OnServerEvent:Connect(function(player, msg)
		if type(msg) ~= "table" then
			return
		end
		local a = msg.action
		if a == "claimQuest" then
			claimQuest(player, msg.id)
		elseif a == "claimChest" then
			claimChest(player)
		elseif a == "claimOnline" and type(msg.tier) == "number" then
			claimOnline(player, msg.tier)
		elseif a == "claimDaily" then
			claimDaily(player)
		elseif a == "claimIndex" and type(msg.count) == "number" then
			claimIndex(player, msg.count)
		elseif a == "setSetting" then
			DataService.setSetting(player, msg.key, msg.value)
		elseif a == "checkGroup" then
			checkGroup(player)
		end
	end)

	Remotes.func("RedeemCode").OnServerInvoke = redeem

	-- count online time (every 30 s) and roll quests over at midnight UTC
	task.spawn(function()
		while true do
			task.wait(30)
			for _, player in Players:GetPlayers() do
				local p = DataService.getProfile(player)
				if p then
					resetOnline(p)
					rollQuests(p, player)
					p.online.seconds += 30
					DataService.push(player)
				end
			end
		end
	end)
end

return RewardService
