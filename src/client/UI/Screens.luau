--!strict
-- Modal screens and overlays: draft, defeat (free restart), run results,
-- developer test results, settings, peg key, tips, notices, waiting room,
-- idle warning. Each opens and closes with a transition and sound.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balls = require(Shared.Content.Balls)
local Components = require(Shared.Content.Components)
local Pegs = require(Shared.Content.Pegs)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Audio = require(script.Parent.Parent.Juice.Audio)

local C = Theme.Color

local Screens = {}

local layer: Frame

function Screens.init(_parentGui: ScreenGui, root: Frame)
	layer = root
end

-- Shared modal shell: dim backdrop + centred panel, animated in and out.
export type Modal = { backdrop: Frame, panel: Frame, close: () -> () }

local function modal(name: string, size: UDim2, color: Color3?): Modal
	local backdrop = Kit.new("Frame", {
		Name = name,
		BackgroundColor3 = C.ink,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Active = true,
		Parent = layer,
	})
	Kit.tween(backdrop, Theme.Motion.open, { BackgroundTransparency = 0.35 })
	local panel = Kit.panel({ Size = size, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Color = color or C.panel, Style = "ornate", ZIndex = 21, Parent = backdrop })
	Kit.popIn(panel)
	Audio.play("open")
	local closed = false
	return {
		backdrop = backdrop,
		panel = panel,
		close = function()
			if closed then
				return
			end
			closed = true
			Kit.tween(backdrop, Theme.Motion.close, { BackgroundTransparency = 1 })
			local s = panel:FindFirstChildOfClass("UIScale")
			if s then
				Kit.tween(s, Theme.Motion.close, { Scale = 0.7 })
			end
			Kit.tween(panel, Theme.Motion.close, { BackgroundTransparency = 1 })
			for _, d in panel:GetDescendants() do
				if d:IsA("TextLabel") then
					Kit.tween(d, Theme.Motion.close, { TextTransparency = 1 })
				elseif d:IsA("ImageLabel") then
					Kit.tween(d, Theme.Motion.close, { ImageTransparency = 1 })
				end
			end
			task.delay(Theme.Motion.close + 0.02, function()
				backdrop:Destroy()
			end)
		end,
	}
end

-- A modal's heading on an iron plaque straddling the frame's top edge.
local function plaqueTitle(panel: Frame, text: string, width: number?, z: number?)
	return Kit.plaque({ Text = text, Height = 58, Size = UDim2.fromOffset(width or 420, 58), Position = UDim2.new(0.5, 0, 0, -26), AnchorPoint = Vector2.new(0.5, 0), ZIndex = (z or 22) + 2, Parent = panel })
end
Screens.plaqueTitle = plaqueTitle

-- Draft ------------------------------------------------------------------

export type DraftOption = { kind: string, id: string, badge: string }

local BADGE = {
	targeted = { text = "CLASS PICK", color = C.gold },
	kit = { text = "CLASS", color = C.gold },
	flex = { text = "FLEXIBLE", color = C.cyan },
	wild = { text = "WILDCARD", color = C.pink },
}

local function optionText(o: DraftOption, _rack: { string }): (string, string, string, Color3)
	if o.kind == "component" then
		local c = Components.ById[o.id]
		return c.name, c.description, c.icon, C.panelLight
	elseif o.kind == "ball" then
		local b = Balls.ById[o.id]
		return b.name, b.description, "🔮", b.color
	else
		local b = Balls.ById[o.id]
		return "Upgrade " .. b.name, `+1 damage per hit for your {b.name}.`, "⬆️", b.color
	end
end

export type Draft = { modal: Modal, setDeadline: (deadline: number, now: number) -> (), setPicked: (picked: boolean) -> (), update: (offer: { DraftOption }, rerolls: number) -> () }

