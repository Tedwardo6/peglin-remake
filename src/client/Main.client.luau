--!strict
-- Client entry point. The client owns input, presentation, and local
-- ball physics; it reports results for the server to validate.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

print(`[{Config.GAME_NAME}] client started (Rojo sync OK)`)
