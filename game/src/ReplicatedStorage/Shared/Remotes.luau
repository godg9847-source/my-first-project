--!strict
-- Creates (server) or finds (client) every RemoteEvent / RemoteFunction.
-- See game/docs/PROTOCOL.md for what each one carries.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local EVENTS = { "Data", "Notify", "Match", "MatchFx", "Queue", "MatchAction", "UIAction" }
local UNRELIABLE = { "MatchState" }
local FUNCTIONS = { "Summon", "RedeemCode", "BuyProduct" }

local folder: Folder? = nil

local function getFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local f = ReplicatedStorage:FindFirstChild("Remotes")
		if not f then
			f = Instance.new("Folder")
			f.Name = "Remotes"
			for _, n in EVENTS do
				local r = Instance.new("RemoteEvent")
				r.Name = n
				r.Parent = f
			end
			for _, n in UNRELIABLE do
				local r = Instance.new("UnreliableRemoteEvent")
				r.Name = n
				r.Parent = f
			end
			for _, n in FUNCTIONS do
				local r = Instance.new("RemoteFunction")
				r.Name = n
				r.Parent = f
			end
			f.Parent = ReplicatedStorage
		end
		folder = f :: Folder
	else
		folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	end
	return folder :: Folder
end

function Remotes.event(name: string): RemoteEvent
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.unreliable(name: string): UnreliableRemoteEvent
	return getFolder():WaitForChild(name) :: UnreliableRemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function Remotes.setup()
	getFolder()
end

return Remotes
