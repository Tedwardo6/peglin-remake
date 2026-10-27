--!strict
-- The lobby hall's menu: pick a campaign, pick your hero's class, then
-- begin a solo mission or form a co-op party (leader picks the campaign,
-- members ready up, leader starts). Open parties and expeditions already
-- underway on this server can be joined from here. Optional challenges,
-- draft pools and privacy sit behind OPTIONS; trails and the developer
-- tools behind their own buttons. Unlocks are options and appearance only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Kits = require(Shared.Content.Kits)
local Balls = require(Shared.Content.Balls)
local Modifiers = require(Shared.Content.Modifiers)
local Cosmetics = require(Shared.Content.Cosmetics)
local Campaigns = require(Shared.Content.Campaigns)
local Config = require(Shared.Config)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Hud = require(script.Parent.Hud)

local C = Theme.Color
local myUid = Players.LocalPlayer.UserId

local LobbyMenu = {}

export type Choices = {
	kit: string,
	campaign: string,
	modifiers: { [string]: boolean },
	families: { [string]: boolean },
	privacy: string,
}

export type Callbacks = {
	onSolo: (Choices) -> (),
	onCreateParty: (Choices) -> (),
	onJoinParty: (partyId: string, kit: string) -> (),
	onLeaveParty: () -> (),
	onReady: (ready: boolean) -> (),
	onStartParty: (Choices) -> (),
	onPartyKit: (kit: string) -> (),
	onPartyCampaign: (campaign: string) -> (),
	onContinue: () -> (),
	onJoinRun: (runId: string, kit: string) -> (),
	onTrail: (id: string) -> (),
	onDevTest: (condition: string) -> (),
	onGallery: () -> (),
	onSettings: () -> (),
	onClassPreview: (kitId: string) -> (),
}

export type Menu = {
	frame: Frame,
	setProfile: (profile: { [string]: any }) -> (),
	setLobby: (payload: { [string]: any }) -> (),
	setTestLog: (history: { any }) -> (),
	show: (on: boolean) -> (),
	choices: Choices,
}

local FAMILY_NAMES = { ricochet = "Ricochet", relay = "Relay", guard = "Guard", wild = "Wild" }
local FAMILY_ORDER = { "ricochet", "relay", "guard", "wild" }
local CLASS_GLYPH = { ricochet = "⚔️", relay = "🔮", guard = "🛡️" }

local function heading(parent: Instance, text: string, y: number, z: number): TextLabel
	return Kit.label({ Text = text, Title = true, Bold = true, TextSize = 26, TextColor3 = C.gold, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, y), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = z, Parent = parent })
end

local function popup(parent: Instance, title: string, size: UDim2): (Frame, () -> ())
	local back = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = parent })
	local panel = Kit.panel({ Size = size, Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Color = C.panel, ZIndex = 31, Parent = back })
	Kit.label({ Text = title, Title = true, Bold = true, TextSize = 34, TextColor3 = C.gold, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 10), ZIndex = 32, Parent = panel })
	local function close()
		back:Destroy()
	end
	Kit.button({ Text = "X", Size = UDim2.fromOffset(44, 44), Position = UDim2.new(1, -10, 0, 10), AnchorPoint = Vector2.new(1, 0), Face = C.panelLight, TextSize = 20, ZIndex = 33, OnActivated = close, Parent = panel })
	Kit.popIn(panel)
	return panel, close
end

