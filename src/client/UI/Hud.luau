--!strict
-- In-fight HUD. Corners hold stable controls in thumb reach on phones:
--   top-left: act and path progress   · top-right: settings / peg key
--   right: monster HP (lost HP split by who dealt it), armor, intent card
--   bottom-left: your HP + shield, held Empower charge
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
		actLabel: TextLabel,
		contribHolder: Frame,
		contribSegs: { Frame },
		legend: Frame,
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
		shieldBar: Kit.Bar,
		enemyFace: Frame,
		enemyModelKey: string,
		selfFace: ImageLabel,
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

	-- Act and path progress (top-left).
	local pipHolder = Kit.panel({ Name = "Progress", Size = UDim2.fromOffset(330, 58), Position = UDim2.fromOffset(16, 12), Color = C.panel, Transparency = 0.1, Parent = root })
	self.pipHolder = pipHolder
	Kit.new("UIScale", { Parent = pipHolder })
	self.actLabel = Kit.label({ Text = "", Title = true, TextSize = 22, TextColor3 = C.gold, Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(10, 3), TextXAlignment = Enum.TextXAlignment.Left, Parent = pipHolder })
	self.pips = {}
	for i = 1, 4 do
		local boss = i == 4
		local d = if boss then 22 else 16
		local pip = Kit.new("Frame", {
			Name = "Pip" .. i,
			Size = UDim2.fromOffset(d, d),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(20 + (i - 1) * 30, 42),
			BackgroundColor3 = C.panelLight,
			Rotation = 45,
			Parent = pipHolder,
		})
		Kit.stroke(1.5, C.goldDeep).Parent = pip
		Kit.new("UIScale", { Parent = pip })
		self.pips[i] = pip
	end

	-- Settings and peg key (top-right).
	self.settingsButton = Kit.button({ Text = "⚙", Size = UDim2.fromOffset(60, 58), Position = UDim2.new(1, -16, 0, 12), AnchorPoint = Vector2.new(1, 0), Face = C.panelLight, TextSize = 30, Depth = 6, OnActivated = onSettings, Parent = root })
	self.keyButton = Kit.button({ Text = "?", Size = UDim2.fromOffset(60, 58), Position = UDim2.new(1, -86, 0, 12), AnchorPoint = Vector2.new(1, 0), Face = C.panelLight, TextSize = 30, Depth = 6, OnActivated = onKey, Parent = root })

	-- Monster panel (top band): its portrait in a spiked seal, name, HP.
	local enemyPanel = Kit.panel({ Name = "Enemy", Size = UDim2.fromOffset(392, 92), Position = UDim2.fromOffset(372, 12), Color = C.panel, Parent = root })
	self.enemyPanel = enemyPanel
	local seal, face = Kit.portrait({ Name = "EnemySeal", Size = UDim2.fromOffset(78, 78), Position = UDim2.new(0, -14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3, Parent = enemyPanel })
	local _ = seal
	self.enemyFace = face
	self.enemyModelKey = ""
	self.enemyName = Kit.label({ Text = "Monster", Title = true, Bold = true, TextSize = 28, Size = UDim2.new(1, -96, 0, 30), Position = UDim2.fromOffset(84, 4), TextXAlignment = Enum.TextXAlignment.Left, Parent = enemyPanel })
	self.phaseLabel = Kit.label({ Text = "", TextSize = 16, TextColor3 = C.gold, Size = UDim2.new(1, -96, 0, 20), Position = UDim2.fromOffset(84, 8), TextXAlignment = Enum.TextXAlignment.Right, Parent = enemyPanel })
	self.enemyBar = Kit.bar({ Size = UDim2.new(1, -100, 0, 30), Position = UDim2.fromOffset(84, 44), Color = C.enemyHp, OverlayColor = C.armor, TextSize = 19, Parent = enemyPanel })
	self.armorLabel = Kit.label({ Text = "", TextSize = 15, TextColor3 = C.armor, Size = UDim2.new(1, -96, 0, 18), Position = UDim2.new(0, 84, 1, 4), TextXAlignment = Enum.TextXAlignment.Right, Parent = enemyPanel })
	-- Lost HP split by who dealt it: one segment per hero, in seat colours,
	-- drawn inside the empty right-hand part of the bar.
	local contrib = Kit.new("Frame", { Name = "Contribution", BackgroundTransparency = 1, Size = UDim2.new(1, -104, 0, 26), Position = UDim2.fromOffset(86, 46), ClipsDescendants = true, ZIndex = 2, Parent = enemyPanel })
	self.contribHolder = contrib
	self.contribSegs = {}
	for i = 1, 4 do
		local seg = Kit.new("Frame", { BackgroundColor3 = Theme.slot(i), BackgroundTransparency = 0.35, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Visible = false, ZIndex = 2, Parent = contrib })
		self.contribSegs[i] = seg
	end
	local legend = Kit.new("Frame", { Name = "Legend", BackgroundTransparency = 1, Size = UDim2.new(1, -96, 0, 18), Position = UDim2.new(0, 84, 1, 4), Parent = enemyPanel })
	Kit.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), Parent = legend })
	self.legend = legend

	-- Threat card (right, mid-height near the monster's head).
	local card = Kit.panel({ Name = "Threat", Size = UDim2.fromOffset(250, 96), Position = UDim2.new(1, -16, 0, 86), AnchorPoint = Vector2.new(1, 0), Color = Color3.fromRGB(40, 22, 28), StrokeColor = C.threat, Parent = root })
	self.threatCard = card
	self.threatScale = Kit.new("UIScale", { Parent = card })
	self.threatTitle = Kit.label({ Text = "Slam", Title = true, Bold = true, TextSize = 26, TextColor3 = C.threat, Size = UDim2.new(1, -86, 0, 30), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
	self.threatDetail = Kit.label({ Text = "8 damage to each player", TextSize = 16, Size = UDim2.new(1, -86, 0, 56), Position = UDim2.fromOffset(12, 38), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Parent = card })
	local timeBox = Kit.panel({ Size = UDim2.fromOffset(66, 66), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = C.ink, Radius = 33, Gradient = false, Parent = card })
	self.threatTime = Kit.label({ Text = "12", TextSize = 34, Bold = true, Size = UDim2.fromScale(1, 1), Parent = timeBox })

	-- Player panel (bottom-left): your hero's seal, health (red) and shield
	-- (blue) in stone housings, status, held charge.
	local playerPanel = Kit.panel({ Name = "Player", Size = UDim2.fromOffset(372, 112), Position = UDim2.new(0, 22, 1, -16), AnchorPoint = Vector2.new(0, 1), Color = C.panel, Parent = root })
	self.playerPanel = playerPanel
	local _seal, selfHolder = Kit.portrait({ Name = "SelfSeal", Size = UDim2.fromOffset(82, 82), Position = UDim2.new(0, -12, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = 3, Parent = playerPanel })
	self.selfFace = Kit.new("ImageLabel", { Name = "Headshot", BackgroundColor3 = Color3.fromRGB(30, 22, 40), Size = UDim2.fromScale(1, 1), Image = Hud.portrait(Players.LocalPlayer.UserId), ZIndex = 1, Parent = selfHolder })
	self.hullLabel = Kit.label({ Text = "", Heavy = true, TextSize = 14, TextColor3 = C.gold, Size = UDim2.fromOffset(150, 16), Position = UDim2.fromOffset(84, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = playerPanel })
	self.shieldLabel = Kit.label({ Text = "", TextSize = 13, TextColor3 = C.shield, Size = UDim2.fromOffset(150, 16), Position = UDim2.fromOffset(84, 70), TextXAlignment = Enum.TextXAlignment.Left, Parent = playerPanel })
	self.shieldLabel.Visible = false
	self.hullBar = Kit.bar({ Size = UDim2.fromOffset(168, 26), Position = UDim2.fromOffset(84, 14), Color = C.hull, OverlayColor = C.shield, TextSize = 17, Parent = playerPanel })
	self.shieldBar = Kit.bar({ Size = UDim2.fromOffset(150, 16), Position = UDim2.fromOffset(84, 50), Color = C.shield, OverlayColor = C.shield, TextSize = 12, Parent = playerPanel })
	self.shieldBar.set(0, 1, true)
	self.statusLabel = Kit.label({ Text = "", TextSize = 14, TextColor3 = C.textDim, Size = UDim2.fromOffset(170, 30), Position = UDim2.fromOffset(84, 74), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = playerPanel })
	-- Charge slot: shows who sent it before you aim.
	local slot = Kit.panel({ Name = "Charge", Size = UDim2.fromOffset(86, 92), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), Color = C.purpleDeep, StrokeColor = C.purple, Parent = playerPanel })
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
	self.chargeEmpty = Kit.label({ Text = "EMPOWER\nempty", TextSize = 13, TextColor3 = C.textDim, Size = UDim2.fromScale(1, 1), TextWrapped = true, Parent = slot })

	-- Rack + LAUNCH (bottom-right).
	local rackPanel = Kit.new("Frame", { Name = "Rack", BackgroundTransparency = 1, Size = UDim2.fromOffset(460, 150), Position = UDim2.new(1, -16, 1, -16), AnchorPoint = Vector2.new(1, 1), Parent = root })
	self.rackPanel = rackPanel
	self.rack = {}
	for i = 1, 3 do
		local b = Kit.button({
			Text = "",
			Size = UDim2.fromOffset(92, 104),
			Position = UDim2.fromOffset((i - 1) * 100, 46),
			Face = Color3.fromRGB(46, 40, 44),
			Depth = 6,
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
		Face = C.ember,
		TextSize = 30,
		Depth = 8,
		Sound = "launch",
		OnActivated = function()
			self.onLaunch()
		end,
		Parent = rackPanel,
	})

	-- Centre banner for moments.
	self.banner = Kit.label({ Name = "Banner", Text = "", TextSize = 72, Title = true, Bold = true, Size = UDim2.fromOffset(800, 80), Position = UDim2.fromScale(0.42, 0.42), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 30, Parent = root })
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

-- `step` is the node within the act (1..steps, the last is the boss).
function Hud.setProgress(self: Hud, step: number, steps: number, actText: string?)
	self.pipHolder.Visible = steps > 1
	self.actLabel.Text = actText or ""
	for i, pip in self.pips do
		pip.Visible = i <= steps
		local done = i < step
		local current = i == step
		pip.BackgroundColor3 = if done then C.goldDeep elseif current then C.gold else C.panelLight
		local stroke = pip:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if current then Color3.new(1, 1, 1) else C.goldDeep
		end
	end
end

export type Contribution = { uid: number, name: string, seat: number, damage: number }

-- Splits the monster's lost HP between heroes and labels each share.
function Hud.setContribution(self: Hud, list: { Contribution }, hp: number, maxHp: number)
	local lost = math.max(0, maxHp - hp)
	local total = 0
	for _, c in list do
		total += c.damage
	end
	local x = math.clamp(hp / math.max(1, maxHp), 0, 1)
	for i, seg in self.contribSegs do
		local c = list[i]
		if c and total > 0 and lost > 0 and #list > 1 then
			local w = (lost / maxHp) * (c.damage / total)
			seg.Visible = true
			seg.BackgroundColor3 = Theme.slot(c.seat)
			seg.Position = UDim2.fromScale(x, 0)
			seg.Size = UDim2.fromScale(w, 1)
			x += w
		else
			seg.Visible = false
		end
	end
	for _, ch in self.legend:GetChildren() do
		if ch:IsA("GuiObject") then
			ch:Destroy()
		end
	end
	if #list > 1 then
		for _, c in list do
			local pct = if total > 0 then math.floor(c.damage / total * 100 + 0.5) else 0
			Kit.label({ Text = `● {c.name} {pct}%`, TextSize = 13, Bold = true, TextColor3 = Theme.slot(c.seat), Size = UDim2.fromOffset(100, 18), AutomaticSize = nil, TextXAlignment = Enum.TextXAlignment.Left, Parent = self.legend })
		end
		self.armorLabel.Position = UDim2.new(0, 10, 1, 20)
	else
		self.armorLabel.Position = UDim2.new(0, 10, 1, 2)
	end
end

-- The monster's bust inside the seal: a live 3D view of its model.
function Hud.setEnemyPortrait(self: Hud, modelKey: string)
	if modelKey == self.enemyModelKey then
		return
	end
	self.enemyModelKey = modelKey
	self.enemyFace:ClearAllChildren()
	Kit.corner(999).Parent = self.enemyFace
	local folder = ReplicatedStorage:FindFirstChild("MonsterModels")
	local src = if folder then folder:FindFirstChild(modelKey) else nil
	if not (src and src:IsA("Model")) then
		return
	end
	local vp = Kit.new("ViewportFrame", {
		Name = "Bust",
		BackgroundColor3 = Color3.fromRGB(26, 18, 36),
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 160, 200),
		LightColor = Color3.fromRGB(255, 240, 225),
		LightDirection = Vector3.new(-0.6, -0.8, 0.5),
		ZIndex = 1,
		Parent = self.enemyFace,
	})
	Kit.corner(999).Parent = vp
	local m = src:Clone()
	m.Parent = vp
	local cf, size = m:GetBoundingBox()
	-- The model faces -Z: look at its upper body from the front.
	local focus = cf.Position + Vector3.new(0, size.Y * 0.22, 0)
	local span = math.max(size.X, size.Y * 0.62)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(focus + Vector3.new(span * 0.35, span * 0.12, -span * 1.95), focus)
	cam.Parent = vp
	vp.CurrentCamera = cam
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
	self.threatCard.BackgroundColor3 = if armed then Color3.fromRGB(112, 28, 26) else Color3.fromRGB(40, 22, 28)
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
	self.hullBar.setText(`{hull} / {maxHull}`)
	self.shieldBar.set(math.min(shield, maxHull), maxHull)
	self.shieldBar.setText(if shield > 0 then `SHIELD {shield}` else "no shield")
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
