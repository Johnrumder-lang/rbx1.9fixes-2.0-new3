--!nonstrict
-- WeaponSkins (v2.1d): looks for weapons. A skin is ONLY a change of colour and material (texture) - no particles, no lights, no trails:
-- "Black Frost" = black + the Ice material, "Courthouse" = white Marble + gold metal. Every one of the 69 skins is different.
--   * every kill gives Config.KillCash dollars; a RANDOM skin: Config.RandomSkinCost dollars or Config.RandomSkinRobux Robux
--   * a skin of your choice: Config.SkinRobux Robux (inventory > weapon > skin)
--   * the ODDS are fixed (shown in the inventory): a rarity has a fixed share, split evenly between its skins. A skin you already own
--     is paid back in dollars (WeaponSkins.DupeCash)
-- How a weapon is painted: its parts are sorted by how dark they are in the normal weapon - the darkest parts (grips, mags) get the
-- DARK colour + material, the middle ones (receiver, blade) the MAIN, the lightest (details, edges) the ACCENT.

local WeaponSkins = {}

local function mat(name: string): Enum.Material
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return ok and m or Enum.Material.SmoothPlastic
end

export type Rarity = { name: string, color: Color3, weight: number }
WeaponSkins.Rarity = {
	common = { name = "COMMON", color = Color3.fromRGB(170, 176, 186), weight = 46 },
	rare = { name = "RARE", color = Color3.fromRGB(70, 140, 255), weight = 30 },
	epic = { name = "EPIC", color = Color3.fromRGB(172, 92, 255), weight = 17 },
	legendary = { name = "LEGENDARY", color = Color3.fromRGB(255, 170, 40), weight = 6 },
	mythic = { name = "MYTHIC", color = Color3.fromRGB(255, 52, 96), weight = 1 },
} :: { [string]: Rarity }
WeaponSkins.RarityOrder = { "common", "rare", "epic", "legendary", "mythic" }
-- a skin you already own pays this many dollars back
WeaponSkins.DupeCash = { common = 60, rare = 120, epic = 250, legendary = 500, mythic = 1000 } :: { [string]: number }

