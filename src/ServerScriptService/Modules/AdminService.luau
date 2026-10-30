--!nonstrict
-- AdminService: things only the game owner may do (the client asks, this checks Items.IsOwner).
--   fly      : B toggles flying; while you fly you are invincible (no damage, nothing cuts or breaks
--              you, no sleep darts, no virus). The client flies the body (it owns it); the server
--              only keeps the "God" / "Flying" attributes that everything else checks.
--   punch    : L, the super punch. The client reports what the fist hits; this does the damage.
--   laser    : K while flying, the laser eyes. The client says where they burn ~12x a second.
--   daynight / time : the day / night cycle (menu, M)
--   map / mode / spawning : the city map, the game modes, spawning for everybody (menu, M) -
--              handed on to MapService / GameModeService (hooks set by Main)
-- (v2.0) admins: the game owner everywhere; in a PRIVATE server also the private server's owner (free, see
--   Config.FreeAdminInPrivate) and everybody who owns the admin game pass (Config.AdminPassId). They get the
--   player attribute "Admin" and with it every owner power, the admin menu and these commands:
--   kick (a player out of the server), bring / goto, heal all, respawn all, gravity, time stop, the hotdog, the
--   sun cannon, the NPC bots on / off.

local Players = game:GetService("Players")
local SaveGate = require(script.Parent:WaitForChild("SaveGate"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local Config = require(Shared:WaitForChild("Config"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))
local FireService = require(Modules:WaitForChild("FireService"))
local LightingService = require(Modules:WaitForChild("LightingService"))

local AdminRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Admin") :: RemoteEvent
local MarketplaceService = game:GetService("MarketplaceService")
local DataStoreService = game:GetService("DataStoreService")

local AdminService = {}
-- (v2.1) hooks other services fill in
AdminService.GiveCash = nil :: ((Player, number) -> ())?
AdminService.SpawnSandevistan = nil :: ((Player) -> ())?
AdminService.SpawnLedger = nil :: ((Player) -> ())?

-- (v2.9) wipe EVERY player's progress (dollars, skins, titles, kills, quests, cyberware, the sword, chips) and save it
-- gone. Only the game's real owner may do it. Each player's body is rebuilt clean.
function AdminService.WipeAll(by: Player)
	local ok, msg = require(Modules:WaitForChild("ProgressEpoch")).Wipe(by)
	if not ok and by.Parent then AdminRemote:FireClient(by, "reseterror", msg) end
end

------------------------------------------------------------------------
-- (v2.0) who is an admin
------------------------------------------------------------------------

function AdminService.IsPrivateServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0
end

local function ownsPass(player: Player): boolean
	if Config.AdminPassId <= 0 then
		return false
	end
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, Config.AdminPassId)
	end)
	return ok and owns == true
end

function AdminService.RefreshAdmin(player: Player)
	local private = AdminService.IsPrivateServer()
	local admin = false
	if not Items.IsGameOwner(player) then
		if player:GetAttribute("GiftAdmin") == true then
			admin = true -- (v2.0) the owner made them an admin (saved: it stays until the owner takes it back)
		elseif private and Config.FreeAdminInPrivate and player.UserId == game.PrivateServerOwnerId then
			admin = true
		elseif (private or not Config.AdminPassOnlyPrivate) and ownsPass(player) then
			admin = true
		end
	end
	player:SetAttribute("Admin", admin or nil)
end

------------------------------------------------------------------------
-- (v2.0) gifts are saved: a power (or admin) the owner gives somebody stays until the owner takes it back - also
-- when that player leaves and comes back, in any server (DataStore Config.GiftStoreName, by user id)
------------------------------------------------------------------------

local Titles = require(Shared:WaitForChild("Titles"))
local GiftRegistry = require(Modules.GiftRegistry)
local function applyGifts(player, data)
	player:SetAttribute("GiftAdmin", data.admin or nil)
	AdminService.RefreshAdmin(player)
	for _, power in Items.POWERS do
		local on = table.find(data.powers, power) ~= nil
		player:SetAttribute("Gift_" .. power, on or nil)
		if not on and not Items.IsOwner(player) then
			if power == "fly" then AdminService.SetFlying(player, false)
			elseif power == "wonder" and AdminService.OnWonder then AdminService.OnWonder(player, false) end
		end
	end
	for _, t in Titles.List do if t.source == "gift" then player:SetAttribute("GiftTitle_" .. t.id, table.find(data.titles, t.id) ~= nil or nil) end end
	player:SetAttribute("GiftAdmin", data.admin or nil)
	AdminService.RefreshAdmin(player)
