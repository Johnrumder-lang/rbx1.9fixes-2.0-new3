--!nonstrict
-- WoundHoles (v2.0): a bullet that goes clean through an arm, a leg or the torso leaves a real hole you can look
-- through. Every screen does this for itself (the server only says which part, where the bullet went in and where it
-- came out: "tunnel").
-- How: the body part stays where it is (it is the physics, the hits, the joints) but is hidden on this screen; in its
-- place a shell of boxes is drawn - the same block with a square tunnel cut out along the shot (the side of the
-- block the shot crosses most). The tunnel is lined with raw red and rimmed dark at both openings. Up to
-- MAX_HOLES holes per part; the shell is cut again for each.
-- Heads (a rounded mesh) and parts that are not plain blocks get no hole (the normal wound stays).

local RunService = game:GetService("RunService")

local WoundHoles = {}

local MAX_HOLES = 4
local MAX_PIECES = 48
local FLESH = Color3.fromRGB(150, 24, 28)
local RIM = Color3.fromRGB(70, 8, 10)

type Box = { min: Vector3, max: Vector3 }
type Rec = { part: BasePart, boxes: { Box }, holes: number, folder: Folder, openings: { { box: Box, k: number } }, closing: boolean? }

local recs: { [BasePart]: Rec } = setmetatable({}, { __mode = "k" }) :: any

local function comp(v: Vector3, i: number): number
	return i == 1 and v.X or (i == 2 and v.Y or v.Z)
end

local function setComp(v: Vector3, i: number, x: number): Vector3
	return i == 1 and Vector3.new(x, v.Y, v.Z) or (i == 2 and Vector3.new(v.X, x, v.Z) or Vector3.new(v.X, v.Y, x))
end

-- box B minus box H: up to six boxes (the slabs of B on each side of H)
local function subtract(b: Box, h: Box, out: { Box })
	for i = 1, 3 do
		if comp(b.max, i) <= comp(h.min, i) or comp(b.min, i) >= comp(h.max, i) then
			table.insert(out, b) -- (no overlap)
			return
		end
	end
	local cur = { min = b.min, max = b.max }
	for i = 1, 3 do
		if comp(cur.min, i) < comp(h.min, i) then
			table.insert(out, { min = cur.min, max = setComp(cur.max, i, comp(h.min, i)) })
			cur.min = setComp(cur.min, i, comp(h.min, i))
		end
		if comp(cur.max, i) > comp(h.max, i) then
			table.insert(out, { min = setComp(cur.min, i, comp(h.max, i)), max = cur.max })
			cur.max = setComp(cur.max, i, comp(h.max, i))
		end
	end
	-- (what is left lies inside the hole: gone)
end

local function plainBlock(part: BasePart): boolean
	if part.Name == "Head" or part:FindFirstChildOfClass("SpecialMesh") or part:IsA("MeshPart") then
		return false
	end
	return not part:IsA("Part") or (part :: Part).Shape == Enum.PartType.Block
end

