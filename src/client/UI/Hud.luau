--!strict
-- In-fight HUD. Corners hold stable controls in thumb reach on phones:
--   top-left: run progress   · top-right: settings / peg key
--   right: monster HP, armor, threat countdown card
--   bottom-left: your hull + shield, held Relay Charge
--   bottom-right: ball rack + LAUNCH (separate from aiming)
-- Everything is built once and updated in place; nothing pops in or out
-- without a transition.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Balls = require(Shared.Content.Balls)

local Theme = require(script.Parent.Theme)
local Kit = require(script.Parent.Kit)
local Audio = require(script.Parent.Parent.Juice.Audio)

local C = Theme.Color

local Hud = {}
Hud.__index = Hud

export type RackSlot = {
	button: Kit.Button,
	swatch: Frame,
	cooldown: TextLabel,
	cdShade: Frame,
	ballId: string,
}

export type Hud = typeof(setmetatable(
	{} :: {
		gui: Instance,
		root: Frame,
		scale: UIScale,
		pips: { Frame },
		pipHolder: Frame,
		enemyName: TextLabel,
		enemyBar: Kit.Bar,
		armorLabel: TextLabel,
		phaseLabel: TextLabel,
		threatCard: Frame,
		threatTitle: TextLabel,
		threatDetail: TextLabel,
		threatTime: TextLabel,
		threatScale: UIScale,
		hullBar: Kit.Bar,
		hullLabel: TextLabel,
		shieldLabel: TextLabel,
		chargeSlot: Frame,
		chargePortrait: ImageLabel,
		chargeText: TextLabel,
		chargeEmpty: TextLabel,
		rack: { RackSlot },
		launch: Kit.Button,
		settingsButton: Kit.Button,
		keyButton: Kit.Button,
		selectedSlot: number,
		onSelectSlot: (slot: number) -> (),
		onLaunch: () -> (),
		lastThreatSecond: number,
		banner: TextLabel,
		bannerSub: TextLabel,
		bannerScale: UIScale,
		statusLabel: TextLabel,
		enemyPanel: Frame,
		playerPanel: Frame,
		rackPanel: Frame,
	},
	Hud
))

