--!nonstrict
--[[
	QueueService: the match pads in Shonen Plaza (framework §3.2, §8.7).

	Pad Models in Workspace.Lobby.QueuePads have attributes Mode ("1v1", "2v2",
	"Bot"), Capacity and (bot pads) Difficulty, a "Pad" part to stand on and a
	"Display" part with SurfaceGui/TextLabel "Text". Players press E to join.
	  * a full pad starts a match (MatchService)
	  * a pad you wait on alone offers "Fight a Bot" after 45 s (25 s below level 5)
	  * QUICK MATCH (client button) puts you on the best pad; your very first
	    match is a tutorial against the Training Bot
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)

local QueueService = {}

local pads = {}
local playerPad = {} -- [Player] = pad state
local MatchService, DataService

local MC = Config.Match

local function padLabel(pad)
	if pad.mode == "Bot" then
		local d = pad.difficulty or "Normal"
		if d == "TryOut" then
			return "TRY-OUT · ANY FIGHTER VS BOT"
		end
		return "PRACTICE · " .. string.upper(d) .. " BOT"
	end
	local win = MC.Payouts[pad.mode] and MC.Payouts[pad.mode].win or 100
	return string.format("%d/%d PLAYERS | WIN %d+", #pad.players, pad.capacity, win)
end

local function offerSeconds(player)
	local p = DataService.getProfile(player)
	if p and p.level < 5 then
		return MC.BotOfferSecondsNewPlayer
	end
	return MC.BotOfferSeconds
end

local function refresh(pad)
	local display = pad.model:FindFirstChild("Display", true)
	local label = display and display:FindFirstChild("Text", true)
	if label and label:IsA("TextLabel") then
		label.Text = padLabel(pad)
	end
	if pad.prompt then
		pad.prompt.ObjectText = padLabel(pad)
	end
	local ev = Remotes.event("Queue")
	for _, p in pad.players do
		local waited = os.clock() - (pad.since[p] or os.clock())
		local offerAt = offerSeconds(p)
		ev:FireClient(p, {
			inQueue = true,
			mode = pad.mode,
			count = #pad.players,
			capacity = pad.capacity,
			padName = pad.model.Name,
			waitTime = waited,
			botOffer = waited >= offerAt,
			botOfferIn = math.max(0, offerAt - waited),
		})
	end
end

local function standCFrame(pad, index)
	local part = pad.model:FindFirstChild("Pad", true)
	if not part then
		return nil
	end
	local n = pad.capacity
	local spread = math.min(part.Size.X, part.Size.Z) * 0.3
	local offset = 0
	if n > 1 then
		offset = ((index - 1) / (n - 1) - 0.5) * 2 * spread
	end
	return part.CFrame * CFrame.new(offset, part.Size.Y / 2 + 3, 0)
end

function QueueService.leave(player, silent)
	local pad = playerPad[player]
	if not pad then
		return
	end
	playerPad[player] = nil
	pad.since[player] = nil
	local idx = table.find(pad.players, player)
	if idx then
		table.remove(pad.players, idx)
	end
	if not silent and player.Parent then
		Remotes.event("Queue"):FireClient(player, { inQueue = false })
	end
	refresh(pad)
end

function QueueService.isQueued(player)
	return playerPad[player] ~= nil
end

local function launch(pad, group, mode, opts)
	for _, p in group do
		playerPad[p] = nil
		pad.since[p] = nil
		Remotes.event("Queue"):FireClient(p, { inQueue = false })
		local idx = table.find(pad.players, p)
		if idx then
			table.remove(pad.players, idx)
		end
	end
	refresh(pad)
	local ok, err = MatchService.startMatch(group, mode, opts)
	if not ok then
		for _, p in group do
			Remotes.event("Notify"):FireClient(p, { text = err or "No arena free, try again!", color = "#ff6b6b" })
		end
	end
end

local function startIfFull(pad)
	if pad.mode == "Bot" then
		if #pad.players >= 1 then
			local d = pad.difficulty or "Normal"
			launch(pad, { pad.players[1] }, "1v1", { bots = 1, practice = true, difficulty = d })
		end
		return
	end
	if #pad.players >= pad.capacity then
		launch(pad, table.clone(pad.players), pad.mode, {})
	end
end

function QueueService.join(player, pad)
	if playerPad[player] == pad or MatchService.isInMatch(player) then
		return
	end
	local profile = DataService.getProfile(player)
	if pad.mode == "2v2" and profile and profile.level < Config.Unlocks["2v2"] then
		Remotes.event("Notify"):FireClient(player, { text = "2v2 unlocks at level " .. Config.Unlocks["2v2"] .. "!", color = "#ff6b6b" })
		return
	end
	if playerPad[player] then
		QueueService.leave(player, true)
	end
	if #pad.players >= pad.capacity and pad.mode ~= "Bot" then
		Remotes.event("Notify"):FireClient(player, { text = "This pad is full!", color = "#ff6b6b" })
		return
	end
	table.insert(pad.players, player)
	playerPad[player] = pad
	pad.since[player] = os.clock()
	local char = player.Character
	local cf = standCFrame(pad, #pad.players)
	if char and cf then
		char:PivotTo(cf)
	end
	refresh(pad)
	startIfFull(pad)
end

-- QUICK MATCH: first match ever = tutorial vs the Training Bot; else the fullest open 1v1 pad
function QueueService.quickMatch(player)
	if MatchService.isInMatch(player) then
		return
	end
	local profile = DataService.getProfile(player)
	if profile and profile.stats.matches == 0 and not profile.flags.tutorialDone then
		profile.flags.tutorialDone = true
		QueueService.leave(player, true)
		local ok, err = MatchService.startMatch({ player }, "1v1", { bots = 1, practice = true, difficulty = "Easy", tutorial = true })
		if not ok then
			Remotes.event("Notify"):FireClient(player, { text = err, color = "#ff6b6b" })
		end
		return
	end
	local best
	for _, pad in pads do
		if pad.mode == "1v1" and #pad.players < pad.capacity then
			if not best or #pad.players > #best.players then
				best = pad
			end
		end
	end
	if best then
		QueueService.join(player, best)
	else
		Remotes.event("Notify"):FireClient(player, { text = "All pads are busy — try again in a moment!", color = "#ff6b6b" })
	end
end

-- "Fight a Bot" from the queue panel once the offer time has passed
function QueueService.fightBot(player)
	local pad = playerPad[player]
	if not pad then
		return
	end
	local waited = os.clock() - (pad.since[player] or os.clock())
	if waited < offerSeconds(player) - 0.5 then
		return
	end
	launch(pad, { player }, "1v1", { bots = 1, practice = true, difficulty = "Normal" })
end

local function setupPad(model)
	local mode = model:GetAttribute("Mode") or "1v1"
	local capacity = model:GetAttribute("Capacity") or (mode == "2v2" and 4 or (mode == "Bot" and 1 or 2))
	local part = model:FindFirstChild("Pad", true)
	if not part then
		warn("[QueueService] pad without a 'Pad' part:", model:GetFullName())
		return
	end
	local pad = { model = model, mode = mode, capacity = capacity, difficulty = model:GetAttribute("Difficulty"), players = {}, since = {} }
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "JoinPrompt"
	prompt.ActionText = mode == "Bot" and "Practice" or ("Join " .. mode)
	prompt.ObjectText = padLabel(pad)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	pad.prompt = prompt
	prompt.Triggered:Connect(function(player)
		QueueService.join(player, pad)
	end)
	table.insert(pads, pad)
	refresh(pad)
end

function QueueService.init(matchService, dataService)
	MatchService = matchService
	DataService = dataService
	local lobby = workspace:WaitForChild("Lobby", 10)
	local folder = lobby and lobby:FindFirstChild("QueuePads", true)
	if not folder then
		warn("[QueueService] Workspace.Lobby.QueuePads not found — no queue pads!")
	else
		for _, m in folder:GetChildren() do
			if m:IsA("Model") then
				setupPad(m)
			end
		end
	end

	Remotes.event("MatchAction").OnServerEvent:Connect(function(player, msg)
		if type(msg) ~= "table" then
			return
		end
		if msg.action == "leaveQueue" then
			QueueService.leave(player)
		elseif msg.action == "quickMatch" then
			QueueService.quickMatch(player)
		elseif msg.action == "fightBot" then
			QueueService.fightBot(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		QueueService.leave(player, true)
	end)

	-- leave if you walk away from the pad; refresh timers
	task.spawn(function()
		while true do
			task.wait(1)
			for player, pad in playerPad do
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local part = pad.model:FindFirstChild("Pad", true)
				if not hrp or not part or (hrp.Position - part.Position).Magnitude > math.max(part.Size.X, part.Size.Z) + 12 then
					QueueService.leave(player)
				end
			end
			for _, pad in pads do
				if #pad.players > 0 then
					refresh(pad)
				end
			end
		end
	end)
end

return QueueService
