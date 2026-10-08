--!nonstrict
--[[
	MatchService: runs a whole match (design framework §3, §8).

	Per round:
	  PICK    3 cards from your collection. Round 1 is a blind pick; from round 2
	          the last round's winner (Champion) locks first and the loser
	          (Challenger) sees it and counter-picks. First reroll per match is
	          free, then gems. Hero Pick (any fighter you own) once per match.
	  REVEAL  cards flip
	  AIM     drag the launch direction, Lock Aim
	  FIGHT   the simulation runs by itself; inputs: ULT tap, Tag Out (first 6 s)
	  FINISH  the winning fighter flies into the losing player(s): −1 heart
	First side to lose all hearts loses. Rewards are paid on the Results screen.

	Arenas: templates from Workspace.Arenas are moved to ServerStorage at start;
	each match clones one into a free slot high in the sky (Y = 1000).
	Bots fill empty seats (Training Dojo pads, "Fight a Bot", tutorial).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Fighters = require(Shared.Fighters)
local Remotes = require(Shared.Remotes)

local Sim = ServerScriptService:WaitForChild("Sim")
local Battle = require(Sim.Battle)
local Renderer = require(script.Parent.Renderer)

local MatchService = {}

local DataService, RewardService -- injected in init
local templates = {} -- arena templates (in ServerStorage)
local slots = {} -- [i] = true when used
local matches = {}
local playerMatch = {} -- [Player] = match
local lastArena = {} -- [userId] = ArenaId (never the same arena twice in a row)
local nextMatchId = 0
local botCounter = 0

local MC = Config.Match
local SLOT_Y = 1000
local SLOT_SPACING = 220

----------------------------------------------------------------------
-- module loaders (cached)
----------------------------------------------------------------------

local abilityCache = {}
local function loadAbilities(id)
	if abilityCache[id] ~= nil then
		return abilityCache[id] or nil
	end
	local folder = Sim:FindFirstChild("Abilities")
	local mod = folder and folder:FindFirstChild(id)
	if mod then
		local ok, res = pcall(require, mod)
		if ok then
			abilityCache[id] = res
			return res
		end
		warn("[MatchService] ability module error for", id, res)
	else
		warn("[MatchService] no ability module for", id)
	end
	abilityCache[id] = false
	return nil
end

local gimmickCache = {}
local function loadGimmick(name)
	if not name or name == "none" or name == "pillars" then
		return nil
	end
	if gimmickCache[name] ~= nil then
		return gimmickCache[name] or nil
	end
	local folder = Sim:FindFirstChild("Arenas")
	local mod = folder and folder:FindFirstChild(name)
	local res = false
	if mod then
		local ok, m = pcall(require, mod)
		if ok then
			res = m
		else
			warn("[MatchService] gimmick error", name, m)
		end
	end
	gimmickCache[name] = res
	return res or nil
end

----------------------------------------------------------------------
-- arenas
----------------------------------------------------------------------

local function floorTop(model)
	local floor = model:FindFirstChild("Floor", true)
	if not floor then
		return nil
	end
	return floor.Position + Vector3.new(0, floor.Size.Y / 2, 0)
end

local function scanArenas()
	local folder = workspace:WaitForChild("Arenas", 10)
	if not folder then
		warn("[MatchService] Workspace.Arenas not found!")
		return
	end
	local store = Instance.new("Folder")
	store.Name = "ArenaTemplates"
	store.Parent = ServerStorage
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and floorTop(m) then
			m.Parent = store
			table.insert(templates, m)
		elseif m:IsA("Model") then
			warn("[MatchService] arena without Floor:", m:GetFullName())
		end
	end
	folder.Name = "LiveArenas" -- clones go here
	if #templates == 0 then
		warn("[MatchService] no arena templates!")
	end
end

local function pickTemplate(mode, players)
	local wantMode = mode == "2v2" and "2v2" or "1v1"
	local neutral, gimmick, any = {}, {}, {}
	local avoid = {}
	for _, pl in players do
		if lastArena[pl.UserId] then
			avoid[lastArena[pl.UserId]] = true
		end
	end
	for _, t in templates do
		local m = t:GetAttribute("Mode") or "1v1"
		if m == wantMode then
			table.insert(any, t)
			if not avoid[t:GetAttribute("ArenaId") or t.Name] then
				if (t:GetAttribute("Pool") or "neutral") == "gimmick" then
					table.insert(gimmick, t)
				else
					table.insert(neutral, t)
				end
			end
		end
	end
	local pool
	if #gimmick > 0 and (#neutral == 0 or math.random() < 0.5) then
		pool = gimmick
	elseif #neutral > 0 then
		pool = neutral
	else
		pool = (#any > 0) and any or templates
	end
	return pool[math.random(1, #pool)]
end

local function readArena(model, origin)
	local data = {
		halfX = model:GetAttribute("HalfX") or 24,
		halfY = model:GetAttribute("HalfY") or 24,
		gimmick = model:GetAttribute("Gimmick") or "none",
		theme = model:GetAttribute("Theme") or model.Name,
		arenaId = model:GetAttribute("ArenaId") or model.Name,
		obstacles = {},
		portals = {},
		puddles = {},
	}
	local function circles(folderName, into)
		local f = model:FindFirstChild(folderName)
		if f then
			for _, p in f:GetDescendants() do
				if p:IsA("BasePart") then
					local r = p:GetAttribute("Radius") or (math.min(p.Size.Y, p.Size.Z) / 2)
					table.insert(into, { x = p.Position.X - origin.X, y = p.Position.Z - origin.Z, r = r, name = p.Name })
				end
			end
		end
	end
	circles("Obstacles", data.obstacles)
	circles("Portals", data.portals)
	circles("Puddles", data.puddles)
	table.sort(data.portals, function(a, b)
		return a.x < b.x
	end)
	return data
end

-- clone a template into a free sky slot
local function takeArena(mode, players)
	local template = pickTemplate(mode, players)
	if not template then
		return nil
	end
	local slot = 1
	while slots[slot] do
		slot += 1
	end
	slots[slot] = true
	local clone = template:Clone()
	local col = (slot - 1) % 6
	local row = math.floor((slot - 1) / 6)
	local target = Vector3.new(col * SLOT_SPACING, SLOT_Y, row * SLOT_SPACING + 600)
	local top = floorTop(clone)
	clone:PivotTo(clone:GetPivot() + (target - top))
	clone.Parent = workspace:FindFirstChild("LiveArenas") or workspace
	local origin = floorTop(clone)
	local arena = {
		model = clone,
		slot = slot,
		origin = origin,
		stand = { clone:FindFirstChild("Stand1", true), clone:FindFirstChild("Stand2", true) },
		camera = clone:FindFirstChild("CameraPoint", true),
	}
	arena.data = readArena(clone, origin)
	for _, pl in players do
		lastArena[pl.UserId] = arena.data.arenaId
	end
	return arena
end

local function releaseArena(arena)
	if arena.model then
		arena.model:Destroy()
	end
	slots[arena.slot] = nil
end

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------

local function sendTo(p, msg)
	if p.player and p.player.Parent then
		Remotes.event("Match"):FireClient(p.player, msg)
	end
end

local function send(match, msg, onlyTeam)
	for _, p in match.participants do
		if onlyTeam == nil or p.team == onlyTeam then
			sendTo(p, msg)
		end
	end
end

local function notify(player, text, color)
	if player and player.Parent then
		Remotes.event("Notify"):FireClient(player, { text = text, color = color })
	end
end

local function now()
	return workspace:GetServerTimeNow()
end

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function quest(p, kind, amount)
	if p.player and RewardService and not p.noQuests then
		RewardService.progress(p.player, kind, amount or 1)
	end
end

-- every fighter this participant may draw from
local function ownedList(p)
	if p.tryOut then
		local all = {}
		for _, f in Fighters.List do
			table.insert(all, f.id)
		end
		return all
	end
	if p.isBot then
		local pool = {}
		for _, f in Fighters.List do
			local okRarity = (p.difficulty == "Hard") or f.rarity == "Rare" or f.rarity == "Epic"
			if okRarity then
				table.insert(pool, f.id)
			end
		end
		return pool
	end
	local list = DataService.ownedFighters(p.player)
	if #list < MC.OptionsPerRound then
		-- "Loaner" fighters so 3 cards can always be dealt
		for _, id in Config.StarterFighters do
			if not table.find(list, id) then
				table.insert(list, id)
			end
		end
	end
	return list
end

local function drawOptions(p, exclude)
	local all = ownedList(p)
	local list = {}
	for _, id in all do
		if not (exclude and #all >= 6 and table.find(exclude, id)) then
			table.insert(list, id)
		end
	end
	shuffle(list)
	local opts = {}
	for i = 1, math.min(MC.OptionsPerRound, #list) do
		table.insert(opts, list[i])
	end
	local k = 1
	while #opts < MC.OptionsPerRound do
		table.insert(opts, all[k] or Config.StarterFighters[1])
		k += 1
	end
	return opts
end

local function roleEdge(attackerId, targetId)
	local a, t = Fighters.get(attackerId), Fighters.get(targetId)
	local edge = Battle.ROLE_EDGE[a.role]
	return edge ~= nil and edge[t.role] == true
end

----------------------------------------------------------------------
-- avatars on the balconies
----------------------------------------------------------------------

local function teammates(match, team)
	local out = {}
	for _, q in match.participants do
		if q.team == team then
			table.insert(out, q)
		end
	end
	return out
end

local function standPosition(match, p)
	local stand = match.arena.stand[p.team]
	if not stand then
		local o = match.arena.origin
		return o + Vector3.new(0, 6, (p.team == 1 and -1 or 1) * (match.arena.data.halfY + 8))
	end
	local mates = teammates(match, p.team)
	local idx = table.find(mates, p) or 1
	local offset = 0
	if #mates > 1 then
		offset = (idx == 1) and -2.5 or 2.5
	end
	return (stand.CFrame * CFrame.new(offset, stand.Size.Y / 2 + 3, 0)).Position
end

local function makeBotDummy(match, p)
	local m = Instance.new("Model")
	m.Name = p.name
	local function part(name, size, color, mat, shape)
		local x = Instance.new("Part")
		x.Name = name
		x.Size = size
		x.Color = color
		x.Material = mat or Enum.Material.SmoothPlastic
		x.Shape = shape or Enum.PartType.Block
		x.Anchored = true
		x.CanCollide = false
		x.Parent = m
		return x
	end
	part("Body", Vector3.new(2, 2.5, 1.2), Color3.fromRGB(120, 125, 140), Enum.Material.Metal)
	part("Head", Vector3.one * 1.8, Color3.fromRGB(160, 170, 190), Enum.Material.Metal, Enum.PartType.Ball)
	part("Eye", Vector3.new(1.2, 0.25, 0.2), Color3.fromRGB(255, 60, 60), Enum.Material.Neon)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 30)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = p.name
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.3
	t.Parent = bb
	bb.Parent = m.Head
	m.PrimaryPart = m.Body
	m.Parent = match.folder
	return m
end

local function placeAvatar(match, p)
	local pos = standPosition(match, p)
	local o = match.arena.origin
	local cf = CFrame.lookAt(pos, Vector3.new(o.X, pos.Y, o.Z))
	if p.isBot then
		p.dummy = p.dummy or makeBotDummy(match, p)
		local m = p.dummy
		m.Body.CFrame = cf * CFrame.new(0, -1.2, 0)
		m.Head.CFrame = cf * CFrame.new(0, 0.95, 0)
		m.Eye.CFrame = cf * CFrame.new(0, 1.05, -0.85)
		return
	end
	local char = p.player and p.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		char:PivotTo(cf)
		hrp.Anchored = true
	end
end

local function releaseAvatar(p)
	local char = p.player and p.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		hrp.Anchored = false
	end
end

local function avatarPosition(match, p)
	if p.isBot then
		return p.dummy and p.dummy.Head.Position or standPosition(match, p)
	end
	local char = p.player and p.player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and hrp.Position or standPosition(match, p)
end

local function lobbySpawn()
	local lobby = workspace:FindFirstChild("Lobby")
	if lobby then
		local spawns = {}
		for _, d in lobby:GetDescendants() do
			if d:IsA("SpawnLocation") then
				table.insert(spawns, d)
			end
		end
		if #spawns > 0 then
			local s = spawns[math.random(1, #spawns)]
			return s.CFrame + Vector3.new(0, 4, 0)
		end
	end
	return CFrame.new(0, 10, 0)
end

----------------------------------------------------------------------
-- waiting helper
----------------------------------------------------------------------

local function waitUntil(match, deadline, predicate)
	while now() < deadline do
		if match.aborted then
			return false
		end
		if predicate and predicate() then
			return true
		end
		task.wait(0.1)
	end
	return predicate and predicate() or false
end

----------------------------------------------------------------------
-- PICK
----------------------------------------------------------------------

local function allLocked(match, field, team)
	for _, p in match.participants do
		if (team == nil or p.team == team) and not p[field] then
			return false
		end
	end
	return true
end

function MatchService.lockPick(match, p, fighterId, how)
	if p.pickLocked or not Fighters.get(fighterId) then
		return
	end
	p.pick = fighterId
	p.pickLocked = true
	p.heroPickRound = (how == "hero")
	if how ~= "timeout" then
		p.inputs += 1
	end
	sendTo(p, { phase = "picked", fighterId = fighterId })
	-- teammates always see each other; enemies only see Champion picks (counter-pick)
	for _, q in match.participants do
		if q ~= p then
			if q.team == p.team or match.championTeam == p.team then
				sendTo(q, { phase = "opponentPicked", team = p.team, userId = p.userId, fighterId = fighterId, teammate = q.team == p.team })
			end
		end
	end
end

local function sendPick(match, p, endsAt, keepTimer)
	if p.isBot then
		return
	end
	local profile = DataService.getProfile(p.player)
	local freeLeft = math.max(0, p.freeRerolls - p.rerollsUsedFree)
	sendTo(p, {
		phase = "pick",
		round = match.round,
		endsAt = endsAt,
		keepTimer = keepTimer,
		options = p.options,
		heroPickAvailable = not p.heroPickUsed,
		freePickAvailable = not p.heroPickUsed, -- (older UI name)
		rerollCost = freeLeft > 0 and 0 or MC.RerollGemCost,
		rerollFree = freeLeft > 0,
		paidRerollsLeft = MC.MaxPaidRerollsPerRound - p.paidRerollsThisRound,
		gems = profile and profile.gems or 0,
		hearts = match.hearts,
		role = match.championTeam == nil and "blind" or (match.championTeam == p.team and "champion" or "challenger"),
	})
end

local function botPick(match, p)
	local choice = p.options[math.random(1, #p.options)]
	if p.difficulty == "Hard" and match.championTeam and match.championTeam ~= p.team then
		-- counter-pick the revealed Champion fighter if possible
		for _, q in match.participants do
			if q.team ~= p.team and q.pick then
				for _, opt in p.options do
					if roleEdge(opt, q.pick) then
						choice = opt
					end
				end
			end
		end
	end
	MatchService.lockPick(match, p, choice, "bot")
end

local function pickPhase(match)
	match.phase = "pick"
	local start = now()
	local deadline = start + MC.PickTime
	local champDeadline = start + MC.ChampionPickTime
	for _, p in match.participants do
		p.pick = nil
		p.pickLocked = false
		p.heroPickRound = false
		p.paidRerollsThisRound = 0
		p.options = drawOptions(p)
		p.dealt = table.clone(p.options)
		local isChampion = match.championTeam == p.team
		sendPick(match, p, isChampion and champDeadline or deadline)
		if p.isBot then
			local delay = isChampion and math.random(10, 40) / 10 or math.random(25, 70) / 10
			task.delay(delay, function()
				if match.phase == "pick" and not p.pickLocked then
					botPick(match, p)
				end
			end)
		end
	end
	if match.championTeam then
		-- the Champion must lock within 10 s (timeout = left card)
		waitUntil(match, champDeadline, function()
			return allLocked(match, "pickLocked", match.championTeam)
		end)
		for _, p in match.participants do
			if p.team == match.championTeam and not p.pickLocked then
				MatchService.lockPick(match, p, p.options[1], "timeout")
			end
		end
	end
	waitUntil(match, deadline, function()
		return allLocked(match, "pickLocked")
	end)
	for _, p in match.participants do
		if not p.pickLocked then
			MatchService.lockPick(match, p, p.options[1], "timeout")
		end
	end
	-- REVEAL
	local reveal = {}
	for _, p in match.participants do
		table.insert(reveal, { team = p.team, userId = p.userId, name = p.name, fighterId = p.pick })
	end
	send(match, { phase = "reveal", picks = reveal })
	task.wait(MC.RevealTime)
end

----------------------------------------------------------------------
-- AIM
----------------------------------------------------------------------

local function startPositions(match)
	local pos = {}
	for team = 1, 2 do
		local mates = teammates(match, team)
		local sign = team == 1 and -1 or 1
		for i, p in mates do
			if #mates > 1 then
				pos[p] = { x = (i == 1) and -8 or 8, y = sign * 18 }
			else
				pos[p] = { x = 0, y = sign * MC.SpawnY }
			end
		end
	end
	return pos
end

local function aimPhase(match)
	match.phase = "aim"
	local deadline = now() + MC.AimTime
	local starts = startPositions(match)
	match.starts = starts
	local data = match.arena.data
	local battle = Battle.new({
		fighters = Fighters.ById,
		abilities = loadAbilities,
		gimmick = loadGimmick(data.gimmick),
		config = Config.Battle,
		seed = math.random(1, 2 ^ 30),
		halfX = data.halfX,
		halfY = data.halfY,
		obstacles = data.obstacles,
		arenaData = data,
		finalClash = match.finalClash,
	})
	match.battle = battle
	match.renderer = Renderer.new(battle, match.arena.origin, match.folder)
	local picks = {}
	for _, p in match.participants do
		p.aimLocked = false
		local s = starts[p]
		-- default aim: at the enemy spawn
		local enemyY = -s.y
		p.aim = math.atan2(enemyY - s.y, 0 - s.x)
		local profile = p.player and DataService.getProfile(p.player)
		p.unit = battle:addUnit({
			team = p.team,
			fighterId = p.pick,
			x = s.x,
			y = s.y,
			dirX = math.cos(p.aim),
			dirY = math.sin(p.aim),
			ownerId = p.userId,
			instantUlt = profile and profile.settings and profile.settings.instantUlt or false,
		})
		if match.finalClash then
			p.unit.hp = p.unit.maxHp * 0.5
		end
		if match.hearts[p.team] == 1 then
			p.unit.charge = MC.LastHeartCharge -- Last Heart Spirit
		end
		if match.tutorial and not p.isBot then
			p.unit.charge = 80
		end
		table.insert(picks, { team = p.team, userId = p.userId, fighterId = p.pick, name = p.name, unitId = p.unit.id, start = s })
		if p.isBot then
			task.delay(math.random(10, 40) / 10, function()
				local e = starts[p]
				p.aim = math.atan2(-e.y - e.y, -e.x) + math.rad(math.random(-35, 35))
				p.aimLocked = true
			end)
		end
	end
	if match.tutorial then
		for _, p in match.participants do
			if p.isBot and p.unit then
				p.unit.hp = 450
				p.unit.maxHp = 450
			end
		end
	end
	match.renderer:frame(0)
	local aimConn = RunService.Heartbeat:Connect(function(dt)
		for _, p in match.participants do
			if p.unit then
				p.unit.vx, p.unit.vy = math.cos(p.aim), math.sin(p.aim)
			end
		end
		if match.renderer then
			match.renderer:frame(dt)
		end
	end)
	for _, p in match.participants do
		sendTo(p, {
			phase = "aim",
			round = match.round,
			endsAt = deadline,
			myStart = starts[p],
			myAngle = p.aim,
			fighterId = p.pick,
			picks = picks,
			origin = match.arena.origin,
			half = math.min(data.halfX, data.halfY),
			halfX = data.halfX,
			halfY = data.halfY,
			obstacles = data.obstacles,
		})
	end
	waitUntil(match, deadline, function()
		return allLocked(match, "aimLocked")
	end)
	aimConn:Disconnect()
	for _, p in match.participants do
		local u = p.unit
		u.vx, u.vy = math.cos(p.aim) * u.baseSpeed, math.sin(p.aim) * u.baseSpeed
	end
end

----------------------------------------------------------------------
-- FIGHT
----------------------------------------------------------------------

-- bots tap their ULT with different skill levels
local function botUlt(match, p, battle)
	local u = p.unit
	if not u or not u.alive or not u.ultReady then
		p.botUltAt = nil
		return
	end
	if p.difficulty == "Easy" then
		return -- never taps: auto-fire only
	end
	if p.difficulty == "Hard" then
		local t, d = battle:nearestEnemy(u)
		if t and (d < 16 or t.hp / t.maxHp < 0.25) then
			battle:requestUlt(p.userId)
		end
		return
	end
	p.botUltAt = p.botUltAt or (battle.time + math.random(10, 40) / 10)
	if battle.time >= p.botUltAt then
		battle:requestUlt(p.userId)
		p.botUltAt = nil
	end
end

local function fightPhase(match)
	match.phase = "launch"
	send(match, { phase = "launch", round = match.round })
	task.wait(MC.LaunchTime)
	match.phase = "fight"
	match.fightStart = os.clock()
	local battle = match.battle
	local renderer = match.renderer
	send(match, { phase = "fight", round = match.round, tagOutWindow = MC.TagOutWindow, tagOutCost = MC.TagOutGemCost })
	battle:start()
	local stepDt = 1 / (Config.Battle.TickRate or 60)
	local acc, stateTimer = 0, 0
	local stateEvent = Remotes.unreliable("MatchState")
	local fxEvent = Remotes.event("MatchFx")
	local done = Instance.new("BindableEvent")
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if match.aborted then
			conn:Disconnect()
			done:Fire()
			return
		end
		acc += math.min(dt, 0.1)
		local steps = 0
		while acc >= stepDt and steps < 4 and not battle.result do
			battle:step(stepDt)
			acc -= stepDt
			steps += 1
		end
		for _, p in match.participants do
			if p.isBot then
				botUlt(match, p, battle)
			end
		end
		renderer:frame(dt)
		stateTimer += dt
		if stateTimer >= 0.1 then
			stateTimer = 0
			local snap = battle:snapshot()
			for _, p in match.participants do
				if p.player and p.player.Parent then
					stateEvent:FireClient(p.player, snap)
				end
			end
		end
		local cfx = renderer:takeClientFx()
		if #cfx > 0 then
			for _, p in match.participants do
				if p.player and p.player.Parent then
					fxEvent:FireClient(p.player, cfx)
				end
			end
		end
		if battle.result then
			conn:Disconnect()
			done:Fire()
		end
	end)
	done.Event:Wait()
	done:Destroy()
	if #battle.errors > 0 then
		warn(string.format("[MatchService] %d ability errors this round (first: %s)", #battle.errors, battle.errors[1]))
	end
end

----------------------------------------------------------------------
-- FINISHER
----------------------------------------------------------------------

local function flyInto(root, goal, duration)
	local start = root.Position
	local mid = (start + goal) / 2 + Vector3.new(0, 16, 0)
	local t1 = TweenService:Create(root, TweenInfo.new(duration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(mid) })
	t1:Play()
	t1.Completed:Wait()
	local t2 = TweenService:Create(root, TweenInfo.new(duration * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(goal) })
	t2:Play()
	t2.Completed:Wait()
	local boom = Instance.new("Explosion")
	boom.Position = goal
	boom.BlastRadius = 0
	boom.BlastPressure = 0
	boom.DestroyJointRadiusPercent = 0
	boom.ExplosionType = Enum.ExplosionType.NoCraters
	boom.Parent = workspace
end

local function finisherPhase(match)
	match.phase = "finisher"
	local battle = match.battle
	local result = battle.result
	if not result then
		return
	end
	local losers = {}
	if result.doubleKO then
		losers = { 1, 2 }
	else
		losers = { result.loserTeam }
	end
	local final = false
	for _, t in losers do
		if match.hearts[t] <= 1 then
			final = true
		end
	end
	local total = final and MC.FinalFinisherTime or MC.FinisherTime
	send(match, {
		phase = "finisher",
		winnerTeam = result.winnerTeam,
		loserTeam = result.loserTeam,
		doubleKO = result.doubleKO,
		reason = result.reason,
		final = final,
		hearts = match.hearts,
	})
	local t0 = os.clock()
	if not result.doubleKO then
		task.wait(1.2)
		-- each surviving winner fighter flies at one losing avatar (2v2)
		local winners = {}
		for _, u in battle.units do
			if u.team == result.winnerTeam and not u.isMinion then
				local model = match.renderer:getUnitModel(u.id)
				if model and model.PrimaryPart then
					table.insert(winners, model.PrimaryPart)
				end
			end
		end
		local targets = teammates(match, result.loserTeam)
		if #winners > 0 then
			local threads = {}
			for i, t in targets do
				local root = winners[((i - 1) % #winners) + 1]
				table.insert(threads, task.spawn(function()
					if i > #winners then
						task.wait(0.8)
					end
					flyInto(root, avatarPosition(match, t), 1.2)
				end))
			end
			task.wait(1.4 + (#targets > #winners and 0.8 or 0))
		end
	end
	for _, t in losers do
		match.hearts[t] = math.max(0, match.hearts[t] - 1)
	end
	send(match, { phase = "heartLost", loserTeam = result.loserTeam, doubleKO = result.doubleKO, hearts = match.hearts })
	local left = total - (os.clock() - t0)
	if left > 0 then
		task.wait(left)
	end
	-- round recap + quests
	local stats = {}
	for _, p in match.participants do
		local u = p.unit
		if u then
			local won = not result.doubleKO and p.team == result.winnerTeam
			table.insert(stats, { userId = p.userId, team = p.team, fighterId = p.pick, damage = math.floor(u.stats.damageDealt), ults = u.stats.casts2, focused = u.stats.focused })
			p.matchDamage += u.stats.damageDealt
			if won then
				p.roundsWon += 1
			end
			if p.player then
				quest(p, "damage", math.floor(u.stats.damageDealt))
				if u.stats.focused > 0 then
					quest(p, "focusUlt", u.stats.focused)
				end
				if (u.stats.slams or 0) > 0 then
					quest(p, "slam", u.stats.slams)
				end
				if won then
					local f = Fighters.get(p.pick)
					if f.rarity == "Rare" then
						quest(p, "rareRound")
					end
					if match.championTeam and match.championTeam ~= p.team then
						quest(p, "challengerRound")
					end
					if p.heroPickRound then
						quest(p, "heroPickRound")
					end
					for _, q in match.participants do
						if q.team ~= p.team and roleEdge(p.pick, q.pick) then
							quest(p, "edgeWin")
							break
						end
					end
				end
			end
		end
	end
	match.lastResult = result
	send(match, { phase = "recap", hearts = match.hearts, stats = stats })
	task.wait(MC.RecapTime)
	match.renderer:destroy()
	match.renderer = nil
	match.battle = nil
	for _, p in match.participants do
		p.unit = nil
		p.taggedThisRound = false
	end
end

----------------------------------------------------------------------
-- RESULTS
----------------------------------------------------------------------

local function payout(match, p, won, reason)
	local profile = DataService.getProfile(p.player)
	if not profile then
		return 0, 0, {}
	end
	local key = match.practice and "Bot" or match.mode
	local table_ = MC.Payouts[key] or MC.Payouts["1v1"]
	local lines = {}
	local coins = 0
	local xp = 0
	local leaver = reason == "forfeit" and not won
	local afk = p.inputs < 2
	if match.tryOut or leaver then
		return 0, 0, { { "No rewards", 0 } }
	end
	local botCapped = false
	if key == "Bot" then
		botCapped = not DataService.useBotPayout(p.player)
	end
	if not botCapped and not (afk and not won) then
		coins = won and table_.win or table_.loss
		table.insert(lines, { won and "Victory" or "Match played", coins })
		local perRound = (table_.perRound or 0) * p.roundsWon
		if perRound > 0 then
			coins += perRound
			table.insert(lines, { "Rounds won", perRound })
		end
		if won and not match.practice then
			local streak = (profile.stats.streak or 0) + 1
			local bonus = math.min(MC.WinStreakMax, MC.WinStreakBonus * math.max(0, streak - 1))
			if bonus > 0 then
				coins += bonus
				table.insert(lines, { "Win streak", bonus })
			end
		end
	end
	local firstWin = won and not match.practice and DataService.claimFirstWin(p.player)
	if firstWin then
		coins += MC.FirstWinBonus
		table.insert(lines, { "First win of the day", MC.FirstWinBonus })
	end
	if not (afk and not won) then
		xp = (won and MC.XpWin or MC.XpLoss) + MC.XpPerRound * p.roundsWon
		if firstWin then
			xp *= 2
		end
	end
	return coins, xp, lines
end

local function finish(match, winnerTeam, reason)
	if match.finished then
		return
	end
	match.finished = true
	match.phase = "results"
	for _, p in match.participants do
		if p.player and p.player.Parent and not p.left then
			local won = p.team == winnerTeam
			local coins, xp, lines = payout(match, p, won, reason)
			local got = DataService.addCurrency(p.player, "coins", coins, "match")
			local levelUp, newLevel = DataService.addXp(p.player, xp)
			DataService.recordMatch(p.player, won, match.mode, match.practice or match.tryOut)
			if not match.practice and not match.tryOut then
				quest(p, "play")
				if won then
					quest(p, "win")
				end
				if match.mode == "2v2" then
					quest(p, "play2v2")
				end
				if match.friendDuel then
					quest(p, "duelFriend")
				end
			end
			sendTo(p, {
				phase = "results",
				won = won,
				coins = got,
				coinLines = lines,
				xp = xp,
				levelUp = levelUp,
				newLevel = newLevel,
				hearts = match.hearts,
				reason = reason,
				practice = match.practice,
			})
			DataService.push(p.player)
		end
	end
	task.wait(MC.ResultsTime)
	send(match, { phase = "ended" })
	for _, p in match.participants do
		if p.player then
			playerMatch[p.player] = nil
			releaseAvatar(p)
			local char = p.player.Character
			if char and p.player.Parent then
				char:PivotTo(lobbySpawn())
			end
		end
	end
	if match.renderer then
		match.renderer:destroy()
	end
	match.folder:Destroy()
	releaseArena(match.arena)
	matches[match.id] = nil
end

local function teamHasHumans(match, team)
	for _, p in match.participants do
		if p.team == team and p.player and p.player.Parent and not p.left then
			return true
		end
	end
	return false
end

local function runMatch(match)
	send(match, {
		phase = "start",
		matchId = match.id,
		mode = match.mode,
		arena = match.arena.model,
		cameraPoint = match.arena.camera,
		origin = match.arena.origin,
		half = math.min(match.arena.data.halfX, match.arena.data.halfY),
		halfX = match.arena.data.halfX,
		halfY = match.arena.data.halfY,
		theme = match.arena.data.theme,
		gimmick = match.arena.data.gimmick,
		players = match.publicPlayers,
		hearts = match.hearts,
		practice = match.practice,
		tutorial = match.tutorial,
	})
	for _, p in match.participants do
		placeAvatar(match, p)
	end
	task.wait(MC.CountdownTime + MC.IntroTime)
	while not match.aborted do
		match.round += 1
		pickPhase(match)
		if match.aborted then
			break
		end
		aimPhase(match)
		if match.aborted then
			break
		end
		fightPhase(match)
		if match.aborted then
			break
		end
		finisherPhase(match)
		local r = match.lastResult
		-- next round's Champion = this round's winner (a double KO resets to a blind pick)
		match.championTeam = (r and not r.doubleKO) and r.winnerTeam or nil
		local dead1, dead2 = match.hearts[1] <= 0, match.hearts[2] <= 0
		if dead1 and dead2 then
			if match.finalClash then
				-- second double KO: more total damage across the match wins
				local d = { 0, 0 }
				for _, p in match.participants do
					d[p.team] += p.matchDamage
				end
				finish(match, d[1] >= d[2] and 1 or 2, "damage")
				return
			end
			match.finalClash = true
			match.hearts[1], match.hearts[2] = 1, 1
			send(match, { phase = "finalClash", hearts = match.hearts })
		elseif dead1 or dead2 then
			finish(match, dead1 and 2 or 1, "hearts")
			return
		end
	end
	local winner = match.abortWinner or (teamHasHumans(match, 1) and 1 or 2)
	if match.renderer then
		match.renderer:destroy()
		match.renderer = nil
	end
	finish(match, winner, "forfeit")
end

----------------------------------------------------------------------
-- public API
----------------------------------------------------------------------

function MatchService.isInMatch(player)
	return playerMatch[player] ~= nil
end

--[[
	players: {Player}, mode: "1v1" | "2v2"
	opts = { bots = n, practice = bool, difficulty = "Easy"|"Normal"|"Hard"|"TryOut", tutorial = bool }
]]
function MatchService.startMatch(players, mode, opts)
	opts = opts or {}
	local arena = takeArena(mode, players)
	if not arena then
		return false, "No arena available — try again in a few seconds!"
	end
	nextMatchId += 1
	local hearts = MC.Hearts
	local match = {
		id = nextMatchId,
		mode = mode,
		arena = arena,
		participants = {},
		hearts = { [1] = hearts, [2] = hearts },
		round = 0,
		practice = opts.practice or false,
		tryOut = opts.difficulty == "TryOut",
		tutorial = opts.tutorial or false,
		folder = Instance.new("Folder"),
	}
	if match.tutorial then
		match.hearts[2] = 1 -- the Training Bot has one heart
	end
	match.folder.Name = "Match" .. match.id
	match.folder.Parent = arena.model
	local seats = mode == "2v2" and 4 or 2
	local list = {}
	for _, pl in shuffle(table.clone(players)) do
		local passes = DataService.passes(pl)
		table.insert(list, {
			player = pl,
			userId = pl.UserId,
			name = pl.DisplayName,
			isBot = false,
			tryOut = match.tryOut,
			noQuests = match.practice,
			freeRerolls = MC.FreeRerollsPerMatch + (passes.VIP and 1 or 0),
		})
	end
	local names = { "Kenta", "Miko", "Ryo", "Aki", "Sora", "Yuki", "Haru", "Nana" }
	while #list < seats do
		botCounter += 1
		local diff = opts.difficulty or "Normal"
		if diff == "TryOut" then
			diff = "Normal"
		end
		table.insert(list, {
			player = nil,
			userId = -botCounter,
			name = (match.tutorial and "Training Bot") or (diff .. " Bot " .. names[botCounter % #names + 1]),
			isBot = true,
			difficulty = diff,
			freeRerolls = 0,
		})
	end
	for i, p in list do
		p.team = (seats == 2) and i or ((i % 2 == 1) and 1 or 2)
		p.heroPickUsed = false
		p.rerollsUsedFree = 0
		p.paidRerollsThisRound = 0
		p.inputs = p.isBot and 99 or 0
		p.roundsWon = 0
		p.matchDamage = 0
		table.insert(match.participants, p)
		if p.player then
			playerMatch[p.player] = match
		end
	end
	if #players >= 2 then
		local ok, isFriend = pcall(function()
			return players[1]:IsFriendsWith(players[2].UserId)
		end)
		match.friendDuel = ok and isFriend or false
	end
	match.publicPlayers = {}
	for _, p in match.participants do
		table.insert(match.publicPlayers, { userId = p.userId, name = p.name, team = p.team, isBot = p.isBot, difficulty = p.difficulty })
	end
	matches[match.id] = match
	task.spawn(function()
		local ok, err = pcall(runMatch, match)
		if not ok then
			warn("[MatchService] match crashed:", err)
			match.aborted = true
			pcall(finish, match, 1, "error")
		end
	end)
	return true
end

local function participantOf(player)
	local match = playerMatch[player]
	if not match then
		return nil
	end
	for _, p in match.participants do
		if p.player == player then
			return match, p
		end
	end
	return nil
end

local function onAction(player, msg)
	if type(msg) ~= "table" then
		return
	end
	local match, p = participantOf(player)
	if not match then
		return
	end
	local a = msg.action
	if a == "pick" and match.phase == "pick" then
		if table.find(p.options, msg.fighterId) then
			MatchService.lockPick(match, p, msg.fighterId, "card")
		end
	elseif (a == "heroPick" or a == "freePick") and match.phase == "pick" then
		if not p.heroPickUsed and not p.pickLocked and table.find(ownedList(p), msg.fighterId) then
			p.heroPickUsed = true
			MatchService.lockPick(match, p, msg.fighterId, "hero")
		end
	elseif a == "reroll" and match.phase == "pick" then
		if p.pickLocked then
			return
		end
		local free = p.rerollsUsedFree < p.freeRerolls
		if not free then
			if match.mode == "ranked" then
				return
			end
			if p.paidRerollsThisRound >= MC.MaxPaidRerollsPerRound then
				notify(player, "No more rerolls this round!", "#ff6b6b")
				return
			end
			if not DataService.spendGems(player, MC.RerollGemCost, "reroll") then
				notify(player, "Not enough gems!", "#ff6b6b")
				return
			end
			p.paidRerollsThisRound += 1
		else
			p.rerollsUsedFree += 1
		end
		p.inputs += 1
		p.options = drawOptions(p, p.options)
		p.dealt = table.clone(p.options)
		sendPick(match, p, nil, true)
	elseif a == "aim" and match.phase == "aim" and not p.aimLocked then
		if type(msg.angle) == "number" and msg.angle == msg.angle then
			p.aim = msg.angle
			p.aimed = true
		end
	elseif a == "lock" and match.phase == "aim" then
		if type(msg.angle) == "number" and msg.angle == msg.angle then
			p.aim = msg.angle
		end
		if not p.aimLocked then
			p.inputs += 1
		end
		p.aimLocked = true
	elseif a == "ult" and match.phase == "fight" and match.battle then
		if match.battle:requestUlt(p.userId) then
			p.inputs += 1
		end
	elseif (a == "tagOut" or a == "swap") and match.phase == "fight" and match.battle and p.unit then
		-- Tag Out: swap to one of your other 2 cards in the first 6 s (once per round)
		if p.taggedThisRound or not p.unit.alive then
			return
		end
		if os.clock() - (match.fightStart or 0) > MC.TagOutWindow then
			notify(player, "Too late to Tag Out this round!", "#ff6b6b")
			return
		end
		local choices = {}
		for _, id in p.dealt or p.options do
			if id ~= p.pick then
				table.insert(choices, id)
			end
		end
		local newId = msg.fighterId
		if not table.find(choices, newId) then
			newId = choices[math.random(1, math.max(1, #choices))]
		end
		if not newId then
			return
		end
		if not (DataService.useTagTicket(player) or DataService.spendGems(player, MC.TagOutGemCost, "tagOut")) then
			notify(player, "Tag Out needs " .. MC.TagOutGemCost .. " gems or a Tag Ticket!", "#ff6b6b")
			return
		end
		p.taggedThisRound = true
		p.pick = newId
		p.unit = match.battle:replaceUnit(p.unit, newId)
		send(match, { phase = "swapped", userId = p.userId, team = p.team, fighterId = newId, unitId = p.unit.id })
	elseif a == "forfeit" then
		match.abortWinner = 3 - p.team
		match.aborted = true
	end
end

function MatchService.init(deps)
	DataService = deps.DataService
	RewardService = deps.RewardService
	scanArenas()
	Remotes.event("MatchAction").OnServerEvent:Connect(onAction)
	Players.PlayerRemoving:Connect(function(player)
		local match, p = participantOf(player)
		if match then
			playerMatch[player] = nil
			p.left = true
			p.player = nil
			if not teamHasHumans(match, p.team) then
				match.abortWinner = 3 - p.team
				match.aborted = true
			end
		end
	end)
	local function hookCharacter(player)
		player.CharacterAdded:Connect(function()
			task.wait(0.2)
			local match, p = participantOf(player)
			if match and not match.finished then
				placeAvatar(match, p)
			end
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
end

MatchService._matches = matches

return MatchService
