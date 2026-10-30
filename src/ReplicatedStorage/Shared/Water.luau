--!nonstrict
-- Water: where the pool water is (the invisible WaterVolume parts in the map; the water you see is
-- terrain water filled into them at runtime). Used by the swimming, the drowning and the NPCs.

local Water = {}

local volumes: { BasePart }? = nil
local volumesFor: any = false

-- (v2.0) the pool in the sandbox and the water of the loaded map (the sea)
function Water.Volumes(): { BasePart }
	local v = volumes
	local mapId = workspace:GetAttribute("MapLoaded")
	if v and #v > 0 and v[1].Parent and volumesFor == mapId then
		return v
	end
	local list = {}
	for _, root in { workspace:FindFirstChild("Map"), workspace:FindFirstChild("ActiveMap") } do
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "WaterVolume" then
					table.insert(list, d)
				end
			end
		end
	end
	volumes = list
	volumesFor = mapId
	return list
end

-- the height of the water surface over this point (nil = no water here)
function Water.SurfaceAt(p: Vector3): number?
	for _, v in Water.Volumes() do
		local l = v.CFrame:PointToObjectSpace(p)
		local h = v.Size * 0.5
		if math.abs(l.X) <= h.X and math.abs(l.Z) <= h.Z and l.Y <= h.Y + 1.5 and l.Y >= -h.Y - 2 then
			return v.Position.Y + h.Y
		end
	end
	return nil
end

-- how deep under the surface a point is (> 0 = under water), nil = no water here
function Water.Depth(p: Vector3): number?
	local s = Water.SurfaceAt(p)
	return s and (s - p.Y) or nil
end

return Water
