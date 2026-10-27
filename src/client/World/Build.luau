--!strict
-- Small helpers for building the scene from parts. Everything is anchored,
-- non-colliding and query-free: the scene is presentation only.

local Build = {}

Build.INK = Color3.fromRGB(8, 15, 56)

export type Opts = {
	material: Enum.Material?,
	transparency: number?,
	shadow: boolean?,
	name: string?,
	reflect: number?,
}

local function base(className: string, parent: Instance?, color: Color3, opts: Opts?): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = if opts and opts.shadow ~= nil then opts.shadow else false
	p.Material = if opts and opts.material then opts.material else Enum.Material.SmoothPlastic
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Reflectance = if opts and opts.reflect then opts.reflect else 0
	if opts and opts.transparency then
		p.Transparency = opts.transparency
	end
	if opts and opts.name then
		p.Name = opts.name
	end
	p.Parent = parent
	return p
end

function Build.block(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): Part
	local p = base("Part", parent, color, opts) :: Part
	p.Shape = Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	return p
end

function Build.ball(parent: Instance?, diameter: number, pos: Vector3, color: Color3, opts: Opts?): Part
	local p = base("Part", parent, color, opts) :: Part
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * diameter
	p.CFrame = CFrame.new(pos)
	return p
end

-- Cylinder whose axis points along the CFrame's X axis.
function Build.cylinder(parent: Instance?, length: number, diameter: number, cf: CFrame, color: Color3, opts: Opts?): Part
	local p = base("Part", parent, color, opts) :: Part
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.CFrame = cf
	return p
end

-- Disc facing the camera (+Z): a cylinder rotated so its axis is Z.
function Build.disc(parent: Instance?, diameter: number, depth: number, pos: Vector3, color: Color3, opts: Opts?): Part
	return Build.cylinder(parent, depth, diameter, CFrame.new(pos) * CFrame.Angles(0, math.rad(90), 0), color, opts)
end

-- Non-uniform ellipsoid via a sphere SpecialMesh (part keeps a uniform box).
function Build.ellipsoid(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): Part
	local p = base("Part", parent, color, opts) :: Part
	p.Shape = Enum.PartType.Block
	p.Size = size
	p.CFrame = cf
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

function Build.wedge(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, opts: Opts?): WedgePart
	local p = base("WedgePart", parent, color, opts) :: WedgePart
	p.Size = size
	p.CFrame = cf
	return p
end

function Build.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- One outline for a whole model (monster, cabinet frame).
function Build.outline(model: Instance, thickness: number?): Highlight
	local h = Instance.new("Highlight")
	h.Adornee = model
	h.FillTransparency = 1
	h.OutlineColor = Build.INK
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	return h
end

function Build.light(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Shadows = false
	l.Parent = parent
	return l
end

return Build
