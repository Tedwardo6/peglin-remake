--!strict
-- Between-runs workshop menu: kit, optional modifiers, ball-family pool,
-- party privacy, earned trails, play / continue, friends' runs to join,
-- and (Studio or owner only) the developer test-condition panel.
-- Unlocks are options, knowledge and appearance — never combat power.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kits = require(Shared.Content.Kits)
local Balls = require(Shared.Content.Balls)
local Modifiers = require(Shared.Content.Modifiers)
local Cosmetics = require(Shared.Content.Cosmetics)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)

local C = Theme.Color

local WorkshopMenu = {}

export type Choices = {
	kit: string,
	modifiers: { [string]: boolean },
	families: { [string]: boolean },
	privacy: string,
}

export type Callbacks = {
	onPlay: (Choices) -> (),
	onContinue: () -> (),
	onJoin: (runId: string, kit: string) -> (),
	onTrail: (id: string) -> (),
	onDevTest: (condition: string) -> (),
	onKitPreview: (kitId: string) -> (),
}

export type Menu = {
	frame: Frame,
	setProfile: (profile: { [string]: any }) -> (),
	setLobby: (list: { any }) -> (),
	setTestLog: (history: { any }) -> (),
	show: (on: boolean) -> (),
	choices: Choices,
}

local FAMILY_NAMES = { ricochet = "Ricochet", relay = "Relay", guard = "Guard", wild = "Wild" }
local FAMILY_ORDER = { "ricochet", "relay", "guard", "wild" }

local function section(parent: Instance, title: string, order: number, height: number): Frame
	local f = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height), LayoutOrder = order, Parent = parent })
	Kit.label({ Text = title, TextSize = 18, TextColor3 = C.textDim, Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = f })
	return f
end

