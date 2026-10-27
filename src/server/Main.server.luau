--!strict
-- Server entry point. The server owns consequential state: damage, rewards,
-- run progress, and persistence. Validate everything clients send.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(`[{Config.GAME_NAME}] server started (Rojo sync OK)`)
