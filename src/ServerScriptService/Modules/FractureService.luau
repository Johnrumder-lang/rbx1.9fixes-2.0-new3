--!nonstrict
-- FractureService (v2.0): buildings break.
-- Every wall of a house / building ("Fracture" attribute, set by Register) can get holes: an explosion, a rocket, a
-- car crashing into it at speed, a super punch or enough bullets on one spot knock a hole in it. The wall is cut
-- into a few big pieces around the hole (no gap, no flicker) and the bit that was in the hole flies away as
-- chunks of the same material. A wall can be broken again and again; a while after the last hit (when nobody
-- stands there) the original wall comes back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Modules = script.Parent
local GoreService = require(Modules:WaitForChild("GoreService"))

local FractureService = {}

local WALL_NAMES = {
	Wall = true, InnerWall = true, BathWall = true, StairWall = true, HangarSide = true, HangarBack = true,
	-- (v2.0 maps)
	ShipWall = true, CabinWall = true, StoreWall = true, AisleWall = true, HorrorWall = true, Partition = true,
	-- (v2.0) the houses all through (floors, the roof edge) and the construction site (its slabs and fences)
	UpperFloor = true, Parapet = true, FencePanel = true, ScaffoldPlank = true, TowerWall = true, KitchenWall = true,
}
local function fracturable(name: string): boolean
	return WALL_NAMES[name] == true or string.match(name, "^Slab_%d+$") ~= nil
end
local MAX_DEBRIS = 180 -- (v2.8: was 420 - the server simulated them all)
local MAX_CHUNKS = 18 -- chunks one hole throws at most (v2.8: was 26)

type Rec = { part: BasePart, parent: Instance, pieces: { BasePart }, t: number, box: CFrame, size: Vector3 }
local roots: { [string]: Rec } = {}
local nextId = 0
local debris: { BasePart } = {}
local hold: Folder? = nil
local rng = Random.new()

local function holdFolder(): Folder
	if hold and hold.Parent then
		return hold
	end
	local f = Instance.new("Folder")
	f.Name = "BrokenWalls"
	f.Parent = ServerStorage
	hold = f
	return f
end

local function fxFolder(): Instance
	return workspace:FindFirstChild("FX") or workspace
end

-- mark the walls under `root` (a map, a loaded map) that can break
function FractureService.Register(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Anchored and fracturable(d.Name) and d.Material ~= Enum.Material.Glass and not d:GetAttribute("Destructible") then
			local s = d.Size
			local thin = math.min(s.X, s.Y, s.Z)
			if thin <= 3 and s.Magnitude > 4 then
				d:SetAttribute("Fracture", true)
			end
		end
	end
end

-- the closest point of a part's box to `p`
function FractureService.Closest(part: BasePart, p: Vector3): Vector3
	local l = part.CFrame:PointToObjectSpace(p)
	local h = part.Size * 0.5
	return part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z)))
end

local function addDebris(p: BasePart)
	table.insert(debris, p)
	while #debris > MAX_DEBRIS do
		local old = table.remove(debris, 1)
		if old and old.Parent then
			old:Destroy()
		end
	end
	p:SetAttribute("BornAt", os.clock())
	task.delay(rng:NextNumber(16, 26), function()
		if p.Parent then
			p:Destroy()
		end
	end)
end

-- (v2.8) rubble that has come to rest is pinned where it lies: it looks the same and costs the physics nothing
task.spawn(function()
	while true do
		task.wait(1.5)
		local now = os.clock()
		for _, p in debris do
			if p.Parent and not p.Anchored then
				local born = p:GetAttribute("BornAt")
				if typeof(born) == "number" and now - born > 2.5 and p.AssemblyLinearVelocity.Magnitude < 0.8 and p.AssemblyAngularVelocity.Magnitude < 1 then
					p.Anchored = true
					p.CanTouch = false
					p:SetAttribute("Settled", true) -- (grabbing it lets it go again: OwnershipService)
				end
			end
		end
	end
end)

-- axis helpers: component i (1 = X, 2 = Y, 3 = Z) of a vector
local function comp(v: Vector3, i: number): number
	return i == 1 and v.X or (i == 2 and v.Y or v.Z)
end
local function vec(i: number, a: number, j: number, b: number, k: number, c: number): Vector3
	local t = { 0, 0, 0 }
	t[i], t[j], t[k] = a, b, c
	return Vector3.new(t[1], t[2], t[3])
end

