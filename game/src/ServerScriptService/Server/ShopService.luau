--!nonstrict
--[[
	ShopService: summons (gacha), game passes and developer products (framework §10.4-10.5).

	Banners are in Config.Banners. Pity (Standard and Featured, separate counters):
	Legendary-or-better guaranteed by pull 40 (soft pity from 30), Mythic by 120
	(soft pity from 90). The Standard 10-pull guarantees at least one Epic. On the
	Featured Shrine the featured fighter takes 50 % of its rarity's pulls.
	Duplicates are released for coins (Config.Rarities[r].spareCoins).
	Gem summons are disabled for players where paid random items are restricted.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Fighters = require(Shared.Fighters)
local Remotes = require(Shared.Remotes)

local ShopService = {}

local DataService, RewardService
local rng = Random.new()
local policyCache = {}

local function banner(id)
	for _, b in Config.Banners do
		if b.id == id then
			return b
		end
	end
	return nil
end
ShopService.banner = banner

local function order(r)
	return Config.Rarities[r].order
end

local function paidRandomRestricted(player)
	if policyCache[player] == nil then
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		policyCache[player] = ok and info and info.ArePaidRandomItemsRestricted or false
	end
	return policyCache[player]
end

-- roll a rarity with soft pity applied
local function rollRarity(b, pity)
	local odds = table.clone(b.odds)
	if b.pity then
		local L, M = Config.Pity.Legendary, Config.Pity.Mythic
		if pity.leg >= L.softFrom then
			odds.Legendary += (pity.leg - L.softFrom + 1) * L.softPerPull
		end
		if pity.myth >= M.softFrom then
			odds.Mythic += (pity.myth - M.softFrom + 1) * M.softPerPull
		end
	end
	local total = 0
	for _, r in Config.RarityOrder do
		total += odds[r] or 0
	end
	local x = rng:NextNumber() * total
	for _, r in Config.RarityOrder do
		x -= odds[r] or 0
		if x <= 0 then
			return r
		end
	end
	return "Rare"
end

local function poolFor(b, rarity)
	local pool = Fighters.ofRarity(rarity)
	if b.id == "basic" and order(rarity) > order("Epic") then
		pool = Fighters.ofRarity("Epic")
	end
	if #pool == 0 then
		pool = Fighters.ofRarity("Rare")
	end
	return pool
end

-- one pull. returns {fighterId, rarity, isNew, refund, name}
local function pull(player, b, floorRarity)
	local p = DataService.getProfile(player)
	p.pity[b.id] = p.pity[b.id] or { leg = 0, myth = 0 }
	local pity = p.pity[b.id]
	pity.leg += 1
	pity.myth += 1
	local rarity = rollRarity(b, pity)
	if b.pity then
		if pity.myth >= Config.Pity.Mythic.hard then
			rarity = "Mythic"
		elseif pity.leg >= Config.Pity.Legendary.hard and order(rarity) < order("Legendary") then
			rarity = "Legendary"
		end
	end
	if floorRarity and order(rarity) < order(floorRarity) then
		rarity = floorRarity
	end
	if order(rarity) >= order("Legendary") then
		pity.leg = 0
	end
	if rarity == "Mythic" then
		pity.myth = 0
	end
	local id
	local featured = b.featured and b.featured[rarity]
	if featured and Fighters.get(featured) then
		-- 50/50 for the featured fighter; losing it guarantees it next time
		local guaranteed = p.flags["featuredGuarantee_" .. rarity]
		if guaranteed or rng:NextNumber() < (b.featuredShare or 0.5) then
			id = featured
			p.flags["featuredGuarantee_" .. rarity] = nil
		else
			p.flags["featuredGuarantee_" .. rarity] = true
		end
	end
	if not id then
		local pool = poolFor(b, rarity)
		id = pool[rng:NextInteger(1, #pool)]
	end
	local isNew, refund = DataService.giveFighter(player, id)
	p.stats.summons = (p.stats.summons or 0) + 1
	local f = Fighters.get(id)
	return { fighterId = id, rarity = f.rarity, isNew = isNew, refund = refund, name = f.name }
end

-- RemoteFunction Summon(bannerId, count, payWith) ; payWith = "gems" for Featured gem pulls
local function summon(player, bannerId, count, payWith)
	local b = banner(bannerId)
	if not b then
		return { ok = false, error = "Unknown shrine." }
	end
	count = (count == 10) and 10 or 1
	local p = DataService.getProfile(player)
	if not p then
		return { ok = false, error = "Still loading, try again." }
	end
	local currency, cost = b.currency, (count == 10 and b.cost10 or b.cost)
	if payWith == "gems" and b.gemCost then
		if paidRandomRestricted(player) then
			return { ok = false, error = "Gem summons are not available in your region." }
		end
		currency, cost = "gems", (count == 10 and b.gemCost10 or b.gemCost)
	end
	if not DataService.spend(player, currency, cost, "summon") then
		return { ok = false, error = "Not enough " .. currency .. "!" }
	end
	local results = {}
	local bestOrder = 0
	for i = 1, count do
		local floorR = nil
		if count == 10 and i == 10 and b.tenPullFloor and bestOrder < order(b.tenPullFloor) then
			floorR = b.tenPullFloor
		end
		local res = pull(player, b, floorR)
		bestOrder = math.max(bestOrder, order(res.rarity))
		table.insert(results, res)
		if order(res.rarity) >= order("Legendary") then
			-- server-wide shout for big pulls
			for _, other in Players:GetPlayers() do
				Remotes.event("Notify"):FireClient(other, {
					text = player.DisplayName .. " summoned " .. string.upper(res.rarity) .. " " .. res.name .. "!",
					color = Config.Rarities[res.rarity].color,
				})
			end
		end
	end
	if RewardService then
		RewardService.progress(player, "summon", count)
	end
	DataService.push(player)
	return { ok = true, results = results }
end

-- free summons from rewards / level-ups / login days. Returns the last result.
function ShopService.freeSummon(player, bannerId, times)
	local b = banner(bannerId or "standard")
	if not b or not DataService.getProfile(player) then
		return nil
	end
	local last
	for _ = 1, (times or 1) do
		last = pull(player, b)
		Remotes.event("Notify"):FireClient(player, {
			text = (last.isNew and "NEW FIGHTER: " or "Summoned: ") .. last.name .. " (" .. last.rarity .. ")",
			color = Config.Rarities[last.rarity].color,
		})
	end
	DataService.push(player)
	return last
end

-- a random fighter of a rarity the player does not own yet (level rewards, Rare Selector)
function ShopService.giveUnowned(player, rarity)
	local pool = {}
	for _, id in Fighters.ofRarity(rarity) do
		if not DataService.owns(player, id) then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		pool = Fighters.ofRarity(rarity)
	end
	if #pool == 0 then
		return nil
	end
	local id = pool[rng:NextInteger(1, #pool)]
	DataService.giveFighter(player, id)
	local f = Fighters.get(id)
	Remotes.event("Notify"):FireClient(player, { text = "NEW FIGHTER: " .. f.name .. " (" .. f.rarity .. ")", color = Config.Rarities[f.rarity].color })
	return id
end

----------------------------------------------------------------------
-- Robux
----------------------------------------------------------------------

local function productById(id)
	for k, info in Config.Products do
		if info.id == id and id ~= 0 then
			return k, info
		end
	end
	return nil
end

local function buy(player, key, choice)
	if type(key) ~= "string" then
		return { ok = false, message = "?" }
	end
	local pass = Config.GamePasses[key]
	if pass then
		if pass.id == 0 then
			return { ok = false, message = "Coming soon!" }
		end
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
		return { ok = true, message = "" }
	end
	local info = Config.Products[key]
	if info then
		if info.id == 0 then
			return { ok = false, message = "Coming soon!" }
		end
		local p = DataService.getProfile(player)
		if info.oncePerPlayer and p and p.flags["bought_" .. key] then
			return { ok = false, message = "You already own this pack." }
		end
		if info.fighterChoice and p then
			p.flags.pendingChoice = (type(choice) == "string" and table.find(info.fighterChoice, choice)) and choice or info.fighterChoice[1]
		end
		MarketplaceService:PromptProductPurchase(player, info.id)
		return { ok = true, message = "" }
	end
	return { ok = false, message = "Unknown item." }
end

local granted = {}

local function processReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = DataService.getProfile(player)
	if not p then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if granted[receipt.PurchaseId] or p.flags["receipt_" .. receipt.PurchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key, info = productById(receipt.ProductId)
	if not info then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if info.gems then
		DataService.addCurrency(player, "gems", info.gems, "purchase")
	end
	if info.fighterChoice then
		DataService.giveFighter(player, p.flags.pendingChoice or info.fighterChoice[1])
		p.flags.pendingChoice = nil
	end
	if info.oncePerPlayer then
		p.flags["bought_" .. key] = true
	end
	p.flags["receipt_" .. receipt.PurchaseId] = true
	granted[receipt.PurchaseId] = true
	DataService.save(player)
	Remotes.event("Notify"):FireClient(player, { text = "Thank you! Purchase delivered.", color = "#7dff8a" })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

----------------------------------------------------------------------
-- init
----------------------------------------------------------------------

function ShopService.init(deps)
	DataService = deps.DataService
	RewardService = deps.RewardService
	Remotes.func("Summon").OnServerInvoke = summon
	Remotes.func("BuyProduct").OnServerInvoke = buy
	MarketplaceService.ProcessReceipt = processReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		for name, info in Config.GamePasses do
			if info.id == passId then
				DataService.setPass(player, name, true)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		policyCache[player] = nil
	end)
	-- lobby objects that open screens on the client
	local lobby = workspace:FindFirstChild("Lobby")
	local function addPrompt(part, action, object, open, extra)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = action
		prompt.ObjectText = object
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = part
		prompt.Triggered:Connect(function(player)
			local msg = { open = open }
			for k, v in extra or {} do
				msg[k] = v
			end
			Remotes.event("Notify"):FireClient(player, msg)
		end)
	end
	if lobby then
		local shrines = lobby:FindFirstChild("SummonShrines", true)
		if shrines then
			for _, shrine in shrines:GetChildren() do
				local part = shrine:FindFirstChild("Prompt", true)
				if part then
					local b = banner(shrine:GetAttribute("Banner") or "standard")
					addPrompt(part, "Summon", b and b.name or "Shrine", "Summon", { banner = b and b.id })
				end
			end
		end
		for _, pair in { { "QuestBoard", "Quests" }, { "CodeBoard", "Codes" }, { "WhatsNewBoard", "Gifts" }, { "SenseiMaru", "Help" } } do
			local m = lobby:FindFirstChild(pair[1], true)
			local part = m and m:FindFirstChild("Prompt", true)
			if part then
				addPrompt(part, pair[1] == "SenseiMaru" and "Talk" or "Open", pair[2], pair[2])
			end
		end
	end
end

return ShopService
