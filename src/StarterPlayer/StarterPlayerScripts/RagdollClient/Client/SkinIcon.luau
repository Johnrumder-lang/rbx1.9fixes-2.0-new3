--!nonstrict
-- SkinIcon (v2.1e): what a skin LOOKS like - not a weapon but its material and colour: a big sphere in the MAIN colour + material, and
-- two tiles beside it in the DARK and the ACCENT ones (the same colours and materials the weapon gets, WeaponSkins.Paint). It turns slowly
-- so the light runs over the texture. Square corners like the rest of the game.
-- SkinIcon.new(parent, skin, size) -> ViewportFrame

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponSkins = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeaponSkins"))

local SkinIcon = {}

local active: { [ViewportFrame]: { cam: Camera, seed: number } } = {}
local connected = false

local CENTER = Vector3.new(0, 0, 0)
local DIST = 6.2

local function ensureLoop()
	if connected then
		return
	end
	connected = true
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for vp, st in active do
			if not vp.Parent then
				active[vp] = nil
			elseif vp.Visible and vp.AbsoluteSize.X > 0 then
				local a = t * 0.45 + st.seed
				st.cam.CFrame = CFrame.lookAt(Vector3.new(math.sin(a) * 1.7, 1.5, DIST), CENTER)
			end
		end
	end)
end

function SkinIcon.new(parent: Instance, skin: WeaponSkins.Skin, size: UDim2): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Size = size
	vp.BackgroundColor3 = Color3.fromRGB(14, 15, 18)
	vp.BackgroundTransparency = 0
	vp.BorderSizePixel = 0
	vp.Ambient = Color3.fromRGB(140, 140, 146)
	vp.LightColor = Color3.fromRGB(255, 252, 245)
	vp.LightDirection = Vector3.new(-0.5, -0.8, -0.7)
	vp.Parent = parent
	local model = Instance.new("Model")
	model.Parent = vp
	local function piece(shape: Enum.PartType, sz: Vector3, at: Vector3, lum: number)
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.Shape = shape
		p.Size = sz
		p.CFrame = CFrame.new(at)
		local color, material, refl = WeaponSkins.Paint(skin.look, lum)
		p.Color = color
		p.Material = material
		p.Reflectance = refl
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		return p
	end
	piece(Enum.PartType.Ball, Vector3.new(3.2, 3.2, 3.2), Vector3.new(0, 0.35, 0), 0.4) -- the MAIN material
	piece(Enum.PartType.Block, Vector3.new(1.5, 1.5, 1.5), Vector3.new(-2.1, -1.5, 0.6), 0.05) -- the DARK one
	piece(Enum.PartType.Block, Vector3.new(1.5, 1.5, 1.5), Vector3.new(2.1, -1.5, 0.6), 0.9) -- the ACCENT one
	local cam = Instance.new("Camera")
	cam.FieldOfView = 42
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 1.5, DIST), CENTER)
	vp.CurrentCamera = cam
	cam.Parent = vp
	active[vp] = { cam = cam, seed = math.random() * 6 }
	ensureLoop()
	return vp
end

return SkinIcon
