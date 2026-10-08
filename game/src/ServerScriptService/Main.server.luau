--!nonstrict
-- Anime vs Anime — server entry point. Starts every service in order.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
Remotes.setup()

local Server = script.Parent:WaitForChild("Server")
local DataService = require(Server.DataService)
local ShopService = require(Server.ShopService)
local RewardService = require(Server.RewardService)
local MatchService = require(Server.MatchService)
local QueueService = require(Server.QueueService)
local LeaderboardService = require(Server.LeaderboardService)
local LobbyService = require(Server.LobbyService)

DataService.init()
ShopService.init({ DataService = DataService, RewardService = RewardService })
RewardService.init({ DataService = DataService, ShopService = ShopService })
MatchService.init({ DataService = DataService, RewardService = RewardService })
QueueService.init(MatchService, DataService)
LeaderboardService.init({ DataService = DataService })
LobbyService.init({ MatchService = MatchService })

print("[Anime vs Anime] server ready")
