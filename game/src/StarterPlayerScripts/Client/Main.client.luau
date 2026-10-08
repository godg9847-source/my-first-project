--!nonstrict
-- Anime vs Anime — client entry point.
local Client = script.Parent
local State = require(Client.State)
State.init()

local LobbyUI = require(Client.UI.LobbyUI)
local MatchUI = require(Client.UI.MatchUI)

LobbyUI.init()
MatchUI.init()