function Screens.draft(offer: { DraftOption }, rack: { string }, rerolls: number, fallback: number, title: string, onPick: (choice: number, slot: number?) -> (), onReroll: () -> ()): Draft
	local m = modal("Draft", UDim2.fromOffset(820, 470))
	local p = m.panel
	plaqueTitle(p, "Claim a relic", 440)
	Kit.label({ Text = title, TextSize = 18, TextColor3 = C.textDim, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 46), ZIndex = 22, Parent = p })
	local cardsHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -40, 0, 290), Position = UDim2.fromOffset(20, 100), ZIndex = 22, Parent = p })
	local timerBar = Kit.bar({ Size = UDim2.new(1, -260, 0, 22), Position = UDim2.new(0, 20, 1, -42), Color = C.gold, TextSize = 14, ZIndex = 22, Parent = p })
	local picked = false
	local cards: { Frame } = {}

	local reroll: Kit.Button
	local function askSlot(choice: number)
		local sm = modal("Slot", UDim2.fromOffset(520, 250))
		plaqueTitle(sm.panel, "Replace which ball?", 400, 22)
		for i = 2, #rack do
			local b = Balls.ById[rack[i]]
			Kit.button({
				Text = b.name,
				Size = UDim2.fromOffset(220, 74),
				Position = UDim2.new(if i == 2 then 0.27 else 0.73, 0, 0, 90),
				AnchorPoint = Vector2.new(0.5, 0),
				Face = b.color,
				TextSize = 22,
				ZIndex = 23,
				OnActivated = function()
					sm.close()
					onPick(choice, i)
				end,
				Parent = sm.panel,
			})
		end
		Kit.button({ Text = "Back", Size = UDim2.fromOffset(140, 50), Position = UDim2.new(0.5, 0, 1, -16), AnchorPoint = Vector2.new(0.5, 1), Face = C.panelLight, TextSize = 20, ZIndex = 23, OnActivated = sm.close, Parent = sm.panel })
	end

	local function build(opts: { DraftOption })
		for _, c in cards do
			c:Destroy()
		end
		cards = {}
		for i, o in opts do
			local name, desc, icon, tint = optionText(o, rack)
			local card = Kit.panel({ Size = UDim2.new(1 / 3, -14, 1, 0), Position = UDim2.new((i - 1) / 3, 7, 0, 0), Color = C.panelLight, ZIndex = 22, Parent = cardsHolder })
			local badge = BADGE[o.badge] or BADGE.flex
			local chip = Kit.panel({ Size = UDim2.fromOffset(120, 28), Position = UDim2.new(0.5, 0, 0, -12), AnchorPoint = Vector2.new(0.5, 0), Color = badge.color, Radius = 14, ZIndex = 24, Parent = card })
			Kit.label({ Text = badge.text, TextSize = 15, Size = UDim2.fromScale(1, 1), ZIndex = 25, Parent = chip })
			local iconBox = Kit.panel({ Size = UDim2.fromOffset(84, 84), Position = UDim2.new(0.5, 0, 0, 26), AnchorPoint = Vector2.new(0.5, 0), Color = tint, Radius = 42, ZIndex = 23, Parent = card })
			Kit.label({ Text = icon, TextSize = 34, Bold = true, Size = UDim2.fromScale(1, 1), ZIndex = 24, Parent = iconBox })
			Kit.label({ Text = name, TextSize = 22, Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 118), ZIndex = 23, TextScaled = true, MaxTextSize = 22, Parent = card })
			Kit.label({ Text = desc, TextSize = 16, TextColor3 = C.textDim, Size = UDim2.new(1, -20, 0, 70), Position = UDim2.fromOffset(10, 150), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 23, Parent = card })
			Kit.button({
				Text = if o.kind == "ball" then "TAKE BALL" else "TAKE",
				Size = UDim2.new(1, -24, 0, 54),
				Position = UDim2.new(0.5, 0, 1, -12),
				AnchorPoint = Vector2.new(0.5, 1),
				Face = C.ember,
				TextSize = 22,
				ZIndex = 24,
				Sound = "reward",
				OnActivated = function()
					if picked then
						return
					end
					if o.kind == "ball" then
						askSlot(i)
					else
						onPick(i, nil)
					end
				end,
				Parent = card,
			})
			Kit.popIn(card, (i - 1) * 0.06)
			cards[i] = card
		end
	end
	build(offer)

	reroll = Kit.button({
		Text = `REROLL ({rerolls})`,
		Size = UDim2.fromOffset(200, 56),
		Position = UDim2.new(1, -20, 1, -14),
		AnchorPoint = Vector2.new(1, 1),
		Face = C.blue,
		TextSize = 20,
		ZIndex = 23,
		OnActivated = onReroll,
		Parent = p,
	})
	reroll.setEnabled(rerolls > 0)

	local deadlineAt = 0
	local fallbackText = `If time runs out: heal {fallback}`
	local running = true
	task.spawn(function()
		while running do
			local left = deadlineAt - workspace:GetServerTimeNow()
			if deadlineAt > 0 then
				timerBar.set(math.max(0, left), 20, true)
				timerBar.setText(if picked then "Waiting for teammates…" else `{math.max(0, math.ceil(left))}s · {fallbackText}`)
			end
			task.wait(0.1)
		end
	end)
	local wrapped = m.close
	m.close = function()
		running = false
		wrapped()
	end
	return {
		modal = m,
		setDeadline = function(deadline: number, _now: number)
			deadlineAt = deadline
		end,
		setPicked = function(on: boolean)
			picked = on
			reroll.setEnabled(not on and rerolls > 0)
			for _, c in cards do
				Kit.tween(c, 0.2, { BackgroundTransparency = if on then 0.5 else 0 })
			end
		end,
		update = function(newOffer: { DraftOption }, newRerolls: number)
			rerolls = newRerolls
			reroll.setText(`REROLL ({rerolls})`)
			reroll.setEnabled(rerolls > 0 and not picked)
			build(newOffer)
		end,
	}
