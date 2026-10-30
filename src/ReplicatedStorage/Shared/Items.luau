--!nonstrict
-- Items: things that are held rigidly in one hand (guns, melee weapons, explosives, tools).
-- An item is a Model with the attribute "Item" = kind, a PrimaryPart and a "GripAttachment" on it
-- (attachment LookVector = the item's forward: barrel / tip, UpVector = its top).

local Items = {}

Items.Kinds = {
	package = { name = "DELIVERY PACKAGE" },
	pistol = { gun = true, name = "PISTOL" },
	revolver = { gun = true, name = "REVOLVER" },
	rifle = { gun = true, auto = true, name = "RIFLE" },
	smg = { gun = true, auto = true, name = "SMG" },
	shotgun = { gun = true, name = "SHOTGUN" },
	sniper = { gun = true, scope = true, name = "SNIPER" },
	launcher = { gun = true, name = "ROCKET LAUNCHER" },
	sleepdart = { gun = true, name = "SLEEP DARTS" },
	healdart = { gun = true, name = "HEAL DARTS" },
	paradart = { gun = true, name = "PARALYSIS DARTS" }, -- (v2.8) down for 40 s, awake
	smartpistol = { gun = true, name = "SMART PISTOL" }, -- (v2.8) with WARDEN OPTICS: every shot goes to the locked target
	smartsmg = { gun = true, auto = true, name = "SMART SMG" },
	spear = { melee = "stab", name = "SPEAR" },
	blade = { melee = "slash", name = "BLADE" },
	katana = { melee = "slash", name = "KATANA" },
	axe = { melee = "slash", heavy = true, name = "AXE" },
	bat = { melee = "blunt", name = "BAT" },
	sledge = { melee = "blunt", heavy = true, name = "SLEDGEHAMMER" },
	grenade = { throwable = true, name = "GRENADE" },
	flash = { throwable = true, name = "FLASHBANG" },
	tether = { use = true, name = "TETHER ROPE" },
	c4 = { throwable = true, name = "C4" },
	detonator = { use = true, name = "DETONATOR" },
	bandage = { use = true, name = "BANDAGE" },
	ledger = { use = true, name = "BLACK LEDGER" }, -- (v2.1) F: write a name (LedgerService / LedgerClient)
	apple = { use = true, name = "APPLE" },
	armor = { use = true, name = "BODY ARMOR" },
	sandevistan = { use = true, name = "SANDEVISTAN" },
	implantcase = { use = true, name = "IMPLANT CASE" }, -- (v2.8) F near another player: the implant in it goes in (CyberService)
	ripperkit = { use = true, name = "RIPPER KIT" }, -- (v2.8) F near somebody asleep: an implant comes out
	syringe = { use = true, name = "SYRINGE" }, -- (v2.8) F aimed at somebody close: asleep 3x as long as a sleep dart -- (v2.1) F near another player: the implant (SandevistanService) -- (v2.1) F: put the whole set on (ArmorService) -- (v2.1) F: eat it, or feed it to Kuro
	rope = { use = true, name = "ROPE" },
	boombox = { use = true, name = "BOOMBOX" },
	laser = { use = true, name = "LASER POINTER" },
	shield = { shield = true, name = "SHIELD" },
	virus = { throwable = true, ownerOnly = true, name = "VIRUS" },
	physgun = { physgun = true, ownerOnly = true, name = "PHYSICS GUN" },
	nuke = { use = true, ownerOnly = true, name = "NUKE" },
	-- v1.8
	knife = { melee = "stab", name = "KNIFE" },
	machete = { melee = "slash", name = "MACHETE" },
	crossbow = { gun = true, name = "CROSSBOW" },
	minigun = { gun = true, auto = true, heavy = true, name = "MINIGUN" },
	flamethrower = { use = true, name = "FLAMETHROWER" },
	molotov = { throwable = true, name = "MOLOTOV" },
	-- v2.0
	banhammer = { melee = "blunt", heavy = true, ownerOnly = true, name = "KICK HAMMER" },
	usp = { gun = true, name = "USP" },
	mp5 = { gun = true, auto = true, name = "MP5" },
	garand = { gun = true, name = "M1 GARAND" },
	lockon = { gun = true, name = "LOCK-ON LAUNCHER" },
	taser = { gun = true, name = "TASER" },
	harpoon = { gun = true, name = "HARPOON GUN" },
	flaregun = { gun = true, name = "FLARE GUN" },
	flashlight = { use = true, name = "FLASHLIGHT" },
	glue = { use = true, name = "GLUE" },
	prosthetic_arm = { use = true, prosthetic = "Arm", name = "PROSTHETIC ARM" },
	prosthetic_leg = { use = true, prosthetic = "Leg", name = "PROSTHETIC LEG" },
	steelball = { use = true, ball = true, name = "STEEL BALL" },
	crowbar = { melee = "blunt", name = "CROWBAR" },
	chainsaw = { melee = "slash", heavy = true, name = "CHAINSAW" },
	-- v2.8
	sheath = { name = "SHEATH" }, -- STILLWATER's sheath: wear it in a pocket, put the sword into the same pocket (StillCutService)
	-- v2.9: the cyberdeck
	camera = { use = true, name = "VIDEO CAMERA" }, -- F: start / stop filming; a video chip pops out when you stop (CameraService)
	chip = { use = true, name = "CHIP" }, -- F: play the video on it; grab somebody + F (chip in the other hand): push it into them (ChipService)
	computer = { use = true, name = "COMPUTER" }, -- set it down; F (or the prompt) opens it: buy / program chips (ComputerService)
}

-- the physics gun is for the game's owner only (and anyone testing in Studio). For a group game the
-- owner is the group's owner (looked up once in the background).
local ownerId: number? = nil
local lookingUp = false
-- (v2.0) admins: the game owner everywhere; in a PRIVATE server also its owner (free) and whoever owns the admin
-- game pass (Config.AdminPassId). The server decides and sets the player attribute "Admin"; everything that asks
-- IsOwner treats an admin like the owner (all powers, the admin menu, the physics gun, the nuke ...).
function Items.IsOwner(player: Player): boolean
	if player:GetAttribute("Admin") == true then
		return true
	end
	return Items.IsGameOwner(player)
end

-- (v2.0) nobody can kick the game owner (in Studio everybody may be kicked, to test it)
function Items.Unkickable(player: Player): boolean
	if game:GetService("RunService"):IsStudio() then
		return false
	end
	return Items.IsGameOwner(player)
end

-- the real owner of the game (or anyone testing in Studio)
function Items.IsGameOwner(player: Player): boolean
	local RunService = game:GetService("RunService")
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return player.UserId == game.CreatorId
	end
	if not ownerId and not lookingUp then
		lookingUp = true
		task.spawn(function()
			local ok, info = pcall(function()
				return game:GetService("GroupService"):GetGroupInfoAsync(game.CreatorId)
			end)
			if ok and typeof(info) == "table" and typeof(info.Owner) == "table" and typeof(info.Owner.Id) == "number" then
				ownerId = info.Owner.Id
			else
				lookingUp = false -- try again later
			end
		end)
	end
	return ownerId ~= nil and player.UserId == ownerId
end

function Items.ModelOf(inst: Instance?): Model?
	if not inst then
		return nil
	end
	local m = inst:FindFirstAncestorOfClass("Model")
	if m and (m:GetAttribute("Item") or m:GetAttribute("Gun")) then
		return m
	end
	return nil
end

function Items.Kind(model: Model?): string?
	if not model then
		return nil
	end
	local k = model:GetAttribute("Item")
	if typeof(k) == "string" then
		return k
	end
	return model:GetAttribute("Gun") and "pistol" or nil
end

function Items.IsGun(model: Model?): boolean
	local k = Items.Kind(model)
	return k ~= nil and Items.Kinds[k] ~= nil and Items.Kinds[k].gun == true
end

function Items.IsAuto(model: Model?): boolean
	local k = Items.Kind(model)
	return k ~= nil and Items.Kinds[k] ~= nil and Items.Kinds[k].auto == true
end

function Items.HasScope(model: Model?): boolean
	local k = Items.Kind(model)
	return k ~= nil and Items.Kinds[k] ~= nil and Items.Kinds[k].scope == true
end

-- only the game's owner may hold it (physics gun, nuke)
-- (v1.9) the owner can GIVE single powers to players (gift menu): a gift is a player attribute "Gift_<power>"
Items.POWERS = { "fly", "punch", "laser", "nuke", "virus", "physgun", "wonder",
	-- (v2.8) more admin things an admin can give: time stop (I), the hotdog (P), SEVER (K), the Sandevistan without an implant,
	-- the COLOSSUS protocol and ZERO HOUR (at the ripperdoc, free)
	"timestop", "hotdog", "sever", "sandevistan", "colossus", "zerohour",
	-- STILL CUT ability; summoning STILLWATER requires completing its quest.
	"stillcut", "freecam" }

function Items.Has(player: Player?, power: string): boolean
	if not player then
		return false
	end
	if Items.IsOwner(player) then
		return true
	end
	return player:GetAttribute("Gift_" .. power) == true
end

-- may this player hold / use an owner-only item (nuke, virus, physics gun)? (owner, or gifted)
function Items.MayUse(player: Player, model: Model?): boolean
	if not Items.IsOwnerOnly(model) then
		return true
	end
	local k = Items.Kind(model)
	return Items.Has(player, k or "__owner")
end

function Items.IsOwnerOnly(model: Model?): boolean
	local k = Items.Kind(model)
	return (k ~= nil and Items.Kinds[k] ~= nil and Items.Kinds[k].ownerOnly == true) or (model ~= nil and model:GetAttribute("OwnerOnly") == true)
end

function Items.Melee(model: Model?): string?
	local k = Items.Kind(model)
	return k and Items.Kinds[k] and Items.Kinds[k].melee or nil
end

function Items.Muzzle(model: Model): Attachment?
	local m = model:FindFirstChild("Muzzle", true)
	if m and m:IsA("Attachment") then
		return m
	end
	-- (a part that happens to be called "Muzzle" must not hide the real attachment: that is why
	-- the minigun never fired in v1.8)
	for _, d in model:GetDescendants() do
		if d.Name == "Muzzle" and d:IsA("Attachment") then
			return d
		end
	end
	return nil
end

-- world points that hurt when a melee weapon hits something (tip of a spear, edge of a blade)
function Items.DamagePoints(model: Model): { { part: BasePart, point: Vector3 } }
	local out = {}
	local kind = Items.Kind(model)
	if kind == "spear" then
		for _, n in { "SpearPoint", "SpearTip" } do
			local p = model:FindFirstChild(n)
			if p and p:IsA("BasePart") then
				table.insert(out, { part = p, point = p.CFrame.Position })
			end
		end
	elseif kind == "blade" or kind == "katana" or kind == "knife" or kind == "machete" or kind == "chainsaw" then
		local b = model:FindFirstChild("Blade")
		if b and b:IsA("BasePart") then
			-- the blade's long axis is its Z (forward = -Z)
			for _, t in { -0.45, -0.1, 0.25 } do
				table.insert(out, { part = b, point = b.CFrame:PointToWorldSpace(Vector3.new(0, 0, t * b.Size.Z)) })
			end
		end
	elseif kind == "axe" or kind == "bat" or kind == "sledge" or kind == "banhammer" or kind == "crowbar" then
		local h = model:FindFirstChild(kind == "axe" and "AxeHead" or (kind == "bat" and "BatEnd" or (kind == "crowbar" and "Bar" or "SledgeHead")))
		if h and h:IsA("BasePart") then
			-- along the part's longest axis (the bat end is a cylinder: its length is X)
			local s = h.Size
			local axis = (s.X >= s.Y and s.X >= s.Z) and Vector3.xAxis * s.X or (s.Y >= s.Z and Vector3.yAxis * s.Y or Vector3.zAxis * s.Z)
			for _, t in { -0.35, 0, 0.35 } do
				table.insert(out, { part = h, point = h.CFrame:PointToWorldSpace(axis * t) })
			end
		end
	end
	return out
end

-- thrown point first and sticks (a spear, blades, knives)
local SHARP = { spear = true, blade = true, katana = true, knife = true, machete = true }
function Items.Sharp(model: Model?): boolean
	local k = Items.Kind(model)
	return k ~= nil and SHARP[k] == true
end

-- the very tip of a sharp thing (world space), or nil
function Items.TipPoint(model: Model): Vector3?
	local sp = model:FindFirstChild("SpearPoint")
	if sp and sp:IsA("BasePart") then
		return sp.CFrame.Position
	end
	local b = model:FindFirstChild("Blade")
	if b and b:IsA("BasePart") then
		return b.CFrame:PointToWorldSpace(Vector3.new(0, 0, -0.5 * b.Size.Z)) -- (blades point along -Z)
	end
	return nil
end

-- a frame at pos looking along `forward` with `up` as its top (no CFrame.lookAlong needed)
function Items.FrameAlong(pos: Vector3, forward: Vector3, up: Vector3): CFrame
	local f = forward.Unit
	local u = (up - f * up:Dot(f)).Unit
	return CFrame.fromMatrix(pos, f:Cross(u), u)
end

return Items