end
function AdminService.SetGift(by: Player, target: Player, power: string, on: boolean)
	local ok, message = GiftRegistry.Set(by, target.UserId, power == "admin" and "admin" or ("power:" .. power), on)
	if not ok then AdminRemote:FireClient(by, "reseterror", message) end
end
function AdminService.SetGiftTitle(by: Player, target: Player, id: string, on: boolean)
	local ok, message = GiftRegistry.Set(by, target.UserId, "title:" .. id, on)
	if not ok then AdminRemote:FireClient(by, "reseterror", message) end
end

-- set by Main: (player, action, value) for "map", "mode", "spawning"
-- set by Main: the "Wonder of U" spec on / off for a player
AdminService.OnWonder = nil :: ((Player, boolean) -> ())?
AdminService.OnCommand = nil :: ((Player, string, any, any) -> ())?

function AdminService.SetFlying(player: Player, on: boolean)
	local char = player.Character
	if not char or char:GetAttribute("Dead") then
		return
	end
	char:SetAttribute("Flying", on or nil)
	char:SetAttribute("God", on or nil)
	if not on then
		char:SetAttribute("LaserEyes", nil)
	end
end

------------------------------------------------------------------------
-- super punch
------------------------------------------------------------------------

local punched: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

-- the dash itself (150 studs/s into walls) must not hurt or tear the one who punches: for the dash and a
-- second after it nothing can damage the body (flying has its own "God")
local safeUntil: { [Player]: number } = {}

local function punchSafe(player: Player)
	local char = player.Character
	if not char or char:GetAttribute("Dead") then
		return
	end
	local untilT = os.clock() + Config.SuperPunchTime + Config.SuperPunchSafeTime
	safeUntil[player] = untilT
	char:SetAttribute("God", true)
	task.delay(Config.SuperPunchTime + Config.SuperPunchSafeTime + 0.05, function()
		if safeUntil[player] == untilT and char.Parent and not char:GetAttribute("Flying") then
			char:SetAttribute("God", nil)
		end
	end)
end

local function superPunch(player: Player, part: any, dir: any)
	local char = player.Character
	local torso = char and char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") or char:GetAttribute("Dead") then
		return
	end
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") or not part:IsDescendantOf(workspace) or part:IsDescendantOf(char) then
		return
	end
	if typeof(dir) ~= "Vector3" or dir ~= dir or dir.Magnitude < 0.5 then
		return
	end
	dir = dir.Unit
	if (torso.Position - part.Position).Magnitude > part.Size.Magnitude * 0.5 + 10 then
		return
	end
	local body, region = DamageService.BodyOf(part)
	local key: Instance = body or part.AssemblyRootPart or part
	local now = os.clock()
	if now - (punched[key] or 0) < 0.3 then
		return
	end
	punched[key] = now
	GoreService.Sound("punchBoom", part.Position, 1)
	GoreService.FX({ t = "boomSmall", p = part.Position, d = dir })
	if body and region then
		DamageService.ApplyDamage(body, region, Config.SuperPunchDamage, part.Position, {
			cause = "Super punched by " .. player.DisplayName,
			allowSever = true,
			severAt = Config.SuperPunchDamage * 0.7,
			attacker = player,
		})
		DamageService.Fling(body, dir * Config.SuperPunchKnock + Vector3.new(0, Config.SuperPunchKnock * 0.3, 0), dir)
		GoreService.Sound("bodyHit", part.Position, 1)
		return
	end
	if part.Anchored then
		if ExplosionService.CanShatter(part) then
			ExplosionService.Shatter(part, part.Position, dir)
		elseif part:GetAttribute("Destructible") then
			-- the brick and its neighbours fly out
			for _, p in workspace:GetPartBoundsInRadius(part.Position, 3.5) do
				if p.Anchored and p:GetAttribute("Destructible") then
					ExplosionService.Break(p, dir * Config.SuperPunchPropSpeed * 0.5 + Vector3.new(0, 10, 0))
				end
			end
		elseif part:GetAttribute("Fracture") and ExplosionService.OnFracture then
			-- (v2.0) a fist-shaped hole through the wall
			local fist = torso.Position + dir * 2
			local l = part.CFrame:PointToObjectSpace(fist)
			local h = part.Size * 0.5
			local cp = part.CFrame:PointToWorldSpace(Vector3.new(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z)))
			ExplosionService.OnFracture(part, cp, 3.6, dir, Config.SuperPunchPropSpeed)
		end
		return
	end
	local root = part.AssemblyRootPart
	if not root or root.Anchored then
		return
	end
	local ok, owner = pcall(function()
		return root:GetNetworkOwner()
	end)
	local push = dir * Config.SuperPunchPropSpeed + Vector3.new(0, Config.SuperPunchPropSpeed * 0.25, 0)
	if ok and owner == nil then
		pcall(function()
			root.AssemblyLinearVelocity += push
			root.AssemblyAngularVelocity += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 6
		end)
	else
		GoreService.FX({ t = "push", part = root, i = push * root.AssemblyMass, p = part.Position })
	end
	root:SetAttribute("LastHolder", player.UserId)