-- knock a hole of `radius` around `point` (world) into `part`; `dir` / `power` throw the chunks
function FractureService.Fracture(part: BasePart, point: Vector3, radius: number, dir: Vector3?, power: number?): boolean
	if not part.Parent or not part.Anchored or not part:GetAttribute("Fracture") then
		return false
	end
	local size = part.Size
	local partCF = part.CFrame
	-- the thin axis is the wall's thickness; u and v run along its face
	local n = 1
	if size.Y < comp(size, n) then
		n = 2
	end
	if size.Z < comp(size, n) then
		n = 3
	end
	local u = n == 1 and 2 or 1
	local v = (n == 3) and 2 or 3
	if u == v then
		v = 3
	end
	local su, sv, sn = comp(size, u), comp(size, v), comp(size, n)
	local lp = partCF:PointToObjectSpace(point)
	local cu = math.clamp(comp(lp, u), -su / 2, su / 2)
	local cv = math.clamp(comp(lp, v), -sv / 2, sv / 2)
	-- the grid
	local cell = math.clamp(radius * 0.42, 0.9, 4)
	local nu = math.max(1, math.ceil(su / cell))
	local nv = math.max(1, math.ceil(sv / cell))
	while nu * nv > 1400 do
		cell *= 1.25
		nu = math.max(1, math.ceil(su / cell))
		nv = math.max(1, math.ceil(sv / cell))
	end
	local du, dv = su / nu, sv / nv
	local hole: { { boolean } } = {}
	local any, all = false, true
	local holeCells = {}
	for i = 1, nu do
		hole[i] = {}
		local x = -su / 2 + (i - 0.5) * du
		for j = 1, nv do
			local y = -sv / 2 + (j - 0.5) * dv
			local d = math.sqrt((x - cu) ^ 2 + (y - cv) ^ 2)
			-- a ragged edge
			local edge = radius * (0.82 + 0.36 * ((math.sin(i * 12.9898 + j * 78.233) * 43758.5453) % 1))
			local h = d <= edge
			hole[i][j] = h
			if h then
				any = true
				table.insert(holeCells, { x, y })
			else
				all = false
			end
		end
	end
	if not any then
		return false
	end
	-- whose wall is it (a piece of an already broken wall belongs to the original)
	local rootId = part:GetAttribute("FractureRoot")
	local rec = typeof(rootId) == "string" and roots[rootId] or nil
	if not rec then
		nextId += 1
		rootId = "W" .. nextId
		rec = { part = part, parent = part.Parent :: Instance, pieces = {}, t = os.clock(), box = part.CFrame, size = part.Size }
		roots[rootId :: string] = rec
	end
	local r = rec :: Rec
	r.t = os.clock()
	-- the solid rest: greedy rectangles over the cells that are not in the hole
	local template = part:Clone()
	template:SetAttribute("FractureRoot", rootId)
	for _, c in template:GetChildren() do
		if not (c:IsA("Texture") or c:IsA("Decal") or c:IsA("SurfaceAppearance")) then
			c:Destroy()
		end
	end
	local used: { { boolean } } = {}
	for i = 1, nu do
		used[i] = {}
	end
	local made = 0
	if not all then
		for j = 1, nv do
			for i = 1, nu do
				if not hole[i][j] and not used[i][j] then
					-- widest run along u
					local i1 = i
					while i1 + 1 <= nu and not hole[i1 + 1][j] and not used[i1 + 1][j] do
						i1 += 1
					end
					-- as many rows down as the run stays solid
					local j1 = j
					local ok = true
					while ok and j1 + 1 <= nv do
						for ii = i, i1 do
							if hole[ii][j1 + 1] or used[ii][j1 + 1] then
								ok = false
								break
							end
						end
						if ok then
							j1 += 1
						end
					end
					for ii = i, i1 do
						for jj = j, j1 do
							used[ii][jj] = true
						end
					end
					local u0, u1 = -su / 2 + (i - 1) * du, -su / 2 + i1 * du
					local v0, v1 = -sv / 2 + (j - 1) * dv, -sv / 2 + j1 * dv
					local piece = template:Clone()
					piece.Size = vec(u, u1 - u0, v, v1 - v0, n, sn)
					piece.CFrame = partCF * CFrame.new(vec(u, (u0 + u1) / 2, v, (v0 + v1) / 2, n, 0))
					piece.Parent = part.Parent
					table.insert(r.pieces, piece)
					made += 1
				end
			end
		end
	end
	template:Destroy()
	-- the part that was hit goes: the original is kept aside (to come back), a piece is simply removed
	if part == r.part then
		part.Parent = holdFolder()
	else
		local idx = table.find(r.pieces, part)
		if idx then
			table.remove(r.pieces, idx)
		end
		part:Destroy()
	end
	-- the chunks out of the hole
	local throw = (dir and dir.Magnitude > 0.01) and dir.Unit or partCF:VectorToWorldSpace(vec(n, 1, u, 0, v, 0))
	local speed = math.clamp((power or 60) * 0.5, 15, 120)
	local step = math.max(1, math.ceil(#holeCells / MAX_CHUNKS))
	for idx = 1, #holeCells, step do
		local c = holeCells[idx]
		local chunk = Instance.new("Part")
		chunk.Name = "Rubble"
		local k = rng:NextNumber(0.6, 0.95)
		chunk.Size = vec(u, du * k * math.min(step, 2), v, dv * k, n, sn * 0.9)
		chunk.CFrame = partCF * CFrame.new(vec(u, c[1], v, c[2], n, 0))
		chunk.Color = part.Color
		chunk.Material = part.Material
		chunk.TopSurface = Enum.SurfaceType.Smooth
		chunk.BottomSurface = Enum.SurfaceType.Smooth
		chunk.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.6, 0.1, 1, 1)
		chunk:SetAttribute("Gore", true) -- (blood and bullets treat it as loose stuff)
		chunk.Parent = fxFolder()
		pcall(function()
			chunk:SetNetworkOwner(nil)
		end)
		chunk.AssemblyLinearVelocity = (throw + Vector3.new(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 0.6), rng:NextNumber(-0.4, 0.4))).Unit * speed * rng:NextNumber(0.4, 1)
		chunk.AssemblyAngularVelocity = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 10
		addDebris(chunk)
	end
	-- things hanging on the wall where the hole is fall down (pictures, lamps, shelves)
	local holeCenter = partCF * CFrame.new(vec(u, cu, v, cv, n, 0))
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { fxFolder() }
	for _, p in workspace:GetPartBoundsInRadius(holeCenter.Position, radius + 0.5, op) do
		if p.Anchored and not p.CanCollide and p.Size.Magnitude < 7 and not p:GetAttribute("Fracture") and not p:IsA("SpawnLocation") then
			local m = p:FindFirstAncestorOfClass("Model")
			if m and not m:GetAttribute("Car") then
				p.Anchored = false
				p.CanCollide = true
				addDebris(p)
			end
		end
	end
	GoreService.Sound("debris", holeCenter.Position, 1)
	GoreService.FX({ t = "boomSmall", p = holeCenter.Position, d = throw })
	return made >= 0
