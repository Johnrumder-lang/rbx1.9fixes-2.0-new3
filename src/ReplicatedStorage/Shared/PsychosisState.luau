--!nonstrict
-- One visible overload value for server effects and client presentation.
local Items = require(script.Parent.Items)
local Config = require(script.Parent.Config)
local State = {}
function State.Level(p)
	if workspace:GetAttribute("PsychosisOff") then return 0 end
	if p:GetAttribute("AdminPsychoEnabled") ~= true and (Items.IsOwner(p) or (p.Character and p.Character:GetAttribute("Colossus"))) then return 0 end
	local load = p:GetAttribute("CyLoad") or 0
	local capacity = Config.CyberTolerance + (p:GetAttribute("CyTolBonus") or 0)
	if load <= capacity then return 0 end
	return math.clamp(p:GetAttribute("CyPsycho") or 0, 0, 1)
end
return State
