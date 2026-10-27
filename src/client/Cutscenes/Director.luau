--!strict
-- Code-driven camera and short cutscenes (each ≤ 5 s, skippable after the
-- first viewing):
--   intro      workshop → cabinet dolly while the monster rises (first run)
--   fight      monster reveal with a name card (ordinary fights)
--   boss       push-in on the boss, then back to the board
--   leg        leg transition beat: palette shift and banner
-- The fight camera itself never moves during play.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Layout = require(script.Parent.Parent.World.Layout)
local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Audio = require(script.Parent.Parent.Juice.Audio)

local C = Theme.Color

local Director = {}

local FOV = 48
local cam: Camera
local mode: "fight" | "workshop" | "move" = "workshop"
local moveFrom: CFrame = CFrame.identity
local moveTo: () -> CFrame = function()
	return CFrame.identity
end
local moveT = 0
local moveDur = 1
local moveDone: (() -> ())? = nil
local skipButton: Kit.Button? = nil
local skipRequested = false
local overlay: Frame

local function ease(u: number): number
	return u * u * (3 - 2 * u)
end

function Director.fightCFrame(): CFrame
	return Layout.fightCamera(cam.ViewportSize, FOV)
end

function Director.init(parentGui: Frame)
	overlay = parentGui
	cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FOV
	cam.CFrame = Layout.workshopCamera()
	RunService:BindToRenderStep("CabinetCamera", Enum.RenderPriority.Camera.Value + 1, function(dt)
		cam.CameraType = Enum.CameraType.Scriptable
		if mode == "fight" then
			cam.CFrame = Director.fightCFrame()
		elseif mode == "workshop" then
			local t = os.clock()
			-- Slow idle drift in the workshop view.
			cam.CFrame = Layout.workshopCamera() * CFrame.Angles(math.sin(t * 0.2) * 0.01, math.sin(t * 0.13) * 0.02, 0)
		elseif mode == "move" then
			moveT += dt
			if skipRequested then
				moveT = moveDur
			end
			local u = math.clamp(moveT / moveDur, 0, 1)
			cam.CFrame = moveFrom:Lerp(moveTo(), ease(u))
			if u >= 1 then
				mode = "fight"
				local done = moveDone
				moveDone = nil
				if done then
					done()
				end
			end
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if skipButton and (input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == Enum.KeyCode.Escape) then
			skipRequested = true
		end
	end)
end

function Director.mode(): string
	return mode
end

function Director.toWorkshop()
	mode = "workshop"
end

function Director.toFight()
	mode = "fight"
end

local function moveCamera(target: () -> CFrame, duration: number, done: (() -> ())?)
	moveFrom = cam.CFrame
	moveTo = target
	moveT = 0
	moveDur = duration
	moveDone = done
	mode = "move"
end

local function showSkip(skippable: boolean)
	skipRequested = false
	if skipButton then
		(skipButton :: Kit.Button).destroy()
		skipButton = nil
	end
	if skippable then
		skipButton = Kit.button({
			Text = "SKIP ▸",
			Size = UDim2.fromOffset(130, 52),
			Position = UDim2.new(1, -16, 1, -16),
			AnchorPoint = Vector2.new(1, 1),
			Face = C.panelLight,
			TextSize = 20,
			ZIndex = 60,
			OnActivated = function()
				skipRequested = true
			end,
			Parent = overlay,
		})
	end
end

local function hideSkip()
	if skipButton then
		(skipButton :: Kit.Button).destroy()
		skipButton = nil
	end
end

function Director.skipRequested(): boolean
	return skipRequested
end