local function deco(folder: Folder, part: BasePart, name: string, box: Box, color: Color3, material: Enum.Material?, reflect: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = box.max - box.min
	p.CFrame = part.CFrame * CFrame.new((box.min + box.max) / 2)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Reflectance = reflect or 0
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = part.CastShadow
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local w = Instance.new("WeldConstraint")
	w.Part0 = part
	w.Part1 = p
	w.Parent = p
	p.Parent = folder
	return p
end

local function rebuildShell(rec: Rec)
	for _, c in rec.folder:GetChildren() do
		if c.Name == "Shell" then
			c:Destroy()
		end
	end
	local part = rec.part
	for _, b in rec.boxes do
		local s = b.max - b.min
		if s.X > 0.01 and s.Y > 0.01 and s.Z > 0.01 then
			deco(rec.folder, part, "Shell", b, part.Color, part.Material, part.Reflectance).Transparency = part.Transparency
		end
	end
end

-- the tunnel: lining on its four walls, a dark rim round both openings
local function dress(rec: Rec, hole: Box, k: number)
	local part = rec.part
	local others = { 1, 2, 3 }
	table.remove(others, k)
	local i, j = others[1], others[2]
	local inset = 0.012
	for _, which in { { i, "min" }, { i, "max" }, { j, "min" }, { j, "max" } } do
		local ax = which[1]
		local v = which[2] == "min" and comp(hole.min, ax) or comp(hole.max, ax)
		local wall = { min = hole.min, max = hole.max }
		if which[2] == "min" then
			wall.max = setComp(wall.max, ax, v + 0.03)
			wall.min = setComp(wall.min, ax, v + inset)
		else
			wall.min = setComp(wall.min, ax, v - 0.03)
			wall.max = setComp(wall.max, ax, v - inset)
		end
		deco(rec.folder, part, "Lining", wall, FLESH, Enum.Material.SmoothPlastic, 0.15)
	end
	local half = part.Size / 2
	for _, sgn in { -1, 1 } do
		local face = sgn * comp(half, k)
		local t = 0.06
		for _, ax in { i, j } do
			local other = ax == i and j or i
			for _, side in { "min", "max" } do
				local v = side == "min" and comp(hole.min, ax) or comp(hole.max, ax)
				local bar = { min = hole.min, max = hole.max }
				bar.min = setComp(bar.min, ax, side == "min" and v - t or v)
				bar.max = setComp(bar.max, ax, side == "min" and v or v + t)
				bar.min = setComp(bar.min, other, comp(hole.min, other) - t)
				bar.max = setComp(bar.max, other, comp(hole.max, other) + t)
				bar.min = setComp(bar.min, k, sgn > 0 and face or face - 0.02)
				bar.max = setComp(bar.max, k, sgn > 0 and face + 0.02 or face)
				deco(rec.folder, part, "Rim", bar, RIM)
			end
		end
	end
end

-- the real part goes; so do the wound marks lying over an opening (you would not see through them)
local function hide(rec: Rec)
	rec.part.LocalTransparencyModifier = 1
	local wounds = rec.part:FindFirstChild("Wounds")
	if not wounds then
		return
	end
	for _, w in wounds:GetDescendants() do
		if w:IsA("BasePart") then
			local lp = rec.part.CFrame:PointToObjectSpace(w.Position)
			for _, o in rec.openings do
				local inside = true
				for ax = 1, 3 do
					if ax ~= o.k and (comp(lp, ax) < comp(o.box.min, ax) - 0.08 or comp(lp, ax) > comp(o.box.max, ax) + 0.08) then
						inside = false
					end
				end
				if inside then
					w.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

-- payload: { part, a = entry (part space), b = exit (part space), k = power }
local function onTunnel(payload)
	local part = payload.part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part.Parent then
		return
	end
	if typeof(payload.a) ~= "Vector3" or typeof(payload.b) ~= "Vector3" or not plainBlock(part) then
		return
	end
	local rec = recs[part]
	if rec and (rec.holes >= MAX_HOLES or rec.closing) then
		return
	end
	local a, b = payload.a :: Vector3, payload.b :: Vector3
	local d = b - a
	if d.Magnitude < 0.05 then
		return
	end
	-- along the side the shot crosses most
	local ad = Vector3.new(math.abs(d.X), math.abs(d.Y), math.abs(d.Z))
	local k = (ad.X >= ad.Y and ad.X >= ad.Z) and 1 or (ad.Y >= ad.Z and 2 or 3)
	local power = typeof(payload.k) == "number" and payload.k or 1
	local h = math.clamp(0.13 + power * 0.05, 0.13, 0.24)
	local half = part.Size / 2
	local mid = (a + b) / 2
	local hmin, hmax = Vector3.zero, Vector3.zero
	for ax = 1, 3 do
		if ax == k then
			hmin = setComp(hmin, ax, -comp(half, ax) - 0.05)
			hmax = setComp(hmax, ax, comp(half, ax) + 0.05)
		else
			local lim = comp(half, ax) - h - 0.06
			if lim <= 0 then
				return -- (too thin here for a hole)
			end
			local c = math.clamp(comp(mid, ax), -lim, lim)
			hmin = setComp(hmin, ax, c - h)
			hmax = setComp(hmax, ax, c + h)
		end
	end
	local hole: Box = { min = hmin, max = hmax }
	if not rec then
		local folder = Instance.new("Folder")
		folder.Name = "Tunnels"
		folder.Parent = part
		rec = { part = part, boxes = { { min = -half, max = half } }, holes = 0, folder = folder, openings = {} }
		recs[part] = rec
	end
	local r = rec :: Rec
	local out: { Box } = {}
	for _, bx in r.boxes do
		subtract(bx, hole, out)
	end
	if #out > MAX_PIECES then
		return
	end
	r.boxes = out
	r.holes += 1
	table.insert(r.openings, { box = hole, k = k })
	rebuildShell(r)
	dress(r, hole, k)
	hide(r)
	task.delay(0.4, function()
		if recs[part] == r then
			hide(r) -- (the wound marks may arrive a moment after the message)
		end
	end)
end

-- (v2.8.2) HEALING: the holes close - the tunnels shrink to nothing over `seconds`, then the part is whole again
local function shrink(b: Box, k: number, f: number): Box
	local mn, mx = b.min, b.max
	for ax = 1, 3 do
		if ax ~= k then
			local c = (comp(mn, ax) + comp(mx, ax)) / 2
			local h = (comp(mx, ax) - comp(mn, ax)) / 2 * f
			mn = setComp(mn, ax, c - h)
			mx = setComp(mx, ax, c + h)
		end
	end
	return { min = mn, max = mx }
end

local function onMend(payload)
	local part = payload.part
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then
		return
	end
	local rec = recs[part]
	if not rec or rec.closing then
		return
	end
	rec.closing = true
	local seconds = typeof(payload.s) == "number" and payload.s or 2.5
	local holes = table.clone(rec.openings)
	local steps = 10
	task.spawn(function()
		for s = 1, steps do
			task.wait(seconds / steps)
			if not part.Parent or recs[part] ~= rec then
				return
			end
			local f = 1 - s / steps
			for _, c in rec.folder:GetChildren() do
				c:Destroy()
			end
			if f <= 0.05 then
				break
			end
			local half = part.Size / 2
			local boxes: { Box } = { { min = -half, max = half } }
			for _, o in holes do
				local hb = shrink(o.box, o.k, f)
				local out: { Box } = {}
				for _, bx in boxes do
					subtract(bx, hb, out)
				end
				boxes = out
			end
			rec.boxes = boxes
			rebuildShell(rec)
			for _, o in holes do
				dress(rec, shrink(o.box, o.k, f), o.k)
			end
		end
		recs[part] = nil
		rec.folder:Destroy()
		part.LocalTransparencyModifier = 0
	end)
end

function WoundHoles.Has(part: BasePart): boolean
	return recs[part] ~= nil
end

function WoundHoles.Init(events: any)
	events.On("tunnel", onTunnel)
	events.On("mend", onMend)
	-- keep the real parts hidden (other effects may set them back); forget parts that are gone
	RunService.Heartbeat:Connect(function()
		for part, rec in recs do
			if not part.Parent or not rec.folder.Parent then
				recs[part] = nil
			elseif part.LocalTransparencyModifier < 1 then
				part.LocalTransparencyModifier = 1
			end
		end
	end)
end

return WoundHoles
