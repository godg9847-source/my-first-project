--!strict
--[[
	Config: every tunable number in one place (values from the design framework,
	docs/Anime-vs-Anime-Design.md Part 2). Change values here — no other file
	should hard-code these.

	IDs you must fill in after publishing the game (Creator Dashboard):
	  Config.GroupId, Config.GamePasses.*.id, Config.Products.*.id
	While they are 0 the related buttons just say "Coming soon!".
]]

local Config = {}

Config.GameName = "Anime vs Anime"
Config.Version = "0.1.0"

-- Your Roblox group id (for the "like + join the group" reward and +5 % coins). 0 = disabled.
Config.GroupId = 0

----------------------------------------------------------------------
-- Match flow (seconds unless noted) — framework §3.2
----------------------------------------------------------------------
Config.Match = {
	CountdownTime = 3, -- pad full → transfer
	IntroTime = 3, -- VS intro before round 1
	PickTime = 20, -- "CHOOSE YOUR FIGHTER" (skips ahead when everyone locks)
	ChampionPickTime = 10, -- from round 2 the last round's winner must lock within this
	RevealTime = 1.5,
	AimTime = 10, -- "ADJUST YOUR AIM"
	LaunchTime = 1.5, -- "READY... FIGHT!"
	FinisherTime = 4.5, -- KO → winning fighter flies into the loser (6.0 in the final round)
	FinalFinisherTime = 6.0,
	RecapTime = 1.5,
	ResultsTime = 12,
	Hearts = 3, -- per player (1v1) or per team (2v2)
	OptionsPerRound = 3,
	SpawnY = 14, -- fighters start at (0, -14) and (0, +14); 2v2 at (±8, ±18)
	LastHeartCharge = 25, -- "Last Heart Spirit": start the round with this much ULT meter

	-- rerolls (pick screen): first one per match is free, then gems
	FreeRerollsPerMatch = 1,
	RerollGemCost = 10,
	MaxPaidRerollsPerRound = 2,
	-- Tag Out (mid-fight swap to one of your other 2 cards)
	TagOutWindow = 6,
	TagOutGemCost = 20,

	-- payouts (framework §10.2)
	Payouts = {
		["1v1"] = { win = 100, loss = 20, perRound = 10 },
		["2v2"] = { win = 120, loss = 25, perRound = 10 },
		Bot = { win = 40, loss = 10, perRound = 0, dailyLimit = 10 },
	},
	WinStreakBonus = 10, -- per consecutive win
	WinStreakMax = 50,
	FirstWinBonus = 100, -- first win of the day (+ double XP)
	GroupCoinBonus = 0.05,
	XpWin = 60,
	XpLoss = 25,
	XpPerRound = 10,

	BotOfferSeconds = 45, -- a lonely pad offers "Fight a Bot" after this long
	BotOfferSecondsNewPlayer = 25, -- players below level 5
}

----------------------------------------------------------------------
-- Battle simulation (passed to Sim/Battle.luau; see the DEFAULTS there for every key)
----------------------------------------------------------------------
Config.Battle = {
	TickRate = 60,
	RoundTime = 60, -- Arena Collapse starts
	HardEnd = 75, -- decided by HP %
	UltWindow = 6,
}

----------------------------------------------------------------------
-- Rarities — framework §6.2
----------------------------------------------------------------------
Config.RarityOrder = { "Rare", "Epic", "Legendary", "Mythic" }
Config.Rarities = {
	Rare = { color = "#3b82f6", order = 1, spareCoins = 75 },
	Epic = { color = "#a855f7", order = 2, spareCoins = 200 },
	Legendary = { color = "#f59e0b", order = 3, spareCoins = 600 },
	Mythic = { color = "#ef4444", color2 = "#ec4899", order = 4, spareCoins = 2000 },
}