end

------------------------------------------------------------------------
-- laser eyes
------------------------------------------------------------------------

local laserLast: { [Player]: number } = {}
local laserBlastT: { [Player]: number } = {} -- (v2.0) when the beam last blew up where it burns
local laserFire: { [Player]: number } = {}
local laserHeat: { [BasePart]: number } = setmetatable({}, { __mode = "k" }) :: any
local laserParams = RaycastParams.new()
laserParams.FilterType = Enum.RaycastFilterType.Exclude

local function laser(player: Player, target: any)
	local char = player.Character
	if not char then
		return
	end
	if target == false or target == nil then
		char:SetAttribute("LaserEyes", nil)
		laserLast[player] = nil
		return
	end
	if not char:GetAttribute("Flying") or char:GetAttribute("Dead") or typeof(target) ~= "Vector3" or target ~= target then
		char:SetAttribute("LaserEyes", nil)
		return
	end
	local head = char:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local now = os.clock()
	local dt = math.min(now - (laserLast[player] or now - 0.08), 0.25)
	laserLast[player] = now
	local to = target - head.Position
	if to.Magnitude > Config.LaserEyesRange + 5 then
		to = to.Unit * Config.LaserEyesRange
	end
	local ignore: { Instance } = { char }
	local fx = workspace:FindFirstChild("FX")
	if fx then
		table.insert(ignore, fx)
	end
	laserParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(head.Position, to.Magnitude > 0.1 and to * 1.02 or head.CFrame.LookVector, laserParams)
	char:SetAttribute("LaserEyes", hit and hit.Position or head.Position + to)
	if not hit then
		return
	end
	local part = hit.Instance
	local dir = to.Unit
	-- (v2.0) where the beams burn, it keeps blowing up: everybody and everything near is thrown away from it
	if now - (laserBlastT[player] or 0) >= Config.LaserBlastEvery then
		laserBlastT[player] = now
		ExplosionService.Explode(hit.Position + hit.Normal * 0.5, {
			radius = Config.LaserBlastRadius,
			damage = Config.LaserBlastDamage,
			power = Config.LaserBlastPower,
			attacker = player,
			cause = "Lasered by " .. player.DisplayName,
			ignore = char,
			kind = "laser",
			sound = "laserBlast",
		})
	end
	local body, region = DamageService.BodyOf(part)
	if body and region then
		if body ~= char then
			DamageService.ApplyDamage(body, region, Config.LaserEyesDPS * dt, hit.Position, {
				cause = "Lasered by " .. player.DisplayName,
				allowSever = true,
				severAt = 45,
				quiet = true,
				attacker = player,
			})
			FireService.SetOnFire(body, 3, player)
		end
		return
	end
	if ExplosionService.CanShatter(part) then
		ExplosionService.Shatter(part, hit.Position, dir)
		return
	end
	if part.Anchored and part:GetAttribute("Destructible") then
		local h = (laserHeat[part] or 0) + dt
		laserHeat[part] = h
		if h > Config.LaserBrickTime then
			laserHeat[part] = nil
			ExplosionService.Break(part, dir * 30 + Vector3.new(0, 8, 0))
		end
	end
	-- the ground / things it burns catch fire
	if now - (laserFire[player] or 0) > Config.LaserGroundTick then
		laserFire[player] = now
		FireService.Ignite(hit.Position, Config.LaserGroundRadius, Config.LaserGroundTime, player)
	end
end

------------------------------------------------------------------------

-- (v2.0) admin menu commands handed on to Main (they need the map / mode / super services)
local FORWARD = {
	map = true, mode = true, spawning = true, weather = true,
	bring = true, goto = true, healall = true, respawnall = true, gravity = true,
	timestop = true, hotdog = true, sun = true, bots = true, botcars = true, quest = true,
	psychosis = true, -- (v2.8.2) cyberpsychosis on / off for the whole server
}