-- Title card that slides in from the left during reveals.
local function titleCard(title: string, sub: string, color: Color3, hold: number)
	local card = Kit.panel({ Size = UDim2.fromOffset(460, 92), Position = UDim2.new(0, -480, 0.68, 0), AnchorPoint = Vector2.new(0, 0.5), Color = C.panel, ZIndex = 55, Parent = overlay })
	Kit.new("Frame", { Size = UDim2.new(0, 10, 1, -16), Position = UDim2.fromOffset(10, 8), BackgroundColor3 = color, ZIndex = 56, Parent = card })
	Kit.label({ Text = title, TextSize = 34, Bold = true, TextColor3 = color, Size = UDim2.new(1, -40, 0, 42), Position = UDim2.fromOffset(30, 8), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 56, Parent = card })
	Kit.label({ Text = sub, TextSize = 18, TextColor3 = C.textDim, Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(30, 52), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, ZIndex = 56, Parent = card })
	Kit.tween(card, 0.35, { Position = UDim2.new(0, 24, 0.68, 0) }, Enum.EasingStyle.Back)
	Audio.play("whoosh")
	task.delay(hold, function()
		Kit.tween(card, 0.25, { Position = UDim2.new(0, -480, 0.68, 0) })
		task.delay(0.3, function()
			card:Destroy()
		end)
	end)
end

export type RevealArgs = {
	kind: "intro" | "fight" | "boss" | "leg",
	duration: number,
	skippable: boolean,
	autoSkip: boolean?,
	title: string,
	sub: string,
	color: Color3,
	monsterReveal: (seconds: number) -> (),
	monsterHead: () -> Vector3,
	legTitle: string?,
	onLegShift: (() -> ())?,
	onDone: () -> (),
}

-- Plays a cutscene of exactly `duration` seconds (or less when skipped).
function Director.play(a: RevealArgs)
	showSkip(a.skippable)
	if a.autoSkip then
		-- Seen before and the player chose to skip: reveal at once.
		skipRequested = true
	end
	local finished = false
	local function finish()
		if finished then
			return
		end
		finished = true
		hideSkip()
		if skipRequested then
			-- Snap the reveal so a skipped scene still lands cleanly.
			a.monsterReveal(0.3)
		end
		mode = "fight"
		a.onDone()
	end
	local legTime = 0
	if a.legTitle then
		-- Leg beat first: hold the fight view while the cabinet changes colour.
		legTime = math.min(2.6, a.duration * 0.45)
		mode = "fight"
		Audio.play("victory", { pitch = 1.2 })
		titleCard(a.legTitle, "New palette. Tougher monsters.", C.gold, legTime - 0.4)
		if a.onLegShift then
			(a.onLegShift :: () -> ())()
		end
	end
	local rest = a.duration - legTime
	task.delay(legTime, function()
		if finished then
			return
		end
		if a.kind == "intro" then
			cam.CFrame = Layout.workshopCamera()
			moveCamera(Director.fightCFrame, rest * 0.85, nil)
			task.delay(rest * 0.3, function()
				a.monsterReveal(rest * 0.45)
				Audio.play("telegraph", { pitch = 0.8 })
			end)
			task.delay(rest * 0.45, function()
				titleCard(a.title, a.sub, a.color, rest * 0.5)
			end)
		elseif a.kind == "boss" then
			local head = a.monsterHead()
			local push = CFrame.lookAt(head + Vector3.new(-6, -1, 16), head - Vector3.new(0, 2, 0))
			a.monsterReveal(rest * 0.4)
			Audio.play("telegraph", { pitch = 0.6 })
			moveCamera(function()
				return push
			end, rest * 0.35, function()
				moveCamera(Director.fightCFrame, rest * 0.35, nil)
			end)
			titleCard(a.title, a.sub, a.color, rest * 0.75)
		else
			mode = "fight"
			a.monsterReveal(rest * 0.5)
			titleCard(a.title, a.sub, a.color, rest * 0.7)
		end
		local t0 = os.clock()
		while os.clock() - t0 < rest and not skipRequested do
			task.wait()
		end
		finish()
	end)
	-- A skip during the leg beat ends the whole sequence.
	task.spawn(function()
		while not finished do
			if skipRequested then
				finish()
			end
			task.wait()
		end
	end)
end

return Director