Config.Roles = {
	Brawler = { color = "#ef4444", beats = { "Blaster" } },
	Blaster = { color = "#f59e0b", beats = { "Trickster" } },
	Trickster = { color = "#a855f7", beats = { "Brawler" } },
	Controller = { color = "#22c55e", beats = { "Assassin" } },
	Assassin = { color = "#64748b", beats = { "Guardian" } },
	Guardian = { color = "#0ea5e9", beats = { "Controller" } },
}

----------------------------------------------------------------------
-- New players
----------------------------------------------------------------------
Config.StartingCoins = 300
Config.StartingGems = 25
-- Sky Spiker, Muscle Mage, Spatial Striker (all Rare) — framework §1
Config.StarterFighters = { "hinata", "mash", "isagi" }

----------------------------------------------------------------------
-- Summoning — framework §10.4
----------------------------------------------------------------------
Config.Banners = {
	{
		id = "basic",
		name = "Basic Shrine",
		currency = "coins",
		cost = 150,
		cost10 = 1350,
		odds = { Rare = 80, Epic = 20, Legendary = 0, Mythic = 0 },
		color = "#3b82f6",
	},
	{
		id = "standard",
		name = "Standard Shrine",
		currency = "coins",
		cost = 600,
		cost10 = 5400, -- 10 % off, at least one Epic or better guaranteed
		odds = { Rare = 62, Epic = 28, Legendary = 8.5, Mythic = 1.5 },
		pity = true,
		tenPullFloor = "Epic",
		color = "#a855f7",
	},
	{
		id = "featured",
		name = "Featured Shrine",
		currency = "coins",
		cost = 750,
		cost10 = 6750,
		gemCost = 50, -- can also be paid with gems
		gemCost10 = 450,
		odds = { Rare = 60, Epic = 28, Legendary = 10, Mythic = 2 },
		pity = true,
		featured = { Legendary = "naruto", Mythic = "gojo" }, -- rotate weekly
		featuredShare = 0.5,
		color = "#ef4444",
	},
}
-- pity (Standard and Featured, separate counters)
Config.Pity = {
	Legendary = { hard = 40, softFrom = 30, softPerPull = 3 }, -- Legendary-or-better by pull 40
	Mythic = { hard = 120, softFrom = 90, softPerPull = 1.5 },
}

----------------------------------------------------------------------
-- Levels — framework §10.8
----------------------------------------------------------------------
Config.MaxLevel = 100
function Config.xpForLevel(level: number): number
	if level >= 30 then
		return 1000
	end
	return 100 + 30 * (level - 1)
end
-- reward when you REACH a level
Config.LevelRewards = {
	[2] = { summon = "basic" },
	[3] = { coins = 200 },
	[4] = { fighterOf = "Rare" },
	[5] = { summon = "standard" },
	[6] = { coins = 300, gems = 10 },
	[7] = { fighterOf = "Epic" },
	[8] = { coins = 400 },
	[9] = { summon = "standard" },
	[10] = { summon = "standard", summons = 3 },
}
Config.LevelRewardDefault = { coins = 150 } -- level 11+
Config.EveryFifthLevel = { summon = "standard", gems = 10 }
Config.Unlocks = { ["2v2"] = 3, Ranked = 10, Trading = 10 }

----------------------------------------------------------------------
-- Daily quests (3 per day, 100 coins each; all 3 → Daily Chest) — framework §10.3
----------------------------------------------------------------------
Config.QuestsPerDay = 3
Config.QuestPool = {
	{ id = "play5", type = "play", goal = 5, text = "Play 5 matches" },
	{ id = "win3", type = "win", goal = 3, text = "Win 3 matches" },
	{ id = "friend", type = "duelFriend", goal = 1, text = "Duel a friend" },
	{ id = "focus3", type = "focusUlt", goal = 3, text = "Land 3 FOCUSED Ultimates" },
	{ id = "rareRound", type = "rareRound", goal = 1, text = "Win a round with a Rare fighter" },
	{ id = "challenger", type = "challengerRound", goal = 1, text = "Win a round as the Challenger" },
	{ id = "slam", type = "slam", goal = 1, text = "Trigger a Wall Slam" },
	{ id = "heroPick", type = "heroPickRound", goal = 1, text = "Use Hero Pick and win that round" },
	{ id = "duo", type = "play2v2", goal = 2, text = "Play 2v2 twice" },
	{ id = "edge", type = "edgeWin", goal = 1, text = "Win a round with role advantage" },
	{ id = "dmg", type = "damage", goal = 5000, text = "Deal 5,000 damage" },
}
Config.QuestReward = { coins = 100 }
Config.DailyChest = { coins = 100, gems = 5, tagTickets = 1 }

