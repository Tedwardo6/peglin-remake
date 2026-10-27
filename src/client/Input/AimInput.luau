--!strict
-- Aiming and launching are separate controls (plan §2):
--   touch: drag anywhere outside buttons to aim; tap LAUNCH to fire
--   mouse: point to aim; click the board or press Space to fire
--   keyboard: A/D or ←/→ fine-tune; 1/2/3 pick a ball; Space/Enter fire
--   gamepad: left stick aims; LB/RB pick a ball; A or RT fires
-- Output is the quantized aim integer the server will simulate.

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Aim = require(Shared.Sim.Aim)

local Layout = require(script.Parent.Parent.World.Layout)

export type Callbacks = {
	onAim: (aim: number) -> (),
	onLaunch: () -> (),
	onSlot: (slot: number) -> (),
	onActivity: () -> (),
}

local AimInput = {}

local cb: Callbacks
local enabled = false
local aim = 0
local dragging: InputObject? = nil
local stickX = 0
local keyDir = 0
local lastSent = 0

function AimInput.device(): string
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return "gamepad"
	end
	return "keyboard"
end

local function setAim(a: number)
	a = Aim.clamp(a)
	if a ~= aim then
		aim = a
		cb.onAim(aim)
		local now = os.clock()
		if now - lastSent > 1 then
			lastSent = now
			cb.onActivity()
		end
	end
end

local function aimAtScreen(pos: Vector2)
	local cam = workspace.CurrentCamera
	local ray = cam:ViewportPointToRay(pos.X, pos.Y)
	local planeZ = Layout.BOARD_CENTER.Z + Layout.PEG_Z
	if math.abs(ray.Direction.Z) < 1e-4 then
		return
	end
	local t = (planeZ - ray.Origin.Z) / ray.Direction.Z
	if t <= 0 then
		return
	end
	local hit = ray.Origin + ray.Direction * t
	local bx, by = Layout.worldToBoard(hit)
	local dx = bx - Config.Board.LAUNCH_X
	local dy = by - Config.Board.LAUNCH_Y
	if dy < 0.6 then
		dy = 0.6
	end
	setAim(Aim.fromDirection(dx, dy))
end

function AimInput.init(callbacks: Callbacks)
	cb = callbacks
	UserInputService.InputBegan:Connect(function(input, processed)
		if not enabled then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch then
			if processed then
				return
			end
			dragging = input
			aimAtScreen(Vector2.new(input.Position.X, input.Position.Y))
		elseif t == Enum.UserInputType.MouseButton1 then
			if processed then
				return
			end
			aimAtScreen(UserInputService:GetMouseLocation())
			cb.onLaunch()
		elseif t == Enum.UserInputType.Keyboard then
			if processed then
				return
			end
			local k = input.KeyCode
			if k == Enum.KeyCode.Space or k == Enum.KeyCode.Return then
				cb.onLaunch()
			elseif k == Enum.KeyCode.One then
				cb.onSlot(1)
			elseif k == Enum.KeyCode.Two then
				cb.onSlot(2)
			elseif k == Enum.KeyCode.Three then
				cb.onSlot(3)
			elseif k == Enum.KeyCode.A or k == Enum.KeyCode.Left then
				keyDir = -1
			elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
				keyDir = 1
			end
		elseif t == Enum.UserInputType.Gamepad1 then
			local k = input.KeyCode
			if k == Enum.KeyCode.ButtonA or k == Enum.KeyCode.ButtonR2 then
				cb.onLaunch()
			elseif k == Enum.KeyCode.ButtonL1 then
				cb.onSlot(-1)
			elseif k == Enum.KeyCode.ButtonR1 then
				cb.onSlot(-2)
			end
		end
	end)
	UserInputService.InputChanged:Connect(function(input, processed)
		if not enabled then
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.Touch and (dragging :: any) == input then
			local pos: Vector3 = input.Position
			aimAtScreen(Vector2.new(pos.X, pos.Y))
		elseif t == Enum.UserInputType.MouseMovement and not processed then
			aimAtScreen(UserInputService:GetMouseLocation())
		elseif t == Enum.UserInputType.Gamepad1 and input.KeyCode == Enum.KeyCode.Thumbstick1 then
			stickX = if math.abs(input.Position.X) > 0.15 then input.Position.X else 0
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if (dragging :: any) == input then
			dragging = nil
		end
		if input.UserInputType == Enum.UserInputType.Keyboard then
			local k = input.KeyCode
			if k == Enum.KeyCode.A or k == Enum.KeyCode.Left or k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
				keyDir = 0
			end
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if not enabled then
			return
		end
		-- Rate-based fine aiming for keys and sticks (slower near centre).
		local rate = stickX * 900 + keyDir * 520
		if rate ~= 0 then
			setAim(aim + rate * dt)
		end
	end)
end

function AimInput.setEnabled(on: boolean)
	enabled = on
	if not on then
		dragging = nil
		keyDir = 0
		stickX = 0
	end
end

function AimInput.get(): number
	return aim
end

function AimInput.set(a: number)
	aim = Aim.clamp(a)
end

return AimInput
