--!strict
-- Developer Monster Gallery: shows every monster on the battlefield and
-- runs it through each animation (reveal, idle, threat wind-up, slam,
-- flinches small to big, armor, death) so animation quality can be checked
-- and approved monster by monster. Studio or experience owner only (the
-- lobby shows the button to those players).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enemies = require(Shared.Content.Enemies)
local Campaigns = require(Shared.Content.Campaigns)

local Layout = require(script.Parent.Layout)
local Monster = require(script.Parent.Monster)
local Hero = require(script.Parent.Hero)
local Scenery = require(script.Parent.Scenery)
local Theme = require(script.Parent.Parent.UI.Theme)
local Kit = require(script.Parent.Parent.UI.Kit)
local Fx = require(script.Parent.Parent.Juice.Fx)
local Audio = require(script.Parent.Parent.Juice.Audio)

local C = Theme.Color

local Gallery = {}

local running = false
local token = 0

-- Which act scene each monster appears in (for a fair lighting check).
local function sceneFor(enemyId: string): (string, Scenery.ActPalette?)
	local camp = Campaigns.ById[Campaigns.DEFAULT]
	for _, act in camp.acts do
		if act.boss == enemyId or act.opener == enemyId or table.find(act.pool, enemyId) then
			return act.scene, act.palette
		end
	end
	return camp.acts[1].scene, camp.acts[1].palette
end

function Gallery.active(): boolean
	return running
end

function Gallery.start(worldRoot: Instance, gui: Instance, onExit: () -> ())
	if running then
		return
	end
	running = true
	token += 1
	local myToken = token
	local folder = Instance.new("Folder")
	folder.Name = "Gallery"
	folder.Parent = worldRoot
	local hero = Hero.new(folder, Players.LocalPlayer.UserId, "guard", Theme.slot(1), Layout.heroSpot(1, 1), Layout.HERO_FACING)

	local panel = Kit.panel({ Size = UDim2.fromOffset(520, 120), Position = UDim2.new(0.5, 0, 1, -16), AnchorPoint = Vector2.new(0.5, 1), Color = C.panel, ZIndex = 40, Parent = gui })
	local title = Kit.label({ Text = "", Title = true, Bold = true, TextSize = 30, TextColor3 = C.gold, Size = UDim2.new(1, -20, 0, 34), Position = UDim2.fromOffset(10, 6), ZIndex = 41, Parent = panel })
	local phase = Kit.label({ Text = "", TextSize = 16, TextColor3 = C.textDim, Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 40), ZIndex = 41, Parent = panel })

	local ids = Enemies.Order
	local index = 1
	local paused = false
	local skip = 0
	local current: Monster.Monster? = nil

	local function stop()
		running = false
		token += 1
		if current then
			(current :: Monster.Monster):destroy()
		end
		hero:destroy()
		folder:Destroy()
		panel:Destroy()
		onExit()
	end
	Kit.button({ Text = "◀ PREV", Size = UDim2.fromOffset(110, 44), Position = UDim2.fromOffset(10, 68), Face = C.panelLight, TextSize = 15, ZIndex = 42, OnActivated = function()
		index = ((index - 3) % #ids) + 1
		skip += 1
	end, Parent = panel })
	local pauseBtn: Kit.Button
	pauseBtn = Kit.button({ Text = "PAUSE", Size = UDim2.fromOffset(110, 44), Position = UDim2.fromOffset(130, 68), Face = C.panelLight, TextSize = 15, ZIndex = 42, OnActivated = function()
		paused = not paused
		pauseBtn.setText(if paused then "RESUME" else "PAUSE")
	end, Parent = panel })
	Kit.button({ Text = "NEXT ▶", Size = UDim2.fromOffset(110, 44), Position = UDim2.fromOffset(250, 68), Face = C.panelLight, TextSize = 15, ZIndex = 42, OnActivated = function()
		skip += 1
	end, Parent = panel })
	Kit.button({ Text = "EXIT", Size = UDim2.fromOffset(130, 44), Position = UDim2.new(1, -10, 0, 68), AnchorPoint = Vector2.new(1, 0), Face = C.redDeep, TextSize = 15, ZIndex = 42, OnActivated = stop, Parent = panel })

	task.spawn(function()
		while running and token == myToken do
			local id = ids[index]
			local def = Enemies.ById[id]
			local scene, pal = sceneFor(id)
			if pal then
				Scenery.setScene(scene, pal)
			end
			if current then
				(current :: Monster.Monster):destroy()
			end
			local m = Monster.new(folder, id, Layout.MONSTER_BASE)
			current = m
			m:hide()
			title.Text = `{index}/{#ids} · {def.name}{if m.fallback then " (model missing!)" else ""}`
			local mySkip = skip
			local function wait(s: number): boolean
				local t0 = os.clock()
				while os.clock() - t0 < s do
					if not running or token ~= myToken or skip ~= mySkip then
						return false
					end
					if paused then
						t0 += 1 / 60
					end
					task.wait()
				end
				return true
			end
			local steps: { { name: string, run: () -> (), hold: number } } = {
				{ name = "Reveal", run = function()
					m:revealIn(1.2)
				end, hold = 1.6 },
				{ name = "Idle", run = function() end, hold = 2.5 },
				{ name = "Threat wind-up", run = function()
					task.spawn(function()
						for k = 0, 30 do
							if m.dead then
								return
							end
							m:setTelegraph(k / 30, k > 22)
							task.wait(2.4 / 30)
						end
					end)
				end, hold = 2.6 },
				{ name = "Slam", run = function()
					m:setTelegraph(0, false)
					m:attack()
					Audio.play("telegraph", { pitch = 1.1 })
					hero:hit()
				end, hold = 1.4 },
				{ name = "Small hits", run = function()
					task.spawn(function()
						for _ = 1, 3 do
							m:hit(8, false)
							Fx.number(m:centerPosition() + Vector3.new(0, 1, 2), "8", Theme.slot(1), 8)
							task.wait(0.35)
						end
					end)
				end, hold = 1.6 },
				{ name = "Big strike", run = function()
					hero:strike(0.25, function()
						Fx.bolt(hero:weaponPosition(), m:centerPosition(), Theme.slot(1), 0.18, function()
							m:hit(70, true)
							Fx.number(m:centerPosition() + Vector3.new(0, 1, 2), "70", Theme.slot(1), 70)
							Audio.play("bigHit", { pitch = 0.9 })
						end)
					end)
				end, hold = 1.6 },
				{ name = "Armor up / down", run = function()
					m:setArmor(true)
					task.delay(1.2, function()
						m:setArmor(false)
					end)
				end, hold = 1.8 },
				{ name = "Death", run = function()
					m:die()
					Audio.play("monsterDeath")
				end, hold = 2 },
			}
			local ok = true
			for _, s in steps do
				phase.Text = s.name
				s.run()
				if not wait(s.hold) then
					ok = false
					break
				end
			end
			if not running or token ~= myToken then
				break
			end
			if ok or skip ~= mySkip then
				index = (index % #ids) + 1
			end
		end
	end)
end

return Gallery