function WorkshopMenu.new(parent: Instance, cb: Callbacks): Menu
	local choices: Choices = {
		kit = "ricochet",
		modifiers = {},
		families = { ricochet = true, relay = true, guard = true, wild = true },
		privacy = "friends",
	}
	local frame = Kit.panel({ Name = "WorkshopMenu", Size = UDim2.new(0, 470, 1, -32), Position = UDim2.new(1, -16, 0, 16), AnchorPoint = Vector2.new(1, 0), Color = C.panel, Visible = false, ZIndex = 5, Parent = parent })
	Kit.label({ Text = "WORKSHOP", TextSize = 36, Bold = true, Size = UDim2.new(1, -24, 0, 44), Position = UDim2.fromOffset(14, 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = frame })
	local statsLine = Kit.label({ Text = "", TextSize = 15, TextColor3 = C.textDim, Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(14, 52), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = frame })

	local scroll: ScrollingFrame = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -24, 1, -170),
		Position = UDim2.fromOffset(12, 80),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.panelEdge,
		BorderSizePixel = 0,
		ZIndex = 6,
		Parent = frame,
	})
	Kit.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	Kit.new("UIPadding", { PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4), Parent = scroll })

	-- Kit choice.
	local kitSec = section(scroll, "STARTER KIT", 1, 170)
	local kitButtons: { [string]: Kit.Button } = {}
	local kitDesc = Kit.label({ Text = "", TextSize = 16, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 104), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 7, Parent = kitSec })
	local rackRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 130), ZIndex = 7, Parent = kitSec })
	local function refreshKit()
		for id, b in kitButtons do
			b.setSelected(id == choices.kit)
		end
		local k = Kits.ById[choices.kit]
		kitDesc.Text = k.description
		for _, ch in rackRow:GetChildren() do
			ch:Destroy()
		end
		for i, bid in k.rack do
			local b = Balls.ById[bid]
			local chip = Kit.panel({ Size = UDim2.fromOffset(140, 32), Position = UDim2.fromOffset((i - 1) * 146, 0), Color = C.panelLight, Radius = 16, ZIndex = 7, Parent = rackRow })
			local sw = Kit.new("Frame", { Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(8, 6), BackgroundColor3 = b.color, ZIndex = 8, Parent = chip })
			Kit.corner(10).Parent = sw
			Kit.stroke(2).Parent = sw
			Kit.label({ Text = b.name, TextSize = 14, Size = UDim2.new(1, -36, 1, 0), Position = UDim2.fromOffset(32, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = chip })
		end
	end
	for i, id in Kits.Order do
		local k = Kits.ById[id]
		kitButtons[id] = Kit.button({
			Text = string.upper((string.gsub(k.name, " Kit", ""))),
			Size = UDim2.new(1 / 3, -8, 0, 70),
			Position = UDim2.new((i - 1) / 3, 4, 0, 28),
			Face = k.color,
			TextSize = 20,
			ZIndex = 7,
			OnActivated = function()
				choices.kit = id
				refreshKit()
				cb.onKitPreview(id)
			end,
			Parent = kitSec,
		})
	end
	refreshKit()

	-- Modifiers (optional; patterns and constraints, never more HP).
	local modSec = section(scroll, "OPTIONAL CHALLENGES", 2, 30 + 64 * 2)
	for i, id in Modifiers.Order do
		local def = Modifiers.ById[id]
		local col = (i - 1) % 2
		local row = (i - 1) // 2
		local b: Kit.Button
		b = Kit.button({
			Text = def.name,
			Size = UDim2.new(0.5, -6, 0, 56),
			Position = UDim2.new(col * 0.5, if col == 0 then 0 else 6, 0, 28 + row * 64),
			Face = C.panelLight,
			TextSize = 18,
			ZIndex = 7,
			OnActivated = function()
				choices.modifiers[id] = not choices.modifiers[id]
				b.setFace(if choices.modifiers[id] then C.red else C.panelLight)
				b.setText(if choices.modifiers[id] then def.name .. " ✓" else def.name)
			end,
			Parent = modSec,
		})
	end

	-- Ball family pool (bounded: keep at least two).
	local famSec = section(scroll, "BALL FAMILIES IN DRAFTS (KEEP 2+)", 3, 92)
	for i, fam in FAMILY_ORDER do
		local b: Kit.Button
		b = Kit.button({
			Text = FAMILY_NAMES[fam],
			Size = UDim2.new(0.25, -6, 0, 56),
			Position = UDim2.new((i - 1) * 0.25, 3, 0, 28),
			Face = C.green,
			TextSize = 16,
			ZIndex = 7,
			OnActivated = function()
				local on = 0
				for _, v in choices.families do
					if v then
						on += 1
					end
				end
				if choices.families[fam] and on <= 2 then
					return
				end
				choices.families[fam] = not choices.families[fam]
				b.setFace(if choices.families[fam] then C.green else C.panelLight)
			end,
			Parent = famSec,
		})
	end

	-- Party privacy.
	local privSec = section(scroll, "WHO CAN JOIN YOUR RUN", 4, 92)
	local privButtons: { [string]: Kit.Button } = {}
	for i, id in { "open", "friends", "closed" } do
		privButtons[id] = Kit.button({
			Text = string.upper(id),
			Size = UDim2.new(1 / 3, -6, 0, 56),
			Position = UDim2.new((i - 1) / 3, 3, 0, 28),
			Face = C.blue,
			TextSize = 18,
			ZIndex = 7,
			OnActivated = function()
				choices.privacy = id
				for pid, pb in privButtons do
					pb.setSelected(pid == id)
				end
			end,
			Parent = privSec,
		})
	end
	privButtons.friends.setSelected(true)

	-- Trails.
	local trailSec = section(scroll, "TRAILS (EARNED)", 5, 100)
	local trailHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 28), ZIndex = 7, Parent = trailSec })

	-- Runs to join.
	local joinSec = section(scroll, "JOIN A RUN ON THIS SERVER", 6, 120)
	local joinHolder = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 90), Position = UDim2.fromOffset(0, 28), ZIndex = 7, Parent = joinSec })
	Kit.new("UIListLayout", { Padding = UDim.new(0, 6), Parent = joinHolder })

	-- Developer test conditions (plan §12).
	local devSec = section(scroll, "DEVELOPER TEST MODE", 7, 150)
	devSec.Visible = false
	for i, cond in { "solo", "duo_self", "duo_teammate" } do
		Kit.button({
			Text = ({ "SOLO", "DUO · SELF", "DUO · TEAM" })[i],
			Size = UDim2.new(1 / 3, -6, 0, 56),
			Position = UDim2.new((i - 1) / 3, 3, 0, 28),
			Face = C.purple,
			TextSize = 16,
			ZIndex = 7,
			OnActivated = function()
				cb.onDevTest(cond)
			end,
			Parent = devSec,
		})
	end
	local testLog = Kit.label({ Text = "Same board, HP, threat, upgrade and timing in each condition.", TextSize = 13, TextColor3 = C.textDim, Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 90), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7, Parent = devSec })

	-- Primary actions.
	Kit.button({ Text = "PLAY", Size = UDim2.new(0.5, -18, 0, 72), Position = UDim2.new(1, -12, 1, -12), AnchorPoint = Vector2.new(1, 1), Face = C.green, TextSize = 30, ZIndex = 7, Sound = "launch", OnActivated = function()
		cb.onPlay(choices)
	end, Parent = frame })
	local cont = Kit.button({ Text = "CONTINUE", Size = UDim2.new(0.5, -18, 0, 72), Position = UDim2.new(0, 12, 1, -12), AnchorPoint = Vector2.new(0, 1), Face = C.gold, TextSize = 22, ZIndex = 7, OnActivated = cb.onContinue, Parent = frame })
	cont.root.Visible = false

	local menu: Menu = {
		frame = frame,
		choices = choices,
		setProfile = function(profile: { [string]: any })
			local st = profile.stats or {}
			statsLine.Text = `Runs finished {st.runsFinished or 0} · Best shot {st.biggestShot or 0} · Charges used by friends {st.chargesUsedByOthers or 0}`
			devSec.Visible = profile.devAllowed == true
			local cp = profile.checkpoint
			cont.root.Visible = cp ~= nil and (cp.completed or 9) < 9
			if cp then
				cont.setText(`CONTINUE · FIGHT {cp.completed + 1}/9`)
			end
			if profile.familyPool then
				for fam, on in profile.familyPool do
					choices.families[fam] = on
				end
			end
			for _, ch in trailHolder:GetChildren() do
				ch:Destroy()
			end
			for i, id in Cosmetics.Order do
				local def = Cosmetics.ById[id]
				local unlocked = profile.unlocked and profile.unlocked[id]
				local equipped = profile.equippedTrail == id
				local b = Kit.button({
					Text = if unlocked then def.name else "🔒",
					Size = UDim2.new(0.25, -6, 0, 60),
					Position = UDim2.new((i - 1) * 0.25, 3, 0, 0),
					Face = if unlocked then def.colorA:Lerp(def.colorB, 0.4) else C.greyDeep,
					TextSize = 14,
					ZIndex = 8,
					OnActivated = function()
						if unlocked then
							cb.onTrail(id)
						end
					end,
					Parent = trailHolder,
				})
				b.setSelected(equipped)
				if not unlocked then
					b.label.Text = "🔒 " .. def.description
					b.label.TextSize = 11
				end
			end
		end,
		setLobby = function(list: { any })
			for _, ch in joinHolder:GetChildren() do
				if ch:IsA("GuiObject") then
					ch:Destroy()
				end
			end
			if #list == 0 then
				Kit.label({ Text = "No other runs right now.", TextSize = 15, TextColor3 = C.textDim, Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = joinHolder })
				return
			end
			for _, r in list do
				local row = Kit.panel({ Size = UDim2.new(1, 0, 0, 52), Color = C.panelLight, ZIndex = 8, Parent = joinHolder })
				local wait = if r.state == "draft" then "joins now" elseif r.waitLow and r.waitHigh then `~{r.waitLow}–{r.waitHigh}s` else "after this fight"
				Kit.label({ Text = `{r.hostName} · fight {r.index}/9 · {r.size}/{r.maxParty} · {wait}`, TextSize = 15, Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(10, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
				local full = r.size >= r.maxParty
				local jb = Kit.button({ Text = if full then "FULL" else "JOIN", Size = UDim2.fromOffset(100, 42), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Face = C.green, TextSize = 18, ZIndex = 9, OnActivated = function()
					cb.onJoin(r.id, choices.kit)
				end, Parent = row })
				jb.setEnabled(not full)
			end
		end,
		setTestLog = function(history: { any })
			local lines = {}
			for i = math.max(1, #history - 2), #history do
				local e = history[i]
				local bonus = 0
				for _, p in e.players do
					bonus += p.bonusDamage
				end
				table.insert(lines, string.format("%s: %s in %.0fs, bonus dmg %d", e.condition, if e.won then "won" else "lost", e.duration, bonus))
			end
			testLog.Text = table.concat(lines, "\n")
		end,
		show = function(on: boolean)
			if on and not frame.Visible then
				frame.Visible = true
				frame.Position = UDim2.new(1, 500, 0, 16)
				Kit.tween(frame, 0.35, { Position = UDim2.new(1, -16, 0, 16) }, Enum.EasingStyle.Back)
			elseif not on and frame.Visible then
				Kit.tween(frame, 0.2, { Position = UDim2.new(1, 500, 0, 16) })
				task.delay(0.21, function()
					frame.Visible = false
				end)
			end
		end,
	}
	return menu
end

return WorkshopMenu
