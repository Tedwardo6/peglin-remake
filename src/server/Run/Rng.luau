--!strict
-- Kept for existing requires; the PRNG lives in Shared so the client can
-- reproduce act maps.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Rng = require(ReplicatedStorage:WaitForChild("Shared").Sim.Rng)
export type Rng = Rng.Rng
return Rng