end

-- Defeat: free immediate restart (plan §2) ---------------------------------

function Screens.defeat(onRestart: () -> (), onLeave: () -> ()): Modal
	local m = modal("Defeat", UDim2.fromOffset(560, 300), Color3.fromRGB(50, 14, 34))
	Kit.label({ Text = "THE PARTY FALLS", Title = true, TextSize = 52, Bold = true, TextColor3 = C.red, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 20), ZIndex = 22, Parent = m.panel })
	Kit.label({ Text = "Rising again is free: retry this fight with your build intact.", TextSize = 19, Size = UDim2.new(1, -40, 0, 50), Position = UDim2.fromOffset(20, 86), TextWrapped = true, ZIndex = 22, Parent = m.panel })
	Kit.button({ Text = "RISE AGAIN", Size = UDim2.fromOffset(260, 70), Position = UDim2.new(0.5, -10, 1, -24), AnchorPoint = Vector2.new(1, 1), Face = C.ember, TextSize = 24, ZIndex = 23, OnActivated = function()
		m.close()
		onRestart()
	end, Parent = m.panel })
	Kit.button({ Text = "RETURN TO HALL", Size = UDim2.fromOffset(220, 70), Position = UDim2.new(0.5, 10, 1, -24), AnchorPoint = Vector2.new(0, 1), Face = C.panelLight, TextSize = 20, ZIndex = 23, OnActivated = function()
		m.close()
		onLeave()
	end, Parent = m.panel })
	Audio.play("defeat")
	return m
end

-- Run results card ----------------------------------------------------------

export type ResultRow = { name: string, seat: number, damage: number, biggest: number, sent: number, used: number, guarded: number?, mended: number?, blocked: number? }

