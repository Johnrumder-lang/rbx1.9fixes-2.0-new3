--!strict
-- Ground: "where is the real ground?" for marks that must never float (scorch marks, craters, fire patches).
-- Only ANCHORED surfaces count (terrain, floors, walls, slopes). Bodies, dummies, cars, props and anything else
-- loose that a ray happens to hit first is skipped, so a burn mark can not hang in the air on a player.

local Ground = {}

-- like workspace:Raycast, but returns the first hit on something anchored (or nil)
function Ground.Cast(origin: Vector3, direction: Vector3, params: RaycastParams?): RaycastResult?
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if params then
		p.CollisionGroup = params.CollisionGroup
		p.IgnoreWater = params.IgnoreWater
		ignore = table.clone(params.FilterDescendantsInstances)
	end
	for _ = 1, 10 do
		p.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(origin, direction, p)
		if not hit then
			return nil
		end
		local inst = hit.Instance
		if inst:IsA("Terrain") or (inst:IsA("BasePart") and inst.Anchored) then
			return hit
		end
		table.insert(ignore, inst)
	end
	return nil
end

return Ground
