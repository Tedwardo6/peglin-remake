--!strict
-- The compact workshop room the cabinet stands in: plank floor, panelled
-- back wall with a bright window, pegboard of tools, ball shelves, a kit
-- bench, hanging lamps, and the monster's stage. Code-built placeholder
-- set dressing in one module, replaceable by a modelled room later.

local Build = require(script.Parent.Build)
local Layout = require(script.Parent.Layout)

local Workshop = {}

export type Handles = {
	model: Model,
	stage: BasePart,
	stageRim: BasePart,
	kitCases: { [string]: BasePart },
	lamps: { BasePart },
	setStageColor: (color: Color3) -> (),
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

function Workshop.build(parent: Instance): Handles
	local model = Build.model("Workshop", parent)
	local root = Layout.ROOT
	local fy = Layout.FLOOR_Y
	local bz = Layout.BOARD_CENTER.Z

	-- Floor planks.
	local woodA, woodB = c(196, 136, 88), c(178, 118, 74)
	for i = 0, 19 do
		Build.block(model, Vector3.new(4, 1, 70), CFrame.new(root.X - 40 + i * 4 + 2, fy - 0.5, bz + 10), if i % 2 == 0 then woodA else woodB)
	end
	-- Rug under the cabinet.
	Build.cylinder(model, 0.12, 22, CFrame.new(root.X, fy + 0.06, bz + 1.5) * CFrame.Angles(0, 0, math.rad(90)), c(64, 82, 170))
	Build.cylinder(model, 0.14, 17, CFrame.new(root.X, fy + 0.07, bz + 1.5) * CFrame.Angles(0, 0, math.rad(90)), c(92, 116, 220))

	-- Back wall with wainscot and trim.
	local wallZ = bz - 7
	Build.block(model, Vector3.new(84, 46, 1), CFrame.new(root.X, fy + 23, wallZ), c(118, 196, 196))
	Build.block(model, Vector3.new(84, 7, 1.3), CFrame.new(root.X, fy + 3.5, wallZ + 0.2), c(70, 132, 150))
	Build.block(model, Vector3.new(84, 0.6, 1.6), CFrame.new(root.X, fy + 7.2, wallZ + 0.3), c(250, 236, 200))
	-- Side walls.
	for _, sx in { -1, 1 } do
		Build.block(model, Vector3.new(1, 46, 60), CFrame.new(root.X + sx * 42, fy + 23, bz + 22), c(104, 178, 182))
	end

	-- Window with daylight glow (left of the cabinet).
	local winC = Vector3.new(root.X - 21, fy + 21, wallZ + 0.6)
	Build.block(model, Vector3.new(13, 12, 0.6), CFrame.new(winC), c(250, 236, 200))
	Build.block(model, Vector3.new(11.6, 10.6, 0.4), CFrame.new(winC + Vector3.new(0, 0, 0.2)), c(170, 230, 255), { material = Enum.Material.Neon, transparency = 0.15 })
	Build.block(model, Vector3.new(0.5, 10.6, 0.5), CFrame.new(winC + Vector3.new(0, 0, 0.45)), c(250, 236, 200))
	Build.block(model, Vector3.new(11.6, 0.5, 0.5), CFrame.new(winC + Vector3.new(0, 0, 0.45)), c(250, 236, 200))

	-- Pegboard of tools (right of the cabinet, behind the stage).
	local pbC = Vector3.new(root.X + 26, fy + 22, wallZ + 0.6)
	Build.block(model, Vector3.new(14, 10, 0.4), CFrame.new(pbC), c(214, 170, 120))
	for ix = -6, 6, 2 do
		for iy = -4, 4, 2 do
			Build.disc(model, 0.25, 0.1, pbC + Vector3.new(ix * 0.9, iy * 0.9, 0.25), c(150, 110, 70))
		end
	end
	-- Wrench and hammer silhouettes.
	Build.block(model, Vector3.new(0.6, 5, 0.3), CFrame.new(pbC + Vector3.new(-4, 0, 0.4)) * CFrame.Angles(0, 0, math.rad(15)), c(170, 180, 200))
	Build.cylinder(model, 0.3, 1.8, CFrame.new(pbC + Vector3.new(-4.6, 2.4, 0.4)) * CFrame.Angles(0, math.rad(90), 0), c(170, 180, 200))
	Build.block(model, Vector3.new(0.5, 4.2, 0.3), CFrame.new(pbC + Vector3.new(0, -0.4, 0.4)), c(180, 110, 60))
	Build.block(model, Vector3.new(2.6, 1.0, 0.4), CFrame.new(pbC + Vector3.new(0, 1.9, 0.45)), c(120, 130, 150))
	Build.block(model, Vector3.new(0.5, 3.4, 0.3), CFrame.new(pbC + Vector3.new(4, 0, 0.4)) * CFrame.Angles(0, 0, math.rad(-12)), c(240, 90, 80))

	-- Ball shelves (left and right of the window).
	local ballColors = { c(255, 214, 64), c(120, 255, 236), c(206, 140, 255), c(110, 170, 255), c(255, 120, 80), c(245, 245, 255) }
	for s, shelfX in { root.X - 35, root.X + 12 } do
		for row = 0, 1 do
			local y = fy + 13 + row * 5
			Build.block(model, Vector3.new(9, 0.5, 2.4), CFrame.new(shelfX, y, wallZ + 1.4), c(160, 104, 64))
			for i = 0, 3 do
				local col = ballColors[((i + row * 2 + s) % #ballColors) + 1]
				Build.ball(model, 1.5, Vector3.new(shelfX - 3 + i * 2, y + 1.0, wallZ + 1.6), col)
			end
		end
	end

	-- Kit bench with three cases (left foreground).
	local benchC = Vector3.new(root.X - 22, fy, bz + 5)
	Build.block(model, Vector3.new(12, 0.8, 5), CFrame.new(benchC + Vector3.new(0, 4.4, 0)), c(160, 104, 64))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.block(model, Vector3.new(0.7, 4.0, 0.7), CFrame.new(benchC + Vector3.new(sx * 5.3, 2.0, sz * 2.0)), c(120, 76, 46))
		end
	end
	local kitCases: { [string]: BasePart } = {}
	local kitCols = { ricochet = c(255, 196, 46), relay = c(190, 92, 255), guard = c(64, 150, 255) }
	local ids = { "ricochet", "relay", "guard" }
	for i, id in ids do
		local pos = benchC + Vector3.new(-3.6 + (i - 1) * 3.6, 5.8, 0)
		local case = Build.block(model, Vector3.new(3, 2, 2.2), CFrame.new(pos), kitCols[id])
		Build.block(model, Vector3.new(3.1, 0.25, 2.3), CFrame.new(pos + Vector3.new(0, 0.3, 0)), Build.INK)
		Build.block(model, Vector3.new(1.2, 0.3, 0.3), CFrame.new(pos + Vector3.new(0, 1.2, 0)), Build.INK)
		kitCases[id] = case
	end

	-- Monster stage: a round pedestal with a rim and spotlights.
	local stagePos = Layout.MONSTER_BASE
	local stage = Build.cylinder(model, stagePos.Y - fy, 14, CFrame.new(Vector3.new(stagePos.X, (stagePos.Y + fy) / 2, stagePos.Z)) * CFrame.Angles(0, 0, math.rad(90)), c(70, 80, 150))
	local rim = Build.cylinder(model, 0.6, 14.8, CFrame.new(Vector3.new(stagePos.X, stagePos.Y - 0.25, stagePos.Z)) * CFrame.Angles(0, 0, math.rad(90)), c(255, 214, 64))
	Build.cylinder(model, 0.3, 13, CFrame.new(Vector3.new(stagePos.X, stagePos.Y + 0.02, stagePos.Z)) * CFrame.Angles(0, 0, math.rad(90)), c(92, 108, 190))
	local stageModel = Build.model("Stage", model)
	stage.Parent = stageModel
	rim.Parent = stageModel
	Build.outline(stageModel)

	-- Hanging lamps.
	local lamps: { BasePart } = {}
	for _, lx in { root.X - 14, root.X + 2, root.X + 18 } do
		Build.block(model, Vector3.new(0.2, 8, 0.2), CFrame.new(lx, fy + 38, bz + 2), Build.INK)
		Build.cylinder(model, 1.6, 3.2, CFrame.new(lx, fy + 33.6, bz + 2) * CFrame.Angles(0, 0, math.rad(90)), c(255, 214, 64))
		local bulb = Build.ball(model, 1.4, Vector3.new(lx, fy + 32.6, bz + 2), c(255, 244, 210), { material = Enum.Material.Neon })
		table.insert(lamps, bulb)
	end
	-- No PointLights: on lower graphics levels (common on phones) they wash
	-- the whole room out. The place's own Lighting does the work.

	return {
		model = model,
		stage = stage,
		stageRim = rim,
		kitCases = kitCases,
		lamps = lamps,
		setStageColor = function(color: Color3)
			rim.Color = color
		end,
	}
end

return Workshop
