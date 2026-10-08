--!nonstrict
--[[
	LeaderboardService: global top-10 boards in the lobby.
	Boards are Models in Workspace.Lobby.Leaderboards with attribute Stat
	("Wins" or "Level") and a part "Screen" with SurfaceGui > Frame "List".
	Uses OrderedDataStores; in Studio without API access it shows local players only.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local LeaderboardService = {}

local DataService
local stores = {}
local nameCache = {}

local function getStore(stat)
	if stores[stat] == nil then
		local ok, s = pcall(function()
			return DataStoreService:GetOrderedDataStore("AvA_Top_" .. stat .. "_v1")
		end)
		stores[stat] = ok and s or false
	end
	return stores[stat] or nil
end

local STATS = { "Wins", "BestStreak", "Level", "Index" }

local function statValue(profile, stat)
	if stat == "Wins" then
		return profile.stats.wins
	elseif stat == "Level" then
		return profile.level
	elseif stat == "BestStreak" then
		return profile.stats.bestStreak or 0
	elseif stat == "Index" then
		local n = 0
		for _ in profile.indexEver or {} do
			n += 1
		end
		return n
	end
	return 0
end

local function userName(userId)
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	nameCache[userId] = ok and name or ("Player " .. userId)
	return nameCache[userId]
end

local function drawBoard(board, stat, rows)
	local screen = board:FindFirstChild("Screen", true)
	local list = screen and screen:FindFirstChild("List", true)
	if not list then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("TextLabel") or c:IsA("Frame") then
			c:Destroy()
		end
	end
	if not list:FindFirstChildOfClass("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = list
	end
	for i, row in rows do
		local label = Instance.new("TextLabel")
		label.LayoutOrder = i
		label.Size = UDim2.new(1, 0, 1 / (Config.LeaderboardSize + 1), -4)
		label.BackgroundTransparency = i % 2 == 0 and 0.85 or 0.7
		label.BackgroundColor3 = Color3.new(0, 0, 0)
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = i == 1 and Color3.fromRGB(255, 215, 80) or (i == 2 and Color3.fromRGB(220, 225, 235) or (i == 3 and Color3.fromRGB(230, 150, 90) or Color3.new(1, 1, 1)))
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Text = string.format("  #%d  %s  —  %d", i, row.name, row.value)
		label.Parent = list
	end
	if #rows == 0 then
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 0.15, 0)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Text = "Be the first on the board!"
		label.Parent = list
	end
end

local function refresh()
	local lobby = workspace:FindFirstChild("Lobby")
	local folder = lobby and lobby:FindFirstChild("Leaderboards", true)
	if not folder then
		return
	end
	-- write current players' stats
	for _, player in Players:GetPlayers() do
		local p = DataService.getProfile(player)
		if p then
			for _, stat in STATS do
				local s = getStore(stat)
				if s then
					pcall(function()
						s:SetAsync(tostring(player.UserId), statValue(p, stat))
					end)
				end
			end
		end
	end
	for _, board in folder:GetChildren() do
		local stat = board:GetAttribute("Stat") or "Wins"
		local rows = {}
		local s = getStore(stat)
		local ok = false
		if s then
			ok = pcall(function()
				local pages = s:GetSortedAsync(false, Config.LeaderboardSize)
				for _, entry in pages:GetCurrentPage() do
					table.insert(rows, { name = userName(tonumber(entry.key)), value = entry.value })
				end
			end)
		end
		if not ok then
			rows = {}
			for _, player in Players:GetPlayers() do
				local p = DataService.getProfile(player)
				if p then
					table.insert(rows, { name = player.DisplayName, value = statValue(p, stat) })
				end
			end
			table.sort(rows, function(a, b)
				return a.value > b.value
			end)
		end
		drawBoard(board, stat, rows)
	end
end

function LeaderboardService.init(deps)
	DataService = deps.DataService
	task.spawn(function()
		task.wait(5)
		while true do
			pcall(refresh)
			task.wait(Config.LeaderboardRefresh)
		end
	end)
end

return LeaderboardService