-- Contribution bars: each hero's share of the party's damage, plus what
-- they did for others (empowers sent, shield raised, wounds mended).
local function contributionRows(parent: Frame, rows: { ResultRow }, y0: number, rowH: number)
	local total = 0
	local best = 0
	for _, row in rows do
		total += row.damage
		best = math.max(best, row.damage)
	end
	for i, row in rows do
		local y = y0 + (i - 1) * rowH
		local col = Theme.slot(row.seat)
		local pct = if total > 0 then row.damage / total else 0
		local name = Kit.label({ Text = row.name .. (if row.damage == best and #rows > 1 and best > 0 then "  ★ MVP" else ""), TextSize = 19, Bold = true, TextColor3 = col, Size = UDim2.new(0.3, 0, 0, 26), Position = UDim2.new(0.04, 0, 0, y), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = parent })
		Kit.popIn(name, 0.1 + i * 0.08)
		local barBack = Kit.new("Frame", { BackgroundColor3 = Color3.fromRGB(8, 8, 22), Size = UDim2.new(0.42, 0, 0, 20), Position = UDim2.new(0.34, 0, 0, y + 3), ZIndex = 22, Parent = parent })
		Kit.corner(4).Parent = barBack
		Kit.stroke(1, C.goldDeep).Parent = barBack
		local fill = Kit.new("Frame", { BackgroundColor3 = col, Size = UDim2.fromScale(0, 1), ZIndex = 23, Parent = barBack })
		Kit.corner(4).Parent = fill
		task.delay(0.25 + i * 0.1, function()
			Kit.tween(fill, 0.6, { Size = UDim2.fromScale(math.max(0.02, pct), 1) })
		end)
		Kit.label({ Text = `{row.damage} dmg · {math.floor(pct * 100 + 0.5)}%`, TextSize = 14, Size = UDim2.new(0.42, 0, 0, 20), Position = UDim2.new(0.34, 0, 0, y + 3), ZIndex = 24, Parent = parent })
		local support = {}
		if row.sent > 0 then
			table.insert(support, `🔮 {row.sent} empowers`)
		end
		if (row.guarded or 0) > 0 then
			table.insert(support, `🛡️ {row.guarded} shield`)
		end
		if (row.mended or 0) > 0 then
			table.insert(support, `♥{row.mended} mended`)
		end
		table.insert(support, `best {row.biggest}`)
		Kit.label({ Text = table.concat(support, " · "), TextSize = 13, TextColor3 = C.textDim, Size = UDim2.new(0.22, 0, 0, 26), Position = UDim2.new(0.77, 0, 0, y), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 22, Parent = parent })
	end
end
Screens.contributionRows = contributionRows

function Screens.results(title: string, rows: { ResultRow }, squadTotal: number, minutes: number, rematchLabel: string, onRematch: () -> (), onLeave: () -> ()): Modal
	local m = modal("Results", UDim2.fromOffset(780, 470), C.panel)
	local t = Kit.label({ Text = title, Title = true, TextSize = 54, Bold = true, TextColor3 = C.gold, Size = UDim2.new(1, 0, 0, 58), Position = UDim2.fromOffset(0, 14), ZIndex = 22, Parent = m.panel })
	Kit.shimmer(t, 30, ColorSequence.new({ ColorSequenceKeypoint.new(0, C.gold), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 240, 200)), ColorSequenceKeypoint.new(1, C.gold) }))
	Kit.label({ Text = string.format("Party total %d damage · %.1f min", squadTotal, minutes), TextSize = 18, TextColor3 = C.textDim, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 74), ZIndex = 22, Parent = m.panel })
	contributionRows(m.panel, rows, 118, 48)
	Kit.button({ Text = rematchLabel, Size = UDim2.fromOffset(240, 70), Position = UDim2.new(0.5, -10, 1, -22), AnchorPoint = Vector2.new(1, 1), Face = C.ember, TextSize = 24, ZIndex = 23, OnActivated = function()
		m.close()
		onRematch()
	end, Parent = m.panel })
	Kit.button({ Text = "RETURN TO HALL", Size = UDim2.fromOffset(220, 70), Position = UDim2.new(0.5, 10, 1, -22), AnchorPoint = Vector2.new(0, 1), Face = C.panelLight, TextSize = 20, ZIndex = 23, OnActivated = function()
		m.close()
		onLeave()
	end, Parent = m.panel })
	Audio.play("victory")
	return m
end

-- Campfire: each hero repairs or trains a ball ---------------------------------

export type Rest = { modal: Modal, setStatus: (text: string) -> (), setChosen: (chosen: boolean) -> (), setDeadline: (deadline: number, now: number) -> () }