----------------------------------------------------------------------
-- Online-time rewards (gift icon) — 400 coins in total; 10 % chance of x2 coins for 10 min each
----------------------------------------------------------------------
Config.OnlineRewards = {
	{ minutes = 5, coins = 25 },
	{ minutes = 10, coins = 25 },
	{ minutes = 20, coins = 50 },
	{ minutes = 30, coins = 75 },
	{ minutes = 45, coins = 100 },
	{ minutes = 60, coins = 125 },
}
Config.BoostChance = 0.10
Config.BoostMinutes = 10

----------------------------------------------------------------------
-- 7-day login streak (missing 1 day keeps it, missing 2 resets)
----------------------------------------------------------------------
Config.DailyRewards = {
	{ coins = 100 },
	{ summon = "basic" },
	{ coins = 150 },
	{ gems = 10 },
	{ coins = 200 },
	{ summon = "standard" },
	{ gems = 25, summon = "standard" }, -- first cycle: a Rare you don't own instead
}

----------------------------------------------------------------------
-- Index rewards (fighters ever owned)
----------------------------------------------------------------------
Config.IndexRewards = {
	{ count = 5, coins = 500 },
	{ count = 10, coins = 1000, title = "Collector" },
	{ count = 15, gems = 50 },
	{ count = 20, summon = "standard", summons = 2 },
	{ count = 25, gems = 100 },
	{ count = 30, summon = "featured", summons = 3, title = "Full Roster" },
}

----------------------------------------------------------------------
-- Codes (NOT case-sensitive). Add a new UPD code with every weekly update!
----------------------------------------------------------------------
Config.Codes = {
	ANIMEVSANIME = { coins = 500 },
	UPD1 = { coins = 150 },
}
Config.NewestCode = "ANIMEVSANIME"

----------------------------------------------------------------------
-- Robux (fill in real ids after you create them in the Creator Dashboard)
----------------------------------------------------------------------
Config.GamePasses = {
	VIP = { id = 0, name = "VIP", price = 399, desc = "+15% match coins, +1 free reroll per match, VIP Deck, gold nameplate" },
	DoubleCoins = { id = 0, name = "2x Coins", price = 349, desc = "+100% match coins" },
	FastSummon = { id = 0, name = "Fast Summon", price = 149, desc = "Skip summon animations" },
	ExtraQuest = { id = 0, name = "Extra Daily Quest", price = 149, desc = "A 4th daily quest slot" },
}
Config.Products = {
	Gems40 = { id = 0, gems = 40, price = 29 },
	Gems120 = { id = 0, gems = 120, price = 79 },
	Gems250 = { id = 0, gems = 250, price = 159 },
	Gems700 = { id = 0, gems = 700, price = 399 },
	Gems1500 = { id = 0, gems = 1500, price = 799 },
	Gems3300 = { id = 0, gems = 3300, price = 1599 },
	StarterPack = { id = 0, gems = 200, fighterChoice = { "natsu", "edward", "asta" }, price = 99, oncePerPlayer = true },
}

----------------------------------------------------------------------
-- Leaderboards
----------------------------------------------------------------------
Config.LeaderboardRefresh = 60
Config.LeaderboardSize = 10

return Config
