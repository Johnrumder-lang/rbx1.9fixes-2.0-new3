local total=0
local function check(ok,why) assert(ok,why);total+=1 end
local function eq(a,b,why) check(a==b,(why or "mismatch")..": "..tostring(a).." / "..tostring(b)) end
local realType=typeof
local function typeof(v) return type(v)=="table" and v.__type or realType(v) end
local vm={}
local function vec(x,y,z) return setmetatable({X=x,Y=y,Z=z,__type="Vector3"},vm) end
vm.__sub=function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
vm.__add=function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
vm.__mul=function(a,b) if type(a)=="number" then a,b=b,a end;return vec(a.X*b,a.Y*b,a.Z*b) end
vm.__index=function(a,k) if k=="Magnitude" then return math.sqrt(a.X*a.X+a.Y*a.Y+a.Z*a.Z) end;if k=="Unit" then return a*(1/a.Magnitude) end end
local Vector3={new=vec,zero=vec(0,0,0),yAxis=vec(0,1,0),one=vec(1,1,1)}
local Color3={fromRGB=function(r,g,b) return {R=r/255,G=g/255,B=b/255} end,new=function(r,g,b) return {R=r,G=g,B=b} end}
local function event() return {Connect=function(self,fn) self.callback=fn;return {Disconnect=function() end} end} end
local function object(class)
 local o={attrs={},children={},ClassName=class,Parent=true,__type="Instance"}
 function o:GetAttribute(k) return self.attrs[k] end
 function o:SetAttribute(k,v) self.attrs[k]=v end
 function o:FindFirstChild(k) return self.children[k] end
 function o:WaitForChild(k) return self.children[k] end
 function o:GetChildren() return {} end
 function o:GetDescendants() return {} end
 function o:IsA(c) return self.ClassName==c or c=="Instance" end
 function o:GetAttributeChangedSignal() return event() end
 function o:Destroy() self.Parent=nil end
 return o
end
local workspace=object("Workspace")
function workspace:GetServerTimeNow() return 1000 end
workspace.Gravity=196.2
local Players={list={},PlayerAdded=event(),PlayerRemoving=event()}
function Players:GetPlayers() return self.list end
function Players:GetPlayerByUserId(id) for _,p in self.list do if p.UserId==id then return p end end end
function Players:GetPlayerFromCharacter(c) for _,p in self.list do if p.Character==c then return p end end end
local function player(id,pos,admin)
 local p=object("Player");p.UserId=id;p.DisplayName="P"..id;p.admin=admin;p.CharacterAdded=event();p.Character=object("Model")
 local torso=object("BasePart");torso.Position=pos;p.Character.children.Torso=torso;return p
