--!nonstrict
--[[
	Lobby/Reveal: the full-screen summon results animation.
	Cards appear face down, then flip one by one. Each flip flashes the card
	in its rarity colour; Legendary flashes the screen a little, Mythic a lot.
	Every card shows the portrait, name, rarity and "NEW!" or "+N COINS".

	Reveal.play(results, onDone)  -- results from the Summon RemoteFunction
	Reveal.cancel()               -- remove it at once (e.g. a match starts)
]]

local Util = require(script.Parent.Util)
local Kit = Util.Kit

local Reveal = {}

local token = 0 -- changes on every play/cancel so an old animation stops

-- sizes for a single big card or a grid of small ones
local LAYOUT = {
	big = { cell = Vector2.new(240, 320), portrait = 130, nameY = 156, nameH = 38, rarityH = 26, tagH = 48 },
	small = { cell = Vector2.new(140, 190), portrait = 78, nameY = 94, nameH = 26, rarityH = 18, tagH = 32 },
}

-- the overlay is built once and reused for every summon
local ui = nil -- {gui, root, area, button}
local done = false -- all cards flipped
local skipping = false -- player pressed SKIP
local onDoneCallback = nil

function Reveal.cancel()
	token += 1
	if ui then
		ui.root.Visible = false
		ui.area:ClearAllChildren()
	end
end

function Reveal.isOpen()
	return ui ~= nil and ui.root.Visible
end

local function onButton()
	if not done then
		skipping = true
		return
	end
	Reveal.cancel()
	local cb = onDoneCallback
	onDoneCallback = nil
	if cb then
		cb()
	end
end

local function build()
	local gui = Kit.screen("AvA_SummonReveal", 30)
	local root = Util.box(gui, { name = "Reveal", color = Color3.new(0, 0, 0), transparency = 0.25, corner = false })
	root.Active = true -- block clicks to things behind
	root.Visible = false
	local holder = Util.group(root, {
		name = "Holder",
		size = UDim2.fromOffset(820, 540),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})
	Util.autoScale(holder, 1280, 600)
	Kit.label(holder, {
		text = "SUMMON RESULTS",
		color = Kit.C.gold,
		size = UDim2.new(1, 0, 0, 46),
		strokeThickness = 3,
	})
	local area = Util.group(holder, { name = "Cards", size = UDim2.new(1, 0, 0, 400), position = UDim2.fromOffset(0, 56) })
	local button = Kit.button(holder, {
		text = "SKIP",
		color = Util.GREY,
		size = UDim2.fromOffset(220, 58),
		position = UDim2.new(0.5, 0, 1, -8),
		anchor = Vector2.new(0.5, 1),
	})
	Util.onClick(button, onButton)
	ui = { gui = gui, root = root, area = area, button = button }
end

-- full-screen colour flash
local function flash(color, strength, duration)
	if not Reveal.isOpen() then
		return
	end
	local f = Util.box(ui.root, {
		name = "Flash",
		color = color,
		transparency = 1 - strength,
		corner = false,
		z = 50,
	})
	Kit.tween(f, duration, { BackgroundTransparency = 1 })
	task.delay(duration + 0.05, function()
		f:Destroy()
	end)
end

-- big "MYTHIC!" text in the middle of the screen
local function shout(text, color)
	if not Reveal.isOpen() then
		return
	end
	local l = Kit.label(ui.root, {
		text = text,
		color = color,
		size = UDim2.fromScale(0.6, 0.18),
		position = UDim2.fromScale(0.5, 0.45),
		anchor = Vector2.new(0.5, 0.5),
		strokeThickness = 4,
		z = 51,
	})
	Kit.popIn(l)
	task.delay(1, function()
		if l.Parent then
			Util.fadeOut(l, 0.4)
			task.wait(0.45)
			l:Destroy()
		end
	end)
end

