--!nonstrict
-- Skins (v2.0): other looks for weapons. A skin is only a look - the weapon works exactly like the normal one.
-- You unlock a skin with a code (M > CODES, RewardService); then it is in the spawn menu (T) like any other item
-- (PropCatalog entry with `skin = <id>`) and in M > INVENTORY.
-- Every update brings ONE new skin with its own code, and the code of the update before stops working
-- (skins people already have stay theirs).
--   2.0 : GOLDEN PISTOL   (code: update2)

local Skins = {}

export type Look = { main: Color3, dark: Color3, material: Enum.Material, reflectance: number }
export type Skin = { id: string, name: string, base: string, item: string, look: string, update: string, how: string }

Skins.Looks = {
	gold = { main = Color3.fromRGB(246, 196, 64), dark = Color3.fromRGB(140, 96, 22), material = Enum.Material.Metal, reflectance = 0.18 },
	-- (v2.9) a neon-violet chrome for the cyberdeck update
	neon = { main = Color3.fromRGB(184, 120, 255), dark = Color3.fromRGB(38, 20, 58), material = Enum.Material.Metal, reflectance = 0.28 },
} :: { [string]: Look }

Skins.List = {
	{ id = "golden_pistol", name = "Golden Pistol", base = "pistol", item = "pistol_golden", look = "gold", update = "2.0", how = "Retired update 2.0 reward" },
	-- (v2.9) NEON RIFLE: the cyberdeck update's skin (code: netrunner)
	{ id = "neon_rifle", name = "Neon Rifle", base = "rifle", item = "rifle_neon", look = "neon", update = "2.9", how = "Retired update 2.9 reward" },
} :: { Skin }

Skins.ById = {} :: { [string]: Skin }
for _, s in Skins.List do
	Skins.ById[s.id] = s
end

-- paint a built weapon in the skin's look: every visible part keeps how light or dark it was, in the new colour
function Skins.Apply(model: Instance, skinId: string)
	local skin = Skins.ById[skinId]
	local look = skin and Skins.Looks[skin.look]
	if not look then
		return
	end
	local function paint(p: BasePart)
		if p.Transparency >= 1 or p.Material == Enum.Material.Neon or p.Material == Enum.Material.Glass then
			return -- (hidden grips / hit boxes, glowing sights, lenses stay as they are)
		end
		local col = p.Color
		local lum = 0.299 * col.R + 0.587 * col.G + 0.114 * col.B
		p.Color = look.dark:Lerp(look.main, math.clamp(0.3 + lum * 1.6, 0, 1))
		p.Material = look.material
		p.Reflectance = look.reflectance
	end
	if model:IsA("BasePart") then
		paint(model)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			paint(d)
		end
	end
	model:SetAttribute("Skin", skinId)
end

return Skins