-- kind, name, rarity, main {r,g,b}, dark, accent, main material, dark material, accent material, reflectance, tag
local ROWS: { { any } } = {
	{ "pistol", "Black Frost", "rare", { 22, 24, 32 }, { 8, 8, 12 }, { 72, 96, 124 }, "Ice", "Slate", "Glacier", 0.12, "BLACK ICE" },
	{ "pistol", "Rust Belt", "common", { 158, 88, 44 }, { 48, 34, 26 }, { 196, 150, 70 }, "CorrodedMetal", "Metal", "DiamondPlate", 0, "RUSTED IRON" },
	{ "pistol", "Courthouse", "legendary", { 236, 236, 240 }, { 38, 38, 44 }, { 204, 164, 64 }, "Marble", "Granite", "Metal", 0.3, "WHITE MARBLE AND GOLD" },
	{ "revolver", "Desert Bone", "common", { 214, 186, 140 }, { 96, 70, 44 }, { 240, 232, 208 }, "Sandstone", "Leather", "Limestone", 0, "SANDSTONE" },
	{ "revolver", "Black Pearl", "epic", { 16, 16, 22 }, { 6, 6, 8 }, { 190, 194, 206 }, "Marble", "Metal", "Foil", 0.25, "BLACK MARBLE" },
	{ "revolver", "Copper Hand", "rare", { 184, 115, 51 }, { 70, 42, 22 }, { 232, 178, 98 }, "Foil", "WoodPlanks", "Metal", 0.2, "COPPER AND WOOD" },
	{ "rifle", "Mossback", "common", { 62, 96, 44 }, { 30, 24, 16 }, { 140, 120, 70 }, "Grass", "Wood", "Sand", 0, "MOSS" },
	{ "rifle", "Arctic Snow", "rare", { 238, 242, 248 }, { 70, 78, 92 }, { 160, 190, 214 }, "Snow", "Slate", "Ice", 0, "SNOW CAMO" },
	{ "rifle", "Garnet Fang", "epic", { 24, 22, 28 }, { 8, 8, 10 }, { 150, 30, 36 }, "Basalt", "Glass", "Metal", 0.15, "BASALT AND GARNET" },
	{ "smg", "Pink Concrete", "common", { 236, 150, 190 }, { 70, 50, 60 }, { 255, 220, 235 }, "Concrete", "Rubber", "Plaster", 0, "PINK CONCRETE" },
	{ "smg", "Slate Hornet", "rare", { 70, 80, 98 }, { 24, 26, 32 }, { 230, 190, 60 }, "Slate", "Metal", "Metal", 0.1, "SLATE AND YELLOW" },
	{ "smg", "Brick Tiger", "epic", { 196, 98, 40 }, { 30, 22, 16 }, { 248, 214, 120 }, "Brick", "Granite", "Sandstone", 0, "TIGER BRICK" },
	{ "shotgun", "Cobble Wall", "common", { 130, 126, 120 }, { 52, 46, 40 }, { 190, 184, 170 }, "Cobblestone", "Wood", "Pebble", 0, "COBBLESTONE" },
	{ "shotgun", "Ghost Barrel", "rare", { 190, 230, 226 }, { 90, 130, 128 }, { 240, 255, 252 }, "Glass", "Ice", "Glacier", 0.2, "GLASS AND ICE" },
	{ "shotgun", "Dragon Scale", "legendary", { 40, 110, 70 }, { 14, 40, 28 }, { 214, 176, 80 }, "Pebble", "Slate", "Metal", 0.1, "SCALES" },
	{ "sniper", "Glacier Scope", "rare", { 150, 200, 240 }, { 40, 70, 110 }, { 235, 248, 255 }, "Glacier", "Slate", "Ice", 0.1, "GLACIER" },
	{ "sniper", "Lapis Ink", "epic", { 30, 50, 150 }, { 4, 4, 14 }, { 120, 140, 230 }, "Marble", "Basalt", "Foil", 0.2, "LAPIS MARBLE" },
	{ "sniper", "Golden Eagle", "mythic", { 255, 208, 64 }, { 120, 84, 20 }, { 255, 244, 170 }, "Foil", "Metal", "Foil", 0.5, "SOLID GOLD" },
	{ "usp", "Red Polymer", "common", { 168, 32, 40 }, { 30, 10, 12 }, { 232, 120, 120 }, "Plastic", "Rubber", "SmoothPlastic", 0, "RED POLYMER" },
	{ "usp", "Olive Cloth", "common", { 92, 98, 52 }, { 36, 38, 22 }, { 150, 150, 92 }, "Fabric", "Rubber", "Fabric", 0, "OLIVE CLOTH" },
	{ "usp", "Ceramic", "epic", { 230, 236, 244 }, { 60, 70, 90 }, { 120, 160, 220 }, "CeramicTile", "Rubber", "Glass", 0.2, "CERAMIC" },
	{ "mp5", "Toxic Mud", "rare", { 96, 130, 40 }, { 30, 40, 16 }, { 190, 220, 70 }, "Mud", "Slate", "Salt", 0, "TOXIC MUD" },
	{ "mp5", "Purple Velvet", "epic", { 88, 30, 110 }, { 22, 8, 30 }, { 210, 170, 240 }, "Fabric", "Leather", "Foil", 0.1, "VELVET" },
	{ "mp5", "Mirror Chrome", "legendary", { 210, 216, 226 }, { 60, 66, 76 }, { 255, 255, 255 }, "Foil", "Metal", "Glass", 0.6, "MIRROR CHROME" },
	{ "garand", "Walnut", "rare", { 130, 84, 46 }, { 50, 32, 18 }, { 214, 176, 110 }, "Wood", "WoodPlanks", "Sandstone", 0, "WALNUT" },
	{ "garand", "Parade Ivory", "epic", { 240, 234, 216 }, { 150, 122, 80 }, { 210, 170, 70 }, "Plaster", "Leather", "Metal", 0.1, "IVORY" },
	{ "garand", "Trench Dirt", "common", { 92, 70, 50 }, { 40, 30, 22 }, { 140, 120, 90 }, "Ground", "Wood", "Sand", 0, "DIRT" },
	{ "crossbow", "Oak", "common", { 150, 108, 60 }, { 56, 40, 22 }, { 190, 160, 100 }, "WoodPlanks", "Wood", "Leather", 0, "OAK" },
	{ "crossbow", "Moonstone", "rare", { 190, 200, 230 }, { 60, 66, 96 }, { 240, 244, 255 }, "Marble", "Granite", "Glass", 0.2, "MOONSTONE" },
	{ "crossbow", "Cursed Bone", "legendary", { 146, 134, 112 }, { 30, 26, 22 }, { 150, 30, 40 }, "Limestone", "Basalt", "Leather", 0, "CURSED BONE" },
	{ "minigun", "Worn Steel", "rare", { 120, 126, 130 }, { 38, 40, 44 }, { 214, 150, 50 }, "CorrodedMetal", "Metal", "DiamondPlate", 0.05, "WORN STEEL" },
	{ "minigun", "Hazard", "epic", { 238, 196, 36 }, { 24, 24, 26 }, { 60, 60, 66 }, "DiamondPlate", "Rubber", "Metal", 0.1, "HAZARD YELLOW" },
	{ "minigun", "Rose Gold", "mythic", { 232, 160, 140 }, { 90, 52, 44 }, { 255, 214, 200 }, "Foil", "Metal", "Marble", 0.45, "ROSE GOLD" },
	{ "launcher", "Violet Slate", "epic", { 40, 36, 64 }, { 12, 10, 22 }, { 190, 150, 255 }, "Slate", "Basalt", "Glass", 0.1, "VIOLET SLATE" },
	{ "launcher", "Red Brick", "common", { 140, 30, 34 }, { 60, 16, 20 }, { 250, 170, 170 }, "Brick", "Concrete", "Plaster", 0, "RED BRICK" },
	{ "launcher", "Brass", "legendary", { 150, 128, 60 }, { 66, 48, 18 }, { 238, 208, 120 }, "Metal", "Wood", "Foil", 0.35, "BRASS" },
	{ "flamethrower", "Blue Ice", "epic", { 90, 150, 255 }, { 14, 28, 70 }, { 200, 225, 255 }, "Ice", "Glass", "Glacier", 0.15, "BLUE ICE" },
	{ "flamethrower", "Asphalt", "common", { 36, 34, 36 }, { 16, 14, 16 }, { 120, 110, 100 }, "Asphalt", "Rubber", "Pavement", 0, "ASPHALT" },
	{ "flamethrower", "Ember Copper", "rare", { 214, 96, 44 }, { 80, 30, 14 }, { 250, 180, 90 }, "DiamondPlate", "Slate", "Foil", 0.25, "EMBER COPPER" },
	{ "katana", "Moonblade", "epic", { 214, 236, 255 }, { 32, 44, 70 }, { 255, 255, 255 }, "Ice", "Slate", "Glass", 0.2, "FROZEN STEEL" },
	{ "katana", "Sakura Reaper", "rare", { 214, 128, 160 }, { 120, 60, 84 }, { 255, 238, 244 }, "Granite", "Fabric", "Plaster", 0.05, "PINK GRANITE" },
	{ "katana", "Night Shift", "legendary", { 20, 20, 24 }, { 6, 6, 8 }, { 196, 160, 70 }, "Metal", "Leather", "Foil", 0.35, "BLACK STEEL AND GOLD" },
	{ "blade", "Obsidian Edge", "rare", { 24, 20, 30 }, { 8, 6, 10 }, { 120, 100, 150 }, "Glass", "Basalt", "Metal", 0.2, "OBSIDIAN" },
	{ "blade", "Emerald", "epic", { 50, 200, 120 }, { 10, 70, 40 }, { 200, 255, 225 }, "Glass", "Marble", "Ice", 0.2, "EMERALD" },
	{ "blade", "Rose Steel", "legendary", { 255, 226, 190 }, { 150, 100, 60 }, { 255, 250, 240 }, "Foil", "Leather", "Glass", 0.4, "ROSE STEEL" },
	{ "knife", "Bone Shiv", "common", { 232, 226, 206 }, { 70, 56, 40 }, { 250, 246, 232 }, "Limestone", "Leather", "Plaster", 0, "BONE" },
	{ "knife", "Rust Fang", "rare", { 126, 88, 70 }, { 40, 26, 18 }, { 180, 130, 70 }, "Rock", "Wood", "Metal", 0, "ROCK AND RUST" },
	{ "knife", "Jade Dagger", "epic", { 80, 170, 130 }, { 20, 60, 48 }, { 200, 250, 226 }, "Marble", "Slate", "Glass", 0.2, "JADE" },
	{ "machete", "Moss Stone", "common", { 86, 110, 70 }, { 30, 34, 24 }, { 170, 180, 140 }, "Cobblestone", "Wood", "Pebble", 0, "MOSS STONE" },
	{ "machete", "Tide", "rare", { 70, 170, 200 }, { 16, 60, 80 }, { 210, 240, 250 }, "Glacier", "Slate", "Ice", 0.1, "TIDE" },
	{ "machete", "Golden Cleaver", "epic", { 240, 190, 64 }, { 90, 62, 20 }, { 255, 236, 160 }, "Metal", "Wood", "Foil", 0.4, "GOLD" },
	{ "axe", "Quarry", "common", { 150, 148, 142 }, { 44, 30, 18 }, { 170, 172, 176 }, "Concrete", "Wood", "Metal", 0, "QUARRY" },
	{ "axe", "Granite", "rare", { 120, 126, 140 }, { 40, 44, 54 }, { 220, 226, 240 }, "Granite", "Slate", "Marble", 0, "GRANITE" },
	{ "axe", "Valkyrie", "legendary", { 210, 214, 222 }, { 70, 76, 90 }, { 120, 170, 230 }, "Metal", "Slate", "Ice", 0.4, "SILVER AND ICE" },
	{ "bat", "Ash", "common", { 226, 200, 150 }, { 110, 76, 44 }, { 250, 240, 210 }, "Wood", "WoodPlanks", "Plaster", 0, "ASH WOOD" },
	{ "bat", "Dark Steel", "epic", { 70, 74, 80 }, { 24, 24, 26 }, { 190, 60, 50 }, "DiamondPlate", "Rubber", "Metal", 0.1, "DARK STEEL" },
	{ "bat", "Pastel", "rare", { 150, 210, 240 }, { 250, 170, 210 }, { 255, 255, 255 }, "Plaster", "Rubber", "Salt", 0, "PASTEL" },
	{ "spear", "Sea Glass", "epic", { 60, 170, 190 }, { 16, 64, 80 }, { 190, 240, 240 }, "Glass", "Slate", "Ice", 0.2, "SEA GLASS" },
	{ "spear", "Red Slate", "legendary", { 170, 50, 34 }, { 40, 16, 12 }, { 240, 170, 60 }, "Slate", "Basalt", "Metal", 0.1, "RED SLATE" },
	{ "spear", "Salt", "rare", { 244, 244, 246 }, { 150, 160, 176 }, { 100, 120, 150 }, "Salt", "Limestone", "Fabric", 0, "SALT" },
	{ "sledge", "Storm Granite", "legendary", { 66, 84, 130 }, { 30, 34, 44 }, { 190, 220, 255 }, "Granite", "Metal", "Foil", 0.1, "STORM GRANITE" },
	{ "sledge", "Violet Basalt", "epic", { 90, 50, 140 }, { 14, 10, 24 }, { 150, 110, 210 }, "Basalt", "Slate", "Marble", 0.1, "VIOLET BASALT" },
	{ "sledge", "Mint Plaster", "common", { 176, 236, 176 }, { 60, 110, 96 }, { 236, 255, 248 }, "Plaster", "Rubber", "Salt", 0, "MINT" },
	{ "crowbar", "Orange Steel", "common", { 224, 120, 36 }, { 60, 34, 16 }, { 250, 190, 110 }, "Metal", "Rubber", "Foil", 0.1, "ORANGE" },
	{ "crowbar", "Teal Concrete", "rare", { 70, 200, 210 }, { 20, 60, 66 }, { 190, 250, 255 }, "Concrete", "Rubber", "Glass", 0, "TEAL CONCRETE" },
	{ "crowbar", "Verdigris", "epic", { 70, 160, 140 }, { 36, 52, 48 }, { 170, 210, 190 }, "CorrodedMetal", "Metal", "Limestone", 0, "VERDIGRIS" },
	{ "chainsaw", "Blood Cotton", "epic", { 160, 24, 34 }, { 40, 8, 12 }, { 236, 200, 200 }, "Fabric", "Rubber", "Plaster", 0, "BLOOD RED" },
	{ "chainsaw", "Hellraiser", "legendary", { 120, 16, 20 }, { 20, 6, 8 }, { 210, 40, 40 }, "Basalt", "Metal", "Marble", 0.15, "BLOOD BASALT" },
	{ "chainsaw", "High-Vis", "rare", { 200, 230, 50 }, { 40, 50, 12 }, { 250, 255, 150 }, "Plastic", "Rubber", "SmoothPlastic", 0, "HIGH-VIS" },
}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

