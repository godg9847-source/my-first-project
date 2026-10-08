--!nonstrict
--[[
	Kit: shared look & helpers for every client screen (colours, fonts, buttons,
	panels, tweens). All UI is created from code so it is easy to edit in text.

	Usage:
	  local Kit = require(script.Parent.Kit)
	  local btn = Kit.button(parent, {text = "SUMMON", color = Kit.C.gold, size = UDim2.fromOffset(160, 50)})
	  btn.Activated:Connect(...)
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Kit = {}

Kit.C = {
	bg = Color3.fromRGB(22, 20, 38),
	panel = Color3.fromRGB(34, 31, 58),
	panel2 = Color3.fromRGB(48, 44, 80),
	stroke = Color3.fromRGB(12, 10, 22),
	text = Color3.fromRGB(255, 255, 255),
	sub = Color3.fromRGB(190, 186, 220),
	gold = Color3.fromRGB(255, 196, 40),
	coin = Color3.fromRGB(255, 205, 60),
	gem = Color3.fromRGB(90, 220, 255),
	green = Color3.fromRGB(70, 210, 110),
	red = Color3.fromRGB(240, 70, 80),
	blue = Color3.fromRGB(70, 150, 255),
	purple = Color3.fromRGB(170, 90, 255),
	pink = Color3.fromRGB(255, 80, 150),
	team1 = Color3.fromRGB(70, 160, 255),
	team2 = Color3.fromRGB(255, 80, 80),
}

Kit.Font = Enum.Font.FredokaOne
Kit.FontBody = Enum.Font.GothamBold

function Kit.hex(s)
	if typeof(s) == "Color3" then
		return s
	end
	local ok, c = pcall(Color3.fromHex, s or "#ffffff")
	return ok and c or Color3.new(1, 1, 1)
end

function Kit.playerGui()
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

-- a ScreenGui that ignores the top bar inset and resets
function Kit.screen(name, displayOrder)
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = displayOrder or 0
	g.Parent = Kit.playerGui()
	return g
end

function Kit.corner(parent, px)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, px or 12)
	c.Parent = parent
	return c
end

function Kit.stroke(parent, thickness, color, transparency)
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = color or Kit.C.stroke
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function Kit.gradient(parent, top, bottom, rotation)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

function Kit.padding(parent, px)
	local p = Instance.new("UIPadding")
	local u = UDim.new(0, px or 10)
	p.PaddingTop, p.PaddingBottom, p.PaddingLeft, p.PaddingRight = u, u, u, u
	p.Parent = parent
	return p
end

function Kit.list(parent, dir, padding, align)
	local l = Instance.new("UIListLayout")
	l.FillDirection = dir or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, padding or 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = align or Enum.HorizontalAlignment.Center
	l.Parent = parent
	return l
end

function Kit.grid(parent, cell, padding)
	local g = Instance.new("UIGridLayout")
	g.CellSize = cell or UDim2.fromOffset(120, 150)
	g.CellPadding = UDim2.fromOffset(padding or 10, padding or 10)
	g.SortOrder = Enum.SortOrder.LayoutOrder
	g.HorizontalAlignment = Enum.HorizontalAlignment.Center
	g.Parent = parent
	return g
end

-- scale UI down on small (phone) screens
function Kit.autoScale(guiObject, designWidth)
	local scale = Instance.new("UIScale")
	scale.Parent = guiObject
	local cam = workspace.CurrentCamera
	local function update()
		local w = cam.ViewportSize.X
		scale.Scale = math.clamp(w / (designWidth or 1280), 0.55, 1.15)
	end
	update()
	cam:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	return scale
end

function Kit.label(parent, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = props.font or Kit.Font
	l.Text = props.text or ""
	l.TextColor3 = props.color or Kit.C.text
	l.TextScaled = props.scaled ~= false
	l.TextSize = props.textSize or 20
	l.TextWrapped = true
	l.Size = props.size or UDim2.fromScale(1, 0.1)
	l.Position = props.position or UDim2.new()
	l.AnchorPoint = props.anchor or Vector2.zero
	l.TextXAlignment = props.alignX or Enum.TextXAlignment.Center
	l.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	l.ZIndex = props.z or 1
	l.LayoutOrder = props.order or 0
	l.Name = props.name or "Label"
	if props.stroke ~= false then
		local s = Instance.new("UIStroke")
		s.Thickness = props.strokeThickness or 2
		s.Color = Kit.C.stroke
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		s.Parent = l
	end
	l.Parent = parent
	return l
end

-- chunky cartoon button. props: text, color, size, position, anchor, icon (emoji text), textColor
function Kit.button(parent, props)
	local b = Instance.new("TextButton")
	b.Name = props.name or "Button"
	b.AutoButtonColor = false
	b.BackgroundColor3 = props.color or Kit.C.blue
	b.Size = props.size or UDim2.fromOffset(160, 50)
	b.Position = props.position or UDim2.new()
	b.AnchorPoint = props.anchor or Vector2.zero
	b.Text = ""
	b.LayoutOrder = props.order or 0
	b.ZIndex = props.z or 1
	Kit.corner(b, props.corner or 12)
	Kit.stroke(b, 3)
	local base = props.color or Kit.C.blue
	Kit.gradient(b, base:Lerp(Color3.new(1, 1, 1), 0.2), base:Lerp(Color3.new(0, 0, 0), 0.15))
	local l = Kit.label(b, {
		text = props.text or "",
		color = props.textColor or Kit.C.text,
		size = UDim2.new(1, -12, 1, -8),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		z = (props.z or 1) + 1,
		name = "Text",
	})
	l.Parent = b
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.06 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.05), { Scale = 0.94 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	b.Parent = parent
	return b
end

function Kit.setButtonText(b, text)
	local l = b:FindFirstChild("Text")
	if l then
		l.Text = text
	end
end

-- framed panel with an optional title bar and close button. Returns frame, content, closeButton
function Kit.panel(parent, props)
	local f = Instance.new("Frame")
	f.Name = props.name or "Panel"
	f.Size = props.size or UDim2.fromOffset(700, 480)
	f.Position = props.position or UDim2.fromScale(0.5, 0.5)
	f.AnchorPoint = props.anchor or Vector2.new(0.5, 0.5)
	f.BackgroundColor3 = Kit.C.panel
	f.ZIndex = props.z or 5
	Kit.corner(f, 18)
	Kit.stroke(f, 4)
	Kit.gradient(f, Kit.C.panel2, Kit.C.panel)
	f.Parent = parent
	local closeBtn
	local top = 0
	if props.title then
		local bar = Instance.new("Frame")
		bar.Name = "TitleBar"
		bar.Size = UDim2.new(1, 0, 0, 56)
		bar.BackgroundColor3 = props.titleColor or Kit.C.purple
		bar.ZIndex = f.ZIndex + 1
		Kit.corner(bar, 18)
		Kit.stroke(bar, 3)
		bar.Parent = f
		Kit.label(bar, {
			text = props.title,
			size = UDim2.new(1, -120, 1, -12),
			position = UDim2.fromScale(0.5, 0.5),
			anchor = Vector2.new(0.5, 0.5),
			z = f.ZIndex + 2,
		})
		top = 64
		if props.closable ~= false then
			closeBtn = Kit.button(bar, {
				text = "X",
				color = Kit.C.red,
				size = UDim2.fromOffset(44, 44),
				position = UDim2.new(1, -8, 0.5, 0),
				anchor = Vector2.new(1, 0.5),
				z = f.ZIndex + 3,
			})
		end
	end
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -24, 1, -top - 12)
	content.Position = UDim2.fromOffset(12, top)
	content.ZIndex = f.ZIndex + 1
	content.Parent = f
	return f, content, closeBtn
end

function Kit.scroll(parent, props)
	local s = Instance.new("ScrollingFrame")
	s.BackgroundTransparency = 1
	s.Size = props and props.size or UDim2.fromScale(1, 1)
	s.Position = props and props.position or UDim2.new()
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.ScrollBarThickness = 8
	s.ScrollBarImageColor3 = Kit.C.sub
	s.BorderSizePixel = 0
	s.ZIndex = props and props.z or 6
	s.Parent = parent
	return s
end

-- pop-in animation for opening panels
function Kit.popIn(gui)
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function Kit.tween(obj, t, props, style, dir)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- 1234567 -> "1.2M"
function Kit.short(n)
	n = math.floor(n or 0)
	if n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e4 then
		return string.format("%.1fK", n / 1e3)
	end
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

function Kit.rarityColor(rarity)
	local Config = require(game:GetService("ReplicatedStorage").Shared.Config)
	local r = Config.Rarities[rarity]
	return Kit.hex(r and r.color or "#ffffff")
end

-- a small 2D "portrait" of a fighter: coloured circle with hair colour ring and initials
function Kit.portrait(parent, fighter, size)
	local f = Instance.new("Frame")
	f.Name = "Portrait"
	f.Size = size or UDim2.fromOffset(80, 80)
	f.BackgroundColor3 = Kit.hex(fighter.look and fighter.look.skin or "#f5cfa6")
	Kit.corner(f, 999)
	local st = Kit.stroke(f, 4, Kit.hex(fighter.look and fighter.look.hair or "#222222"))
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local band = Instance.new("Frame")
	band.Size = UDim2.fromScale(1, 0.38)
	band.Position = UDim2.fromScale(0, 0.62)
	band.BackgroundColor3 = Kit.hex(fighter.look and fighter.look.outfit or "#555555")
	band.BorderSizePixel = 0
	Kit.corner(band, 999)
	band.Parent = f
	for _, x in { 0.32, 0.68 } do
		local eye = Instance.new("Frame")
		eye.Size = UDim2.fromScale(0.16, 0.2)
		eye.Position = UDim2.fromScale(x, 0.42)
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.BackgroundColor3 = Kit.hex(fighter.look and fighter.look.eyes or "#1b1b1b")
		Kit.corner(eye, 999)
		eye.Parent = f
	end
	local hair = Instance.new("Frame")
	hair.Size = UDim2.fromScale(0.9, 0.3)
	hair.Position = UDim2.fromScale(0.05, -0.02)
	hair.BackgroundColor3 = Kit.hex(fighter.look and fighter.look.hair or "#222222")
	Kit.corner(hair, 999)
	hair.Visible = not (fighter.look and fighter.look.hairStyle == "bald")
	hair.Parent = f
	f.Parent = parent
	return f
end

return Kit