function Screens.rest(rack: { string }, healAmount: number, onHeal: () -> (), onTrain: (slot: number) -> ()): Rest
	local m = modal("Rest", UDim2.fromOffset(760, 420), Color3.fromRGB(30, 14, 30))
	Kit.label({ Text = "THE CAMPFIRE", Title = true, Bold = true, TextSize = 52, TextColor3 = C.ember, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 10), ZIndex = 22, Parent = m.panel })
	Kit.label({ Text = "Warm your bones. Choose one.", TextSize = 17, TextColor3 = C.textDim, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 64), ZIndex = 22, Parent = m.panel })
	local chosen = false
	local buttons: { Kit.Button } = {}
	local healCard = Kit.panel({ Size = UDim2.fromOffset(300, 220), Position = UDim2.fromOffset(30, 100), Color = C.panelLight, ZIndex = 22, Parent = m.panel })
	Kit.label({ Text = "♥", TextSize = 56, TextColor3 = C.hull, Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 8), ZIndex = 23, Parent = healCard })
	Kit.plaque({ Text = "Rest", Height = 40, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 23, Parent = healCard })
	Kit.label({ Text = `Repair {healAmount} health.`, TextSize = 16, TextColor3 = C.textDim, Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 108), TextWrapped = true, ZIndex = 23, Parent = healCard })
	table.insert(buttons, Kit.button({ Text = "REST", Size = UDim2.new(1, -24, 0, 54), Position = UDim2.new(0, 12, 1, -12), AnchorPoint = Vector2.new(0, 1), Face = C.hull, TextSize = 20, ZIndex = 24, OnActivated = function()
		if not chosen then
			chosen = true
			onHeal()
		end
	end, Parent = healCard }))
	local trainCard = Kit.panel({ Size = UDim2.fromOffset(380, 220), Position = UDim2.new(1, -30, 0, 100), AnchorPoint = Vector2.new(1, 0), Color = C.panelLight, ZIndex = 22, Parent = m.panel })
	Kit.label({ Text = "▲", TextSize = 50, TextColor3 = C.gold, Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 8), ZIndex = 23, Parent = trainCard })
	Kit.plaque({ Text = "Train", Height = 40, Size = UDim2.new(1, -40, 0, 40), Position = UDim2.new(0.5, 0, 0, 70), AnchorPoint = Vector2.new(0.5, 0), ZIndex = 23, Parent = trainCard })
	Kit.label({ Text = "+1 damage per hit for one ball:", TextSize = 16, TextColor3 = C.textDim, Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 108), ZIndex = 23, Parent = trainCard })
	for i, id in rack do
		local b = Balls.ById[id]
		table.insert(buttons, Kit.button({ Text = (string.gsub(b.name, " Ball", "")), Size = UDim2.new(1 / #rack, -10, 0, 54), Position = UDim2.new((i - 1) / #rack, 6, 1, -12), AnchorPoint = Vector2.new(0, 1), Face = Theme.deep(b.color, 0.7), TextSize = 15, ZIndex = 24, OnActivated = function()
			if not chosen then
				chosen = true
				onTrain(i)
			end
		end, Parent = trainCard }))
	end
	local timer = Kit.bar({ Size = UDim2.new(1, -60, 0, 18), Position = UDim2.new(0, 30, 1, -40), Color = C.ember, TextSize = 12, ZIndex = 22, Parent = m.panel })
	local status = Kit.label({ Text = "", TextSize = 15, TextColor3 = C.textDim, Size = UDim2.new(1, -60, 0, 20), Position = UDim2.new(0, 30, 1, -64), ZIndex = 22, Parent = m.panel })
	local deadline = 0
	local offset = 0
	task.spawn(function()
		while m.backdrop.Parent do
			local now = os.clock() + offset
			local left = math.max(0, deadline - now)
			timer.set(left, 20)
			timer.setText(`{math.ceil(left)}s · if time runs out: rest`)
			task.wait(0.1)
		end
	end)
	return {
		modal = m,
		setStatus = function(text: string)
			status.Text = text
		end,
		setChosen = function(c: boolean)
			chosen = c
			for _, b in buttons do
				b.setEnabled(not c)
			end
		end,
		setDeadline = function(d: number, now: number)
			deadline = d
			offset = now - os.clock()
		end,
	}
end

-- Settings ---------------------------------------------------------------------

export type SettingsState = { reducedMotion: boolean, music: number, sfx: number, skipSeen: boolean }

function Screens.settings(state: SettingsState, onChange: (SettingsState) -> (), onLeaveRun: (() -> ())?): Modal
	local m = modal("Settings", UDim2.fromOffset(520, 420))
	plaqueTitle(m.panel, "Settings", 320)
	local function toggleRow(y: number, text: string, get: () -> boolean, set: (boolean) -> ())
		Kit.label({ Text = text, TextSize = 22, Size = UDim2.new(0.6, 0, 0, 30), Position = UDim2.new(0.06, 0, 0, y + 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = m.panel })
		local b: Kit.Button
		b = Kit.button({ Text = if get() then "ON" else "OFF", Size = UDim2.fromOffset(110, 50), Position = UDim2.new(0.94, 0, 0, y), AnchorPoint = Vector2.new(1, 0), Face = if get() then C.green else C.panelLight, TextSize = 20, ZIndex = 23, OnActivated = function()
			set(not get())
			b.setText(if get() then "ON" else "OFF")
			b.setFace(if get() then C.green else C.panelLight)
			onChange(state)
		end, Parent = m.panel })
	end
	local function volumeRow(y: number, text: string, get: () -> number, set: (number) -> ())
		Kit.label({ Text = text, TextSize = 22, Size = UDim2.new(0.4, 0, 0, 30), Position = UDim2.new(0.06, 0, 0, y + 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 22, Parent = m.panel })
		local value = Kit.label({ Text = `{math.floor(get() * 100 + 0.5)}%`, TextSize = 22, Size = UDim2.fromOffset(80, 30), Position = UDim2.new(0.94, -70, 0, y + 10), AnchorPoint = Vector2.new(1, 0), ZIndex = 22, Parent = m.panel })
		for _, d in { -1, 1 } do
			Kit.button({ Text = if d < 0 then "–" else "+", Size = UDim2.fromOffset(56, 50), Position = UDim2.new(0.94, if d < 0 then -160 else 0, 0, y), AnchorPoint = Vector2.new(1, 0), Face = C.panelLight, TextSize = 26, ZIndex = 23, OnActivated = function()
				set(math.clamp(math.floor((get() + d * 0.1) * 10 + 0.5) / 10, 0, 1))
				value.Text = `{math.floor(get() * 100 + 0.5)}%`
				onChange(state)
			end, Parent = m.panel })
		end
	end
	toggleRow(76, "Reduced motion", function()
		return state.reducedMotion
	end, function(v)
		state.reducedMotion = v
	end)
	volumeRow(140, "Sound effects", function()
		return state.sfx
	end, function(v)
		state.sfx = v
	end)
	volumeRow(204, "Music", function()
		return state.music
	end, function(v)
		state.music = v
	end)
	toggleRow(268, "Skip seen cutscenes", function()
		return state.skipSeen
	end, function(v)
		state.skipSeen = v
	end)
	Kit.button({ Text = "CLOSE", Size = UDim2.fromOffset(160, 56), Position = UDim2.new(if onLeaveRun then 0.3 else 0.5, 0, 1, -18), AnchorPoint = Vector2.new(0.5, 1), Face = C.gold, TextSize = 22, ZIndex = 23, OnActivated = m.close, Parent = m.panel })
	if onLeaveRun then
		Kit.button({ Text = "LEAVE RUN", Size = UDim2.fromOffset(180, 56), Position = UDim2.new(0.72, 0, 1, -18), AnchorPoint = Vector2.new(0.5, 1), Face = C.red, TextSize = 20, ZIndex = 23, OnActivated = function()
			m.close();
			(onLeaveRun :: () -> ())()
		end, Parent = m.panel })
	end
	return m
end

-- Peg key: knowledge always one tap away -----------------------------------

local function pegIcon(kind: Pegs.PegKind, parent: Instance)
	local def = Pegs.Defs[kind]
	local holder = Kit.new("Frame", { Size = UDim2.fromOffset(44, 44), BackgroundTransparency = 1, ZIndex = 23, Parent = parent })
	local shape = def.shape
	local f = Kit.new("Frame", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = def.color, ZIndex = 24, Parent = holder })
	Kit.stroke(3).Parent = f
	if shape == "round" or shape == "ring" or shape == "spiky" then
		Kit.corner(15).Parent = f
	elseif shape == "square" then
		Kit.corner(5).Parent = f
	elseif shape == "diamond" then
		f.Rotation = 45
		f.Size = UDim2.fromOffset(24, 24)
		Kit.corner(3).Parent = f
	elseif shape == "pill" then
		f.Size = UDim2.fromOffset(38, 22)
		Kit.corner(11).Parent = f
	elseif shape == "plus" then
		f.Size = UDim2.fromOffset(32, 12)
		local v = Kit.new("Frame", { Size = UDim2.fromOffset(12, 32), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = def.color, ZIndex = 24, Parent = holder })
		Kit.stroke(3).Parent = v
	end
	if shape == "ring" then
		local hole = Kit.new("Frame", { Size = UDim2.fromOffset(12, 12), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = C.ink, ZIndex = 25, Parent = f })
		Kit.corner(6).Parent = hole
	end
	return holder
end

function Screens.pegKey(): Modal
	local m = modal("PegKey", UDim2.fromOffset(700, 470))
	plaqueTitle(m.panel, "Peg key", 300)
	for i, kindName in Pegs.Order do
		local kind: Pegs.PegKind = kindName :: any
		local def = Pegs.Defs[kind]
		local col = (i - 1) % 2
		local row = (i - 1) // 2
		local cell = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(0.5, -20, 0, 78), Position = UDim2.new(col * 0.5, 14, 0, 64 + row * 84), ZIndex = 22, Parent = m.panel })
		local icon = pegIcon(kind, cell)
		icon.Position = UDim2.fromOffset(0, 4)
		Kit.label({ Text = def.name, TextSize = 20, Size = UDim2.new(1, -54, 0, 24), Position = UDim2.fromOffset(52, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 23, Parent = cell })
		Kit.label({ Text = def.description, TextSize = 14, TextColor3 = C.textDim, Size = UDim2.new(1, -54, 0, 50), Position = UDim2.fromOffset(52, 24), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 23, Parent = cell })
	end
	Kit.button({ Text = "GOT IT", Size = UDim2.fromOffset(160, 54), Position = UDim2.new(0.5, 0, 1, -14), AnchorPoint = Vector2.new(0.5, 1), Face = C.gold, TextSize = 22, ZIndex = 23, OnActivated = m.close, Parent = m.panel })
	return m
end

-- Contextual tip bubble (one at a time; dismissed by acting or tapping).
local tip: Frame? = nil
function Screens.tip(text: string, anchor: UDim2, hold: number?)
	if tip then
		(tip :: Frame):Destroy()
		tip = nil
	end
	local f = Kit.panel({ Size = UDim2.fromOffset(330, 74), Position = anchor, AnchorPoint = Vector2.new(0.5, 0.5), Color = Color3.fromRGB(214, 186, 132), ZIndex = 35, Parent = layer })
	Kit.label({ Text = text, TextSize = 19, TextColor3 = C.ink, Stroke = false, Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), TextWrapped = true, ZIndex = 36, Parent = f })
	Kit.popIn(f)
	tip = f
	local thisTip = f
	-- Gentle bob draws the eye without flashing.
	task.spawn(function()
		local t0 = os.clock()
		while thisTip.Parent do
			thisTip.Position = anchor + UDim2.fromOffset(0, math.sin((os.clock() - t0) * 3) * 4)
			task.wait()
		end
	end)
	if hold then
		task.delay(hold, function()
			if tip == thisTip then
				Screens.clearTip()
			end
		end)
	end