function AdminService.Init()
	-- which single power an action needs (the owner has all of them; the owner can give single ones away)
	local ACTION_POWER = { fly = "fly", punch = "punch", punchsafe = "punch", laser = "laser", wonder = "wonder", timestop = "timestop", hotdog = "hotdog" }
	AdminRemote.OnServerEvent:Connect(function(player, action, value, extra)
		local need = ACTION_POWER[action]
		if need then
			if not Items.Has(player, need) then
				return
			end
		elseif not Items.IsOwner(player) then
			return
		end
		if action == "adminpsycho" and typeof(value) == "boolean" then
			player:SetAttribute("AdminPsychoEnabled", value or nil)
			local cyber = require(Modules:WaitForChild("CyberService"))
			if cyber.AdminPsychosis then cyber.AdminPsychosis(player, value) end
		elseif action == "gift" then
			-- the gift menu: value = user id, extra = "<power>:1" or "<power>:0" (power "admin" = an admin)
			if typeof(value) ~= "number" or typeof(extra) ~= "string" then
				return
			end
			local power, on = string.match(extra, "^(%a+):([01])$")
			local target = Players:GetPlayerByUserId(value)
			if not power or not target or target == player then
				return
			end
			-- (an admin cannot take things away from another admin the owner made; only the owner can)
			if target:GetAttribute("GiftAdmin") and not Items.IsGameOwner(player) then
				return
			end
			AdminService.SetGift(player, target, power, on == "1")
		elseif action == "cash" then
			-- (v2.1) value = user id, extra = dollars (negative takes some away)
			if typeof(value) ~= "number" or typeof(extra) ~= "number" or extra ~= extra then
				return
			end
			local target = Players:GetPlayerByUserId(value)
			if target and AdminService.GiveCash then
				AdminService.GiveCash(target, math.clamp(math.floor(extra), -10000000, 10000000))
			end
		elseif action == "wipeplayer" then
			if typeof(value) == "number" and extra == "WIPE PLAYER" then
				local ok, message = require(Modules.ProgressEpoch).Wipe(player, value)
				if not ok then AdminRemote:FireClient(player, "reseterror", message) end
			end
		elseif action == "wipeall" then
			-- (v2.9) only the real game owner may wipe everyone's progress (not a gifted admin)
			if Items.IsGameOwner(player) and value == "WIPE EVERYONE" then
				AdminService.WipeAll(player)
			end
		elseif action == "sandevistanspawn" then
			if AdminService.SpawnSandevistan then
				AdminService.SpawnSandevistan(player)
			end
		elseif action == "ledgerspawn" then
			if AdminService.SpawnLedger then
				AdminService.SpawnLedger(player)
			end
		elseif action == "titlegift" then
			-- (v2.1) value = user id, extra = "<title id>:1" or "<title id>:0"
			if typeof(value) ~= "number" or typeof(extra) ~= "string" then
				return
			end
			local id, on = string.match(extra, "^(%w+):([01])$")
			local target = Players:GetPlayerByUserId(value)
			if id and target then
				AdminService.SetGiftTitle(player, target, id, on == "1")
			end
		elseif action == "wonder" and typeof(value) == "boolean" then
			if AdminService.OnWonder then
				AdminService.OnWonder(player, value)
			end
		elseif action == "fly" and typeof(value) == "boolean" then
			AdminService.SetFlying(player, value)
		elseif action == "punch" then
			superPunch(player, value, extra)
		elseif action == "punchsafe" then
			punchSafe(player)
		elseif action == "laser" then
			laser(player, value)
		elseif action == "daynight" and typeof(value) == "boolean" then
			LightingService.SetCycle(value)
		elseif action == "time" and typeof(value) == "number" then
			LightingService.SetTime(value)
		elseif action == "kick" and typeof(value) == "number" then
			-- (v2.0) out of the server. Nobody kicks the game owner; admins do not kick themselves.
			local target = Players:GetPlayerByUserId(value)
			if target and target ~= player and not Items.Unkickable(target) then
				target:Kick("You were kicked from the server by an admin (" .. player.DisplayName .. ").")
			end
		elseif FORWARD[action] and AdminService.OnCommand then
			AdminService.OnCommand(player, action, value, extra)
		end
	end)
	-- (v2.0) admins in private servers
	workspace:SetAttribute("PrivateServer", AdminService.IsPrivateServer() or nil)
	workspace:SetAttribute("AdminPassId", Config.AdminPassId > 0 and Config.AdminPassId or nil)
	GiftRegistry.Init(applyGifts)
	local function onPlayer(p: Player)
		task.spawn(AdminService.RefreshAdmin, p)
		task.spawn(GiftRegistry.Load, p) -- (v2.0) the gifts this player was given before
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(p, passId, bought)
		if bought and passId == Config.AdminPassId then
			AdminService.RefreshAdmin(p)
		end
	end)
	-- beams that are not updated any more go out
	task.spawn(function()
		while true do
			task.wait(0.2)
			local now = os.clock()
			for _, p in Players:GetPlayers() do
				local c = p.Character
				if c and c:GetAttribute("LaserEyes") and now - (laserLast[p] or 0) > 0.35 then
					c:SetAttribute("LaserEyes", nil)
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		laserLast[player] = nil
		laserFire[player] = nil
	end)
end

return AdminService
