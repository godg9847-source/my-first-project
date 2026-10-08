--!nonstrict
--[[
	State: the client's copy of its profile (from the "Data" remote) plus a few
	match flags. UI modules read State.data and listen to State.Changed.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local State = {}

local changed = Instance.new("BindableEvent")
State.Changed = changed.Event -- fires (data) whenever new profile data arrives
State.data = nil -- latest profile view (see docs/PROTOCOL.md)
State.inMatch = false -- set by MatchUI
State.openScreen = nil -- name of the open lobby screen, if any

local matchChanged = Instance.new("BindableEvent")
State.MatchChanged = matchChanged.Event -- fires (inMatch)

function State.setInMatch(v)
	if State.inMatch ~= v then
		State.inMatch = v
		matchChanged:Fire(v)
	end
end

-- open a lobby screen by name from anywhere ("Summon", "Index", "Quests", "Gifts", "Codes", "Shop", "Settings")
local openRequest = Instance.new("BindableEvent")
State.OpenRequested = openRequest.Event
function State.open(name)
	openRequest:Fire(name)
end

function State.init()
	Remotes.event("Data").OnClientEvent:Connect(function(data)
		State.data = data
		changed:Fire(data)
	end)
end

return State