export type Skin = {
	id: string, kind: string, name: string, rarity: string, tag: string,
	look: { main: Color3, dark: Color3, accent: Color3, matMain: Enum.Material, matDark: Enum.Material, matAccent: Enum.Material, reflectance: number },
	odds: number, -- the chance (in percent) that a roll gives exactly this skin
}
WeaponSkins.List = {} :: { Skin }
WeaponSkins.ById = {} :: { [string]: Skin }
WeaponSkins.OfKind = {} :: { [string]: { Skin } }
WeaponSkins.Kinds = {} :: { string }

local perRarity: { [string]: number } = {}
for _, r in ROWS do
	perRarity[r[3]] = (perRarity[r[3]] or 0) + 1
end
local totalWeight = 0
for rar in perRarity do
	totalWeight += WeaponSkins.Rarity[rar].weight
end
local count: { [string]: number } = {}
for _, r in ROWS do
	local kind = r[1] :: string
	if not WeaponSkins.OfKind[kind] then
		WeaponSkins.OfKind[kind] = {}
		table.insert(WeaponSkins.Kinds, kind)
	end
	count[kind] = (count[kind] or 0) + 1
	local rarity = r[3] :: string
	local skin: Skin = {
		id = kind .. "_" .. count[kind], kind = kind, name = r[2], rarity = rarity, tag = r[11],
		look = {
			main = rgb(r[4]), dark = rgb(r[5]), accent = rgb(r[6]), matMain = mat(r[7]), matDark = mat(r[8]), matAccent = mat(r[9]), reflectance = r[10],
		},
		odds = WeaponSkins.Rarity[rarity].weight / totalWeight * 100 / perRarity[rarity],
	}
	table.insert(WeaponSkins.List, skin)
	table.insert(WeaponSkins.OfKind[kind], skin)
	WeaponSkins.ById[skin.id] = skin
