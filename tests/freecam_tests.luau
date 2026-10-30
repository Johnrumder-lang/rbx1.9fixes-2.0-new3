local total=0
local function check(ok,msg) assert(ok,msg);total+=1 end
local function signal() local s={};function s:Connect(fn) self.fn=fn end;return s end
local player={UserId=2,attrs={},signals={}}
function player:GetAttribute(k) return self.attrs[k] end
function player:GetAttributeChangedSignal(k) self.signals[k]=self.signals[k] or signal();return self.signals[k] end
function player:SetAttribute(k,v) self.attrs[k]=v;local s=self.signals[k];if s and s.fn then s.fn() end end
function player:FindFirstChildOfClass() return {GetChildren=function() return {} end} end
function player:WaitForChild() return {} end
local Enum={CreatorType={User=1},TextXAlignment={Right=1},TextTruncate={AtEnd=1},UserInputType={Keyboard=1},KeyCode={U=1,H=2,T=3}}
local game={CreatorType=1,CreatorId=1,GetService=function() return {IsStudio=function() return false end} end}
local Items=(function()
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

end)()
check(table.find(Items.POWERS,"freecam")~=nil,"freecam included in persistent gift catalog")
check(not Items.Has(player,"freecam"),"ordinary player has no freecam")
player:SetAttribute("Gift_freecam",true)
check(Items.Has(player,"freecam"),"freecam gift grants camera")
check(not Items.IsOwner(player),"freecam gift does not grant admin")
check(not Items.Has(player,"nuke"),"freecam gift does not grant other powers")
local Input={TakeWheel=function() return 0 end,IsControlled=function() return false end}
local Cam={override=nil,fovOffset=0}
local UI={C={},FONT_TITLE=1,FONT_NUM=1}
function UI.make(_,p) p.FindFirstChild=function() return nil end;return p end
function UI.panel(p) return p end
function UI.label(p) return p end
function UI.button(p,fn) return p end
local sounds={Play=function() end}
local function folder(t) t.WaitForChild=function(self,k) return self[k] end;return t end
local shared=folder({Items=Items,SoundLibrary=sounds})
local modules=folder({Input=Input,CameraController=Cam,UI=UI})
local uis={InputBegan=signal()}
local rs={Heartbeat=signal(),IsStudio=function() return false end}
local services={Players={LocalPlayer=player},ReplicatedStorage=folder({Shared=shared}),UserInputService=uis,RunService=rs}
game.GetService=function(_,n) return services[n] end
local require=function(v) assert(v,"unexpected dependency");return v end
local script={Parent=modules}
local Vector3={zero={}}
local Vector2={new=function() return {} end}
local UDim2={new=function() return {} end,fromOffset=function() return {} end}
local workspace={CurrentCamera={CFrame={Position={}},ViewportSize={X=1200}}}
local FreeCam=(function()
--!nonstrict
-- FreeCam (admins and players gifted freecam): the camera leaves your body and flies on its own (screenshots, trailers, watching).
--   U (or FREE CAM in the admin menu)  on / off
--   mouse            look              W A S D   fly        E / Q   up / down
--   Shift            fast (x4)         Ctrl      slow       wheel   base speed
--   right mouse      zoom in           H         hide / show the HUD (clean shots)
--   T                bring your body to the camera (admins only)
-- Gamepad: left stick fly, right stick look, R1 / L1 up / down, R2 zoom.
-- Your body stays where it is and does nothing (no key reaches it while the free cam is on). Only on your screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local Cam = require(Modules:WaitForChild("CameraController"))
local UI = require(Modules:WaitForChild("UI"))

local player = Players.LocalPlayer

local FreeCam = {}

local controller = nil
local active = false
local pos = Vector3.zero
local vel = Vector3.zero
local speed = 40
local zoom = 0
local hint: ScreenGui? = nil
local speedLabel: TextLabel? = nil
local controlsLabel: TextLabel? = nil
local hiddenGuis: { [ScreenGui]: boolean } = {}
local hudHidden = false
local prevOverride = nil
local wasFirstPerson = false

function FreeCam.SetController(c)
	controller = c
end

function FreeCam.Active(): boolean
	return active
end

local function allowed(): boolean
	return Items.Has(player, "freecam")
end

local function setHud(hide: boolean)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then
		return
	end
	if hide then
		for _, g in pg:GetChildren() do
			if g:IsA("ScreenGui") and g ~= hint and g.Enabled and g.Name ~= "SafetySettings" then
				hiddenGuis[g] = true
				g.Enabled = false
			end
		end
	else
		for g in hiddenGuis do
			if g.Parent then
				g.Enabled = true
			end
		end
		table.clear(hiddenGuis)
	end
	hudHidden = hide
	if hint then
		local panel = hint:FindFirstChild("Panel")
		if panel and panel:IsA("GuiObject") then
			panel.Visible = not hide
		end
	end
end

local function controlsText(): string
	return "WASD fly | E/Q up/down | Shift fast | Ctrl slow | wheel speed | RMB zoom"
		.. (Items.IsOwner(player) and " | T body here" or "") .. " | H hide | U exit"
end

local function buildHint()
	local pg = player:WaitForChild("PlayerGui")
	local g = UI.make("ScreenGui", { Name = "FreeCamHint", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50, Parent = pg })
	local p = UI.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(640, 52),
		BackgroundTransparency = 0.25,
		Accent = UI.C.amber,
		Parent = g,
	})
	UI.label({
		Text = "FREE CAM",
		Font = UI.FONT_TITLE,
		TextSize = 15,
		TextColor3 = UI.C.amber,
		Position = UDim2.fromOffset(14, 6),
		Size = UDim2.fromOffset(120, 18),
		Parent = p,
	})
	speedLabel = UI.label({
		Text = "",
		Font = UI.FONT_NUM,
		TextSize = 13,
		TextColor3 = UI.C.dim,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -164, 0, 6),
		Size = UDim2.fromOffset(150, 18),
		Parent = p,
	})
	controlsLabel = UI.label({
		Text = controlsText(),
		TextSize = 13,
		TextColor3 = UI.C.text,
		Position = UDim2.fromOffset(14, 27),
		Size = UDim2.new(1, -28, 0, 18),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = p,
	})
	-- (touch: no U key - a button)
	UI.button({
		Text = "EXIT",
		TextSize = 12,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, -30),
		Size = UDim2.fromOffset(64, 24),
		BackgroundColor3 = UI.C.bad,
		Parent = p,
	}, function()
		FreeCam.Set(false)
	end)
	UI.make("UIScale", { Scale = math.min(1, ((workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize.X or 800) - 24) / 640), Parent = p })
	hint = g