local thumbCache: { [number]: string } = {}
function Hud.portrait(uid: number): string
	if thumbCache[uid] then
		return thumbCache[uid]
	end
	local ok, url = pcall(function()
		return Players:GetUserThumbnailAsync(uid, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
	end)
	local u = if ok then url else ""
	thumbCache[uid] = u
	return u
end

function Hud.new(gui: Instance, onSelectSlot: (number) -> (), onLaunch: () -> (), onSettings: () -> (), onKey: () -> ()): Hud
	local self = setmetatable({}, Hud) :: any
	self.gui = gui
	self.onSelectSlot = onSelectSlot
	self.onLaunch = onLaunch
	self.selectedSlot = 1
	self.lastThreatSecond = -1

	local root = Kit.new("Frame", { Name = "Hud", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
	self.root = root

	-- Progress pips (top-left).
	local pipHolder = Kit.panel({ Name = "Progress", Size = UDim2.fromOffset(318, 54), Position = UDim2.fromOffset(16, 14), Color = C.panel, Parent = root })
	self.pipHolder = pipHolder
	Kit.new("UIScale", { Parent = pipHolder })
	self.pips = {}
	for i = 1, 9 do
		local boss = i % 3 == 0
		local d = if boss then 32 else 22
		local pip = Kit.new("Frame", {
			Name = "Pip" .. i,
			Size = UDim2.fromOffset(d, d),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(22 + (i - 1) * 34 + math.floor((i - 1) / 3) * 4, 27),
			BackgroundColor3 = C.panelLight,
			Parent = pipHolder,
		})
		Kit.corner(d // 2).Parent = pip
		Kit.stroke(2.5).Parent = pip
		if boss then
			Kit.label({ Text = "♛", TextSize = 18, Size = UDim2.fromScale(1, 1), Parent = pip })
		end
		Kit.new("UIScale", { Parent = pip })
		self.pips[i] = pip
	end

	-- Settings and peg key (top-right).
	self.settingsButton = Kit.button({ Text = "⚙", Size = UDim2.fromOffset(60, 58), Position = UDim2.new(1, -16, 0, 12), AnchorPoint = Vector2.new(1, 0), Face = C.panelLight, TextSize = 30, Depth = 6, OnActivated = onSettings, Parent = root })
	self.keyButton = Kit.button({ Text = "?", Size = UDim2.fromOffset(60, 58), Position = UDim2.new(1, -86, 0, 12), AnchorPoint = Vector2.new(1, 0), Face = C.panelLight, TextSize = 30, Depth = 6, OnActivated = onKey, Parent = root })

	-- Monster panel (top-right, above the monster).
	local enemyPanel = Kit.panel({ Name = "Enemy", Size = UDim2.fromOffset(360, 92), Position = UDim2.new(1, -16, 0, 80), AnchorPoint = Vector2.new(1, 0), Color = C.panel, Parent = root })
	self.enemyPanel = enemyPanel
	self.enemyName = Kit.label({ Text = "Monster", TextSize = 24, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left, Parent = enemyPanel })
	self.phaseLabel = Kit.label({ Text = "", TextSize = 16, TextColor3 = C.gold, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 6), TextXAlignment = Enum.TextXAlignment.Right, Parent = enemyPanel })
	self.enemyBar = Kit.bar({ Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 40), Color = C.enemyHp, OverlayColor = C.armor, TextSize = 20, Parent = enemyPanel })
	self.armorLabel = Kit.label({ Text = "", TextSize = 16, TextColor3 = C.armor, Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 1, 2), TextXAlignment = Enum.TextXAlignment.Right, Parent = enemyPanel })

	-- Threat card (right, mid-height near the monster's head).
	local card = Kit.panel({ Name = "Threat", Size = UDim2.fromOffset(250, 104), Position = UDim2.new(1, -16, 0, 200), AnchorPoint = Vector2.new(1, 0), Color = Color3.fromRGB(80, 26, 40), Parent = root })
	self.threatCard = card
	self.threatScale = Kit.new("UIScale", { Parent = card })
	self.threatTitle = Kit.label({ Text = "Slam", TextSize = 24, TextColor3 = C.threat, Size = UDim2.new(1, -86, 0, 30), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	self.threatDetail = Kit.label({ Text = "8 damage to each player", TextSize = 16, Size = UDim2.new(1, -86, 0, 56), Position = UDim2.fromOffset(12, 38), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Parent = card })
	local timeBox = Kit.panel({ Size = UDim2.fromOffset(66, 66), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = C.ink, Radius = 33, Gradient = false, Parent = card })
	self.threatTime = Kit.label({ Text = "12", TextSize = 34, Bold = true, Size = UDim2.fromScale(1, 1), Parent = timeBox })

	-- Player panel (bottom-left): hull, shield, held charge.
	local playerPanel = Kit.panel({ Name = "Player", Size = UDim2.fromOffset(330, 112), Position = UDim2.new(0, 16, 1, -16), AnchorPoint = Vector2.new(0, 1), Color = C.panel, Parent = root })
	self.playerPanel = playerPanel
	self.hullLabel = Kit.label({ Text = "HULL", TextSize = 18, Size = UDim2.fromOffset(120, 22), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = playerPanel })
	self.shieldLabel = Kit.label({ Text = "", TextSize = 18, TextColor3 = C.shield, Size = UDim2.fromOffset(110, 22), Position = UDim2.fromOffset(110, 6), TextXAlignment = Enum.TextXAlignment.Right, Parent = playerPanel })
	self.hullBar = Kit.bar({ Size = UDim2.fromOffset(210, 30), Position = UDim2.fromOffset(12, 32), Color = C.hull, OverlayColor = C.shield, TextSize = 18, Parent = playerPanel })
	self.statusLabel = Kit.label({ Text = "", TextSize = 16, TextColor3 = C.textDim, Size = UDim2.fromOffset(210, 36), Position = UDim2.fromOffset(12, 68), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = playerPanel })
	-- Charge slot: shows who sent it before you aim.
	local slot = Kit.panel({ Name = "Charge", Size = UDim2.fromOffset(86, 92), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = C.purpleDeep, Parent = playerPanel })
	self.chargeSlot = slot
	Kit.new("UIScale", { Parent = slot })
	self.chargePortrait = Kit.new("ImageLabel", {
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.new(0.5, 0, 0, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.purple,
		Image = "",
		Visible = false,
		Parent = slot,
	})
	Kit.corner(24).Parent = self.chargePortrait
	Kit.stroke(2.5).Parent = self.chargePortrait
	self.chargeText = Kit.label({ Text = "", TextSize = 15, Size = UDim2.new(1, -6, 0, 30), Position = UDim2.new(0, 3, 1, -34), TextWrapped = true, Parent = slot })
	self.chargeEmpty = Kit.label({ Text = "RELAY\nempty", TextSize = 14, TextColor3 = C.textDim, Size = UDim2.fromScale(1, 1), TextWrapped = true, Parent = slot })

	-- Rack + LAUNCH (bottom-right).
	local rackPanel = Kit.new("Frame", { Name = "Rack", BackgroundTransparency = 1, Size = UDim2.fromOffset(460, 150), Position = UDim2.new(1, -16, 1, -16), AnchorPoint = Vector2.new(1, 1), Parent = root })
	self.rackPanel = rackPanel
	self.rack = {}
	for i = 1, 3 do
		local b = Kit.button({
			Text = "",
			Size = UDim2.fromOffset(92, 104),
			Position = UDim2.fromOffset((i - 1) * 100, 46),
			Face = C.panelLight,
			Depth = 7,
			OnActivated = function()
				self.onSelectSlot(i)
			end,
			Parent = rackPanel,
		})
		local swatch = Kit.new("Frame", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = C.text, ZIndex = 2, Parent = b.face })
		Kit.corner(23).Parent = swatch
		Kit.stroke(3).Parent = swatch
		b.label.Size = UDim2.new(1, -8, 0, 30)
		b.label.Position = UDim2.new(0.5, 0, 1, -18)
		b.label.TextSize = 15
		local shade = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.ink, BackgroundTransparency = 0.35, ZIndex = 4, Visible = false, Parent = b.face })
		Kit.corner(13).Parent = shade
		local cd = Kit.label({ Text = "", TextSize = 34, Bold = true, Size = UDim2.fromScale(1, 0.7), ZIndex = 5, Parent = shade })
		self.rack[i] = { button = b, swatch = swatch, cooldown = cd, cdShade = shade, ballId = "" }
	end
	self.launch = Kit.button({
		Text = "LAUNCH",
		Size = UDim2.fromOffset(150, 132),
		Position = UDim2.new(1, 0, 1, 0),
		AnchorPoint = Vector2.new(1, 1),
		Face = C.green,
		TextSize = 30,
		Depth = 10,
		Sound = "launch",
		OnActivated = function()
			self.onLaunch()
		end,
		Parent = rackPanel,
	})

	-- Centre banner for moments.
	self.banner = Kit.label({ Name = "Banner", Text = "", TextSize = 64, Bold = true, Size = UDim2.fromOffset(800, 80), Position = UDim2.fromScale(0.42, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30, Parent = root })
	self.banner.TextTransparency = 1
	self.bannerScale = Kit.new("UIScale", { Parent = self.banner })
	self.bannerSub = Kit.label({ Name = "BannerSub", Text = "", TextSize = 26, Size = UDim2.fromOffset(800, 34), Position = UDim2.fromScale(0.42, 0.42 + 0.085), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30, Parent = root })
	self.bannerSub.TextTransparency = 1
	return self
end

function Hud.setVisible(self: Hud, on: boolean)
	self.root.Visible = on
end

function Hud.showBanner(self: Hud, text: string, sub: string?, color: Color3?, hold: number?)
	local b = self.banner
	b.Text = text
	b.TextColor3 = color or C.gold
	b.TextTransparency = 0
	local bs = b:FindFirstChildOfClass("UIStroke")
	if bs then
		bs.Transparency = 0
	end
	self.bannerSub.Text = sub or ""
	self.bannerSub.TextTransparency = if sub then 0 else 1
	local ss = self.bannerSub:FindFirstChildOfClass("UIStroke")
	if ss then
		ss.Transparency = if sub then 0 else 1
	end
	self.bannerScale.Scale = if Kit.Settings.reducedMotion then 1 else 0.4
	Kit.tween(self.bannerScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	local token = text .. (sub or "")
	task.delay(hold or 1.4, function()
		if b.Text .. self.bannerSub.Text == token then
			Kit.tween(b, 0.3, { TextTransparency = 1 })
			Kit.tween(self.bannerSub, 0.3, { TextTransparency = 1 })
			if bs then
				Kit.tween(bs, 0.3, { Transparency = 1 })
			end
			if ss then
				Kit.tween(ss, 0.3, { Transparency = 1 })
			end
		end
	end)
end

function Hud.setProgress(self: Hud, index: number, total: number)
	self.pipHolder.Visible = total > 1
	for i, pip in self.pips do
		local done = i < index
		local current = i == index
		pip.BackgroundColor3 = if done then C.green elseif current then C.gold else C.panelLight
		local stroke = pip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if current then Color3.new(1, 1, 1) else C.ink
		end
		if current then
			Kit.bounce(pip, 0.3)
		end
	end
end

function Hud.setEnemy(self: Hud, name: string, hp: number, maxHp: number, armor: number, phaseLabel: string?)
	self.enemyName.Text = name
	self.enemyBar.set(hp, maxHp)
	self.enemyBar.setText(`{math.max(0, math.floor(hp))} / {maxHp}`)
	self.enemyBar.setOverlay(math.min(armor, maxHp), maxHp)
	self.armorLabel.Text = if armor > 0 then `ARMOR {armor}` else ""
	self.phaseLabel.Text = phaseLabel or ""
end

-- Threat countdown. `secs` until it lands; `armed` while inside the warning window.
function Hud.setThreat(self: Hud, title: string, detail: string, secs: number, armed: boolean)
	self.threatTitle.Text = title
	self.threatDetail.Text = detail
	local s = math.max(0, math.ceil(secs))
	self.threatTime.Text = tostring(s)
	self.threatCard.BackgroundColor3 = if armed then Color3.fromRGB(150, 36, 52) else Color3.fromRGB(60, 30, 60)
	self.threatTime.TextColor3 = if s <= 3 and armed then C.red else C.text
	if s ~= self.lastThreatSecond then
		self.lastThreatSecond = s
		if armed and s <= 3 and s > 0 then
			Kit.bounce(self.threatCard, 0.12)
			Audio.play("countdown", { pitch = 1 + (3 - s) * 0.12 })
		end
	end
end

function Hud.setPlayer(self: Hud, hull: number, maxHull: number, shield: number, status: string?)
	self.hullBar.set(hull, maxHull)
	self.hullBar.setOverlay(math.min(shield, maxHull), maxHull)
	self.hullBar.setText(`{hull} / {maxHull}`)
	self.shieldLabel.Text = if shield > 0 then `SHIELD {shield}` else ""
	self.statusLabel.Text = status or ""
end

function Hud.setCharge(self: Hud, charge: { [string]: any }?, _fromName: string?)
	if charge then
		local wasEmpty = self.chargeEmpty.Visible
		self.chargeEmpty.Visible = false
		self.chargePortrait.Visible = true
		self.chargePortrait.Image = Hud.portrait(charge.from)
		self.chargeText.Text = `+{charge.power} ×{charge.hits}`
		self.chargeSlot.BackgroundColor3 = C.purple
		if wasEmpty then
			Kit.bounce(self.chargeSlot, 0.3)
		end
	else
		self.chargeEmpty.Visible = true
		self.chargePortrait.Visible = false
		self.chargeText.Text = ""
		self.chargeSlot.BackgroundColor3 = C.purpleDeep
	end
end

function Hud.setRack(self: Hud, rack: { string }, cooldowns: { number }, jam: number, selected: number, canLaunch: boolean)
	self.selectedSlot = selected
	for i, slot in self.rack do
		local id = rack[i]
		if id then
			local def = Balls.ById[id]
			slot.ballId = id
			slot.swatch.BackgroundColor3 = def.color
			slot.button.setText((string.gsub(def.name, " Ball", "")))
			local cd = cooldowns[i] or 0
			if i > 1 then
				cd += jam
			end
			slot.cdShade.Visible = cd > 0
			slot.cooldown.Text = if cd > 0 then tostring(cd) else ""
			slot.button.setSelected(i == selected)
			slot.button.root.Visible = true
		else
			slot.button.root.Visible = false
		end
	end
	self.launch.setEnabled(canLaunch)
end

function Hud.rackSlotScreenPos(self: Hud, slot: number): Vector2
	local b = self.rack[slot].button.root
	return b.AbsolutePosition + b.AbsoluteSize / 2
end

function Hud.chargeSlotScreenPos(self: Hud): Vector2
	return self.chargeSlot.AbsolutePosition + self.chargeSlot.AbsoluteSize / 2
end

function Hud.enemyBarScreenPos(self: Hud): Vector2
	local r = self.enemyBar.root
	return r.AbsolutePosition + r.AbsoluteSize / 2
end

return Hud