function LobbyMenu.new(parent: Instance, cb: Callbacks): Menu
	local choices: Choices = {
		kit = "ricochet",
		campaign = Campaigns.DEFAULT,
		modifiers = {},
		families = { ricochet = true, relay = true, guard = true, wild = true },
		privacy = "friends",
	}
	local profile: { [string]: any } = {}
	local lobbyState: { [string]: any } = {}
	local testHistory: { any } = {}

	local frame: Frame = Kit.new("Frame", { Name = "LobbyMenu", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 5, Parent = parent })

	-- Title.
	local title = Kit.label({ Text = "ABYSS PEGS", Title = true, Bold = true, TextSize = 58, Size = UDim2.fromOffset(460, 62), Position = UDim2.fromOffset(22, 10), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = frame })
	Kit.shimmer(title, 25)
	Kit.label({ Text = "working title · a co-op peg-roguelike", TextSize = 14, TextColor3 = C.textDim, Size = UDim2.fromOffset(460, 18), Position = UDim2.fromOffset(26, 70), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = frame })
	local statsLine = Kit.label({ Text = "", TextSize = 13, TextColor3 = C.textDim, Size = UDim2.fromOffset(460, 18), Position = UDim2.fromOffset(26, 90), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 6, Parent = frame })

	-- Campaign card (left).
	local camp = Kit.panel({ Size = UDim2.fromOffset(330, 250), Position = UDim2.fromOffset(16, 118), Color = C.panel, Transparency = 0.08, ZIndex = 6, Parent = frame })
	heading(camp, "CAMPAIGN", 8, 7)
	local campName = Kit.label({ Text = "", Title = true, TextSize = 28, Size = UDim2.new(1, -24, 0, 32), Position = UDim2.fromOffset(12, 40), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = camp })
	local campBlurb = Kit.label({ Text = "", TextSize = 14, TextColor3 = C.textDim, Size = UDim2.new(1, -24, 0, 54), Position = UDim2.fromOffset(12, 74), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7, Parent = camp })
	local actList = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 96), Position = UDim2.fromOffset(12, 130), ZIndex = 7, Parent = camp })
	Kit.new("UIListLayout", { Padding = UDim.new(0, 4), Parent = actList })
	local campRec = Kit.label({ Text = "", TextSize = 13, TextColor3 = C.cyan, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.new(0, 12, 1, -26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 7, Parent = camp })
	local function refreshCampaign()
		local c = Campaigns.ById[choices.campaign]
		campName.Text = c.name
		campBlurb.Text = c.blurb
		campRec.Text = `Recommended: {c.recommended} · {#c.acts} acts · branching paths`
		for _, ch in actList:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		for _, act in c.acts do
			local row = Kit.new("Frame", { BackgroundColor3 = act.palette.deep:Lerp(act.palette.glow, 0.25), BackgroundTransparency = 0.2, Size = UDim2.new(1, 0, 0, 28), ZIndex = 7, Parent = actList })
			Kit.corner(5).Parent = row
			Kit.stroke(1, act.palette.glow, 0.3).Parent = row
			Kit.label({ Text = `{act.subtitle} · {act.name}`, TextSize = 14, Size = UDim2.new(1, -16, 1, 0), Position = UDim2.fromOffset(8, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = row })
		end
	end
	refreshCampaign()

	-- Class choice (right top).
	local classPanel = Kit.panel({ Size = UDim2.fromOffset(372, 196), Position = UDim2.new(1, -16, 0, 16), AnchorPoint = Vector2.new(1, 0), Color = C.panel, Transparency = 0.08, ZIndex = 6, Parent = frame })
	heading(classPanel, "YOUR HERO", 8, 7)
	local classButtons: { [string]: Kit.Button } = {}
	local classDesc = Kit.label({ Text = "", TextSize = 14, Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 112), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 7, Parent = classPanel })
	local rackRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -24, 0, 28), Position = UDim2.fromOffset(12, 154), ZIndex = 7, Parent = classPanel })
	local function refreshClass()
		for id, b in classButtons do
			b.setSelected(id == choices.kit)
		end
		local k = Kits.ById[choices.kit]
		classDesc.Text = k.description
		for _, ch in rackRow:GetChildren() do
			ch:Destroy()
		end
		for i, bid in k.rack do
			local b = Balls.ById[bid]
			local chip = Kit.new("Frame", { BackgroundColor3 = C.panelLight, Size = UDim2.fromOffset(112, 26), Position = UDim2.fromOffset((i - 1) * 118, 0), ZIndex = 7, Parent = rackRow })
			Kit.corner(13).Parent = chip
			Kit.stroke(1, b.color, 0.2).Parent = chip
			local sw = Kit.new("Frame", { Size = UDim2.fromOffset(16, 16), Position = UDim2.fromOffset(6, 5), BackgroundColor3 = b.color, ZIndex = 8, Parent = chip })
			Kit.corner(8).Parent = sw
			Kit.label({ Text = b.name, TextSize = 12, Size = UDim2.new(1, -28, 1, 0), Position = UDim2.fromOffset(26, 0), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = chip })
		end
	end
	for i, id in Kits.Order do
		local k = Kits.ById[id]
		classButtons[id] = Kit.button({
			Text = `{CLASS_GLYPH[id] or ""} {string.upper(k.name)}`,
			Size = UDim2.new(1 / 3, -8, 0, 62),
			Position = UDim2.new((i - 1) / 3, if i == 1 then 12 else 4, 0, 44),
			Face = Theme.deep(k.color, 0.75),
			TextSize = 18,
			ZIndex = 7,
			OnActivated = function()
				choices.kit = id
				refreshClass()
				cb.onClassPreview(id)
				if lobbyState.party then
					cb.onPartyKit(id)
				end
			end,
			Parent = classPanel,
		})
	end
	refreshClass()

	-- Party / joinable lists (right).
	local partyPanel = Kit.panel({ Size = UDim2.new(0, 372, 1, -330), Position = UDim2.new(1, -16, 0, 222), AnchorPoint = Vector2.new(1, 0), Color = C.panel, Transparency = 0.08, ZIndex = 6, Parent = frame })
	local partyTitle = heading(partyPanel, "PARTY", 8, 7)
	local partyBody: ScrollingFrame = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -20, 1, -50),
		Position = UDim2.fromOffset(10, 42),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.panelEdge,
		BorderSizePixel = 0,
		ZIndex = 7,
		Parent = partyPanel,
	})
	Kit.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = partyBody })

	-- Primary actions (bottom centre).
	local actions = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(560, 74), Position = UDim2.new(0, 362, 1, -16), AnchorPoint = Vector2.new(0, 1), ZIndex = 6, Parent = frame })
	local solo = Kit.button({ Text = "BEGIN SOLO", Size = UDim2.fromOffset(250, 74), Position = UDim2.fromOffset(0, 0), Face = C.ember, TextSize = 28, ZIndex = 7, Sound = "launch", OnActivated = function()
		cb.onSolo(choices)
	end, Parent = actions })
	local party = Kit.button({ Text = "FORM PARTY", Size = UDim2.fromOffset(180, 74), Position = UDim2.fromOffset(262, 0), Face = C.purpleDeep, TextSize = 22, ZIndex = 7, OnActivated = function()
		if lobbyState.party then
			local p = lobbyState.party
			if p.leader == myUid then
				cb.onStartParty(choices)
			else
				local me = nil
				for _, m in p.members do
					if m.uid == myUid then
						me = m
					end
				end
				cb.onReady(not (me and me.ready))
			end
		else
			cb.onCreateParty(choices)
		end
	end, Parent = actions })
	local cont = Kit.button({ Text = "CONTINUE", Size = UDim2.fromOffset(160, 50), Position = UDim2.fromOffset(454, 12), Face = C.goldDeep, TextSize = 16, ZIndex = 7, OnActivated = cb.onContinue, Parent = actions })
	cont.root.Visible = false

	-- Small corner buttons (bottom left).
	local corner = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(330, 50), Position = UDim2.new(0, 16, 1, -20), AnchorPoint = Vector2.new(0, 1), ZIndex = 6, Parent = frame })
	Kit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), Parent = corner })
	local function openOptions()
		local panel = popup(parent, "OPTIONS", UDim2.fromOffset(520, 430))
		local y = 60
		Kit.label({ Text = "Optional challenges (whole party)", TextSize = 15, TextColor3 = C.textDim, Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, y), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32, Parent = panel })
		for i, id in Modifiers.Order do
			local def = Modifiers.ById[id]
			local col = (i - 1) % 2
			local row = (i - 1) // 2
			local b: Kit.Button
			b = Kit.button({
				Text = if choices.modifiers[id] then def.name .. " ✓" else def.name,
				Size = UDim2.new(0.5, -26, 0, 48),
				Position = UDim2.new(col * 0.5, if col == 0 then 20 else 6, 0, y + 24 + row * 54),
				Face = if choices.modifiers[id] then C.redDeep else C.panelLight,
				TextSize = 16,
				ZIndex = 32,
				OnActivated = function()
					choices.modifiers[id] = not choices.modifiers[id]
					b.setFace(if choices.modifiers[id] then C.redDeep else C.panelLight)
					b.setText(if choices.modifiers[id] then def.name .. " ✓" else def.name)
				end,
				Parent = panel,
			})
		end
		y += 24 + 2 * 54 + 10
		Kit.label({ Text = "Ball families in drafts (keep 2+)", TextSize = 15, TextColor3 = C.textDim, Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, y), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32, Parent = panel })
		for i, fam in FAMILY_ORDER do
			local b: Kit.Button
			b = Kit.button({
				Text = FAMILY_NAMES[fam],
				Size = UDim2.new(0.25, -14, 0, 44),
				Position = UDim2.new((i - 1) * 0.25, 12, 0, y + 24),
				Face = if choices.families[fam] then C.greenDeep else C.panelLight,
				TextSize = 15,
				ZIndex = 32,
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
					b.setFace(if choices.families[fam] then C.greenDeep else C.panelLight)
				end,
				Parent = panel,
			})
		end
		y += 24 + 54
		Kit.label({ Text = "Who can join your party or expedition", TextSize = 15, TextColor3 = C.textDim, Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, y), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32, Parent = panel })
		local privButtons: { [string]: Kit.Button } = {}
		for i, id in { "open", "friends", "closed" } do
			privButtons[id] = Kit.button({
				Text = string.upper(id),
				Size = UDim2.new(1 / 3, -18, 0, 44),
				Position = UDim2.new((i - 1) / 3, 14, 0, y + 24),
				Face = C.blueDeep,
				TextSize = 15,
				ZIndex = 32,
				OnActivated = function()
					choices.privacy = id
					for pid, pb in privButtons do
						pb.setSelected(pid == id)
					end
				end,
				Parent = panel,
			})
		end
		privButtons[choices.privacy].setSelected(true)
	end
	local function openTrails()
		local panel = popup(parent, "TRAILS", UDim2.fromOffset(520, 250))
		for i, id in Cosmetics.Order do
			local def = Cosmetics.ById[id]
			local unlocked = profile.unlocked and profile.unlocked[id]
			local b = Kit.button({
				Text = if unlocked then def.name else "🔒",
				Size = UDim2.new(0.25, -14, 0, 120),
				Position = UDim2.new((i - 1) * 0.25, 10, 0, 70),
				Face = if unlocked then Theme.deep(def.colorA:Lerp(def.colorB, 0.4), 0.8) else C.greyDeep,
				TextSize = 15,
				ZIndex = 32,
				OnActivated = function()
					if unlocked then
						cb.onTrail(id)
					end
				end,
				Parent = panel,
			})
			b.setSelected(profile.equippedTrail == id)
			if not unlocked then
				b.label.Text = "🔒 " .. def.description
				b.label.TextSize = 12
				b.label.TextWrapped = true
			end
		end
	end
	local devButton: Kit.Button
	local function openDev()
		local panel, closeDev = popup(parent, "DEVELOPER", UDim2.fromOffset(560, 300))
		Kit.label({ Text = "Test conditions: same board, HP, threat, upgrade and timing.", TextSize = 14, TextColor3 = C.textDim, Size = UDim2.new(1, -40, 0, 20), Position = UDim2.fromOffset(20, 58), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 32, Parent = panel })
		for i, cond in { "solo", "duo_self", "duo_teammate" } do
			Kit.button({
				Text = ({ "SOLO", "DUO · SELF", "DUO · TEAM" })[i],
				Size = UDim2.new(1 / 3, -18, 0, 52),
				Position = UDim2.new((i - 1) / 3, 14, 0, 84),
				Face = C.purpleDeep,
				TextSize = 16,
				ZIndex = 32,
				OnActivated = function()
					closeDev()
					cb.onDevTest(cond)
				end,
				Parent = panel,
			})
		end
		Kit.button({ Text = "MONSTER GALLERY", Size = UDim2.new(1, -40, 0, 52), Position = UDim2.fromOffset(20, 146), Face = C.blueDeep, TextSize = 18, ZIndex = 32, OnActivated = function()
			closeDev()
			cb.onGallery()
		end, Parent = panel })
		local lines = {}
		for i = math.max(1, #testHistory - 2), #testHistory do
			local e = testHistory[i]
			local bonus = 0
			for _, p in e.players do
				bonus += p.bonusDamage
			end
			table.insert(lines, string.format("%s: %s in %.0fs, bonus dmg %d", e.condition, if e.won then "won" else "lost", e.duration, bonus))
		end
		Kit.label({ Text = if #lines > 0 then table.concat(lines, "\n") else "No test results yet.", TextSize = 13, TextColor3 = C.textDim, Size = UDim2.new(1, -40, 0, 70), Position = UDim2.fromOffset(20, 208), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 32, Parent = panel })
	end
	Kit.button({ Text = "OPTIONS", Size = UDim2.fromOffset(104, 46), Face = C.panelLight, TextSize = 14, ZIndex = 7, OnActivated = openOptions, Parent = corner })
	Kit.button({ Text = "TRAILS", Size = UDim2.fromOffset(92, 46), Face = C.panelLight, TextSize = 14, ZIndex = 7, OnActivated = openTrails, Parent = corner })
	Kit.button({ Text = "⚙", Size = UDim2.fromOffset(46, 46), Face = C.panelLight, TextSize = 20, ZIndex = 7, OnActivated = cb.onSettings, Parent = corner })
	devButton = Kit.button({ Text = "DEV", Size = UDim2.fromOffset(60, 46), Face = C.purpleDeep, TextSize = 14, ZIndex = 7, OnActivated = openDev, Parent = corner })
	devButton.root.Visible = false

	local function memberRow(m: { [string]: any }, leaderView: boolean, order: number)
		local row = Kit.new("Frame", { BackgroundColor3 = C.panelLight, BackgroundTransparency = 0.15, Size = UDim2.new(1, -6, 0, 52), LayoutOrder = order, ZIndex = 8, Parent = partyBody })
		Kit.corner(6).Parent = row
		Kit.stroke(1, Theme.slot(order), 0.2).Parent = row
		local pic = Kit.new("ImageLabel", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = C.inkSoft, Image = Hud.portrait(m.uid), ZIndex = 9, Parent = row })
		Kit.corner(20).Parent = pic
		Kit.stroke(2, Theme.slot(order)).Parent = pic
		local p = Players:GetPlayerByUserId(m.uid)
		local k = Kits.ById[m.kit] or Kits.ById.ricochet
		Kit.label({ Text = (if p then p.DisplayName else "Hero") .. (if m.leader then "  👑" else ""), TextSize = 16, Bold = true, TextColor3 = Theme.slot(order), Size = UDim2.new(1, -150, 0, 22), Position = UDim2.fromOffset(54, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
		Kit.label({ Text = `{CLASS_GLYPH[k.id] or ""} {k.name}`, TextSize = 13, TextColor3 = C.textDim, Size = UDim2.new(1, -150, 0, 18), Position = UDim2.fromOffset(54, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
		Kit.label({ Text = if m.ready then "READY" else "NOT READY", TextSize = 13, Bold = true, TextColor3 = if m.ready then C.green else C.red, Size = UDim2.fromOffset(90, 20), Position = UDim2.new(1, -96, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 9, Parent = row })
		local _ = leaderView
	end

	local function note(text: string, order: number)
		Kit.label({ Text = text, TextSize = 13, TextColor3 = C.textDim, TextWrapped = true, Size = UDim2.new(1, -8, 0, 34), LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = partyBody })
	end

	local function refreshLobby()
		for _, ch in partyBody:GetChildren() do
			if ch:IsA("GuiObject") then
				ch:Destroy()
			end
		end
		local p = lobbyState.party
		if p then
			partyTitle.Text = if p.leader == myUid then "YOUR PARTY" else "PARTY"
			for i, m in p.members do
				memberRow(m, p.leader == myUid, i)
			end
			local campaign = Campaigns.ById[p.campaign]
			note(`Mission: {if campaign then campaign.name else p.campaign} · {#p.members}/{p.maxParty} heroes · {p.privacy}`, 20)
			if p.maxParty < Config.Party.MAX_PARTY_TESTING then
				note(`Parties are capped at {p.maxParty} until phone checks are done.`, 21)
			end
			local leave = Kit.button({ Text = "LEAVE PARTY", Size = UDim2.new(1, -6, 0, 40), Face = C.redDeep, TextSize = 15, LayoutOrder = 30, ZIndex = 8, OnActivated = cb.onLeaveParty, Parent = partyBody })
			local _ = leave
			if p.leader == myUid then
				party.setText("START")
				local allReady = true
				for _, m in p.members do
					if not m.ready then
						allReady = false
					end
				end
				party.setEnabled(allReady)
				party.setFace(C.green:Lerp(C.greenDeep, 0.4))
			else
				local me = nil
				for _, m in p.members do
					if m.uid == myUid then
						me = m
					end
				end
				party.setEnabled(true)
				party.setText(if me and me.ready then "UNREADY" else "READY")
				party.setFace(if me and me.ready then C.panelLight else C.green:Lerp(C.greenDeep, 0.4))
			end
			solo.root.Visible = false
		else
			partyTitle.Text = "JOIN OTHERS"
			party.setText("FORM PARTY")
			party.setEnabled(true)
			party.setFace(C.purpleDeep)
			solo.root.Visible = true
			local parties = lobbyState.parties or {}
			local order = 1
			if #parties == 0 then
				note("No open parties yet. Form one and friends can join you here.", order)
				order += 1
			end
			for _, op in parties do
				local leader = Players:GetPlayerByUserId(op.leader)
				local row = Kit.new("Frame", { BackgroundColor3 = C.panelLight, BackgroundTransparency = 0.15, Size = UDim2.new(1, -6, 0, 50), LayoutOrder = order, ZIndex = 8, Parent = partyBody })
				order += 1
				Kit.corner(6).Parent = row
				local campaign = Campaigns.ById[op.campaign]
				Kit.label({ Text = `{if leader then leader.DisplayName else "?"}'s party`, TextSize = 15, Bold = true, Size = UDim2.new(1, -110, 0, 22), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
				Kit.label({ Text = `{if campaign then campaign.name else ""} · {#op.members}/{op.maxParty}`, TextSize = 12, TextColor3 = C.textDim, Size = UDim2.new(1, -110, 0, 18), Position = UDim2.fromOffset(10, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
				Kit.button({ Text = "JOIN", Size = UDim2.fromOffset(84, 38), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Face = C.green:Lerp(C.greenDeep, 0.4), TextSize = 15, ZIndex = 9, OnActivated = function()
					cb.onJoinParty(op.id, choices.kit)
				end, Parent = row })
			end
			local runs = lobbyState.runs or {}
			if #runs > 0 then
				Kit.label({ Text = "EXPEDITIONS UNDERWAY", TextSize = 14, Bold = true, TextColor3 = C.gold, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = order, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 8, Parent = partyBody })
				order += 1
			end
			for _, r in runs do
				local row = Kit.new("Frame", { BackgroundColor3 = C.panelLight, BackgroundTransparency = 0.15, Size = UDim2.new(1, -6, 0, 50), LayoutOrder = order, ZIndex = 8, Parent = partyBody })
				order += 1
				Kit.corner(6).Parent = row
				local waitText = if r.state == "draft" or r.state == "map" or r.state == "rest" then "joins now" elseif r.waitLow and r.waitHigh then `~{r.waitLow}–{r.waitHigh}s` else "after this fight"
				Kit.label({ Text = `{r.hostName} · Act {r.act or 1}`, TextSize = 15, Bold = true, Size = UDim2.new(1, -110, 0, 22), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
				Kit.label({ Text = `{r.size}/{r.maxParty} heroes · {waitText}`, TextSize = 12, TextColor3 = C.textDim, Size = UDim2.new(1, -110, 0, 18), Position = UDim2.fromOffset(10, 26), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 9, Parent = row })
				local full = r.size >= r.maxParty
				local jb = Kit.button({ Text = if full then "FULL" else "JOIN", Size = UDim2.fromOffset(84, 38), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Face = C.green:Lerp(C.greenDeep, 0.4), TextSize = 15, ZIndex = 9, OnActivated = function()
					cb.onJoinRun(r.id, choices.kit)
				end, Parent = row })
				jb.setEnabled(not full)
			end
		end
	end
	refreshLobby()

	local menu: Menu = {
		frame = frame,
		choices = choices,
		setProfile = function(pr: { [string]: any })
			profile = pr
			local st = pr.stats or {}
			statsLine.Text = `Expeditions finished {st.runsFinished or 0} · Best strike {st.biggestShot or 0} · Bosses felled {st.bossesDefeated or 0}`
			devButton.root.Visible = pr.devAllowed == true
			local cp = pr.checkpoint
			cont.root.Visible = cp ~= nil
			if cp then
				cont.setText(`CONTINUE · ACT {cp.act or 1}`)
			end
			if pr.familyPool then
				for fam, on in pr.familyPool do
					choices.families[fam] = on
				end
			end
		end,
		setLobby = function(payload: { [string]: any })
			lobbyState = payload
			local p = payload.party
			if p then
				choices.campaign = p.campaign
				refreshCampaign()
				for _, m in p.members do
					if m.uid == myUid and m.kit and m.kit ~= choices.kit then
						choices.kit = m.kit
						refreshClass()
					end
				end
			end
			refreshLobby()
		end,
		setTestLog = function(history: { any })
			testHistory = history
		end,
		show = function(on: boolean)
			frame.Visible = on
			if on then
				Kit.popIn(classPanel)
				Kit.popIn(camp, 0.05)
				Kit.popIn(partyPanel, 0.1)
			end
		end,
	}
	return menu
end

return LobbyMenu