end

function Screens.clearTip()
	local t = tip
	if t then
		tip = nil
		local s = t:FindFirstChildOfClass("UIScale")
		if s then
			Kit.tween(s, 0.15, { Scale = 0.5 })
		end
		task.delay(0.16, function()
			t:Destroy()
		end)
	end
end

-- Toast notice (top-centre).
function Screens.notice(text: string, color: Color3?)
	local f = Kit.panel({ Size = UDim2.fromOffset(520, 56), Position = UDim2.new(0.5, 0, 0, -70), AnchorPoint = Vector2.new(0.5, 0), Color = color or C.panelLight, ZIndex = 40, Parent = layer })
	Kit.label({ Text = text, TextSize = 20, Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextWrapped = true, ZIndex = 41, Parent = f })
	Kit.tween(f, 0.25, { Position = UDim2.new(0.5, 0, 0, 84) }, Enum.EasingStyle.Back)
	task.delay(3.2, function()
		Kit.tween(f, 0.25, { Position = UDim2.new(0.5, 0, 0, -70) })
		task.delay(0.3, function()
			f:Destroy()
		end)
	end)
end

-- Idle warning (45 s): any input clears it.
local idle: Modal? = nil
function Screens.idleWarning(show: boolean)
	if show and idle == nil then
		local m = modal("Idle", UDim2.fromOffset(460, 180), C.panelLight)
		plaqueTitle(m.panel, "Still there?", 360)
		Kit.label({ Text = "Aim or launch in 15 s to keep your seat in this fight.", TextSize = 18, Size = UDim2.new(1, -30, 0, 50), Position = UDim2.fromOffset(15, 80), TextWrapped = true, ZIndex = 22, Parent = m.panel })
		m.backdrop.BackgroundTransparency = 0.6
		idle = m
	elseif not show and idle then
		(idle :: Modal).close()
		idle = nil
	end
