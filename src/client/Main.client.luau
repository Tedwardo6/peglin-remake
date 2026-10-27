--!strict
-- Client entry point. The client owns input and presentation and predicts
-- its own shots with the shared simulation; the server decides results.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local Game = require(script.Parent.Game)

print(`[{Config.GAME_NAME}] client started (Rojo sync OK)`)

-- No avatar in this game: hide the default backpack/health UI.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local gui = Instance.new("ScreenGui")
gui.Name = "CabinetUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ScreenInsets = Enum.ScreenInsets.None
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

-- Design canvas 1100×560, scaled to the screen so text stays readable on
-- phones (scale floor 0.62) while the corners stay in thumb reach.
local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Parent = gui
local scale = Instance.new("UIScale")
scale.Parent = root
local safe = Instance.new("UIPadding")
safe.Parent = root

local function resize()
	local cam = workspace.CurrentCamera
	local vp = cam.ViewportSize
	local s = math.clamp(math.min(vp.X / 1100, vp.Y / 560), 0.62, 1.35)
	scale.Scale = s
	root.Size = UDim2.fromOffset(vp.X / s, vp.Y / s)
	-- Keep controls clear of notches and the Roblox top bar.
	local inset = game:GetService("GuiService"):GetGuiInset()
	safe.PaddingTop = UDim.new(0, math.floor(inset.Y / s))
end
resize()
workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize)

Game.start(gui, root)
