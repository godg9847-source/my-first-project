--!nonstrict
--[[
	LobbyService: lobby life.
	  * animations driven by attributes on map parts: SpinSpeed (deg/s), BobHeight (studs)
	  * the What's New board (version + newest code)
	  * Hall of Heroes: a mini model of every fighter on its pedestal
	  * Clash TV: shows live matches in the server
]]

local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Fighters = require(Shared.Fighters)
local FighterModel = require(script.Parent.FighterModel)

local LobbyService = {}

local function setText(model, text)
	if not model then
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == "Text" then
			d.Text = text
		end
	end
end

local function animate(lobby)
	local movers = {}
	for _, d in lobby:GetDescendants() do
		if (d:IsA("BasePart") or d:IsA("Model")) and (d:GetAttribute("SpinSpeed") or d:GetAttribute("BobHeight")) then
			table.insert(movers, {
				obj = d,
				base = d:IsA("Model") and d:GetPivot() or d.CFrame,
				spin = math.rad(d:GetAttribute("SpinSpeed") or 0),
				bob = d:GetAttribute("BobHeight") or 0,
				phase = math.random() * 6,
			})
		end
	end
	return movers
end

local function hallOfHeroes(lobby, movers)
	local hall = lobby:FindFirstChild("HallOfHeroes", true)
	if not hall then
		return
	end
	for _, pedestal in hall:GetChildren() do
		local slot = pedestal:GetAttribute("Slot")
		local top = pedestal:FindFirstChild("Top", true)
		local f = slot and Fighters.List[slot]
		if f and top then
			local radius = 1.6
			local m = FighterModel.build(f.look, radius, Color3.fromHex(Config.Rarities[f.rarity].color), f.name)
			local ring = m:FindFirstChild("TeamRing")
			if ring then
				ring:Destroy()
			end
			local base = top.CFrame * CFrame.new(0, top.Size.Y / 2 + radius + 0.4, 0)
			m:PivotTo(base)
			m.Parent = pedestal
			local bb = Instance.new("BillboardGui")
			bb.Size = UDim2.fromOffset(150, 34)
			bb.StudsOffset = Vector3.new(0, radius + 1.6, 0)
			bb.MaxDistance = 60
			local t = Instance.new("TextLabel")
			t.Size = UDim2.fromScale(1, 1)
			t.BackgroundTransparency = 1
			t.TextScaled = true
			t.Font = Enum.Font.FredokaOne
			t.Text = f.name .. "\n" .. f.rarity .. " · " .. f.role
			t.TextColor3 = Color3.fromHex(Config.Rarities[f.rarity].color)
			t.TextStrokeTransparency = 0.2
			t.Parent = bb
			bb.Parent = m.PrimaryPart
			table.insert(movers, { obj = m, base = base, spin = math.rad(25), bob = 0.3, phase = slot })
		end
	end
end

function LobbyService.init(deps)
	local lobby = workspace:WaitForChild("Lobby", 10)
	if not lobby then
		return
	end
	setText(lobby:FindFirstChild("WhatsNewBoard", true), string.format("WHAT'S NEW · v%s\nNew code: %s", Config.Version, Config.NewestCode))
	local movers = animate(lobby)
	pcall(hallOfHeroes, lobby, movers)
	local t = 0
	RunService.Heartbeat:Connect(function(dt)
		t += dt
		for _, m in movers do
			local cf = m.base * CFrame.new(0, math.sin(t * 1.6 + m.phase) * m.bob, 0) * CFrame.Angles(0, t * m.spin, 0)
			if m.obj.Parent then
				if m.obj:IsA("Model") then
					m.obj:PivotTo(cf)
				else
					m.obj.CFrame = cf
				end
			end
		end
	end)
	-- Clash TV: list live matches
	local tv = lobby:FindFirstChild("ClashTV", true)
	if tv and deps and deps.MatchService then
		task.spawn(function()
			while true do
				local lines = {}
				for _, match in deps.MatchService._matches do
					local names = {}
					for _, p in match.participants do
						table.insert(names, p.name)
					end
					table.insert(lines, string.format("%s  ·  Round %d  ·  %s", table.concat(names, " vs "), match.round, match.arena.data.theme))
					if #lines >= 4 then
						break
					end
				end
				local text = #lines > 0 and ("CLASH TV — LIVE\n" .. table.concat(lines, "\n")) or "CLASH TV\nNo matches right now — step on a pad!"
				setText(tv, text)
				task.wait(3)
			end
		end)
	end
end

return LobbyService
