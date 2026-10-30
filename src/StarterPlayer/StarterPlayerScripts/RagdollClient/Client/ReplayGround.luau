--!nonstrict
-- Ground outside Workspace.Map is copied explicitly, before the detailed environment budget.
local Ground = {}
function Ground.Copy(viewport, center, radius)
	for _, part in workspace:GetChildren() do
		if part:IsA("BasePart") and not part:IsA("Terrain") and part.Archivable and part.Anchored and part.Transparency < 0.95 and part.Size.X >= 40 and part.Size.Z >= 40 then
			local localPoint = part.CFrame:PointToObjectSpace(center)
			local half = part.Size / 2
			local nearest = Vector3.new(math.clamp(localPoint.X, -half.X, half.X), math.clamp(localPoint.Y, -half.Y, half.Y), math.clamp(localPoint.Z, -half.Z, half.Z))
			if (localPoint - nearest).Magnitude <= radius then
				local ok, clone = pcall(function() return part:Clone() end)
				if ok and clone then
					for _, child in clone:GetDescendants() do
						if not (child:IsA("SpecialMesh") or child:IsA("Decal") or child:IsA("Texture") or child:IsA("BlockMesh")) then child:Destroy() end
					end
					clone.Anchored, clone.CanCollide, clone.CanTouch, clone.CanQuery = true, false, false, false
					clone.Parent = viewport
				end
			end
		end
	end
end
return Ground