end

-- bullets: enough hits on one spot of a wall make a small hole
local pitting: { [BasePart]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
function FractureService.Bullet(part: BasePart, point: Vector3, dir: Vector3, power: number)
	if not part:GetAttribute("Fracture") then
		return
	end
	local l = part.CFrame:PointToObjectSpace(point)
	local key = string.format("%d:%d:%d", math.floor(l.X / 2.2), math.floor(l.Y / 2.2), math.floor(l.Z / 2.2))
	local map = pitting[part] or {}
	pitting[part] = map
	map[key] = (map[key] or 0) + power
	local need = (part.Material == Enum.Material.Concrete or part.Material == Enum.Material.Brick) and Config.WallBulletsHard or Config.WallBulletsSoft
	if map[key] >= need then
		map[key] = nil
		FractureService.Fracture(part, point, 1.3, dir, 25)
	end
end

-- the walls come back
local function repairLoop()
	while true do
		task.wait(5)
		local now = os.clock()
		for id, rec in roots do
			if now - rec.t < Config.FractureRepairTime then
				continue
			end
			local blocked = false
			for _, plr in Players:GetPlayers() do
				local t = plr.Character and plr.Character:FindFirstChild("Torso")
				if t and t:IsA("BasePart") then
					local l = rec.box:PointToObjectSpace(t.Position)
					local h = rec.size * 0.5 + Vector3.new(3, 3, 3)
					if math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z then
						blocked = true
						break
					end
				end
			end
			if blocked then
				continue
			end
			roots[id] = nil
			for _, p in rec.pieces do
				if p.Parent then
					p:Destroy()
				end
			end
			if rec.part and rec.parent and rec.parent.Parent then
				rec.part.Parent = rec.parent
			elseif rec.part then
				rec.part:Destroy()
			end
		end
	end
end

-- a map is removed: its broken walls are forgotten
function FractureService.Forget(root: Instance)
	for id, rec in roots do
		if rec.parent == root or rec.parent:IsDescendantOf(root) then
			roots[id] = nil
			for _, p in rec.pieces do
				if p.Parent then
					p:Destroy()
				end
			end
			if rec.part then
				rec.part:Destroy()
			end
		end
	end
end

function FractureService.Init()
	FractureService.Register(workspace)
	task.spawn(repairLoop)
end

return FractureService