end
local task={spawn=function() end,delay=function() end,wait=function() end}
local Random={new=function() return {NextNumber=function(_,a,b) return a or .5 end,NextInteger=function(_,a) return a end} end}
local shared=object("Folder");local replicated=object("Folder");replicated.children.Shared=shared
local remotes=object("Folder");replicated.children.Remotes=remotes
local modules=object("Folder");local script={Parent=modules}
local game={GetService=function(_,name) if name=="Players" then return Players elseif name=="ReplicatedStorage" then return replicated end;return {} end}
local require=function(m) return m end
local Config={CyberTolerance=20,ChipSlots=4,SandevistanCycle=300,SandevistanDuration=10}
shared.children.Config=Config
local Items={IsOwner=function(p) return p.admin==true end,Has=function() return false end}
shared.children.Items=Items
modules.children.Persist={Get=function() return nil end};modules.children.SpineModel={}
local Chips=(function()
--!strict
-- Chips (v2.9): the catalog of neck chips for the cyberdeck. All names and effects are made up for this game
-- (a cyberpunk sandbox), like the implants in Shared/Cyberware.
--   * a body has Config.ChipSlots (4) neck slots. A chip sits in one slot.
--   * KINDS:
--       "combat"   a fast skill that works on its own or on a toggle (REFLEX BUFFER dodges bullets, ZOOM, SCANNER).
--       "net"      a NETRUNNER QUICKHACK: aimed at a person in the netrunner interface (K). It lands only if your
--                  tier is higher than their FIREWALL tier (a FIREWALL chip). A higher tier does more.
--       "firewall" passive defence: antivirus + quickhack resistance. A virus / quickhack of this tier or lower bounces.
--       "capacity" passive: +cyberware tolerance (so more implants fit without cyberpsychosis).
--       "blank"    nothing until you program it at a computer (it becomes a virus chip).
--       "blackwall" admins only. An admin opens the netrunner interface and lets it loose on someone (a red beam, ash).
--                  Anybody who is not an admin that slots it is smitten by the beam themselves.
--   * a VIDEO chip is not in this catalog - the camera makes it (CameraService). It can carry a virus (a trojan).

local Chips = {}

export type Def = {
	id: string,
	name: string,
	kind: string, -- "combat" | "net" | "firewall" | "capacity" | "blank" | "blackwall"
	tiers: number,
	price: { number },
	desc: { string }, -- what each tier does (one line each)
	info: string,
	ability: string?, -- the label (combat toggles / net quickhacks); nil = passive
	cooldown: { number }?, -- s per tier (net quickhacks, combat actives)
	color: { number }, -- {r,g,b} the chip's glow
	admin: boolean?,
}

Chips.List = {
	-- combat / active
	{
		id = "dodge", name = "REFLEX BUFFER", kind = "combat", tiers = 3,
		price = { 400, 1000, 2200 },
		desc = {
			"The next bullet that would hit you is dodged. 20 s between charges.",
			"The next 2 bullets are dodged.",
			"The next 3 bullets are dodged - and the dodge nudges you aside.",
		},
		info = "Reads the shot before it lands and steps your body out of the line. It works on its own.",
		ability = "DODGE", cooldown = { 20, 20, 20 }, color = { 90, 220, 255 },
	},
	{
		id = "zoom", name = "ZOOM OPTICS", kind = "combat", tiers = 3,
		price = { 150, 400, 900 },
		desc = { "Zoom in (toggle in the deck, K).", "Zoom in further.", "A long-range scope." },
		info = "A lens that magnifies what you look at. Toggle it in the cyberdeck (K).",
		ability = "ZOOM", color = { 120, 200, 255 },
	},
	{
		id = "scan", name = "SCANNER", kind = "combat", tiers = 3,
		price = { 250, 650, 1500 },
		desc = {
			"Everything on your screen is boxed and named (people, items, cars).",
			"It also reads their health and what chrome they carry.",
			"It reads their FIREWALL too - who you can hack and who you can not.",
		},
		info = "An identify routine. Draws a box round everything you see. Toggle it in the cyberdeck (K).",
		ability = "SCAN", color = { 120, 255, 200 },
	},
	-- netrunner quickhacks (aimed at a person in the netrunner interface, K)
	{
		id = "burnout", name = "BURNOUT", kind = "net", tiers = 3,
		price = { 500, 1200, 2600 },
		desc = {
			"Overloads a target: a jolt of damage. Beats a FIREWALL below its tier.",
			"More damage, and it stuns them for a moment.",
			"A heavy overload: big damage, it knocks them down and burns their chrome for a few seconds.",
		},
		info = "Pushes a surge back down the link. The classic quickhack.",
		ability = "BURNOUT", cooldown = { 16, 14, 12 }, color = { 255, 90, 70 },
	},
	{
		id = "overheat", name = "OVERHEAT", kind = "net", tiers = 3,
		price = { 450, 1100, 2400 },
		desc = { "Sets the target on fire.", "A bigger fire, longer.", "They burn hard and can not put it out fast." },
		info = "Spins their cooling the wrong way until they cook.",
		ability = "OVERHEAT", cooldown = { 18, 16, 14 }, color = { 255, 140, 40 },
	},
	{
		id = "shortcircuit", name = "SHORT CIRCUIT", kind = "net", tiers = 3,
		price = { 450, 1100, 2400 },
		desc = {
			"A shock, and their chips go dead for 4 s (no quickhacks, no dodge, no implants).",
			"8 s dead, more shock.",
			"12 s dead, a heavy shock that drops them.",
		},
		info = "An EMP down the link: it shuts their chrome off for a while.",
		ability = "EMP", cooldown = { 20, 18, 16 }, color = { 120, 200, 255 },
	},
	{
		id = "reboot", name = "REBOOT OPTICS", kind = "net", tiers = 3,
		price = { 400, 1000, 2200 },
		desc = { "Blinds the target for 3 s.", "Blinds them for 5 s.", "Blinds them for 8 s, and scrambles their aim." },
		info = "Reboots their eyes: their screen goes white.",
		ability = "BLIND", cooldown = { 16, 14, 12 }, color = { 240, 240, 255 },
	},
	{
		id = "contagion", name = "CONTAGION", kind = "net", tiers = 3,
		price = { 550, 1300, 2800 },
		desc = {
			"Infects the target with the virus (it spreads to whoever is near them).",
			"Faster, and it hurts more.",
			"A hard strain that spreads fast and far.",
		},
		info = "Loads the biological virus into their blood over the link. It spreads like the bottle does.",
		ability = "CONTAGION", cooldown = { 22, 20, 18 }, color = { 120, 255, 120 },
	},
	{
		id = "cyberpsycho", name = "CYBERPSYCHOSIS", kind = "net", tiers = 3,
		price = { 700, 1600, 3400 },
		desc = {
			"The target crashes out for a few seconds: they attack whoever is nearest.",
			"Longer, and harder to shake.",
			"A full crash out: they go on a rampage until it wears off.",
		},
		info = "Floods them with chrome-madness. They stop being yours to reason with.",
		ability = "PSYCHO", cooldown = { 28, 26, 24 }, color = { 190, 90, 255 },
	},
	{
		id = "sysreset", name = "SYSTEM RESET", kind = "net", tiers = 3,
		price = { 600, 1400, 3000 },
		desc = { "Knocks the target out cold for a while.", "Longer.", "They drop like a stone and stay down." },
		info = "Flatlines their system to standby: they fall asleep where they stand.",
		ability = "RESET", cooldown = { 30, 28, 26 }, color = { 80, 180, 255 },
	},
	{
		id = "weaponglitch", name = "WEAPON GLITCH", kind = "net", tiers = 3,
		price = { 350, 850, 1800 },
		desc = { "The target drops what is in their hands.", "They drop it and can not grab for 3 s.", "They can not grab for 6 s." },
		info = "Jams the grip servos in their hands: whatever they hold slips out.",
		ability = "GLITCH", cooldown = { 16, 14, 12 }, color = { 255, 200, 70 },
	},
	{
		id = "cripple", name = "CRIPPLE MOVEMENT", kind = "net", tiers = 3,
		price = { 350, 850, 1800 },
		desc = { "Slows the target to a crawl for 4 s.", "6 s, slower.", "8 s, they can barely move." },
		info = "Locks their leg servos half-shut.",
		ability = "CRIPPLE", cooldown = { 16, 14, 12 }, color = { 150, 170, 255 },
	},
	-- defence / passive
	{
		id = "firewall", name = "FIREWALL", kind = "firewall", tiers = 3,
		price = { 400, 1000, 2200 },
		desc = {
			"A firewall of tier 1: viruses and quickhacks of tier 1 bounce off you.",
			"Tier 2: tier 1 and 2 bounce.",
			"Tier 3: only a stronger netrunner can touch you.",
		},
		info = "Antivirus. A virus or quickhack only lands if it is a higher tier than your firewall.",
		color = { 90, 255, 170 },
	},
	{
		id = "capacity", name = "RAM EXPANSION", kind = "capacity", tiers = 3,
		price = { 500, 1200, 2600 },
		desc = {
			"+1 cyberware tolerance (room for more implants before cyberpsychosis).",
			"+2 tolerance.",
			"+3 tolerance.",
		},
		info = "More memory for your chrome. You can carry more implants without crashing out.",
		color = { 255, 210, 90 },
	},
	{
		id = "blank", name = "BLANK CHIP", kind = "blank", tiers = 1,
		price = { 80 },
		desc = { "Empty. Program it at a computer into a virus, or load a video onto it." },
		info = "A blank chip. Take it to a computer to make a virus, or record onto it.",
		color = { 150, 150, 160 },
	},
	{
		id = "blackwall", name = "BLACKWALL SHARD", kind = "blackwall", tiers = 1,
		price = { 0 },
		desc = { "A sliver of the Blackwall. An admin can let it loose on someone: a red beam, and they are ash." },
		info = "Admins only. Anyone else who slots it is burned by the beam themselves.",
		ability = "BLACKWALL", cooldown = { 20 }, color = { 255, 30, 40 }, admin = true,
	},
}

Chips.ById = {} :: { [string]: Def }
for _, d in Chips.List do
	Chips.ById[d.id] = d
end

-- the payloads a virus (a programmed blank chip, or a trojan in a video) can carry
Chips.Payloads = {
	{ id = "explode", name = "DETONATE", info = "They blow up." },
	{ id = "hallucinate", name = "HALLUCINATE", info = "They start seeing things that are not there." },
	{ id = "rampage", name = "RAMPAGE", info = "They crash out and attack whoever is near." },
	{ id = "killtarget", name = "KILL A TARGET", info = "They go after one person you choose until one of them is down." },
}
Chips.PayloadById = {} :: { [string]: { id: string, name: string, info: string } }
for _, p in Chips.Payloads do
	Chips.PayloadById[p.id] = p
end

function Chips.Color(d: Def): Color3
	local c = d.color
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Chips.Price(id: string, tier: number): number
	local d = Chips.ById[id]
	return d and (d.price[math.clamp(tier, 1, d.tiers)] or 0) or 0
end

return Chips

end)()
shared.children.Chips=Chips
local TimeScale=(function()
--!strict
-- TimeScale (v2.8): the Sandevistan's slow motion for everything that moves by script (rockets, flares, bombs, steel
-- balls, bullets in flight, the Crawler, NPC brains, bodies' controllers). Game time = real time x Get().
--   workspace attributes (set by SuperService.SlowMo): SlowScale (0..1), SlowMo (the user's UserId), RealGravity
--   (the gravity before it was lowered: the physics runs with RealGravity x SlowScale^2, so things fall in slow motion).
-- The one who runs it lives in normal time: For(userId) is 1 for them.

local TimeScale = {}

local function rawScale(): number
	local s = workspace:GetAttribute("SlowScale")
	if typeof(s) == "number" and s > 0 and s < 1 then
		return s
	end
	return 1
end

-- A local field never changes the entire world's clock.
function TimeScale.Get(): number
	return workspace:GetAttribute("SlowFieldR") and 1 or rawScale()
end
function TimeScale.Active(): boolean
	return rawScale() < 1
end
-- (v2.9) a LOCAL Sandevistan: the slow motion only catches a body that is within SlowFieldR studs of the one who runs
-- it (SuperService sets SlowFieldR). The user runs at normal speed as always; so does anybody far enough away. With no
-- SlowFieldR set it is the old whole-world slow.
local function isSlowUser(uid: number): boolean
	if workspace:GetAttribute("SlowMo") == uid then
		return true
	end
	local users = workspace:GetAttribute("SlowMoUsers")
	return typeof(users) == "string" and string.find(users, "," .. tostring(uid) .. ",", 1, true) ~= nil
end

function TimeScale.ForField(userId: number?, pos: Vector3?): number
	local base = userId and isSlowUser(userId) and 1 or rawScale()
	if base >= 1 or not pos then
		return pos and base or 1 -- (a user, or no slow running)
	end
	local r = workspace:GetAttribute("SlowFieldR")
	if typeof(r) ~= "number" or r <= 0 then
		return base -- (whole-world slow: no radius)
	end
	local best = math.huge
	for _, p in game:GetService("Players"):GetPlayers() do
		if isSlowUser(p.UserId) then
			local c = p.Character
			local t = c and c:FindFirstChild("Torso")
			if t and t:IsA("BasePart") then
				best = math.min(best, (t.Position - pos).Magnitude)
			end
		end
	end
	return best <= r and base or 1
end

function TimeScale.For(userId: number?): number
	local p = userId and game:GetService("Players"):GetPlayerByUserId(userId)
	local t = p and p.Character and p.Character:FindFirstChild("Torso")
	return TimeScale.ForField(userId, t and t.Position)
end

-- the real gravity (slow motion lowers workspace.Gravity for the physics)
function TimeScale.Gravity(): number
	local g = workspace:GetAttribute("RealGravity")
	if typeof(g) == "number" and TimeScale.Get() < 1 then
		return g
	end
	return workspace.Gravity
end

return TimeScale

end)()
local caster=player(1,vec(0,0,0));local near=player(2,vec(60,0,0));local far=player(3,vec(200,0,0));Players.list={caster,near,far}
workspace:SetAttribute("SlowScale",.06);workspace:SetAttribute("SlowMo",1);workspace:SetAttribute("SlowMoUsers",",1,");workspace:SetAttribute("SlowFieldR",70)
eq(TimeScale.For(1),1,"caster immunity");eq(TimeScale.For(2),.06,"near player slowed");eq(TimeScale.For(3),1,"distant player normal")
eq(TimeScale.Get(),1,"global world stays normal");eq(TimeScale.ForField(nil,vec(70,0,0)),.06,"radius inclusive");eq(TimeScale.ForField(nil,vec(70.01,0,0)),1,"radius exit")
workspace:SetAttribute("SlowMoUsers",",1,2,");eq(TimeScale.For(2),1,"two simultaneous casters")
workspace:SetAttribute("SlowMoUsers",",1,");near.Character.children.Torso.Position=vec(80,0,0);eq(TimeScale.For(2),1,"moving out restores clock")
workspace:SetAttribute("SlowScale",nil);eq(TimeScale.ForField(nil,vec(0,0,0)),1,"field ends")
local Sandy=(function()
--!nonstrict
-- SandevistanService (v2.1i): cyberware. Rare (it can lie in the construction site) or spawned by an admin.
--   * IMPLANT: ANOTHER player aims the item at you and presses F: the same fitting as a prosthetic (same reach, same bar; GearService), but it
--     takes Config.SandevistanImplantTime s. If you are not ASLEEP (a sleep dart) it hurts a bit when it is in. A spine implant is then
--     VISIBLE on your back (SpineModel) for everybody.
--   * USE: double-tap Shift. Config.SandevistanDuration s of SLOW MOTION (the world runs at about 0.05x, bullets crawl), you walk at double
--     speed, leave afterimages, your screen is green, and your punches and kicks hit people.
--       - the first use: clean.
--       - within Config.SandevistanHot s after it ended the circuits are hot: use it AGAIN and it fries (1 s, then you are DOWN for 10 s and
--         2-3 limbs are burnt out).
--       - until Config.SandevistanCycle s after the first use it works but HURTS, the more the sooner it is.
--   * PSYCHOSIS: the longer you carry it and the more you use it, the more you SEE things that are not there (hallucinations, like in the show).
--   * ADMINS are immune: no burnout, no strain, no psychosis, no waiting - and they can use it without an implant.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local SpineModel = require(script.Parent:WaitForChild("SpineModel"))

local SandevistanService = {}

local deps: any = {}
local Remote: RemoteEvent
local rng = Random.new()

type Implant = { firstUse: number?, activeUntil: number, mode: string?, level: number, nextEpisode: number, down: boolean, real: boolean }
local implants: { [Player]: Implant } = {}

local LIMBS = { "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local PART_OF = { Head = "Head", Torso = "Torso", LeftArm = "Left Arm", RightArm = "Right Arm", LeftLeg = "Left Leg", RightLeg = "Right Leg" }

local function say(p: Player, text: string)
	Remote:FireClient(p, "msg", text)
end

local function alive(p: Player): (Model?, BasePart?)
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	if c and t and t:IsA("BasePart") and c:GetAttribute("Dead") ~= true and c.Parent then
		return c, t
	end
	return nil, nil
end

local function newState(real: boolean): Implant
	return { firstUse = nil, activeUntil = 0, mode = nil, level = 0, nextEpisode = os.clock() + 55, down = false, real = real }
end

------------------------------------------------------------------------
-- the implant on the back
------------------------------------------------------------------------

local function attachSpine(char: Model)
	local torso = char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") or char:FindFirstChild("SandevistanSpine", true) then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "SandevistanSpine"
	folder.Parent = torso
	local origin = torso.CFrame * CFrame.new(0, 0.02, 0.5)
	for _, sp in SpineModel.Specs(0.74) do
		local p = Instance.new("Part")
		p.Name = sp.name
		p.Size = sp.size
		p.Color = sp.color
		p.Material = sp.material
		p.Reflectance = sp.refl or 0
		p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.CFrame = origin * sp.off
		p.Parent = folder
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = torso, p
		w.Parent = p
		if sp.name == "SpineTop" then
			local l = Instance.new("PointLight")
			l.Name = "SpineGlow"
			l.Color = Color3.fromRGB(80, 255, 160)
			l.Range = 9
			l.Brightness = 1.6
			l.Enabled = false
			l.Parent = p
		end
	end
	-- two cables from the neck to the shoulders
	for _, s in { -1, 1 } do
		local c = Instance.new("Part")
		c.Name = "SpineCable"
		c.Size = Vector3.new(0.8, 0.07, 0.07)
		c.Color = Color3.fromRGB(14, 14, 16)
		c.Material = Enum.Material.Rubber
		c.CanCollide, c.CanQuery, c.CanTouch, c.Massless = false, false, false, true
		c.CFrame = torso.CFrame * CFrame.new(s * 0.5, 0.86, 0.54) * CFrame.Angles(0, 0, math.rad(s * -14))
		c.Parent = folder
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = torso, c
		w.Parent = c
	end
end

-- the lights of the implant burn bright while it runs
local function spineGlow(char: Model, on: boolean)
	local folder = char:FindFirstChild("SandevistanSpine", true)
	if not folder then
		return
	end
	for _, d in folder:GetChildren() do
		if d.Name == "SpineLed" and d:IsA("BasePart") then
			d.Color = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(60, 255, 150)
		end
		local l = d:FindFirstChild("SpineGlow")
		if l and l:IsA("PointLight") then
			l.Enabled = on
		end
	end
end

-- (v2.8) quiet: no message (a respawn: the implant stays in - CyberService); clean: no side effects (COLOSSUS)
local function grant(p: Player, quiet: boolean?, clean: boolean?)
	local char = p.Character
	local previous = implants[p]
	implants[p] = previous or newState(not clean)
	implants[p].real = not clean
	implants[p].activeUntil = 0
	implants[p].mode = nil
	implants[p].down = false
	p:SetAttribute("HasSandevistan", true)
	if char then
		char:SetAttribute("Sandevistan", true) -- (a body that has one: it cannot get a second)
		if clean then
			char:SetAttribute("SandevistanClean", true)
		end
		attachSpine(char)
	end
	if not quiet then
		say(p, "The Sandevistan is in. Double-tap SHIFT to use it. Careful: it burns you out if you use it twice in a row.")
	end
end
SandevistanService.Grant = grant
-- (v2.8) set by CyberService: the implant went in from the item (it is then remembered like every implant)
SandevistanService.OnImplanted = nil :: ((Player) -> ())?

-- (v2.8) operated out (CyberService)
function SandevistanService.Revoke(p: Player)
	implants[p] = nil
	p:SetAttribute("HasSandevistan", nil)
	p:SetAttribute("SandevistanPsycho", nil)
	p:SetAttribute("SandevistanCycleEnd", nil)
	local char = p.Character
	if char then
		char:SetAttribute("Sandevistan", nil)
		char:SetAttribute("SandevistanClean", nil)
		char:SetAttribute("SandevistanOn", nil)
		local spine = char:FindFirstChild("SandevistanSpine", true)
		if spine then
			spine:Destroy()
		end
	end
end

-- the fitting (GearService) is done: the implant goes in
local function onImplant(surgeon: Player, target: Model, item: Model)
	local p = Players:GetPlayerFromCharacter(target)
	local tchar, ttorso = nil, nil
	if p then
		tchar, ttorso = alive(p)
	end
	if not p or not tchar or not ttorso or target:GetAttribute("Sandevistan") == true then
		return
	end
	-- not asleep: the surgery hurt
	if tchar:GetAttribute("Asleep") ~= true then
		pcall(function()
			deps.DamageService.ApplyDamage(tchar, "Torso", 22, ttorso.Position, { cause = "Implant surgery", allowSever = false, attacker = surgeon, bleed = 0.8, bleedTime = 6 })
		end)
		pcall(function()
			deps.DamageService.Knock(tchar, "Torso", nil, 1.5)
		end)
	end
	pcall(deps.GoreService.Sound, "metal", ttorso, 1)
	pcall(deps.OwnershipService.DropItem, item)
	item:Destroy()
	grant(p)
	if SandevistanService.OnImplanted then
		SandevistanService.OnImplanted(p)
	end
end

------------------------------------------------------------------------
-- strikes: a body that runs the Sandevistan hits what it touches - punches, kicks, drop kicks
------------------------------------------------------------------------

local function targets(except: Model): { Model }
	local out = {}
	for _, pl in Players:GetPlayers() do
		local c = pl.Character
		if c and c ~= except and c:GetAttribute("Dead") ~= true then
			table.insert(out, c)
		end
	end
	for _, name in { "NPCs", "Dummies" } do
		local f = workspace:FindFirstChild(name)
		for _, m in (f and f:GetChildren() or {}) do
			if m:IsA("Model") and m ~= except and m:GetAttribute("Dead") ~= true then
				table.insert(out, m)
			end
		end
	end
	return out
end

local function strikeLoop(p: Player, st: Implant)
	task.spawn(function()
		local last: { [Model]: number } = {}
		while implants[p] == st and st.activeUntil > 0 do
			task.wait(0.05)
			local char = alive(p)
			if not char then
				return
			end
			local now = os.clock()
			for _, body in targets(char) do
				if now - (last[body] or 0) >= 0.5 then
					local done = false
					for _, key in LIMBS do
						local limb = char:FindFirstChild(PART_OF[key])
						if limb and limb:IsA("BasePart") and not done then
							local v = limb.AssemblyLinearVelocity
							local speed = v.Magnitude
							if speed > 15 then
								for region, partName in PART_OF do
									local tp = body:FindFirstChild(partName)
									if tp and tp:IsA("BasePart") and (tp.Position - limb.Position).Magnitude < (tp.Size.Magnitude * 0.5 + 0.9) then
										done = true
										last[body] = now
										local isLeg = key == "LeftLeg" or key == "RightLeg"
										local dmg = (isLeg and 26 or 15) * math.clamp(speed / 20, 1, 2.4)
										pcall(function()
											deps.DamageService.ApplyDamage(body, region, dmg, tp.Position, { cause = "Sandevistan strike", allowSever = false, attacker = p, bleed = 0.4, bleedTime = 4 })
										end)
										local push = v.Unit * (isLeg and 70 or 45) + Vector3.new(0, 14, 0)
										pcall(function()
											deps.DamageService.Blast(body, push, 1.6)
										end)
										pcall(function()
											deps.SuperService.SlowMoImpulse(body, push) -- (the world is slow: so is the push)
										end)
										pcall(function()
											deps.GoreService.Sound(isLeg and "kick" or "punch", tp, 1)
										end)
										break
									end
								end
							end
						end
					end
				end
			end
		end
	end)
end

------------------------------------------------------------------------
-- using it
------------------------------------------------------------------------

local function flash(p: Player, intensity: number, color: string)
	Remote:FireClient(p, "flash", intensity, color)
end

local function stopActive(p: Player)
	local st = implants[p]
	local char = p.Character
	if char then
		char:SetAttribute("SandevistanOn", nil)
		spineGlow(char, false)
	end
	deps.SuperService.SlowMo(p, false) -- (v2.8.1: only this user's part of it ends)
	if st then
		st.mode = nil
		st.activeUntil = 0
	end
	Remote:FireClient(p, "ended")
end

local function burnOut(p: Player)
	local char, torso = alive(p)
	local st = implants[p]
	if not char or not torso or not st then
		return
	end
	st.down = true
	flash(p, 1, "white")
	pcall(function()
		deps.GoreService.Sound("explosion", torso, 0.6)
		deps.GoreService.Burst(torso.Position, Vector3.new(0, 1, 0), 30, 18)
	end)
	-- 2-3 limbs are burnt out: they are broken (not torn off): one or two limbs are all you have left
	local pool = table.clone(LIMBS)
	for _ = 1, rng:NextInteger(2, 3) do
		local limb = table.remove(pool, rng:NextInteger(1, #pool))
		pcall(function()
			deps.DamageService.ApplyDamage(char, limb, 400, torso.Position, { cause = "Burnt-out circuits", allowSever = false, quiet = true })
		end)
	end
	pcall(function()
		deps.DamageService.ApplyDamage(char, "Torso", 35, torso.Position, { cause = "Burnt-out circuits", allowSever = false, quiet = true })
	end)
	pcall(function()
		deps.DamageService.Sleep(char, 10, nil) -- down for 10 s
	end)
	st.level = math.min(100, st.level + 25)
	task.delay(10, function()
		if implants[p] == st then
			st.down = false
		end
	end)
end

local function activate(p: Player)
	local admin = Items.Has(p, "sandevistan") or (p.Character ~= nil and p.Character:GetAttribute("SandevistanClean") == true) -- (v2.8: COLOSSUS, a gift)
	local st = implants[p]
	if not st and admin then
		st = newState(false) -- (an admin needs no implant)
		implants[p] = st
	end
	local char, torso = alive(p)
	if not st or not char or not torso or (st.down and not admin) or os.clock() < st.activeUntil then
		return
	end
	if char:GetAttribute("Asleep") == true and not admin then
		return
	end
	if deps.SuperService.TimeStopped() then
		return
	end
	if char:GetAttribute("SandevistanOn") then
		return -- (already running)
	end
	if (char:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then return end
	local off = char:GetAttribute("ChipsDisabled")
	if typeof(off) == "number" and off > workspace:GetServerTimeNow() then return end
	local now = os.clock()
	local mode, dur
	local since = 0
	if admin then
		mode, dur = "clean", Config.SandevistanDuration -- (no burnout, no strain, no waiting)
	else
		since = st.firstUse and (now - st.firstUse) or math.huge
		if since >= Config.SandevistanCycle then
			mode, dur = "clean", Config.SandevistanDuration
			st.firstUse = now
			since = 0
		elseif since < Config.SandevistanDuration + Config.SandevistanHot then
			mode, dur = "fry", 1
		else
			mode, dur = "strain", Config.SandevistanDuration
		end
	end
	p:SetAttribute("SandevistanCycleEnd", st.firstUse and (workspace:GetServerTimeNow() + math.max(0, Config.SandevistanCycle - (now - st.firstUse))) or nil)
	st.mode = mode
	st.activeUntil = now + dur
	char:SetAttribute("SandevistanOn", true)
	spineGlow(char, true)
	deps.SuperService.SlowMo(p, true)
	local f = math.clamp((Config.SandevistanCycle - since) / (Config.SandevistanCycle - Config.SandevistanDuration - Config.SandevistanHot), 0, 1)
	Remote:FireClient(p, "active", mode, dur, f, since)
	if not admin then
		st.level = math.min(100, st.level + (mode == "clean" and 8 or 14))
	end
	strikeLoop(p, st)
	task.spawn(function()
		local ticks = math.max(1, math.floor(dur))
		for _ = 1, ticks do
			task.wait(mode == "fry" and dur or 1)
			if implants[p] ~= st or p.Character ~= char or st.activeUntil == 0 then
				return
			end
			if mode == "strain" then
				-- it hurts: more the earlier it is used again (f 1 = right after the hot window, 0 = at the end of the cycle)
				local c, t = alive(p)
				if not c or not t then
					stopActive(p)
					return
				end
				pcall(function()
					deps.DamageService.ApplyDamage(c, "Torso", 3 + 9 * f, t.Position, { cause = "Sandevistan strain", allowSever = false, quiet = true })
				end)
				flash(p, 0.35 + 0.65 * f, "red")
			end
			if mode == "fry" then
				break
			end
		end
		if implants[p] ~= st or p.Character ~= char then
			return
		end
		stopActive(p)
		if mode == "fry" then
			burnOut(p)
		end
	end)
end

------------------------------------------------------------------------
-- psychosis: slowly you start to see things that are not there (Hallucinations, on your own screen only)
------------------------------------------------------------------------

local function psychosisStep(p: Player, st: Implant)
	if workspace:GetAttribute("PsychosisOff") or ((not st.real or Items.IsOwner(p)) and p:GetAttribute("AdminPsychoEnabled") ~= true) then
		return -- (admins are immune; an admin who never got an implant has none to go wrong)
	end
	local char = alive(p)
	if not char then
		return
	end
	st.level = math.min(100, st.level + 0.2)
	p:SetAttribute("SandevistanPsycho", st.level / 100) -- (slowly turning)
	local now = os.clock()
	if now < st.nextEpisode or st.level < 12 or now < st.activeUntil then
		return
	end
	local lvl = st.level / 100
	local dur = 12 + 28 * lvl
	st.nextEpisode = now + dur + rng:NextNumber(0.8, 1.2) * (60 - 40 * lvl) -- from a break of ~60 s down to ~20 s
	Remote:FireClient(p, "psycho", dur, lvl)
end

function SandevistanService.Init(d: any)
	deps = d
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remote = Remotes:FindFirstChild("Sandevistan") :: RemoteEvent
	if not Remote then
		local r = Instance.new("RemoteEvent")
		r.Name = "Sandevistan"
		r.Parent = Remotes
		Remote = r
	end
	Remote.OnServerEvent:Connect(function(p, action)
		if action == "use" then
			activate(p)
		end
	end)

	-- the fitting of a prosthetic (GearService) also fits this
	deps.GearService.OnImplant = onImplant

	-- a new body has no implant
	local function hook(p: Player)
		p.CharacterAdded:Connect(function()
			-- Death cancels the active field, never the cooling cycle.
			local st = implants[p]
			if st then
				deps.SuperService.SlowMo(p, false)
				st.activeUntil, st.mode, st.down = 0, nil, false
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		if implants[p] then
			deps.SuperService.SlowMo(p, false)
		end
		implants[p] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(1)
			for p, st in implants do
				if p.Parent then
					psychosisStep(p, st)
				end
			end
		end
	end)

	-- the admin menu spawns one in front of the admin; it also lies in the construction site now and then (rarely)
	local AdminService = require(script.Parent:WaitForChild("AdminService"))
	AdminService.SpawnSandevistan = function(admin: Player)
		local _, torso = alive(admin)
		if torso then
			deps.PropService.Place("sandevistan", torso.CFrame * CFrame.new(0, 0.5, -4), admin)
		end
	end

	local function spawnInSite()
		local site = workspace:FindFirstChild("ConstructionSite", true)
		local at: Vector3? = nil
		if site and site:IsA("Model") then
			local ok, cf, size = pcall(function()
				return site:GetBoundingBox()
			end)
			if ok and cf then
				for _ = 1, 12 do
					local from = (cf * CFrame.new(rng:NextNumber(-0.4, 0.4) * size.X, size.Y / 2 + 30, rng:NextNumber(-0.4, 0.4) * size.Z)).Position
					local hit = workspace:Raycast(from, Vector3.new(0, -size.Y - 80, 0))
					if hit then
						at = hit.Position + Vector3.new(0, 1.2, 0)
						break
					end
				end
			end
		end
		if at then
			pcall(deps.PropService.Place, "sandevistan", CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), nil)
		end
	end
	local function exists(): boolean
		local folder = workspace:FindFirstChild("SpawnedProps")
		for _, m in (folder and folder:GetChildren() or {}) do
			if m:GetAttribute("Item") == "sandevistan" then
				return true
			end
		end
		return false
	end
	task.spawn(function()
		task.wait(10)
		if rng:NextInteger(1, 100) <= 25 and not exists() then
			spawnInSite() -- (rarely: 1 server in 4 starts with one)
		end
		while true do
			task.wait(900)
			if rng:NextInteger(1, 100) <= 10 and not exists() then
				spawnInSite()
			end
		end
	end)
end

SandevistanService._states=implants
return SandevistanService

end)()
local p=player(10,vec(0,0,0));p.Character=nil
Sandy.Grant(p,true,false);Sandy._states[p].firstUse=123;Sandy._states[p].level=27
Sandy.Grant(p,true,false)
eq(Sandy._states[p].firstUse,123,"respawn preserves cooling cycle");eq(Sandy._states[p].level,27,"respawn preserves stress");eq(Sandy._states[p].activeUntil,0,"grant cancels old field")
local Chip=(function()
--!nonstrict
-- ChipService (v2.9): the cyberdeck. Everything about neck chips (Shared/Chips) - the 4 slots, buying and programming
-- them, the netrunner quickhacks, viruses, the REFLEX BUFFER dodge, the FIREWALL, and the Blackwall.
--   * every player has Config.ChipSlots (4) neck slots and a bag of chips they own. Both are kept in the profile
--     (Persist) so they come back - videos are the exception (they live for the session only).
--   * COMBAT chips work on their own / on a toggle: REFLEX BUFFER (dodges bullets, here), ZOOM and SCANNER (client).
--   * NETRUNNER quickhacks (K, the netrunner interface): aimed at a person. They land only if your tier is higher than
--     the target's FIREWALL tier. A FIREWALL is antivirus too (a virus of its tier or lower bounces off).
--   * a VIRUS is a programmed blank chip (ComputerService). Pushed into somebody (grab + F) it infects them if their
--     firewall is too low. A virus can also be baked into a VIDEO (a trojan): watching it sets the payload off.
--   * the BLACKWALL: an admin lets it loose on a target (a red beam, ash). Anybody else who slots it is burned themselves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Chips = require(Shared:WaitForChild("Chips"))
local Items = require(Shared:WaitForChild("Items"))
local Modules = script.Parent
local Persist = require(Modules:WaitForChild("Persist"))

local ChipService = {}

local deps: any = {}
local Remote: RemoteEvent
local rng = Random.new()

-- a chip, in a slot or in the bag or on a held item
export type Chip = {
	uid: number,
	id: string, -- a catalog id, or "virus", or "video"
	kind: string, -- from the catalog, or "virus" / "video"
	tier: number,
	name: string?,
	payload: string?, -- virus / trojan: "explode" | "hallucinate" | "rampage" | "killtarget"
	target: number?, -- killtarget: the userId to go after
	clip: string?, -- video: the clip code (CameraService)
	trojan: boolean?, -- a video that carries a payload
}

type St = {
	slots: { [number]: Chip }, -- 1..Config.ChipSlots
	bag: { Chip },
	dodgeLeft: number,
	dodgeRefill: number,
}
local states: { [Player]: St } = {}
local uidCounter = 0

-- set by ComputerService: is this player standing at a computer right now?
ChipService.NearComputer = nil :: ((Player) -> boolean)?
-- set by CameraService
ChipService.Camera = nil :: any

------------------------------------------------------------------------
-- state
------------------------------------------------------------------------

local function stOf(p: Player): St
	local st = states[p]
	if not st then
		st = { slots = {}, bag = {}, dodgeLeft = 0, dodgeRefill = 0 }
		states[p] = st
	end
	return st
end

local function nextUid(): number
	uidCounter += 1
	return uidCounter
end

local function alive(p: Player): (Model?, BasePart?)
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	if c and t and t:IsA("BasePart") and c:GetAttribute("Dead") ~= true and c.Parent then
		return c, t
	end
	return nil, nil
end

-- the best FIREWALL tier a body has right now (0 = none). EMP'd chips count as 0.
local function firewallOf(p: Player): number
	local st = states[p]
	if not st then
		return 0
	end
	local c = p.Character
	if c and typeof(c:GetAttribute("ChipsDisabled")) == "number" and workspace:GetServerTimeNow() < c:GetAttribute("ChipsDisabled") then
		return 0
	end
	local best = 0
	for _, chip in st.slots do
		if chip.id == "firewall" and chip.tier > best then
			best = chip.tier
		end
	end
	return best
end
ChipService.Firewall = firewallOf

-- the tiers of things the client / others need: firewall, the dodge charges, how much capacity we add
local function publicAttrs(p: Player)
	local st = stOf(p)
	p:SetAttribute("ChipFirewall", firewallOf(p) > 0 and firewallOf(p) or nil)
	-- capacity: +tolerance for the cyberware (CyberService reads CyTolBonus)
	local bonus = 0
	for _, chip in st.slots do
		if chip.id == "capacity" then
			bonus += ({ 1, 2, 3 })[math.clamp(chip.tier, 1, 3)]
		end
	end
	p:SetAttribute("CyTolBonus", bonus > 0 and bonus or nil)
	p:SetAttribute("CyTol", Config.CyberTolerance + bonus) -- (the ripperdoc / cyber page shows this)
	p:SetAttribute("ChipDodge", st.dodgeLeft > 0 and st.dodgeLeft or nil)
end

-- a sanitised copy of a chip for the client (the owner sees everything)
local function wire(chip: Chip): any
	return {
		uid = chip.uid, id = chip.id, kind = chip.kind, tier = chip.tier, name = chip.name,
		payload = chip.payload, target = chip.target, trojan = chip.trojan, video = chip.clip ~= nil,
	}
end

local function sendDeck(p: Player)
	local st = stOf(p)
	local slots = {}
	for i = 1, Config.ChipSlots do
		slots[i] = st.slots[i] and wire(st.slots[i]) or false
	end
	local bag = {}
	for _, chip in st.bag do
		table.insert(bag, wire(chip))
	end
	Remote:FireClient(p, "deck", { slots = slots, bag = bag, dodge = st.dodgeLeft })
end
ChipService.SendDeck = sendDeck

local function changed(p: Player)
	publicAttrs(p)
	sendDeck(p)
	-- (persist)
	local prof = Persist.Get(p)
	if prof then
		local out = {}
		local function pack(chip: Chip, slot: number)
			if chip.clip then
				return -- (videos are not saved)
			end
			table.insert(out, { id = chip.id, tier = chip.tier, slot = slot, payload = chip.payload, target = chip.target })
		end
		local st = stOf(p)
		for i, chip in st.slots do
			pack(chip, i)
		end
		for _, chip in st.bag do
			pack(chip, 0)
		end
		prof.chips = out
		Persist.Dirty(p)
	end
end

------------------------------------------------------------------------
-- making / giving chips
------------------------------------------------------------------------

local function newChip(id: string, tier: number, extra: any?): Chip
	local def = Chips.ById[id]
	local chip: Chip = {
		uid = nextUid(), id = id, kind = (def and def.kind) or (id == "virus" and "virus") or (id == "video" and "video") or "blank",
		tier = tier, name = def and def.name or (id == "virus" and "VIRUS" or "VIDEO"),
	}
	if extra then
		for k, v in extra do
			(chip :: any)[k] = v
		end
	end
	return chip
end

-- give a chip to a player's bag
function ChipService.Give(p: Player, id: string, tier: number, extra: any?): Chip
	local st = stOf(p)
	local chip = newChip(id, tier, extra)
	table.insert(st.bag, chip)
	changed(p)
	return chip
end

-- give a video chip (CameraService): a session-only chip that holds a clip
function ChipService.GiveVideo(p: Player, clipCode: string, label: string?): Chip
	return ChipService.Give(p, "video", 1, { clip = clipCode, name = label or "VIDEO", kind = "video" })
end

local function findBag(st: St, uid: number): (number?, Chip?)
	for i, chip in st.bag do
		if chip.uid == uid then
			return i, chip
		end
	end
	return nil, nil
end

------------------------------------------------------------------------
-- slots
------------------------------------------------------------------------

local SLOTTABLE = { combat = true, net = true, firewall = true, capacity = true, blank = true, blackwall = true, virus = true }

local function smite(p: Player)
	-- a non-admin slotted the Blackwall: the beam comes for them
	local char, torso = alive(p)
	if not char or not torso then
		return
	end
	ChipService.BlackwallBeam(torso.Position)
	task.delay(0.8, function()
		local c = p.Character
		local t = c and c:FindFirstChild("Torso")
		if c and t and not c:GetAttribute("Dead") then
			ChipService.Ash(c)
			c:SetAttribute("ForceKill", true)
			c:SetAttribute("NoRegrowth", true)
			c:SetAttribute("SpawnProtect", nil)
			deps.DamageService.Kill(c, "Burned by the Blackwall")
		end
	end)
end

function ChipService.Install(p: Player, uid: number, slot: number): string?
	if typeof(slot) ~= "number" or slot < 1 or slot > Config.ChipSlots then
		return "bad slot"
	end
	local st = stOf(p)
	if st.slots[slot] then
		return "that slot is full"
	end
	local i, chip = findBag(st, uid)
	if not chip then
		return "no such chip"
	end
	if not SLOTTABLE[chip.kind] then
		return "that chip does not go in a slot"
	end
	local def = Chips.ById[chip.id]
	if def and def.admin and not Items.IsOwner(p) and chip.id ~= "blackwall" then
		return "admins only"
	end
	table.remove(st.bag, i :: number)
	st.slots[slot] = chip
	if chip.id == "dodge" then
		st.dodgeLeft = chip.tier
	end
	changed(p)
	Remote:FireClient(p, "msg", (chip.name or "CHIP") .. " SLOTTED.")
	-- the Blackwall: an admin keeps it (the interface); anybody else is smitten
	if chip.id == "blackwall" and not Items.IsOwner(p) then
		Remote:FireClient(p, "msg", "THE BLACKWALL DOES NOT ANSWER TO YOU.")
		task.delay(0.4, smite, p)
	end
	return nil
end

function ChipService.Eject(p: Player, slot: number)
	local st = stOf(p)
	local chip = st.slots[slot]
	if not chip then
		return
	end
	st.slots[slot] = nil
	table.insert(st.bag, chip)
	if chip.id == "dodge" then
		st.dodgeLeft = 0
	end
	changed(p)
end

-- spawn a bag chip as a held item (and take it out of the bag)
function ChipService.Take(p: Player, uid: number)
	local st = stOf(p)
	local i, chip = findBag(st, uid)
	if not chip then
		return
	end
	local char, torso = alive(p)
	if not torso then
		return
	end
	local item = deps.PropService.Place("chip", torso.CFrame * CFrame.new(0, 0.5, -2), p)
	if not item or not item:IsA("Model") then
		return
	end
	ChipService.Dress(item, chip)
	item:SetAttribute("BoundTo", p.UserId) -- (yours: nobody else handles it)
	table.remove(st.bag, i :: number)
	changed(p)
	-- put it in the hand
	if item.PrimaryPart then
		pcall(deps.OwnershipService.Grab, p, item.PrimaryPart, "Right")
	end
end

-- write a chip onto a held item (attributes + colour)
function ChipService.Dress(item: Model, chip: Chip)
	item:SetAttribute("ChipUid", chip.uid)
	item:SetAttribute("ChipId", chip.id)
	item:SetAttribute("ChipKind", chip.kind)
	item:SetAttribute("ChipTier", chip.tier)
	item:SetAttribute("ChipName", chip.name)
	item:SetAttribute("ChipPayload", chip.payload)
	item:SetAttribute("ChipTarget", chip.target)
	item:SetAttribute("ChipClip", chip.clip)
	item:SetAttribute("ChipTrojan", chip.trojan == true or nil)
	item.Name = chip.name or "Chip"
	local core = item:FindFirstChild("Core")
	if core and core:IsA("BasePart") then
		local def = Chips.ById[chip.id]
		if chip.clip then
			core.Color = chip.trojan and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(120, 200, 255)
		elseif chip.id == "virus" then
			core.Color = Color3.fromRGB(120, 255, 120)
		elseif def then
			core.Color = Chips.Color(def)
		end
	end
end

-- read a chip back off a held item
local function chipOfItem(item: Model): Chip?
	local id = item:GetAttribute("ChipId")
	if typeof(id) ~= "string" then
		return nil
	end
	return {
		uid = typeof(item:GetAttribute("ChipUid")) == "number" and item:GetAttribute("ChipUid") or nextUid(),
		id = id, kind = typeof(item:GetAttribute("ChipKind")) == "string" and item:GetAttribute("ChipKind") or "blank",
		tier = typeof(item:GetAttribute("ChipTier")) == "number" and item:GetAttribute("ChipTier") or 1,
		name = item:GetAttribute("ChipName"), payload = item:GetAttribute("ChipPayload"),
		target = item:GetAttribute("ChipTarget"), clip = item:GetAttribute("ChipClip"), trojan = item:GetAttribute("ChipTrojan") == true,
	}
end

------------------------------------------------------------------------
-- buying / programming (ComputerService calls these; the player must be at a computer)
------------------------------------------------------------------------

local function atComputer(p: Player): boolean
	if Items.IsOwner(p) then
		return true
	end
	return ChipService.NearComputer ~= nil and ChipService.NearComputer(p) == true
end

local function cashOf(p: Player): number
	local c = p:GetAttribute("Cash")
	return typeof(c) == "number" and c or 0
end

local function pay(p: Player, n: number, why: string): boolean
	if n <= 0 or Items.IsOwner(p) then
		return true
	end
	if cashOf(p) < n then
		return false
	end
	if deps.SkinService and deps.SkinService.AddCash then
		deps.SkinService.AddCash(p, -n, why)
	end
	return true
end

local function say(p: Player, text: string)
	Remote:FireClient(p, "msg", text)
end

function ChipService.Buy(p: Player, id: any, tier: any)
	if not atComputer(p) then
		say(p, "GET TO A COMPUTER FIRST.")
		return
	end
	local def = typeof(id) == "string" and Chips.ById[id] or nil
	if not def or typeof(tier) ~= "number" then
		return
	end
	tier = math.clamp(math.floor(tier), 1, def.tiers)
	if def.admin and not Items.IsOwner(p) then
		say(p, "ADMINS ONLY.")
		return
	end
	local price = Chips.Price(id, tier)
	if not pay(p, price, "chip") then
		say(p, string.format("THAT IS $%d. YOU HAVE $%d.", price, cashOf(p)))
		return
	end
	ChipService.Give(p, id, tier)
	Remote:FireClient(p, "sound", "cashDing")
	say(p, (def.name .. " T" .. tier) .. " BOUGHT. IT IS IN YOUR CHIPS (K).")
end

function ChipService.Sell(p: Player, uid: any)
	if not atComputer(p) or typeof(uid) ~= "number" then return end
	local st = stOf(p)
	local i, chip = findBag(st, uid)
	if not chip or not i then return end
	local def = Chips.ById[chip.id]
	if not def or def.admin or chip.clip then say(p, "THIS CHIP CANNOT BE SOLD.") return end
	if Items.IsOwner(p) then say(p, "ADMIN CHIPS ARE FREE AND CANNOT BE SOLD.") return end
	local amount = math.floor(Chips.Price(chip.id, chip.tier) * 0.4)
	table.remove(st.bag, i)
	deps.SkinService.AddCash(p, amount, "chip sale")
	changed(p)
	Remote:FireClient(p, "sound", "cashDing")
	say(p, "SOLD " .. def.name .. " FOR $" .. amount)
end

-- program a blank chip (in the bag) into a virus
function ChipService.Program(p: Player, uid: any, payload: any, tier: any, target: any)
	if not atComputer(p) then
		say(p, "GET TO A COMPUTER FIRST.")
		return
	end
	local st = stOf(p)
	local i, chip = findBag(st, uid)
	if not chip or chip.kind ~= "blank" then
		say(p, "PICK A BLANK CHIP TO PROGRAM.")
		return
	end
	if not Chips.PayloadById[payload] then
		return
	end
	tier = math.clamp(typeof(tier) == "number" and math.floor(tier) or 1, 1, 3)
	if not pay(p, Config.VirusPrice, "virus") then
		say(p, string.format("A VIRUS IS $%d.", Config.VirusPrice))
		return
	end
	chip.id = "virus"
	chip.kind = "virus"
	chip.name = "VIRUS: " .. Chips.PayloadById[payload].name
	chip.tier = tier
	chip.payload = payload
	chip.target = (payload == "killtarget" and typeof(target) == "number") and target or nil
	changed(p)
	say(p, chip.name .. " (T" .. tier .. ") WRITTEN. INSERT IT INTO SOMEBODY, OR BAKE IT INTO A VIDEO.")
end

-- bake a virus chip into a video chip (a trojan): the video now carries the payload
function ChipService.MakeTrojan(p: Player, videoUid: any, virusUid: any)
	if not atComputer(p) then
		say(p, "GET TO A COMPUTER FIRST.")
		return
	end
	local st = stOf(p)
	local _, video = findBag(st, videoUid)
	local vi, virus = findBag(st, virusUid)
	if not video or not video.clip then
		say(p, "PICK A VIDEO.")
		return
	end
	if not virus or virus.kind ~= "virus" then
		say(p, "PICK A VIRUS CHIP.")
		return
	end
	video.payload = virus.payload
	video.target = virus.target
	video.tier = virus.tier
	video.trojan = true
	video.name = (video.name or "VIDEO") .. " [TROJAN]"
	table.remove(st.bag, vi :: number) -- (the virus chip is used up)
	changed(p)
	say(p, "THE VIDEO IS A TROJAN NOW. WHOEVER WATCHES IT GETS THE PAYLOAD.")
end

------------------------------------------------------------------------
-- the effects (quickhacks + virus payloads share this)
------------------------------------------------------------------------

local function fxTo(p: Player?, action: string, ...)
	if p then
		Remote:FireClient(p, action, ...)
	end
end

-- apply one effect to a body. `gate` = check the firewall; returns true if it landed.
function ChipService.Hit(victim: Model, effect: string, tier: number, attacker: Player?, gate: boolean): boolean
	if not victim or not victim.Parent or victim:GetAttribute("Dead") then
		return false
	end
	local vp = Players:GetPlayerFromCharacter(victim)
	-- Admin rank is not a firewall. Keep the game's spawn/team rules.
	if deps.DamageService.Protected(victim, attacker) then return false end
	if gate and vp then
		local fw = firewallOf(vp)
		if fw >= tier then
			if attacker then
				say(attacker, "BLOCKED - THEIR FIREWALL (T" .. fw .. ") HELD.")
			end
			fxTo(vp, "blocked")
			return false
		end
	end
	local torso = victim:FindFirstChild("Torso")
	local tpos = (torso and torso:IsA("BasePart")) and torso.Position or victim:GetPivot().Position
	local atkName = attacker and attacker.DisplayName or "a netrunner"

	if effect == "burnout" then
		deps.DamageService.ApplyDamage(victim, "Torso", 25 + 20 * tier, tpos, { cause = "Burned out by " .. atkName, allowSever = false, cyberAttack = true, attacker = attacker })
		deps.GoreService.FX({ t = "burst", p = tpos, d = Vector3.yAxis, n = 8, s = 14 })
		deps.GoreService.Sound("taser", torso or tpos, 1)
		if tier >= 2 then
			deps.DamageService.Knock(victim, "Torso", nil, tier >= 3 and 2.2 or 1.1)
		end
		if tier >= 3 and vp then
			vp.Character:SetAttribute("ChipsDisabled", workspace:GetServerTimeNow() + 5)
		end
	elseif effect == "overheat" then
		deps.FireService.SetOnFire(victim, 3 + 3 * tier, attacker)
		-- Cybernetic heat also affects admin invulnerability; physical fire retains its own rules.
		if victim:GetAttribute("God") then
			task.spawn(function()
				for _ = 1, 3 + 3 * tier do
					task.wait(1)
					if not victim.Parent or victim:GetAttribute("Dead") then break end
					deps.DamageService.ApplyDamage(victim, "Torso", 5 + tier * 2, nil, { cause = "Neural overheat", cyberAttack = true, allowSever = false, attacker = attacker })
				end
			end)
		end
		deps.GoreService.Sound("ignite", torso or tpos, 1)
	elseif effect == "emp" then
		local dur = 4 * tier
		if vp and vp.Character then
			vp.Character:SetAttribute("ChipsDisabled", workspace:GetServerTimeNow() + dur)
		end
		deps.GoreService.FX({ t = "shock", p = tpos, r = 5 })
		deps.GoreService.Sound("taser", torso or tpos, 1)
		deps.DamageService.ApplyDamage(victim, "Torso", 6 * tier, tpos, { cause = "EMP by " .. atkName, allowSever = false, cyberAttack = true, attacker = attacker })
		if tier >= 3 then
			deps.DamageService.Knock(victim, "Torso", nil, 1.6)
		end
		fxTo(vp, "emp", dur)
	elseif effect == "blind" then
		fxTo(vp, "blind", ({ 3, 5, 8 })[math.clamp(tier, 1, 3)])
	elseif effect == "contagion" then
		if deps.VirusService then
			deps.VirusService.Infect(victim, attacker, true)
			deps.DamageService.ApplyDamage(victim, "Torso", 4 * tier, tpos, { cause = "Contagion", allowSever = false, quiet = true, cyberAttack = true, attacker = attacker })
		end
	elseif effect == "psycho" or effect == "rampage" or effect == "killtarget" then
		local dur = ({ 6, 9, 13 })[math.clamp(tier, 1, 3)]
		local targetUserId = nil
		if effect == "killtarget" then
			targetUserId = attacker and attacker.UserId or nil -- (set by the caller via opts normally)
		end
		fxTo(vp, "rampage", dur, targetUserId)
		if not vp then
			-- an NPC / bot: turn it hostile where it stands (best-effort)
			victim:SetAttribute("Rampage", workspace:GetServerTimeNow() + dur)
		end
	elseif effect == "reset" then
		local dur = ({ 6, 9, 13 })[math.clamp(tier, 1, 3)]
		deps.DamageService.Sleep(victim, dur, attacker, true)
		deps.GoreService.Sound("ringing", torso or tpos, 1)
	elseif effect == "glitch" then
		if vp then
			for _, it in deps.OwnershipService.HeldItems(vp) do
				pcall(deps.OwnershipService.DropItem, it)
			end
			if vp.Character then
				vp.Character:SetAttribute("ChipGrabLock", workspace:GetServerTimeNow() + ({ 0, 3, 6 })[math.clamp(tier, 1, 3)])
			end
			fxTo(vp, "glitch")
		end
	elseif effect == "cripple" then
		if vp and vp.Character then
			vp.Character:SetAttribute("ChipCrawl", ({ 0.4, 0.28, 0.18 })[math.clamp(tier, 1, 3)])
			vp.Character:SetAttribute("ChipCrawlUntil", workspace:GetServerTimeNow() + ({ 4, 6, 8 })[math.clamp(tier, 1, 3)])
		end
		deps.GoreService.FX({ t = "shock", p = tpos, r = 3 })
	elseif effect == "explode" then
		deps.ExplosionService.Explode(tpos, { radius = 14 + 4 * tier, damage = 80 + 30 * tier, power = 60, attacker = attacker, cause = "A planted virus", kind = "grenade" })
	elseif effect == "hallucinate" then
		fxTo(vp, "hallucinate", 10 + 10 * tier)
	end
	return true
end

------------------------------------------------------------------------
-- running a quickhack (the netrunner interface)
------------------------------------------------------------------------

local cd: { [Player]: { [number]: number } } = {}

local EFFECT = {
	burnout = "burnout", overheat = "overheat", shortcircuit = "emp", reboot = "blind", contagion = "contagion",
	cyberpsycho = "psycho", sysreset = "reset", weaponglitch = "glitch", cripple = "cripple",
}

local function linked(p: Player, victim: Model): boolean
	local char, root = alive(p)
	if char and (char:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then return false end
	local target = victim:FindFirstChild("Head") or victim:FindFirstChild("Torso")
	if not root or not target or not target:IsA("BasePart") or victim == char or victim:GetAttribute("Dead") then return false end
	if (target.Position - root.Position).Magnitude > Config.NetRange then return false end
	local head = char:FindFirstChild("Head") or root
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char, workspace:FindFirstChild("FX") or char }
	local hit = workspace:Raycast(head.Position, target.Position - head.Position, rp)
	return not hit or hit.Instance:IsDescendantOf(victim)
end

local function victimOf(userId: any): Model?
	local p = typeof(userId) == "number" and Players:GetPlayerByUserId(userId) or nil
	return p and p.Character or nil
end

function ChipService.Quickhack(p: Player, slot: any, targetUserId: any)
	local st = stOf(p)
	local chip = typeof(slot) == "number" and st.slots[slot] or nil
	if not chip or chip.kind ~= "net" then
		return
	end
	local c = p.Character
	if c and typeof(c:GetAttribute("ChipsDisabled")) == "number" and workspace:GetServerTimeNow() < c:GetAttribute("ChipsDisabled") then
		say(p, "YOUR CHIPS ARE FRIED - WAIT.")
		return
	end
	local def = Chips.ById[chip.id]
	local now = os.clock()
	cd[p] = cd[p] or {}
	if now < (cd[p][slot] or 0) then
		return
	end
	local victim = victimOf(targetUserId)
	local vp = typeof(targetUserId) == "number" and Players:GetPlayerByUserId(targetUserId) or nil
	local _, mytorso = alive(p)
	local vt = victim and victim:FindFirstChild("Torso")
	if not victim or not vt or not vt:IsA("BasePart") or not mytorso or vp == p then
		say(p, "NO TARGET.")
		return
	end
	if (vt.Position - mytorso.Position).Magnitude > Config.NetRange then
		say(p, "TARGET OUT OF RANGE.")
		return
	end
	if not linked(p, victim) then say(p, "LINK LOST — TARGET OCCLUDED.") return end
	local effect = EFFECT[chip.id]
	if not effect then
		return
	end
	cd[p][slot] = now + (def.cooldown and def.cooldown[chip.tier] or 12)
	p:SetAttribute("ChipCD_" .. slot, workspace:GetServerTimeNow() + (def.cooldown and def.cooldown[chip.tier] or 12))
	-- the uplink line shown to everybody
	Remote:FireAllClients("uplink", p.UserId, targetUserId, Chips.Color(def))
	local landed = ChipService.Hit(victim, effect, chip.tier, p, true)
	if landed then
		say(p, def.ability .. " ON " .. string.upper(vp and vp.DisplayName or "TARGET"))
	end
end

------------------------------------------------------------------------
-- the Blackwall
------------------------------------------------------------------------

function ChipService.BlackwallBeam(pos: Vector3)
	Remote:FireAllClients("blackwall", pos)
end

-- turn a body to ash (FX; the kill is done by the caller)
function ChipService.Ash(victim: Model)
	local torso = victim:FindFirstChild("Torso")
	local p = (torso and torso:IsA("BasePart")) and torso.Position or victim:GetPivot().Position
	Remote:FireAllClients("ash", victim, p)
end

function ChipService.Unleash(p: Player, slot: any, targetUserId: any)
	local st = stOf(p)
	local chip = typeof(slot) == "number" and st.slots[slot] or nil
	if not chip or chip.id ~= "blackwall" or not Items.IsOwner(p) then
		return
	end
	local now = os.clock()
	cd[p] = cd[p] or {}
	if now < (cd[p]["bw"] or 0) then
		return
	end
	local victim = victimOf(targetUserId)
	local vt = victim and victim:FindFirstChild("Torso")
	if not victim or not vt or not vt:IsA("BasePart") then
		return
	end
	if not linked(p, victim) then say(p, "NO CLEAR LINK TO TARGET.") return end
	local char = p.Character
	local off = char and char:GetAttribute("ChipsDisabled")
	if typeof(off) == "number" and off > workspace:GetServerTimeNow() then return end
	cd[p]["bw"] = now + 20
	p:SetAttribute("ChipCD_" .. slot, workspace:GetServerTimeNow() + 20)
	ChipService.BlackwallBeam(vt.Position)
	Remote:FireClient(p, "msg", "BLACKWALL RELEASED.")
	task.delay(0.8, function()
		if victim.Parent and not victim:GetAttribute("Dead") then
			ChipService.Ash(victim)
			victim:SetAttribute("ForceKill", true)
			victim:SetAttribute("NoRegrowth", true)
			deps.DamageService.MarkAttacker(victim, p)
			deps.DamageService.Kill(victim, "Erased by the Blackwall")
		end
	end)
end

------------------------------------------------------------------------
-- held chips: play a video / push a chip into somebody
------------------------------------------------------------------------

local function returnChipToBag(p: Player, item: Model, chip: Chip)
	-- the chip goes back into the bag (not consumed)
	if item.Parent then
		pcall(deps.OwnershipService.DropItem, item)
		item:Destroy()
	end
	local st = stOf(p)
	table.insert(st.bag, chip)
	changed(p)
end

-- F with a chip in hand, nobody grabbed: play its video for yourself
function ChipService.PlayHeld(p: Player, item: Model)
	if deps.OwnershipService.ItemHolder(item) ~= p then
		return
	end
	local chip = chipOfItem(item)
	if not chip then
		return
	end
	if not chip.clip then
		say(p, "THIS CHIP HAS NO VIDEO.")
		return
	end
	if ChipService.Camera then
		ChipService.Camera.Play(p, chip.clip, chip.trojan and chip or nil, p)
	end
end

-- grab somebody + F with a chip in the other hand: push it into them
function ChipService.InsertHeld(p: Player, item: Model)
	if deps.OwnershipService.ItemHolder(item) ~= p then
		return
	end
	local chip = chipOfItem(item)
	if not chip then
		return
	end
	local victim = deps.OwnershipService.HeldBody(p)
	local vp = victim and Players:GetPlayerFromCharacter(victim)
	if not victim or not vp then
		say(p, "GRAB SOMEBODY FIRST (Q / E).")
		return
	end
	-- the chip is used up going in
	if item.Parent then
		pcall(deps.OwnershipService.DropItem, item)
		item:Destroy()
	end
	deps.GoreService.Sound("ratchet", victim:FindFirstChild("Torso"), 1)
	say(p, "CHIP PUSHED INTO " .. string.upper(vp.DisplayName) .. ".")
	if chip.clip then
		-- a video: they watch it; a trojan sets its payload off at the end (if their firewall is too low)
		if ChipService.Camera then
			ChipService.Camera.Play(vp, chip.clip, chip.trojan and chip or nil, p)
		end
	elseif chip.kind == "virus" and chip.payload then
		ChipService.FirePayload(victim, chip, p)
	end
end

-- a virus payload fires on a victim (from a direct insert, or a trojan video ending)
function ChipService.FirePayload(victim: Model, chip: Chip, attacker: Player?)
	local payload = chip.payload
	if not payload then
		return
	end
	local effect = payload
	if payload == "rampage" then
		effect = "psycho"
	end
	local landed
	if payload == "killtarget" then
		-- they go after the attacker (or the stored target)
		local vp = Players:GetPlayerFromCharacter(victim)
		local target = chip.target or (attacker and attacker.UserId) or nil
		if vp and firewallOf(vp) < chip.tier then
			Remote:FireClient(vp, "rampage", 14, target)
			landed = true
		end
	else
		landed = ChipService.Hit(victim, effect, chip.tier, attacker, true)
	end
	if landed and attacker then
		say(attacker, "PAYLOAD DELIVERED.")
	end
end

------------------------------------------------------------------------
-- REFLEX BUFFER: the bullet dodge (chained onto DamageService.ShieldBullet)
------------------------------------------------------------------------

local function dodgeTier(p: Player): number
	local st = states[p]
	if not st then
		return 0
	end
	local c = p.Character
	if c and typeof(c:GetAttribute("ChipsDisabled")) == "number" and workspace:GetServerTimeNow() < c:GetAttribute("ChipsDisabled") then
		return 0
	end
	for _, chip in st.slots do
		if chip.id == "dodge" then
			return chip.tier
		end
	end
	return 0
end

local function tryDodge(model: Model, point: Vector3, dir: Vector3): boolean
	local p = Players:GetPlayerFromCharacter(model)
	if not p then
		return false
	end
	local st = states[p]
	local t = dodgeTier(p)
	if not st or t <= 0 or st.dodgeLeft <= 0 then
		return false
	end
	st.dodgeLeft -= 1
	if st.dodgeLeft <= 0 then
		st.dodgeRefill = os.clock() + 20
	end
	p:SetAttribute("ChipDodge", st.dodgeLeft > 0 and st.dodgeLeft or nil)
	Remote:FireClient(p, "dodge")
	-- tier 3 also nudges the body aside
	if t >= 3 then
		local torso = model:FindFirstChild("Torso")
		if torso and torso:IsA("BasePart") then
			local side = dir:Cross(Vector3.yAxis)
			if side.Magnitude > 0.1 then
				side = side.Unit * (rng:NextNumber() < 0.5 and 1 or -1)
				pcall(function()
					torso:ApplyImpulse(side * 22 * torso.AssemblyMass)
				end)
			end
		end
	end
	local _ = point
	return true
end

------------------------------------------------------------------------

function ChipService.Init(d: any)
	deps = d
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	Remote = Remotes:FindFirstChild("Chip") :: RemoteEvent
	if not Remote then
		local r = Instance.new("RemoteEvent")
		r.Name = "Chip"
		r.Parent = Remotes
		Remote = r
	end
	ChipService.Remote = Remote

	-- the dodge sits in front of whatever else shields a bullet
	local prevBullet = deps.DamageService.ShieldBullet
	deps.DamageService.ShieldBullet = function(model, region, point, dir, shooter, kind)
		if tryDodge(model, point, dir) then
			return true
		end
		return prevBullet ~= nil and prevBullet(model, region, point, dir, shooter, kind) or false
	end

	local requests = {}
	Remote.OnServerEvent:Connect(function(p, action, a, b, c, dd)
		if typeof(action) ~= "string" then return end
		local t = os.clock()
		local r = requests[p]
		if not r or t - r.t > 1 then r = { t = t, n = 0 }; requests[p] = r end
		r.n += 1
		if r.n > 16 then return end
		for _, v in { a, b, c, dd } do
			if typeof(v) == "number" and (v ~= v or math.abs(v) == math.huge) then return end
		end
		if action == "deck" then
			sendDeck(p)
		elseif action == "install" then
			local why = ChipService.Install(p, a, b)
			if why then
				say(p, string.upper(why))
			end
		elseif action == "eject" then
			ChipService.Eject(p, a)
		elseif action == "take" then
			ChipService.Take(p, a)
		elseif action == "hack" then
			ChipService.Quickhack(p, a, b)
		elseif action == "blackwall" then
			ChipService.Unleash(p, a, b)
		elseif action == "play" then
			if typeof(a) == "Instance" and a:IsA("Model") then
				ChipService.PlayHeld(p, a)
			end
		elseif action == "insert" then
			if typeof(a) == "Instance" and a:IsA("Model") then
				ChipService.InsertHeld(p, a)
			end
		elseif action == "buy" then
			ChipService.Buy(p, a, b)
		elseif action == "sell" then
			ChipService.Sell(p, a)
		elseif action == "program" then
			ChipService.Program(p, a, b, c, dd)
		elseif action == "trojan" then
			ChipService.MakeTrojan(p, a, b)
		end
	end)

	-- the profile: chips come back
	local prevLoaded = Persist.OnLoaded
	Persist.OnLoaded = function(p, prof)
		if prevLoaded then
			prevLoaded(p, prof)
		end
		local st = stOf(p)
		if typeof(prof.chips) == "table" then
			for _, rec in prof.chips do
				if typeof(rec) == "table" and typeof(rec.id) == "string" and (Chips.ById[rec.id] or rec.id == "virus") then
					local chip = newChip(rec.id, typeof(rec.tier) == "number" and rec.tier or 1, { payload = rec.payload, target = rec.target })
					local slot = typeof(rec.slot) == "number" and rec.slot or 0
					if slot >= 1 and slot <= Config.ChipSlots and not st.slots[slot] and SLOTTABLE[chip.kind] then
						st.slots[slot] = chip
						if chip.id == "dodge" then
							st.dodgeLeft = chip.tier
						end
					else
						table.insert(st.bag, chip)
					end
				end
			end
		end
		publicAttrs(p)
		sendDeck(p)
	end

	Players.PlayerAdded:Connect(function(p)
		stOf(p)
	end)
	for _, p in Players:GetPlayers() do
		stOf(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
		cd[p] = nil
	end)

	-- refill dodge charges, grab-lock expiry
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = os.clock()
			for p, st in states do
				if not p.Parent then
					continue
				end
				local t = dodgeTier(p)
				if t > 0 and st.dodgeLeft <= 0 and now >= st.dodgeRefill then
					st.dodgeLeft = t
					p:SetAttribute("ChipDodge", t)
				end
			end
		end
	end)
end

-- (v2.9) wipe one player's chips (the admin "WIPE ALL PROGRESS")
function ChipService.Reset(p: Player)
	states[p] = { slots = {}, bag = {}, dodgeLeft = 0, dodgeRefill = 0 }
	p:SetAttribute("ChipFirewall", nil)
	p:SetAttribute("CyTolBonus", nil)
	p:SetAttribute("ChipDodge", nil)
	local prof = Persist.Get(p)
	if prof then
		prof.chips = {}
		Persist.Dirty(p)
	end
	publicAttrs(p)
	sendDeck(p)
end

ChipService._states=states
ChipService._public=publicAttrs
ChipService._setup=function(d,r) deps=d;Remote=r end
return ChipService

end)()
local attacker=player(20,vec(0,0,0),false);local admin=player(21,vec(2,0,0),true);Players.list={attacker,admin}
local dealt,sleepForce=0,false
local remote={FireClient=function() end,FireAllClients=function() end}
local damage={Protected=function() return false end,ApplyDamage=function(_,_,amount,_,opts) dealt+=amount;check(opts.cyberAttack==true,"hack bypass flag") end,Knock=function() end,Sleep=function(_,_,_,force) sleepForce=force end}
Chip._setup({DamageService=damage,GoreService={FX=function() end,Sound=function() end}},remote)
check(Chip.Hit(admin.Character,"burnout",1,attacker,true),"admin receives hack");eq(dealt,45,"admin takes damage")
check(Chip.Hit(admin.Character,"reset",1,attacker,true),"admin sleep accepted");eq(sleepForce,true,"sleep bypasses God")
Chip._states[admin]={slots={[1]={id="firewall",tier=2}},bag={},dodgeLeft=0,dodgeRefill=0}
check(not Chip.Hit(admin.Character,"burnout",2,attacker,true),"admin firewall works")
Chip._states[attacker]={slots={[1]={id="capacity",tier=3},[2]={id="capacity",tier=1}},bag={},dodgeLeft=0,dodgeRefill=0}
Chip._public(attacker);eq(attacker:GetAttribute("CyTolBonus"),4,"capacity is 3 + 1");eq(attacker:GetAttribute("CyTol"),24,"capacity display matches bonus")
print("PASS: "..total.." gameplay regression assertions")

modules.children.SaveGate={CanSave=function() return true end}
modules.children.ProgressEpoch={Key=function(id) return "p_"..id end}
local previousService=game.GetService
game.GetService=function(self,name) if name=="RunService" then return {IsStudio=function() return false end} end return previousService(self,name) end
local Persist=(function()
--!nonstrict
-- Persist (v2.1): what a player keeps between sessions besides RewardService's titles - dollars, owned / equipped weapon skins,
-- the Black Ledger quest (kills are per life, but the apples fed and the permanent unlock are saved).
-- DataStore Config.ProfileStoreV2, key "p_<userId>". Without Studio API access everything still works for the session.

local Players = game:GetService("Players")
local SaveGate = require(script.Parent:WaitForChild("SaveGate"))
local ProgressEpoch = require(script.Parent:WaitForChild("ProgressEpoch"))
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Persist = {}

export type Profile = {
	jobsCompleted: number,
	cash: number,
	owned: { [string]: boolean },
	equipped: { [string]: string },
	ledgerUnlocked: boolean,
	ledgerApples: number,
	cyber: { [string]: number }, -- (v2.8) implants: key ("optics", "titan_L") -> tier
	look: { [string]: string }, -- (v2.8) how they look / are set: "titan_L" -> "finish:model", "howler" -> "shell:color"
	sword: number, -- (v2.8) the STILLWATER quest: 0 not begun, 1..3 the quest that runs, 4 done (SwordQuestService)
	swordProg: number, -- (v2.8) blade kills for quest 1 (they add up)
	codes: { [string]: boolean },
	chips: { any }, -- (v2.9) the cyberdeck chips: { {id, tier, slot, payload, target}, ... } (ChipService; videos excluded)
	loaded: boolean,
	canSave: boolean,
	dirty: boolean,
}

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local waiting: { [Player]: { (Profile) -> () } } = {}
-- fired once a profile is loaded: (player, profile)
Persist.OnLoaded = nil :: ((Player, Profile) -> ())?

local function key(p: Player): string
	return ProgressEpoch.Key(p.UserId)
end

local function encode(prof: Profile): any
	local owned = {}
	for id in prof.owned do
		table.insert(owned, id)
	end
	table.sort(owned)
	local eq = {}
	for k, v in prof.equipped do
		eq[k] = v
	end
	local cy, lk = {}, {}
	for k, t in prof.cyber do
		cy[k] = t
	end
	for k, v in prof.look do
		lk[k] = v
	end
	local chips = {}
	for _, rec in prof.chips or {} do
		if typeof(rec) == "table" and typeof(rec.id) == "string" then
			table.insert(chips, { id = rec.id, tier = rec.tier, slot = rec.slot, payload = rec.payload, target = rec.target })
		end
	end
	return { v = 1, jobs = prof.jobsCompleted or 0, cash = math.floor(prof.cash), owned = owned, eq = eq, lu = prof.ledgerUnlocked, la = prof.ledgerApples, cy = cy, lk = lk,
		sw = prof.sword, sp = prof.swordProg, ch = chips, codes = table.clone(prof.codes or {}) }
end

function Persist.Get(p: Player): Profile?
	return profiles[p]
end

-- the profile, once it is loaded (waits up to 'timeout' seconds)
function Persist.Wait(p: Player, timeout: number?): Profile?
	local t0 = os.clock()
	while p.Parent and (not profiles[p] or not profiles[p].loaded) and os.clock() - t0 < (timeout or 20) do
		task.wait(0.2)
	end
	local prof = profiles[p]
	return (prof and prof.loaded) and prof or nil
end

function Persist.Dirty(p: Player)
	local prof = profiles[p]
	if prof then
		prof.dirty = true
	end
end

local saving = {}
local function save(p: Player)
	if not SaveGate.CanSave() then
		return -- (v2.8) a private server saves nothing
	end
	local prof = profiles[p]
	if not prof or not prof.canSave or not prof.dirty or not store then
		return
	end
	if saving[p] then return end
	saving[p] = true
	prof.dirty = false
	local data = encode(prof)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			if typeof(old) == "table" then
				-- Keep redemption receipts when older autosaves race a code claim.
				for id in old.codes or {} do data.codes[id] = true end
				-- another server may have saved meanwhile: skins and ledger progress only ever grow
				local merged = {}
				for _, id in old.owned or {} do
					if typeof(id) == "string" then
						merged[id] = true
					end
				end
				for _, id in data.owned do
					merged[id] = true
				end
				data.owned = {}
				for id in merged do
					table.insert(data.owned, id)
				end
				table.sort(data.owned)
				data.lu = data.lu or old.lu == true
				data.la = math.max(data.la, typeof(old.la) == "number" and old.la or 0)
			end
			return data
		end)
	end)
	saving[p] = nil
	if not ok then
		prof.dirty = true
		warn("[Ragdoll] saving the profile failed:", err)
	end
end

-- (v2.8) something bought with Robux is written down at once, on EVERY server (a private one too, where nothing else is
-- saved): only this one owned id is added to what is stored, nothing else changes
function Persist.SavePurchase(p: Player, ownedId: string)
	if not store or p.UserId <= 0 then
		return
	end
	task.spawn(function()
		for attempt = 1, 3 do
			local ok = pcall(function()
				(store :: DataStore):UpdateAsync(key(p), function(old)
					local data = typeof(old) == "table" and old or { v = 1, jobsCompleted = 0, cash = 0, owned = {}, eq = {} }
					data.owned = typeof(data.owned) == "table" and data.owned or {}
					if not table.find(data.owned, ownedId) then
						table.insert(data.owned, ownedId)
					end
					return data
				end)
			end)
			if ok then
				return
			end
			task.wait(attempt * 2)
		end
	end)
end

-- Called with server-generated rewards only. The receipt and all rewards commit together.
function Persist.ClaimCode(p: Player, code: string, cash: number, skinIds: { string }): (boolean, string)
	local prof = profiles[p]
	if not prof or not prof.loaded then return false, "Your profile is still loading." end
	if prof.codes[code] then return false, "You already redeemed this code." end
	if not SaveGate.CanSave() and not game:GetService("RunService"):IsStudio() then return false, "Redeem codes in a public server so rewards can be saved." end
	if saving[p] then return false, "Your profile is saving; try again in a moment." end
	if not game:GetService("RunService"):IsStudio() and (not store or not prof.canSave) then return false, "Saving is unavailable. Try again later." end
	saving[p] = true
	local data = encode(prof)
	data.codes[code] = true
	data.cash += cash
	for _, id in skinIds do if not table.find(data.owned, id) then table.insert(data.owned, id) end end
	local claimed, ok = false, true
	if store and prof.canSave and SaveGate.CanSave() then
		ok = pcall(function()
			store:UpdateAsync(key(p), function(old)
				claimed = false
				if typeof(old) == "table" and typeof(old.codes) == "table" and old.codes[code] then return nil end
				if typeof(old) == "table" then
					for id in old.codes or {} do data.codes[id] = true end
					for _, id in old.owned or {} do if not table.find(data.owned, id) then table.insert(data.owned, id) end end
				end
				claimed = true
				return data
			end)
		end)
	else
		claimed = true -- Studio / private session: follows the existing save policy.
	end
	saving[p] = nil
	if not ok then return false, "Could not save the code reward. Try again." end
	if not claimed then prof.codes[code] = true; return false, "You already redeemed this code." end
	prof.codes[code] = true
	prof.cash += cash
	for _, id in skinIds do prof.owned[id] = true end
	prof.dirty = true
	return true, "Reward received."
end

function Persist.SaveNow(p: Player)
	task.spawn(save, p)
end

local function load(p: Player)
	local prof: Profile = {
		jobsCompleted = 0, cash = 0, owned = {}, equipped = {}, ledgerUnlocked = false, ledgerApples = 0, cyber = {}, look = {}, sword = 0, swordProg = 0,
		chips = {}, codes = {},
		loaded = false, canSave = false, dirty = false,
	}
	profiles[p] = prof
	if store and p.UserId > 0 then
		for attempt = 1, 3 do
			local ok, data = pcall(function()
				return (store :: DataStore):GetAsync(key(p))
			end)
			if ok then
				if typeof(data) == "table" then
					prof.jobsCompleted = typeof(data.jobs) == "number" and math.clamp(math.floor(data.jobs), 0, 1000000) or 0
					prof.codes = typeof(data.codes) == "table" and data.codes or {}
					prof.cash = typeof(data.cash) == "number" and math.max(0, data.cash) or 0
					for _, id in data.owned or {} do
						if typeof(id) == "string" and #id < 40 then
							prof.owned[id] = true
						end
					end
					for k, v in data.eq or {} do
						if typeof(k) == "string" and typeof(v) == "string" then
							prof.equipped[k] = v
						end
					end
					prof.ledgerUnlocked = data.lu == true
					prof.ledgerApples = typeof(data.la) == "number" and math.clamp(math.floor(data.la), 0, 999) or 0
					-- (v2.8) implants, their looks, the sword quest
					if typeof(data.cy) == "table" then
						for k, t in data.cy do
							if typeof(k) == "string" and #k < 24 and typeof(t) == "number" then
								prof.cyber[k] = math.clamp(math.floor(t), 1, 3)
							end
						end
					end
					if typeof(data.lk) == "table" then
						for k, v in data.lk do
							if typeof(k) == "string" and #k < 24 and typeof(v) == "string" and #v < 40 then
								prof.look[k] = v
							end
						end
					end
					prof.sword = typeof(data.sw) == "number" and math.clamp(math.floor(data.sw), 0, 4) or 0
					prof.swordProg = typeof(data.sp) == "number" and math.clamp(math.floor(data.sp), 0, 999) or 0
					if typeof(data.ch) == "table" then
						for _, rec in data.ch do
							if typeof(rec) == "table" and typeof(rec.id) == "string" and #rec.id < 24 then
								table.insert(prof.chips, { id = rec.id, tier = typeof(rec.tier) == "number" and rec.tier or 1, slot = rec.slot, payload = rec.payload, target = rec.target })
							end
						end
					end
				end
				prof.canSave = true
				break
			end
			warn("[Ragdoll] loading the profile failed:", data)
			task.wait(attempt * 2)
		end
	else
		prof.canSave = false -- (Studio without API access / a guest: the profile lives for this session only)
	end
	if profiles[p] ~= prof then
		return
	end
	prof.loaded = true
	if Persist.OnLoaded then
		task.spawn(Persist.OnLoaded, p, prof)
	end
end

-- (v2.9) the admin "WIPE ALL PROGRESS": dollars, skins, cyberware, the sword quest and chips are cleared and saved gone
function Persist.Reset(p: Player)
	local prof = profiles[p]
	if not prof then
		return
	end
	prof.cash = 0
	prof.owned = {}
	prof.equipped = {}
	prof.ledgerUnlocked = false
	prof.ledgerApples = 0
	prof.cyber = {}
	prof.look = {}
	prof.sword = 0
	prof.swordProg = 0
	prof.chips = {}
	prof.codes = {}
	prof.dirty = true
	p:SetAttribute("Cash", 0)
	p:SetAttribute("SkinsOwned", "")
	p:SetAttribute("LedgerUnlocked", nil)
	task.spawn(save, p)
end

function Persist.Init()
	local ok, result = pcall(function()
		return ProgressEpoch.Store(Config.ProfileStoreV2)
	end)
	if ok then
		store = result
	end
	local function added(p: Player)
		if not profiles[p] then
			task.spawn(load, p)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		profiles[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(45)
			for _, p in Players:GetPlayers() do
				save(p)
			end
		end
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			task.spawn(save, p)
		end
		task.wait(2)
	end)
end

Persist._setup=function(p,prof,st) profiles[p]=prof;store=st end
return Persist

end)()
local Epoch=(function()
--!nonstrict
-- Global progress reset: rotate a namespace, including profiles belonging to offline players.
-- Old servers keep their old namespace, so a late autosave cannot resurrect erased progress.
local DSS = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Messaging = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local Epoch = { Ready = false, Value = 0 }
local store, initialized, closing, wiping = nil, false, false, false
local TOPIC = "RagdollProgressEpoch_v1"
local function closeForReset()
	if closing then return end
	closing = true
	workspace:SetAttribute("ProgressResetPending", true)
	for _, p in Players:GetPlayers() do p:Kick("The game owner reset all progress. Rejoin to start a new save.") end
end
function Epoch.Init()
	if initialized then return end
	initialized = true
	store = DSS:GetDataStore("RagdollProgressControl_v1")
	for attempt = 1, 3 do
		local ok, v = pcall(function() return store:GetAsync("epoch") end)
		if ok then Epoch.Value = typeof(v) == "number" and math.max(0, math.floor(v)) or 0; Epoch.Ready = true; break end
		if RunService:IsStudio() then break end
		task.wait(attempt)
	end
	if not Epoch.Ready then
		warn("[Ragdoll] Progress namespace unavailable; persistence disabled for this session to protect saves.")
		return
	end
	pcall(function()
		Messaging:SubscribeAsync(TOPIC, function(message)
			if typeof(message.Data) == "number" and message.Data > Epoch.Value then closeForReset() end
		end)
	end)
	Players.PlayerAdded:Connect(function(p) if closing then p:Kick("Progress reset in progress. Please rejoin.") end end)
	task.spawn(function()
		while not closing do
			task.wait(30)
			local ok, v = pcall(function() return store:GetAsync("epoch") end)
			if ok and typeof(v) == "number" and v > Epoch.Value then closeForReset() end
		end
	end)
end
function Epoch.Key(userId: number, prefix: string?): string
	local key = (prefix or "p_") .. userId
	return Epoch.Value == 0 and key or ("e" .. Epoch.Value .. "_" .. key)
end
function Epoch.Store(name: string)
	if not Epoch.Ready then error("Progress namespace not ready") end
	return DSS:GetDataStore(name)
end
function Epoch.Wipe(by: Player): (boolean, string)
	local Items = require(game.ReplicatedStorage.Shared.Items)
	if not Items.IsGameOwner(by) then return false, "Only the game owner can reset all progress." end
	if wiping or closing or not Epoch.Ready then return false, "Progress storage is unavailable or a reset is already running." end
	wiping = true
	local ok, value = pcall(function()
		return store:UpdateAsync("epoch", function(old) return math.max(tonumber(old) or 0, Epoch.Value) + 1 end)
	end)
	wiping = false
	if not ok then return false, "The reset failed. No progress was reset. Try again later." end
	-- Deliberately leave Epoch.Value unchanged here; in-flight writes belong to the old epoch.
	pcall(function() Messaging:PublishAsync(TOPIC, value) end)
	closeForReset()
	return true, "All player progress reset."
end
return Epoch

end)()
local Jobs=(function()
--!nonstrict
-- Paid fictional contracts. Targets, completion and payouts are all decided by the server.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Persist = modules.children.Persist
local JobService = {}
local definitions = {
	assassination = { name = "ASSASSINATION", description = "Track and eliminate a marked rogue mercenary.", reward = 450, goal = 1, duration = 300 },
	courier = { name = "NEURAL COURIER", description = "Collect a data package at the ripperdoc and deliver it to the hospital.", reward = 250, goal = 2, duration = 240 },
	cleanup = { name = "STREET CLEANUP", description = "Eliminate three hostile NPCs. Training dummies do not count.", reward = 300, goal = 3, duration = 300 },
}
local active, cooldown, requests = {}, {}, {}
local deps, remote
local function root(p)
	local ch = p.Character
	return ch and not ch:GetAttribute("Dead") and ch:FindFirstChild("Torso") or nil
end
local function send(p, message)
	local job = active[p]
	local d = job and definitions[job.id]
	remote:FireClient(p, "state", job and {
		id = job.id, name = d.name, reward = d.reward, goal = d.goal, progress = job.progress,
		deadline = job.deadline, target = job.target, point = job.point,
		objective = job.id == "courier" and (job.progress == 0 and "COLLECT AT RIPPERDOC" or "DELIVER TO HOSPITAL") or d.description,
	} or false, message, cooldown[p] or 0)
end
local function clear(p)
	local job = active[p]
	active[p] = nil
	if job and job.target and job.target.Parent then job.target:Destroy() end
end
local function finish(p)
	local job = active[p]
	if not job then return end
	local d = definitions[job.id]
	active[p] = nil -- Claim before paying; repeated kill callbacks cannot pay twice.
	if job.target and job.target.Parent then task.delay(4, function() if job.target.Parent then job.target:Destroy() end end) end
	cooldown[p] = workspace:GetServerTimeNow() + 45
	deps.SkinService.AddCash(p, d.reward, "contract: " .. d.name)
	local prof = Persist.Get(p)
	if prof then prof.jobsCompleted = (prof.jobsCompleted or 0) + 1; Persist.Dirty(p) end
	send(p, "CONTRACT COMPLETE  +$" .. d.reward)
end
local function accept(p, id)
	local d, torso = definitions[id], root(p)
	local prof = Persist.Get(p)
	if not d or not torso or not prof or not prof.loaded or active[p] then return end
	if workspace:GetServerTimeNow() < (cooldown[p] or 0) then send(p, "New contracts are cooling down."); return end
	local mode = workspace:GetAttribute("Mode")
	if mode and mode ~= "sandbox" and mode ~= "" then send(p, "Contracts are available in sandbox mode."); return end
	local job = { id = id, progress = 0, deadline = workspace:GetServerTimeNow() + d.duration, character = p.Character }
	if id == "assassination" then
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Include
		local map = workspace:FindFirstChild("Map")
		rp.FilterDescendantsInstances = map and { map } or { workspace.Terrain }
		local at
		for n = 1, 16 do
			local angle = n * math.pi / 8
			local pos = torso.Position + Vector3.new(math.cos(angle) * 65, 18, math.sin(angle) * 65)
			local hit = workspace:Raycast(pos, Vector3.new(0, -55, 0), rp)
			if hit and hit.Normal.Y > 0.85 and math.abs(hit.Position.Y - torso.Position.Y) < 12 then at = hit.Position + Vector3.new(0, 3.5, 0); break end
		end
		if not at then send(p, "Move into the city to locate a contract target."); return end
		job.target = deps.NPCService.Spawn("cyber", CFrame.new(at), p, { name = "Rogue Netrunner", weapon = "smg" })
		if not job.target then send(p, "Target unavailable. Try again."); return end
		job.target:SetAttribute("ContractOwner", p.UserId)
	elseif id == "courier" then
		local map = workspace:FindFirstChild("Map")
		local desk = map and map:FindFirstChild("RipperFrontDesk", true)
		local hospital = map and map:FindFirstChild("ReplayChair", true)
		if not desk or not hospital then send(p, "Load the city map for courier work."); return end
		job.point, job.destination = desk.Position, hospital.Position
	end
	active[p] = job
	send(p, "CONTRACT ACCEPTED")
end
function JobService.Init(d)
	deps = d
	remote = Instance.new("RemoteEvent")
	remote.Name, remote.Parent = "Jobs", ReplicatedStorage.Remotes
	remote.OnServerEvent:Connect(function(p, action, id)
		if typeof(action) ~= "string" then return end
		local now = os.clock()
		if now - (requests[p] or 0) < 0.3 then return end
		requests[p] = now
		if action == "list" then remote:FireClient(p, "catalog", definitions); send(p)
		elseif action == "accept" and typeof(id) == "string" then accept(p, id)
		elseif action == "cancel" then clear(p); cooldown[p] = workspace:GetServerTimeNow() + 15; send(p, "Contract cancelled.") end
	end)
	local prior = deps.DamageService.OnKill
	deps.DamageService.OnKill = function(victim, killer, state)
		if prior then prior(victim, killer, state) end
		if not killer then return end
		local job = active[killer]
		if not job or not root(killer) then return end
		if (job.id == "assassination" and victim == job.target) or (job.id == "cleanup" and victim:GetAttribute("IsNPC") and not victim:GetAttribute("IsDummy") and not victim:GetAttribute("StandUp") and victim:GetAttribute("Hostile") == true and victim:GetAttribute("Spawner") == nil and not victim:GetAttribute("ContractOwner")) then
			job.progress += 1
			if job.progress >= definitions[job.id].goal then finish(killer) else send(killer, "TARGET ELIMINATED") end
		end
	end
	Players.PlayerRemoving:Connect(function(p) clear(p); cooldown[p], requests[p] = nil, nil end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			for p, job in active do
				local torso = root(p)
				if not torso or p.Character ~= job.character or workspace:GetServerTimeNow() >= job.deadline then
					clear(p); cooldown[p] = workspace:GetServerTimeNow() + 15; send(p, "CONTRACT FAILED")
				elseif job.target and (not job.target.Parent or job.target:GetAttribute("Dead")) then
					clear(p); send(p, "The marked target was lost. Choose another contract.")
				elseif job.id == "courier" and job.point and (torso.Position - job.point).Magnitude <= 9 then
					job.progress += 1
					if job.progress >= 2 then finish(p)
					else job.point = job.destination; send(p, "PACKAGE COLLECTED — DELIVER TO HOSPITAL") end
				end
			end
		end
	end)
end
JobService._active=active
JobService._accept=accept
JobService._finish=finish
JobService._setup=function(d,r) deps=d;remote=r end
return JobService

end)()
-- Full profile code with mock DataStore callbacks, including retries and failures.
local function profile() return {cash=10,owned={},equipped={},ledgerUnlocked=false,ledgerApples=0,cyber={},look={},sword=0,swordProg=0,chips={},codes={},loaded=true,canSave=true,dirty=false} end
local persisted
local store={UpdateAsync=function(_,key,cb) local proposal=cb(persisted); if proposal then proposal=cb(persisted); persisted=proposal end; return persisted end}
local payer=player(40,vec(0,0,0))
local prof=profile();Persist._setup(payer,prof,store)
local ok=Persist.ClaimCode(payer,"netrunner",200,{"pistol_1"})
check(ok,"bundle claimed");eq(prof.cash,210,"cash paid once despite UpdateAsync retry");check(prof.owned.pistol_1,"skin granted");check(persisted.codes.netrunner,"receipt committed");eq(persisted.cash,210,"cash committed with receipt")
check(not Persist.ClaimCode(payer,"netrunner",200,{"pistol_2"}),"duplicate rejected");eq(prof.cash,210,"duplicate pays nothing")
local other=profile();Persist._setup(payer,other,store)
check(not Persist.ClaimCode(payer,"netrunner",200,{"pistol_2"}),"other session receipt rejected");eq(other.cash,10,"other session not paid")
local failed=profile();Persist._setup(payer,failed,{UpdateAsync=function() error("service unavailable") end})
check(not Persist.ClaimCode(payer,"chips",499,{"skin_2","skin_3"}),"failed storage rejects claim");eq(failed.cash,10,"failed claim leaves money untouched");check(not failed.codes.chips,"failed claim remains redeemable")
Epoch.Value=0;eq(Epoch.Key(42),"p_42","legacy profile key");eq(Epoch.Key(42,"u_"),"u_42","legacy kill key");eq(Epoch.Key(42,"q_"),"q_42","legacy quest key")
Epoch.Value=3;eq(Epoch.Key(42),"e3_p_42","wipe rotates offline profiles");eq(Epoch.Key(42,"q_"),"e3_q_42","wipe rotates quest saves")
local paid=0;modules.children.Persist.Get=function() return profile() end;modules.children.Persist.Dirty=function() end
Jobs._setup({SkinService={AddCash=function(_,amount) paid+=amount end}}, {FireClient=function() end})
local worker=player(50,vec(0,0,0))
Jobs._accept(worker,"cleanup");check(Jobs._active[worker]~=nil,"mission accepted")
Jobs._finish(worker);eq(paid,300,"contract pays reward");Jobs._finish(worker);eq(paid,300,"contract cannot pay twice")
Jobs._accept(worker,"cleanup");check(Jobs._active[worker]==nil,"repeat contract observes cooldown")
print("PASS: "..total.." total gameplay and transaction assertions")

shared.children.TimeScale=TimeScale
shared.children.HotdogPath={}
local bodies={}
modules.children.DamageService={Bodies=function() return bodies end}
modules.children.GoreService={}
modules.children.ExplosionService={}
modules.children.LightingService={}
modules.children.PropService={}
local frozenTasks={}
task.spawn=function(fn) table.insert(frozenTasks,fn) end
local Super=(function()
--!nonstrict
-- SuperService (v2.0): the admins' super powers.
--   timestop   : the whole server stops - everything that moves freezes where it is and the colours drain - except
--                the admin who stopped it (and what they hold). Again (or after Config.TimeStopMax) time goes on and
--                everything keeps the speed it had.
--   hotdog     : the player nearest to the admin's crosshair is put on a giant hotdog. It charges, launches, flies
--                round and round the map faster and faster (Mach 1 ... Mach 30+), pulls everybody and everything
--                into its tornado and finally explodes - with the whole map.
--   sun cannon : a heavy device (spawn menu) that always aims at the sun. "Fire" in the admin menu: it charges for
--                Config.SunCharge s, then a giant beam goes into the sun (jumping into the beam vaporises you), the
--                sun swells for Config.SunExpand s and goes supernova: everybody dies.
-- The heavy visuals are drawn by the clients (SuperFX) from the start time and a few numbers, so they are smooth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TimeScale = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TimeScale")) -- (v2.8) the Sandevistan's slow motion
local HotdogPath = require(Shared:WaitForChild("HotdogPath"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))
local LightingService = require(Modules:WaitForChild("LightingService"))
local PropService = require(Modules:WaitForChild("PropService"))

local SuperService = {}

-- set by Main: the centre / size of the map a position is in (the sandbox or a loaded map)
SuperService.MapAround = nil :: ((Vector3) -> (Vector3, number))?

local function now(): number
	return workspace:GetServerTimeNow()
end

local function torsoOf(p: Player): BasePart?
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

-- kill even through God mode / spawn protection (the end of the world)
local function forceKill(model: Model, cause: string)
	model:SetAttribute("ForceKill", true)
	model:SetAttribute("God", nil)
	model:SetAttribute("SpawnProtect", nil)
	DamageService.Kill(model, cause)
end

------------------------------------------------------------------------
-- time stop
------------------------------------------------------------------------

type Stop = { by: Player, parts: { [BasePart]: { v: Vector3, w: Vector3 } }, conn: RBXScriptConnection?, token: number, style: string? }
local stop: Stop? = nil
local stopToken = 0

local function exempt(p: BasePart, by: Player): boolean
	local char = by.Character
	if char and p:IsDescendantOf(char) then
		return true
	end
	-- what the admin holds moves with them: anything joined to their body (an item in the hand is welded to it) and
	-- items marked as theirs. (fix) NOT "everything their machine simulates": Roblox gives a player every loose part near
	-- them, so in a solo test that was the whole map - and time stop froze nothing at all.
	local root = p.AssemblyRootPart
	if char and root and root:IsDescendantOf(char) then
		return true
	end
	local item = p:FindFirstAncestorOfClass("Model")
	while item do
		if item:GetAttribute("HolderId") == by.UserId then
			return true
		end
		item = item:FindFirstAncestorOfClass("Model")
	end
	local fx = workspace:FindFirstChild("FX")
	return fx ~= nil and p:IsDescendantOf(fx) and p.Name ~= "Rocket" and p.Name ~= "FlareShot"
end

function SuperService.TimeStopped(): boolean
	return stop ~= nil
end

-- (v2.8) style "still": STILL CUT (StillCutService) - the clients draw it themselves (SwordClient), not the purple drain
function SuperService.TimeStop(by: Player, on: boolean, style: string?)
	if on and not stop then
		stopToken += 1
		local s: Stop = { by = by, parts = {}, conn = nil, token = stopToken, style = style }
		stop = s
		local function freeze(d: Instance)
			if stop ~= s or not d:IsA("BasePart") or d.Anchored or not d:IsDescendantOf(workspace) then
				return
			end
			if exempt(d, by) then
				return
			end
			s.parts[d] = { v = d.AssemblyLinearVelocity, w = d.AssemblyAngularVelocity }
			d.Anchored = true
		end
		for _, d in workspace:GetDescendants() do
			freeze(d)
		end
		s.conn = workspace.DescendantAdded:Connect(function(d)
			task.defer(freeze, d)
		end)
		workspace:SetAttribute("TimeStop", by.UserId)
		local t = torsoOf(by)
		GoreService.FX({ t = "timestop", on = true, by = by.UserId, p = t and t.Position or Vector3.zero, style = style })
		local my = s.token
		task.delay(Config.TimeStopMax, function()
			if stop and stop.token == my then
				SuperService.TimeStop(by, false)
			end
		end)
	elseif not on and stop then
		local s = stop
		stop = nil
		if s.conn then
			s.conn:Disconnect()
		end
		workspace:SetAttribute("TimeStop", nil)
		for p, rec in s.parts do
			if p.Parent then
				p.Anchored = false
				pcall(function()
					p.AssemblyLinearVelocity = rec.v
					p.AssemblyAngularVelocity = rec.w
				end)
			end
		end
		GoreService.FX({ t = "timestop", on = false, by = s.by.UserId, style = s.style })
	end
end

-- (v2.9) a LOCAL freeze (the STILL CUT): only the bodies and loose things within `radius` of `center` stand still for
-- `duration` s - not the whole server. The one who does it (and what they hold) are exempt. It restores itself.
local localHolds = setmetatable({}, { __mode = "k" })
function SuperService.LocalFreeze(by: Player, center: Vector3, radius: number, duration: number)
	-- Only character bodies in the cast radius. Overlaps extend the hold instead of releasing each other.
	for body in DamageService.Bodies() do
		local root = body:FindFirstChild("Torso")
		if body ~= by.Character and root and root:IsA("BasePart") and not body:GetAttribute("Dead") and (root.Position - center).Magnitude <= radius then
			local untilT = now() + duration
			local hold = localHolds[body]
			if hold then
				hold.untilT = math.max(hold.untilT, untilT)
			else
				hold = { untilT = untilT, parts = {} }
				localHolds[body] = hold
				for _, d in body:GetDescendants() do
					if d:IsA("BasePart") and not d.Anchored then
						hold.parts[d] = { v = d.AssemblyLinearVelocity, w = d.AssemblyAngularVelocity, k = TimeScale.ForField(nil, d.Position) }
						d.Anchored = true
					end
				end
				task.spawn(function()
					while body.Parent and now() < hold.untilT do task.wait(0.05) end
					localHolds[body] = nil
					if body.Parent then body:SetAttribute("TemporalFrozenUntil", nil) end
					for part, velocity in hold.parts do
						if part.Parent then
							part.Anchored = false
							local ratio = Players:GetPlayerFromCharacter(body) and 1 or (TimeScale.ForField(nil, part.Position) / math.max(0.02, velocity.k))
							part.AssemblyLinearVelocity, part.AssemblyAngularVelocity = velocity.v * ratio, velocity.w * ratio
						end
					end
				end)
			end
			body:SetAttribute("TemporalFrozenUntil", hold.untilT)
		end
	end
end

------------------------------------------------------------------------
-- (v2.8) SLOW MOTION (the Sandevistan): the world keeps moving - very slowly - instead of the old freeze-and-step.
--   * the physics: gravity becomes RealGravity x k^2 and every loose thing's speed is multiplied by k (and divided by k
--     again at the end: a crate that was falling goes on falling at full speed). The server simulates every loose thing
--     while it runs (only bodies of players are simulated by their own players, who slow themselves down: CharacterController).
--   * everything moved by script reads TimeScale (rockets, flares, bombs, steel balls, bullets in flight, the Crawler, NPC
--     brains): its time runs k times slower, and at full speed again the moment slow motion ends.
--   * the user lives in normal time (their screen keeps the normal gravity, their body is not slowed).
------------------------------------------------------------------------

-- (v2.8.1) users: everybody whose Sandevistan runs right now - they all live in normal time together (a second one
-- that starts while the first runs joins it instead of being slowed)
type Slow = { by: Player, users: { [Player]: number }, k: number, owned: { [BasePart]: boolean }, skip: { [BasePart]: boolean }, conn: RBXScriptConnection?, token: number, gravity: number }
local slow: Slow? = nil
local slowToken = 0

-- a body that is hit in slow motion: its push is slowed like everything else
function SuperService.SlowMoImpulse(model: Model, vel: Vector3)
	local s = slow
	if not s or Players:GetPlayerFromCharacter(model) or (model:FindFirstChild("Torso") and TimeScale.ForField(nil, model.Torso.Position) == 1) then
		return -- (a player's own machine slows its body: CharacterController)
	end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and not d.Anchored then
			pcall(function()
				d.AssemblyLinearVelocity += vel * (s.k - 1) -- (the full push was added already: keep only k of it)
			end)
		end
	end
end

function SuperService.SlowMoActive(): boolean
	return slow ~= nil
end

local function playerBodyOf(part: Instance): boolean
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		if Players:GetPlayerFromCharacter(m) then
			return true
		end
		local h = m:GetAttribute("HolderId")
		if typeof(h) == "number" and h > 0 then
			return true -- (an item in somebody's hand moves with that hand)
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return false
end

-- every assembly a player's body is part of (a car with its driver in the seat, a held item): those stay with that player
local function playerRoots(): { [BasePart]: boolean }
	local out = {}
	for _, pl in Players:GetPlayers() do
		local char = pl.Character
		if char then
			for _, d in char:GetChildren() do
				if d:IsA("BasePart") and d.AssemblyRootPart then
					out[d.AssemblyRootPart :: BasePart] = true
				end
			end
		end
	end
	return out
end

local function slowGrab(s: Slow, d: Instance)
	if slow ~= s or not d:IsA("BasePart") or d.Anchored or s.owned[d] then
		return
	end
	if d.AssemblyRootPart ~= d or not d:IsDescendantOf(workspace) or s.skip[d] then
		return
	end
	local mine = false
	for u in s.users do
		if exempt(d, u) then
			mine = true
		end
	end
	if mine or playerBodyOf(d) then
		return
	end
	if workspace:GetAttribute("SlowFieldR") then
		local belongs = false
		for body in DamageService.Bodies() do
			if d:IsDescendantOf(body) then belongs = true; break end
		end
		if not belongs or TimeScale.ForField(nil, d.Position) >= 1 then return end
		local att = Instance.new("Attachment")
		att.Name, att.Parent = "TemporalGravityAttachment", d
		local force = Instance.new("VectorForce")
		force.Name, force.Attachment0, force.RelativeTo, force.ApplyAtCenterOfMass = "TemporalGravity", att, Enum.ActuatorRelativeTo.World, true
		force.Force = Vector3.new(0, workspace.Gravity * (1 - s.k * s.k) * d.AssemblyMass, 0)
		force.Parent = d
	end
	s.owned[d] = true
	pcall(function()
		d:SetNetworkOwner(nil)
	end)
	pcall(function()
		d.AssemblyLinearVelocity *= s.k
		d.AssemblyAngularVelocity *= s.k
	end)
end

local function slowRelease(s: Slow, d: BasePart)
	for _, name in { "TemporalGravity", "TemporalGravityAttachment" } do
		local old = d:FindFirstChild(name)
		if old then old:Destroy() end
	end
	if not d.Parent or d.Anchored then
		return
	end
	pcall(function()
		if d.AssemblyRootPart == d then
			d.AssemblyLinearVelocity /= s.k
			d.AssemblyAngularVelocity /= s.k
			d:SetNetworkOwnershipAuto()
		end
	end)
end

local function publishUsers(s: Slow)
	local ids = {}
	for u in s.users do
		table.insert(ids, tostring(u.UserId))
	end
	workspace:SetAttribute("SlowMoUsers", #ids > 0 and ("," .. table.concat(ids, ",") .. ",") or nil)
end

function SuperService.SlowMo(by: Player, on: boolean)
	-- (v2.8.1) a second Sandevistan while one runs: its user joins the fast side
	if on and slow and not stop then
		local s = slow
		slowToken += 1
		local my = slowToken
		s.users[by] = my
		publishUsers(s)
		task.delay(Config.SandevistanDuration + 3, function()
			if slow == s and s.users[by] == my then
				SuperService.SlowMo(by, false)
			end
		end)
		return
	end
	if not on and slow and slow.users[by] ~= nil then
		local others = 0
		for u in slow.users do
			if u ~= by and u.Parent then
				others += 1
			end
		end
		if others > 0 then
			slow.users[by] = nil
			if slow.by == by then
				slow.by = next(slow.users) :: Player
				workspace:SetAttribute("SlowMo", slow.by.UserId)
			end
			publishUsers(slow)
			return -- (the others still run: the world stays slow)
		end
	elseif not on and slow and slow.users[by] == nil then
		return -- (not one of the users: nothing to stop)
	end
	if on and not slow and not stop then
		slowToken += 1
		local k = math.clamp(Config.SlowMoScale, 0.02, 0.9)
		local s: Slow = { by = by, users = { [by] = slowToken }, k = k, owned = {}, skip = playerRoots(), conn = nil, token = slowToken, gravity = workspace.Gravity }
		slow = s
		workspace:SetAttribute("RealGravity", s.gravity)
		workspace:SetAttribute("SlowScale", k)
		workspace:SetAttribute("SlowMo", by.UserId)
		-- (v2.9) a LOCAL Sandevistan: only players within this radius of a user are slowed (0 / nil = the whole world)
		workspace:SetAttribute("SlowFieldR", Config.SandevistanRadius > 0 and Config.SandevistanRadius or nil)
		publishUsers(s)
		if not workspace:GetAttribute("SlowFieldR") then workspace.Gravity = s.gravity * k * k end
		for _, d in workspace:GetDescendants() do
			slowGrab(s, d)
		end
		s.conn = workspace.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				task.defer(slowGrab, s, d)
			end
		end)
		-- what is let go of while it runs (thrown, dropped) joins the slow world
		task.spawn(function()
			while slow == s do
				task.wait(0.4)
				s.skip = playerRoots()
				for d in s.owned do -- (somebody climbed into a car / picked it up: it is theirs again)
					if slow == s and (s.skip[d] or not d.Parent or (workspace:GetAttribute("SlowFieldR") and TimeScale.ForField(nil, d.Position) >= 1)) then
						s.owned[d] = nil
						slowRelease(s, d)
					end
				end
				for body in DamageService.Bodies() do
					if body.Parent then
						for _, d in body:GetDescendants() do slowGrab(s, d) end
					end
				end
				local props = workspace:FindFirstChild("SpawnedProps")
				for _, m in (props and props:GetChildren() or {}) do
					if slow ~= s then
						break
					end
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") and not s.owned[d] and d.AssemblyRootPart == d then
							slowGrab(s, d)
						end
					end
				end
			end
		end)
		task.delay(Config.SandevistanDuration + 3, function() -- (a safety: it never stays on)
			if slow and slow.token == s.token then
				SuperService.SlowMo(by, false)
			end
		end)
	elseif not on and slow then
		local s = slow
		slow = nil
		if s.conn then
			s.conn:Disconnect()
		end
		if not workspace:GetAttribute("SlowFieldR") then workspace.Gravity = s.gravity end
		workspace:SetAttribute("SlowMo", nil)
		workspace:SetAttribute("SlowMoUsers", nil)
		workspace:SetAttribute("SlowScale", nil)
		workspace:SetAttribute("RealGravity", nil)
		workspace:SetAttribute("SlowFieldR", nil)
		for d in s.owned do
			slowRelease(s, d)
		end
	end
end

------------------------------------------------------------------------
-- hotdog
------------------------------------------------------------------------

local hotdog: { by: Player, target: Player, info: any, t0: number }? = nil

-- the player closest to where the admin looks (ray from the camera), or nil
function SuperService.PickTarget(by: Player, origin: Vector3, dir: Vector3): Player?
	local best, bestScore = nil, math.huge
	for _, p in Players:GetPlayers() do
		if p ~= by then
			local t = torsoOf(p)
			if t and not p.Character:GetAttribute("Dead") and not p:GetAttribute("InLobby") then
				local to = t.Position - origin
				local along = to:Dot(dir)
				if along > 0 then
					local miss = (to - dir * along).Magnitude
					local ang = math.atan2(miss, along)
					local score = ang + along * 0.0004
					if ang < math.rad(35) and score < bestScore then
						best, bestScore = p, score
					end
				end
			end
		end
	end
	return best
end

function SuperService.Hotdog(by: Player, target: Player)
	if hotdog then
		return -- one at a time
	end
	local t = torsoOf(target)
	local tchar = target.Character
	if not t or not tchar or tchar:GetAttribute("Dead") then
		return
	end
	local center, size = Vector3.new(0, 0, 0), Config.HotdogRadius
	if SuperService.MapAround then
		center, size = SuperService.MapAround(t.Position)
	end
	local info = { start = t.Position, center = center, radius = size, height = Config.HotdogHeight }
	local t0 = now()
	local rec = { by = by, target = target, info = info, t0 = t0 }
	hotdog = rec
	workspace:SetAttribute("Hotdog", target.UserId)
	GoreService.FX({ t = "hotdog", by = by.UserId, target = target.UserId, start = info.start, center = center, radius = size, height = info.height, t0 = t0 })
	-- the one on the hotdog cannot get away (their own client puts them on it); nothing can hurt them before the end
	tchar:SetAttribute("OnHotdog", true)
	local total = Config.HotdogCharge + Config.HotdogFlight
	-- the server pulls what it simulates itself (props, dummies, corpses, NPCs) into the tornado
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if hotdog ~= rec then
			conn:Disconnect()
			return
		end
		if workspace:GetAttribute("TimeStop") then
			rec.t0 += dt -- (time is stopped: so is the hotdog)
			return
		end
		rec.t0 += dt * (1 - TimeScale.Get()) -- (v2.8) slow motion
		local age = now() - rec.t0
		if age >= total then
			conn:Disconnect()
			return
		end
		local pull = HotdogPath.Pull(age)
		if pull <= 0 then
			return
		end
		for _, folderName in { "SpawnedProps", "Dummies", "Corpses", "NPCs" } do
			local f = workspace:FindFirstChild(folderName)
			if f then
				for _, m in f:GetChildren() do
					local root = (m:IsA("Model") and m.PrimaryPart) or (m:IsA("BasePart") and m) or nil
					if root and not root.Anchored and (root.Position - info.center).Magnitude < info.radius * 3 then
						local ok, owner = pcall(function()
							return root:GetNetworkOwner()
						end)
						if ok and owner == nil then
							local want = HotdogPath.Wind(info, age, root.Position)
							local v = root.AssemblyLinearVelocity
							pcall(function()
								root.AssemblyLinearVelocity = v:Lerp(want, math.clamp(pull * dt * 2.5, 0, 1))
							end)
						end
					end
				end
			end
		end
	end)
	task.spawn(function()
		while hotdog == rec and now() - rec.t0 < total do
			task.wait(0.1)
		end
		if hotdog ~= rec then
			return
		end
		local pos = HotdogPath.At(info, total)
		hotdog = nil
		workspace:SetAttribute("Hotdog", nil)
		GoreService.FX({ t = "hotdogboom", p = pos })
		ExplosionService.Nuke(pos, by)
		-- the whole map goes with it: everybody in this map dies
		for _, p in Players:GetPlayers() do
			local c = p.Character
			local tt = torsoOf(p)
			if c and tt and not c:GetAttribute("Dead") and not p:GetAttribute("InLobby") and (p ~= by or not c:GetAttribute("God")) then
				if (tt.Position - info.center).Magnitude < info.radius * 4 + 200 then
					task.delay(math.random() * 0.6, forceKill, c, "Hotdogged at Mach 34")
				end
			end
		end
		tchar:SetAttribute("OnHotdog", nil)
		if SuperService.OnMapBoom then
			SuperService.OnMapBoom(pos, info.radius * 2.5)
		end
	end)
end

-- set by Main: the whole map breaks apart (buildings)
SuperService.OnMapBoom = nil :: ((Vector3, number) -> ())?

------------------------------------------------------------------------
-- sun cannon
------------------------------------------------------------------------

local cannons: { [Model]: boolean } = {}
local sunEvent: { t0: number, by: Player }? = nil

local function sunDir(): Vector3
	local d = Lighting:GetSunDirection()
	return d.Magnitude > 0.01 and d.Unit or Vector3.yAxis
end

local function aimCannons()
	local d = sunDir()
	for m in cannons do
		if not m.Parent then
			cannons[m] = nil
			continue
		end
		local turret = m:FindFirstChild("Turret")
		if turret and turret:IsA("BasePart") then
			local pos = turret.Position
			local cf = CFrame.lookAt(pos, pos + d)
			-- (v2.0) the rotor and the yoke only turn round the upright
			local flat = Vector3.new(d.X, 0, d.Z)
			local yawCF = CFrame.new(pos) * CFrame.Angles(0, flat.Magnitude > 0.01 and math.atan2(-flat.X, -flat.Z) or 0, 0)
			for _, p in m:GetChildren() do
				local off = p:IsA("BasePart") and p:GetAttribute("SunYaw") and p:GetAttribute("YawOff")
				if typeof(off) == "CFrame" then
					(p :: BasePart).CFrame = yawCF * off
				end
			end
			-- (the turret and what is welded to it move together)
			for _, p in m:GetChildren() do
				if p:IsA("BasePart") and p ~= turret then
					local w = p:FindFirstChildOfClass("WeldConstraint")
					if w and (w.Part0 == turret or w.Part1 == turret) then
						p.CFrame = cf * turret.CFrame:ToObjectSpace(p.CFrame)
					end
				end
			end
			turret.CFrame = cf
		end
	end
end

local function registerCannon(m: Model)
	if cannons[m] then
		return
	end
	cannons[m] = true
	-- set down on the ground right where it was spawned
	local base = m.PrimaryPart
	if base then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { m }
		local hit = workspace:Raycast(base.Position + Vector3.new(0, 2, 0), Vector3.new(0, -60, 0), params)
		if hit then
			local bottom = base.Position.Y - base.Size.Y * 0.5
			m:PivotTo(m:GetPivot() + Vector3.new(0, hit.Position.Y - bottom, 0))
		end
	end
	aimCannons()
end

function SuperService.FireSun(by: Player)
	if sunEvent then
		return
	end
	local list = {}
	for m in cannons do
		if m.Parent then
			table.insert(list, m)
		end
	end
	if #list == 0 then
		return
	end
	-- the cannon calls the sun up when it is night
	if sunDir().Y < 0.15 then
		LightingService.SetTime(12)
		task.wait(0.2)
		aimCannons()
	end
	local ev = { t0 = now(), by = by }
	sunEvent = ev
	workspace:SetAttribute("SunCannon", true)
	GoreService.FX({ t = "suncharge", t0 = ev.t0, cannons = list, charge = Config.SunCharge, expand = Config.SunExpand })
	task.spawn(function()
		task.wait(Config.SunCharge)
		if sunEvent ~= ev then
			return
		end
		aimCannons()
		local d = sunDir()
		local beams = {}
		for _, m in list do
			local lens = m:FindFirstChild("Lens")
			if m.Parent and lens and lens:IsA("BasePart") then
				table.insert(beams, { from = lens.Position, dir = d })
			end
		end
		GoreService.FX({ t = "sunbeam", beams = beams, d = Config.SunExpand })
		-- whoever is in a beam is vaporised
		local tEnd = os.clock() + Config.SunExpand
		while os.clock() < tEnd and sunEvent == ev do
			for model in DamageService.Bodies() do
				local torso = model.Parent and model:FindFirstChild("Torso")
				if torso and torso:IsA("BasePart") and not model:GetAttribute("Dead") then
					for _, b in beams do
						local to = torso.Position - b.from
						local along = to:Dot(b.dir)
						if along > 0 and (to - b.dir * along).Magnitude < Config.SunBeamRadius + 1.5 then
							GoreService.FX({ t = "boomSmall", p = torso.Position, d = b.dir })
							forceKill(model, "Vaporized by the sun beam")
						end
					end
				end
			end
			task.wait(0.1)
		end
		if sunEvent ~= ev then
			return
		end
		-- supernova
		GoreService.FX({ t = "supernova" })
		task.wait(1.2)
		for _, p in Players:GetPlayers() do
			local c = p.Character
			if c and not c:GetAttribute("Dead") then
				task.delay(math.random() * 0.8, forceKill, c, "Supernova")
			end
		end
		for model, st in DamageService.Bodies() do
			if not st.player and not model:GetAttribute("Dead") then
				task.delay(math.random(), forceKill, model, "Supernova")
			end
		end
		task.wait(6)
		sunEvent = nil
		workspace:SetAttribute("SunCannon", nil)
		GoreService.FX({ t = "sunreset" })
	end)
end

------------------------------------------------------------------------

function SuperService.Init()
	local prevPlaced = PropService.OnPlaced
	PropService.OnPlaced = function(inst: Instance)
		if prevPlaced then
			prevPlaced(inst)
		end
		if inst:IsA("Model") and inst:GetAttribute("SunCannon") then
			registerCannon(inst)
		end
	end
	task.spawn(function()
		while true do
			task.wait(0.5)
			if next(cannons) then
				aimCannons()
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		if stop and stop.by == p then
			SuperService.TimeStop(p, false)
		end
	end)
	-- the one on the hotdog cannot be hurt before the end
	local prevShield = DamageService.Shield
	DamageService.Shield = function(model, region, dmg, point, opts)
		if model:GetAttribute("OnHotdog") then
			return true
		end
		return prevShield ~= nil and prevShield(model, region, dmg, point, opts) or false
	end
end

return SuperService

end)()

local clock=1000
workspace.GetServerTimeNow=function() return clock end
local source=player(60,vec(0,0,0));local closeP=player(61,vec(5,0,0));local distant=player(62,vec(80,0,0));Players.list={source,closeP,distant}
for _,p in Players.list do
 local t=p.Character.children.Torso;t.Anchored=false;t.AssemblyLinearVelocity=vec(2,0,0);t.AssemblyAngularVelocity=vec(0,1,0)
 p.Character.GetDescendants=function() return {t} end;bodies[p.Character]={}
end
Super.LocalFreeze(source,vec(0,0,0),42,2)
check(closeP.Character.children.Torso.Anchored,"nearby character frozen")
check(not distant.Character.children.Torso.Anchored,"distant character not frozen")
check(not source.Character.children.Torso.Anchored,"caster exempt from local freeze")
eq(closeP.Character:GetAttribute("TemporalFrozenUntil"),1002,"freeze expiry")
clock=1001;Super.LocalFreeze(source,vec(0,0,0),42,4)
eq(closeP.Character:GetAttribute("TemporalFrozenUntil"),1005,"overlapping freeze extends expiry")
eq(#frozenTasks,1,"overlap uses one release owner")
clock=1006;frozenTasks[1]()
check(not closeP.Character.children.Torso.Anchored,"freeze restored anchoring")
eq(closeP.Character.children.Torso.AssemblyLinearVelocity.X,2,"freeze restored velocity")
print("PASS: "..total.." regression assertions including overlapping local freeze")
