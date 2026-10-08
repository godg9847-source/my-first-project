--!nonstrict
--[[
	DataService: loads, saves and changes player profiles.

	Profiles live in the DataStore "AnimeVsAnime_Profiles_v1" under "u_<UserId>".
	In Studio, saving only works if Game Settings > Security > "Enable Studio
	Access to API Services" is on; otherwise profiles are kept in memory and a
	warning is printed (everything else still works).

	Other services change data only through the functions below, then call
	DataService.push(player) (most functions push for you) so the client UI
	updates.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Fighters = require(Shared.Fighters)
local Remotes = require(Shared.Remotes)

local DataService = {}

local STORE_NAME = "AnimeVsAnime_Profiles_v1"
local AUTOSAVE = 120

local store = nil
local storeOk = false
local profiles = {} -- [Player] = profile
local dirty = {}
local onLoaded = Instance.new("BindableEvent")
DataService.Loaded = onLoaded.Event -- (player, profile)

local function today()
	return math.floor(os.time() / 86400)
end
DataService.today = today

local function defaultProfile()
	local owned = {}
	for _, id in Config.StarterFighters do
		if Fighters.get(id) then
			owned[id] = 1
		end
	end
	return {
		version = 1,
		coins = Config.StartingCoins,
		gems = Config.StartingGems,
		level = 1,
		xp = 0,
		owned = owned,
		stats = { wins = 0, losses = 0, matches = 0, streak = 0, bestStreak = 0, summons = 0 },
		quests = { day = -1, list = {} },
		online = { day = -1, seconds = 0, claimed = {} },
		daily = { lastDay = -1, streak = 0 },
		codes = {},
		pity = {},
		x2Until = 0,
		tagTickets = 0,
		settings = { music = true, sfx = true, instantUlt = false, shake = true, flashReduction = false },
		flags = {}, -- one-time rewards (groupReward, starterPack, ...)
		indexEver = table.clone(owned), -- every fighter ever owned (index never goes down)
		indexClaimed = {}, -- ["i5"] = true
		titles = {},
		botPayouts = { day = -1, count = 0 },
		firstWinDay = -1,
		firstJoin = os.time(),
	}
end

-- fill in any fields added in later versions
local function reconcile(p)
	local d = defaultProfile()
	for k, v in d do
		if p[k] == nil then
			p[k] = v
		elseif type(v) == "table" and type(p[k]) == "table" and k ~= "owned" then
			for k2, v2 in v do
				if p[k][k2] == nil then
					p[k][k2] = v2
				end
			end
		end
	end
	-- remove fighters that no longer exist
	for id in p.owned do
		if not Fighters.get(id) then
			p.owned[id] = nil
		end
	end
	for id, n in p.owned do
		if n > 0 then
			p.indexEver[id] = true
		end
	end
	if next(p.owned) == nil then
		p.owned = d.owned
	end
	return p
end

local function key(player)
	return "u_" .. player.UserId
end

local function load(player)
	if not storeOk then
		return defaultProfile()
	end
	for attempt = 1, 3 do
		local ok, data = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			if type(data) == "table" then
				return reconcile(data)
			end
			return defaultProfile()
		end
		warn("[DataService] load failed (attempt " .. attempt .. "):", data)
		task.wait(1.5 * attempt)
	end
	-- could not load: play with a temporary profile but never save it (protects real data)
	local p = defaultProfile()
	p.__noSave = true
	return p
end

function DataService.save(player)
	local p = profiles[player]
	if not p or not storeOk or p.__noSave then
		return
	end
	local copy = table.clone(p)
	local ok, err = pcall(function()
		store:SetAsync(key(player), copy)
	end)
	if ok then
		dirty[player] = nil
	else
		warn("[DataService] save failed:", err)
	end
end

----------------------------------------------------------------------
-- reading
----------------------------------------------------------------------

function DataService.getProfile(player)
	return profiles[player]
end

-- wait (up to 10 s) for the profile to load
function DataService.waitProfile(player)
	local t = 0
	while not profiles[player] and t < 10 and player.Parent do
		t += task.wait(0.1)
	end
	return profiles[player]
end

function DataService.ownedFighters(player)
	local p = profiles[player]
	local out = {}
	if p then
		for id, n in p.owned do
			if n > 0 and Fighters.get(id) then
				table.insert(out, id)
			end
		end
	end
	return out
end

function DataService.owns(player, fighterId)
	local p = profiles[player]
	return p ~= nil and (p.owned[fighterId] or 0) > 0
end

----------------------------------------------------------------------
-- client view
----------------------------------------------------------------------

function DataService.view(player)
	local p = profiles[player]
	if not p then
		return nil
	end
	local quests = {}
	for _, q in p.quests.list do
		table.insert(quests, {
			id = q.id,
			text = q.text,
			progress = q.progress,
			goal = q.goal,
			reward = q.reward,
			claimed = q.claimed,
		})
	end
	return {
		coins = p.coins,
		gems = p.gems,
		level = p.level,
		xp = p.xp,
		xpNeeded = Config.xpForLevel(p.level),
		owned = p.owned,
		stats = p.stats,
		quests = quests,
		online = { seconds = p.online.seconds, claimed = p.online.claimed },
		daily = { streak = p.daily.streak, canClaim = p.daily.lastDay ~= today() },
		x2Until = p.x2Until,
		tagTickets = p.tagTickets,
		pity = p.pity,
		settings = p.settings,
		passes = DataService.passes(player),
		codes = p.codes,
		flags = p.flags,
		indexCount = DataService.indexCount(player),
		indexClaimed = p.indexClaimed,
		titles = p.titles,
		firstWinAvailable = p.firstWinDay ~= today(),
		questsDone = p.quests.chestClaimed or false,
		chestReady = DataService.chestReady and DataService.chestReady(player) or false,
	}
end

function DataService.push(player)
	local v = DataService.view(player)
	if v and player.Parent then
		Remotes.event("Data"):FireClient(player, v)
	end
	dirty[player] = true
end

----------------------------------------------------------------------
-- game passes (cached per session)
----------------------------------------------------------------------

local passCache = {} -- [Player] = {VIP = bool, ...}

function DataService.passes(player)
	if passCache[player] then
		return passCache[player]
	end
	local res = {}
	for name, info in Config.GamePasses do
		res[name] = false
		if info.id and info.id ~= 0 then
			local ok, owns = pcall(function()
				return game:GetService("MarketplaceService"):UserOwnsGamePassAsync(player.UserId, info.id)
			end)
			res[name] = ok and owns or false
		end
	end
	passCache[player] = res
	return res
end

function DataService.setPass(player, name, value)
	local c = DataService.passes(player)
	c[name] = value
	DataService.push(player)
end

----------------------------------------------------------------------
-- changing
----------------------------------------------------------------------

-- kind = "coins" | "gems". reason "match" applies coin boosts. Returns the amount added.
function DataService.addCurrency(player, kind, amount, reason)
	local p = profiles[player]
	if not p or amount == 0 then
		return 0
	end
	if kind == "coins" and reason == "match" and amount > 0 then
		-- bonuses add up: VIP +15 %, 2x Coins +100 %, group +5 %; the timed x2 boost doubles the total
		local mult = 1
		local passes = DataService.passes(player)
		if passes.DoubleCoins then
			mult += 1
		end
		if passes.VIP then
			mult += 0.15
		end
		if p.flags.groupMember then
			mult += Config.Match.GroupCoinBonus
		end
		if p.x2Until > os.time() then
			mult *= 2
		end
		amount = math.floor(amount * mult + 0.5)
	end
	p[kind] = math.max(0, (p[kind] or 0) + amount)
	DataService.push(player)
	return amount
end

function DataService.spend(player, kind, amount, _reason)
	local p = profiles[player]
	if not p or amount < 0 or (p[kind] or 0) < amount then
		return false
	end
	p[kind] -= amount
	DataService.push(player)
	return true
end

function DataService.spendGems(player, amount, reason)
	return DataService.spend(player, "gems", amount, reason)
end

-- returns isNew, refundCoins. Duplicates become Spares, which are released for coins right away
-- (Rare 75 / Epic 200 / Legendary 600 / Mythic 2,000).
function DataService.giveFighter(player, fighterId)
	local p = profiles[player]
	local f = Fighters.get(fighterId)
	if not p or not f then
		return false, 0
	end
	local had = (p.owned[fighterId] or 0) > 0
	p.owned[fighterId] = (p.owned[fighterId] or 0) + 1
	p.indexEver[fighterId] = true
	local refund = 0
	if had then
		refund = Config.Rarities[f.rarity].spareCoins
		p.coins += refund
	end
	DataService.push(player)
	return not had, refund
end

function DataService.indexCount(player)
	local p = profiles[player]
	local n = 0
	if p then
		for id in p.indexEver do
			if Fighters.get(id) then
				n += 1
			end
		end
	end
	return n
end

-- the first win each day pays a bonus; returns true once per day
function DataService.claimFirstWin(player)
	local p = profiles[player]
	if not p or p.firstWinDay == today() then
		return false
	end
	p.firstWinDay = today()
	return true
end

-- bot matches pay coins at most N times per day; returns true if this one pays
function DataService.useBotPayout(player)
	local p = profiles[player]
	if not p then
		return false
	end
	if p.botPayouts.day ~= today() then
		p.botPayouts = { day = today(), count = 0 }
	end
	if p.botPayouts.count >= Config.Match.Payouts.Bot.dailyLimit then
		return false
	end
	p.botPayouts.count += 1
	return true
end

function DataService.useTagTicket(player)
	local p = profiles[player]
	if not p or (p.tagTickets or 0) <= 0 then
		return false
	end
	p.tagTickets -= 1
	DataService.push(player)
	return true
end

function DataService.addTagTickets(player, n)
	local p = profiles[player]
	if p then
		p.tagTickets = (p.tagTickets or 0) + n
		DataService.push(player)
	end
end

-- returns levelUp (bool), newLevel
function DataService.addXp(player, amount)
	local p = profiles[player]
	if not p or amount <= 0 then
		return false, p and p.level
	end
	p.xp += amount
	local leveled = false
	while p.level < Config.MaxLevel and p.xp >= Config.xpForLevel(p.level) do
		p.xp -= Config.xpForLevel(p.level)
		p.level += 1
		leveled = true
		DataService.onLevelUp(player, p.level)
	end
	DataService.push(player)
	return leveled, p.level
end

-- replaced by ShopService/RewardService at init (free summon on level up)
function DataService.onLevelUp(_player, _level) end

function DataService.recordMatch(player, won, _mode, practice)
	local p = profiles[player]
	if not p then
		return
	end
	local s = p.stats
	s.matches += 1
	if won then
		if not practice then
			s.wins += 1
		end
		s.streak += 1
		s.bestStreak = math.max(s.bestStreak, s.streak)
	else
		s.losses += 1
		s.streak = 0
	end
	-- leaderstats
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		local w = ls:FindFirstChild("Wins")
		if w then
			w.Value = s.wins
		end
		local l = ls:FindFirstChild("Level")
		if l then
			l.Value = p.level
		end
	end
	DataService.push(player)
end

-- give a reward table {coins, gems, tagTickets, fighter} (summons are handled by ShopService)
function DataService.grantSimple(player, r)
	if r.coins then
		DataService.addCurrency(player, "coins", r.coins, "reward")
	end
	if r.gems then
		DataService.addCurrency(player, "gems", r.gems, "reward")
	end
	if r.tagTickets then
		DataService.addTagTickets(player, r.tagTickets)
	end
	if r.fighter then
		DataService.giveFighter(player, r.fighter)
	end
	if r.title then
		local p = profiles[player]
		if p and not table.find(p.titles, r.title) then
			table.insert(p.titles, r.title)
		end
	end
end

function DataService.setSetting(player, k, v)
	local p = profiles[player]
	if p and p.settings[k] ~= nil and type(v) == type(p.settings[k]) then
		p.settings[k] = v
		DataService.push(player)
	end
end

----------------------------------------------------------------------
-- lifecycle
----------------------------------------------------------------------

local function onPlayerAdded(player)
	local profile = load(player)
	if not player.Parent then
		return
	end
	profiles[player] = profile
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Value = profile.stats.wins
	wins.Parent = ls
	local lvl = Instance.new("IntValue")
	lvl.Name = "Level"
	lvl.Value = profile.level
	lvl.Parent = ls
	ls.Parent = player
	onLoaded:Fire(player, profile)
	DataService.push(player)
end

function DataService.init()
	local ok, res = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = res
		-- in Studio, check that API access is enabled
		local ok2, err2 = pcall(function()
			store:GetAsync("__probe")
		end)
		storeOk = ok2
		if not ok2 then
			warn("[DataService] DataStores unavailable (" .. tostring(err2) .. "). Progress will NOT be saved. In Studio: Game Settings > Security > Enable Studio Access to API Services.")
		end
	else
		warn("[DataService] DataStores unavailable:", res)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, pl in Players:GetPlayers() do
		task.spawn(onPlayerAdded, pl)
	end
	Players.PlayerRemoving:Connect(function(player)
		DataService.save(player)
		profiles[player] = nil
		dirty[player] = nil
		passCache[player] = nil
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not storeOk then
			return
		end
		local threads = {}
		for player in profiles do
			table.insert(threads, task.spawn(DataService.save, player))
		end
		task.wait(2)
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for player in dirty do
				if player.Parent then
					DataService.save(player)
				end
			end
		end
	end)
end

return DataService
