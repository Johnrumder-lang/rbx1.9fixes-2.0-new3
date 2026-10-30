--!nonstrict
-- SpineModel (v2.1i): the Sandevistan's spine implant (after the "ornamental cyberpunk" spine design): a column of six black vertebra plates with
-- chrome side clamps and a green light each, a neck port on top, a tail ring below, thin rods in between.
-- Specs only (the spine runs along +Y, the plates stand out towards +Z); the item (PropBuilders.sandevistan) and the worn implant
-- (SandevistanService) build their parts from them.

local SpineModel = {}

export type Spec = { name: string, size: Vector3, off: CFrame, color: Color3, material: Enum.Material, refl: number? }

local BLACK = Color3.fromRGB(12, 13, 16)
local BLACK2 = Color3.fromRGB(26, 28, 34)
local CHROME = Color3.fromRGB(200, 205, 216)
local GREEN = Color3.fromRGB(60, 255, 150)

function SpineModel.Specs(scale: number?): { Spec }
	local k = scale or 1
	local out: { Spec } = {}
	local function add(name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material, refl: number?, rot: CFrame?)
		table.insert(out, { name = name, size = size * k, off = CFrame.new(pos * k) * (rot or CFrame.identity), color = color, material = mat, refl = refl })
	end
	-- the neck port and the top cap
	add("SpineNeck", Vector3.new(0.22, 0.3, 0.2), Vector3.new(0, 1.4, 0.02), BLACK, Enum.Material.Metal)
	add("SpineTop", Vector3.new(0.52, 0.34, 0.28), Vector3.new(0, 1.12, 0.03), BLACK2, Enum.Material.Metal)
	add("SpineTopRing", Vector3.new(0.3, 0.1, 0.34), Vector3.new(0, 1.28, 0.03), CHROME, Enum.Material.Metal, 0.4)
	-- six vertebrae: a black core, two chrome clamps, a chrome centre plate and a green light
	for i = 0, 5 do
		local y = 0.78 - i * 0.31
		local w = 0.38 - i * 0.015
		add("SpineCore", Vector3.new(w, 0.27, 0.18), Vector3.new(0, y, 0.09), BLACK, Enum.Material.Metal)
		for _, s in { -1, 1 } do
			add("SpineClamp", Vector3.new(0.26, 0.2, 0.14), Vector3.new(s * (w / 2 + 0.12), y, 0.07), CHROME, Enum.Material.Metal, 0.4)
			add("SpinePin", Vector3.new(0.14, 0.07, 0.07), Vector3.new(s * (w / 2 + 0.02), y, 0.07), BLACK2, Enum.Material.Metal)
		end
		add("SpinePlate", Vector3.new(0.2, 0.14, 0.07), Vector3.new(0, y, 0.2), CHROME, Enum.Material.Metal, 0.35)
		add("SpineLed", Vector3.new(0.075, 0.075, 0.05), Vector3.new(0, y, 0.25), GREEN, Enum.Material.Neon)
		if i < 5 then
			add("SpineRod", Vector3.new(0.1, 0.09, 0.1), Vector3.new(0, y - 0.16, 0.06), BLACK2, Enum.Material.Metal)
		end
	end
	-- the tail
	add("SpineTail", Vector3.new(0.34, 0.24, 0.16), Vector3.new(0, -1.1, 0.07), BLACK2, Enum.Material.Metal)
	add("SpineTailRing", Vector3.new(0.2, 0.2, 0.1), Vector3.new(0, -1.3, 0.05), CHROME, Enum.Material.Metal, 0.4)
	return out
end

return SpineModel