local function makeCard(parent, result, sizes, order)
	local fighter = Util.fighter(result.fighterId)
		or { name = result.name or tostring(result.fighterId), rarity = result.rarity }
	local rarity = result.rarity or fighter.rarity or "Rare"
	local rc = Kit.rarityColor(rarity)

	-- the layout places `slot`; we squash `inner` to fake a 3D flip
	local slot = Util.group(parent, {
		name = "Card" .. order,
		size = UDim2.fromOffset(sizes.cell.X, sizes.cell.Y),
		order = order,
	})
	local inner = Util.group(slot, {
		name = "Inner",
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
	})

	local back = Util.box(inner, { name = "Back", color = Color3.new(1, 1, 1), corner = 14, stroke = 4 })
	Kit.gradient(back, Kit.C.purple, Kit.C.bg)
	Kit.label(back, {
		text = "?",
		size = UDim2.fromScale(0.6, 0.4),
		position = UDim2.fromScale(0.5, 0.5),
		anchor = Vector2.new(0.5, 0.5),
		strokeThickness = 3,
	})

	local face = Util.box(inner, { name = "Face", color = Color3.new(1, 1, 1), corner = 14, stroke = 4, strokeColor = rc })
	Kit.gradient(face, rc, rc:Lerp(Kit.C.bg, 0.65))
	face.Visible = false
	local portrait = Kit.portrait(face, fighter, UDim2.fromOffset(sizes.portrait, sizes.portrait))
	portrait.AnchorPoint = Vector2.new(0.5, 0)
	portrait.Position = UDim2.new(0.5, 0, 0, 12)
	Kit.label(face, {
		text = fighter.name or "?",
		size = UDim2.new(1, -12, 0, sizes.nameH),
		position = UDim2.new(0.5, 0, 0, sizes.nameY),
		anchor = Vector2.new(0.5, 0),
	})
	Kit.label(face, {
		text = string.upper(rarity),
		color = rc:Lerp(Color3.new(1, 1, 1), 0.35),
		size = UDim2.new(1, -12, 0, sizes.rarityH),
		position = UDim2.new(0.5, 0, 0, sizes.nameY + sizes.nameH + 2),
		anchor = Vector2.new(0.5, 0),
		font = Kit.FontBody,
	})
	local tagText, tagColor
	if result.isNew then
		tagText, tagColor = "NEW!", Kit.C.gold
	elseif (tonumber(result.refund) or 0) > 0 then
		tagText, tagColor = "+" .. Kit.short(result.refund) .. " COINS\n(duplicate)", Kit.C.coin
	else
		tagText, tagColor = "DUPLICATE", Kit.C.sub
	end
	Kit.label(face, {
		text = tagText,
		color = tagColor,
		size = UDim2.new(1, -12, 0, sizes.tagH),
		position = UDim2.new(0.5, 0, 1, -8),
		anchor = Vector2.new(0.5, 1),
	})
	local glow = Util.box(face, { name = "Glow", color = rc, transparency = 1, corner = 14, z = 5 })

	return { slot = slot, inner = inner, back = back, face = face, glow = glow, rarity = rarity, color = rc }
end

-- squash the card to nothing, swap back -> face, grow it again
local function flip(card, fast)
	local t = fast and 0.05 or 0.14
	Kit.tween(card.inner, t, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.wait(t)
	card.back.Visible = false
	card.face.Visible = true
	Kit.tween(card.inner, t * 1.6, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	card.glow.BackgroundTransparency = 0.05
	Kit.tween(card.glow, 0.5, { BackgroundTransparency = 1 })
end

function Reveal.play(results, onDone)
	if not ui then
		build()
	end
	Reveal.cancel()
	local myToken = token
	done, skipping, onDoneCallback = false, false, onDone
	ui.root.Visible = true
	Util.styleButton(ui.button, "SKIP", Util.GREY, true)

	local single = #results == 1
	local sizes = single and LAYOUT.big or LAYOUT.small
	if single then
		local l = Kit.list(ui.area, Enum.FillDirection.Horizontal, 0)
		l.VerticalAlignment = Enum.VerticalAlignment.Center
	else
		local g = Kit.grid(ui.area, UDim2.fromOffset(sizes.cell.X, sizes.cell.Y), 12)
		g.VerticalAlignment = Enum.VerticalAlignment.Center
	end

	task.spawn(function()
		local cards = {}
		for i, r in results do
			cards[i] = makeCard(ui.area, r, sizes, i)
			Kit.popIn(cards[i].inner)
		end
		task.wait(0.4)
		for _, card in cards do
			if token ~= myToken then
				return -- cancelled
			end
			flip(card, skipping)
			if card.rarity == "Mythic" then
				flash(card.color, 0.9, 1.0)
				shout("MYTHIC!", card.color)
				if not skipping then
					task.wait(0.8)
				end
			elseif card.rarity == "Legendary" then
				flash(card.color, 0.45, 0.5)
				if not skipping then
					task.wait(0.3)
				end
			end
			if not skipping then
				task.wait(single and 0.1 or 0.22)
			end
		end
		if token ~= myToken then
			return
		end
		done = true
		Util.styleButton(ui.button, "OK", Kit.C.green, true)
		Kit.popIn(ui.button)
	end)
end

return Reveal