end

function FreeCam.Set(on: boolean)
	if on == active then
		return
	end
	if on and not allowed() then
		return
	end
	active = on
	Input.freeCam = on
	Input.wheelCapture = on
	Input.TakeWheel()
	if on then
		local cam = workspace.CurrentCamera
		pos = cam and cam.CFrame.Position or pos
		vel = Vector3.zero
		zoom = 0
		Input.mouseLeft = false
		Input.mouseRight = false
		Input.useHeld = false
		Input.aimHeld = false
		Input.jumpHeld = false
		Input.runHeld = false
		Input.downHeld = false
		-- (your own body is hidden in first person: it shows again while the camera flies)
		wasFirstPerson = Input.firstPerson
		Input.firstPerson = false
		prevOverride = Cam.override
		Cam.override = function(dt: number): CFrame?
			return FreeCam._step(dt)
		end
		if not hint then
			buildHint()
		end
		if hint then
			hint.Enabled = true
		end
		SoundLibrary.Play("click", nil, 0.6)
	else
		Cam.override = prevOverride
		prevOverride = nil
		Cam.fovOffset = 0
		Input.firstPerson = wasFirstPerson
		if hudHidden then
			setHud(false)
		end
		if hint then
			hint.Enabled = false
		end
		SoundLibrary.Play("click", nil, 0.5, 0.8)
	end
end

function FreeCam.Toggle()
	FreeCam.Set(not active)
end