end
table.sort(WeaponSkins.Kinds)

-- what a part of the weapon becomes: 'lum' is how light that part is on the normal weapon (0 black .. 1 white)
function WeaponSkins.Paint(look: any, lum: number): (Color3, Enum.Material, number)
	if lum < 0.22 then
		return look.dark, look.matDark, math.min(look.reflectance, 0.1)
	elseif lum < 0.55 then
		return look.main:Lerp(look.dark, math.clamp((0.4 - lum) * 0.5, 0, 0.2)), look.matMain, look.reflectance
	end
	return look.accent, look.matAccent, look.reflectance
end

-- a roll: the odds are fixed and do not depend on what you own
function WeaponSkins.Roll(rng: Random): Skin
	local r = rng:NextNumber() * 100
	for _, s in WeaponSkins.List do
		r -= s.odds
		if r <= 0 then
			return s
		end
	end
	return WeaponSkins.List[#WeaponSkins.List]
end

-- the odds as the inventory shows them: { { rarity, percent, skins } ... }
function WeaponSkins.OddsTable(): { { rarity: string, percent: number, count: number, each: number } }
	local out = {}
	for _, rar in WeaponSkins.RarityOrder do
		if perRarity[rar] then
			local each = WeaponSkins.Rarity[rar].weight / totalWeight * 100 / perRarity[rar]
			table.insert(out, { rarity = rar, percent = each * perRarity[rar], count = perRarity[rar], each = each })
		end
	end
	return out
end

return WeaponSkins