end

-- Waiting room for newcomers: honest estimate + practice + start solo.
export type Waiting = { frame: Frame, set: (host: string, low: number?, high: number?) -> (), close: () -> () }
function Screens.waiting(onSolo: () -> ()): Waiting
	local f = Kit.panel({ Size = UDim2.fromOffset(440, 150), Position = UDim2.new(1, -16, 0, 84), AnchorPoint = Vector2.new(1, 0), Color = C.panel, ZIndex = 15, Parent = layer })
	Kit.popIn(f)
	local title = Kit.label({ Text = "JOINING…", TextSize = 24, Bold = true, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 16, Parent = f })
	local body = Kit.label({ Text = "", TextSize = 17, Size = UDim2.new(1, -20, 0, 48), Position = UDim2.fromOffset(10, 40), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, ZIndex = 16, Parent = f })
	Kit.button({ Text = "START SOLO NOW", Size = UDim2.fromOffset(220, 50), Position = UDim2.new(1, -12, 1, -12), AnchorPoint = Vector2.new(1, 1), Face = C.gold, TextSize = 18, ZIndex = 17, OnActivated = onSolo, Parent = f })
	Kit.label({ Text = "PRACTICE BOARD", TextSize = 14, TextColor3 = C.textDim, Size = UDim2.fromOffset(180, 20), Position = UDim2.new(0, 12, 1, -36), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 16, Parent = f })
	return {
		frame = f,
		set = function(host: string, low: number?, high: number?)
			title.Text = `JOINING {string.upper(host)}'S RUN`
			if low ~= nil and high ~= nil then
				if (high :: number) <= 0 then
					body.Text = "You'll join at this upgrade break."
				else
					body.Text = `They're mid-fight. You join at the next upgrade break, likely in {low}–{high} s. Practise meanwhile.`
				end
			else
				body.Text = "They're mid-fight. You join at the next upgrade break (time unknown yet). Practise meanwhile."
			end
		end,
		close = function()
			local s = f:FindFirstChildOfClass("UIScale")
			if s then
				Kit.tween(s, 0.15, { Scale = 0.5 })
			end
			task.delay(0.16, function()
				f:Destroy()
			end)
		end,
	}
end

return Screens