-- one frame (called by the camera: Cam.override)
function FreeCam._step(dt: number): CFrame?
	if not active then
		return nil
	end
	local rot = Cam.Rotation()
	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local move = Vector3.zero
	local up = 0
	local mult = 1
	local zoomIn = false
	if not typing then
		local function down(k: Enum.KeyCode): boolean
			return UserInputService:IsKeyDown(k)
		end
		move = Vector3.new((down(Enum.KeyCode.D) and 1 or 0) - (down(Enum.KeyCode.A) and 1 or 0), 0, (down(Enum.KeyCode.S) and 1 or 0) - (down(Enum.KeyCode.W) and 1 or 0))
		up = (down(Enum.KeyCode.E) and 1 or 0) - (down(Enum.KeyCode.Q) and 1 or 0)
		if down(Enum.KeyCode.LeftShift) or down(Enum.KeyCode.RightShift) then
			mult = 4
		elseif down(Enum.KeyCode.LeftControl) or down(Enum.KeyCode.RightControl) then
			mult = 0.25
		end
		zoomIn = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		for _, io in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if io.KeyCode == Enum.KeyCode.Thumbstick1 and io.Position.Magnitude > 0.15 then
				move += Vector3.new(io.Position.X, 0, -io.Position.Y)
			elseif io.KeyCode == Enum.KeyCode.ButtonR1 and io.Position.Z > 0.5 then
				up += 1
			elseif io.KeyCode == Enum.KeyCode.ButtonL1 and io.Position.Z > 0.5 then
				up -= 1
			elseif io.KeyCode == Enum.KeyCode.ButtonR2 and io.Position.Z > 0.3 then
				zoomIn = true
			end
		end
	end
	-- the wheel: base speed
	local w = Input.TakeWheel()
	if w ~= 0 then
		speed = math.clamp(speed * (1.25 ^ w), 4, 2500)
	end
	if move.Magnitude > 1 then
		move = move.Unit
	end
	local want = (rot:VectorToWorldSpace(move) + Vector3.new(0, up, 0)) * speed * mult
	vel = vel:Lerp(want, math.min(1, dt * 6))
	pos += vel * dt
	-- zoom: a narrower view while the right mouse button is held
	zoom += ((zoomIn and 1 or 0) - zoom) * math.min(1, dt * 8)
	Cam.fovOffset = -zoom * 45
	if speedLabel then
		speedLabel.Text = string.format("SPEED %d", math.floor(speed * mult + 0.5))
	end
	return CFrame.new(pos) * rot
end

-- T: your body comes to the camera
local function bringBody()
	if not Items.IsOwner(player) then return end
	local c = controller
	if not c or c.dead or not c.torso then
		return
	end
	local VehicleClient = require(Modules:WaitForChild("VehicleClient")) :: any
	task.spawn(function()
		if VehicleClient.Leave() then
			task.wait(0.35)
		end
		if c and not c.dead and Items.IsOwner(player) then
			SoundLibrary.Play("teleport", c.torso, 1)
			pcall(function()
				c:_teleportTo(pos, true)
				c.airTime = 0
			end)
		end
	end)
end

function FreeCam.Init()
	UserInputService.InputBegan:Connect(function(io, gameProcessed)
		if Input.IsControlled() then return end
		if gameProcessed or io.UserInputType ~= Enum.UserInputType.Keyboard then
			return
		end
		if Input.keysCaptured and not active then
			return -- (playing the piano)
		end
		local k = io.KeyCode
		if k == Enum.KeyCode.U and not Input.menuOpen and not Input.promptOpen then
			if active or allowed() then
				FreeCam.Toggle()
			end
		elseif active and k == Enum.KeyCode.H then
			setHud(not hudHidden)
		elseif active and k == Enum.KeyCode.T then
			bringBody()
		end
	end)
	-- Revocation immediately restores the camera, HUD and normal input.
	for _, attribute in { "Admin", "GiftAdmin", "Gift_freecam" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			if active and not allowed() then FreeCam.Set(false) end
			if controlsLabel then controlsLabel.Text = controlsText() end
		end)
	end
	RunService.Heartbeat:Connect(function()
		if active and Input.menuOpen then
			-- (a menu opened over the free cam: the mouse is free for it, the camera waits)
			vel = Vector3.zero
		end
	end)
end

return FreeCam

end)()
FreeCam.Init()
player:SetAttribute("Gift_freecam",nil)
FreeCam.Set(true)
check(not FreeCam.Active(),"camera refuses access without gift")
player:SetAttribute("Gift_freecam",true)
FreeCam.Set(true)
check(FreeCam.Active() and Input.freeCam and Input.wheelCapture,"gift enables camera and captures wheel")
check(Cam.override~=nil,"gift installs camera override")
-- Non-admin T must not load VehicleClient or move the body.
FreeCam.SetController({dead=false,torso={},_teleportTo=function() error("gift teleported body") end})
uis.InputBegan.fn({UserInputType=1,KeyCode=3},false)
check(true,"gift freecam cannot teleport body")
player:SetAttribute("Gift_freecam",nil)
check(not FreeCam.Active(),"revocation exits camera immediately")
check(not Input.freeCam and not Input.wheelCapture and Cam.override==nil,"revocation restores input and camera")
player:SetAttribute("Admin",true)
FreeCam.Set(true)
check(FreeCam.Active(),"admin retains freecam")
player:SetAttribute("Admin",nil)
check(not FreeCam.Active(),"admin revocation exits freecam")
print("PASS: "..total.." freecam gift assertions")
