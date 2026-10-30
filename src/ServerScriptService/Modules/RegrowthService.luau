--!strict
-- RegrowthService (v2.8.1): bodies that mend themselves.
--   * REGROWTH CORE (an implant in the BONE MARROW slot):
--       tier 1: a broken arm / leg knits again (20 - 30 s: its health is back, the bone holds again)
--       tier 2: + a cut-off arm / leg grows back (20 - 30 s; skin colour, no metal)
--       tier 3: + a lost head or torso (cut off, skull or chest crushed): you lie where you fell for 20 - 40 s, then the
--               body is whole again and gets up right there (once every 3 minutes; otherwise you die as usual)
--   * TITAN FRAME ARMS mend themselves without it: a broken metal arm in 20 - 30 s, a cut-off one is rebuilt (20 - 30 s).
-- Every running timer is an attribute on the body (RegrowAt_<limb> / RegrowUntil = the server time it is done): the
-- client shows it.
-- (v2.8.2) You SEE it grow, all the way through the timer: first the BONE comes out of the stump, then the FLESH grows
-- round it, then the SKIN closes over it (a TITAN arm: the frame, the cables, the plates). A healed bone sinks back into
-- the arm and the holes close (GoreService.Mend). Tier 3 heals the body where it lies - the head / the chest grows back
-- the same way - and it gets up from there in the pose it lay in.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local RigInfo = require(Shared:WaitForChild("RigInfo"))

local RegrowthService = {}

local deps: any = nil
local FXRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FX") :: RemoteEvent
local rng = Random.new()

local LIMBS = { "LeftArm", "RightArm", "LeftLeg", "RightLeg" }
local TITAN_SIDE: { [string]: string } = { LeftArm = "L", RightArm = "R" }
local BODY_COLOR: { [string]: string } = {
	LeftArm = "LeftArmColor3",
	RightArm = "RightArmColor3",
	LeftLeg = "LeftLegColor3",
	RightLeg = "RightLegColor3",
}

local timers: { [Model]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local lastCore: { [Player]: number } = {}
local regrowAt: { [Player]: CFrame } = {}
local regrowPose: { [Player]: { [string]: CFrame } } = {}
local token = 0

local function tierOf(p: Player): number
	local ok, t = pcall(deps.CyberService.Tier, p, "regrowth")
	return ok and typeof(t) == "number" and t or 0
end

-- a TITAN arm in this place (it mends itself)
local function metalArm(p: Player, key: string): boolean
	local side = TITAN_SIDE[key]
	if not side then
		return false
	end
	local ok, eff = pcall(deps.CyberService.Effective, p)
	return ok and typeof(eff) == "table" and eff["titan_" .. side] ~= nil
end

local function heal(char: Model, at: Instance?)
	local t = (at and at:IsA("BasePart")) and at or char:FindFirstChild("Torso")
	if t and t:IsA("BasePart") then
		pcall(deps.GoreService.FX, { t = "heal", p = t.Position })
		pcall(deps.GoreService.Sound, "ratchet", t, 0.8)
	end
end

-- the bone holds again
local function mend(char: Model, key: string)
	char:SetAttribute("HP_" .. key, Config.LimbMaxHP)
	char:SetAttribute("Broken_" .. key, false)
	local part = char:FindFirstChild(RigInfo.RegionPart[key] or "")
	heal(char, part)
	if part and part:IsA("BasePart") then
		pcall(deps.GoreService.Mend, part, 3) -- (v2.8.2) the broken bone sinks back in, the holes close
	end
end

-- a new limb where the old one was cut off
local function regrow(p: Player, char: Model, key: string, metal: boolean)
	local def = RigInfo.ByKey[key]
	if not def then
		return
	end
	local color = Color3.fromRGB(234, 184, 146)
	local bc = char:FindFirstChildOfClass("BodyColors")
	if bc and BODY_COLOR[key] then
		color = (bc :: any)[BODY_COLOR[key]]
	else
		local head = char:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			color = head.Color
		end
	end
	local limb = deps.RigBuilder.Reattach(char, key, nil)
	if not limb then
		return
	end
	limb.Material = Enum.Material.Plastic
	limb.Color = color
	limb.Transparency = 0
	char:SetAttribute("Prosthetic_" .. key, nil) -- (grown, not fitted)
	pcall(function()
		limb:SetNetworkOwner(p)
	end)
	local col = limb:FindFirstChild("Collider")
	if col and col:IsA("BasePart") then
		pcall(function()
			col:SetNetworkOwner(p)
		end)
	end
	FXRemote:FireClient(p, { t = "limb", body = char, key = key })
	if metal then
		pcall(deps.CyberService.Redress, p) -- (the TITAN plates go back on, the real arm hides again)
	end
	heal(char, limb)
end

------------------------------------------------------------------------
-- (v2.8.2) the growth you can watch: bone, flesh, skin
------------------------------------------------------------------------

local BONE = Color3.fromRGB(226, 216, 196)
local FLESH = Color3.fromRGB(150, 30, 36)
local STEEL = Color3.fromRGB(70, 74, 82)
local CABLE = Color3.fromRGB(30, 30, 34)
local ghosts: { [Model]: { [string]: { folder: Folder, token: number } } } = setmetatable({}, { __mode = "k" }) :: any

local function skinOf(char: Model, key: string): Color3
	local bc = char:FindFirstChildOfClass("BodyColors")
	local prop = BODY_COLOR[key] or (key == "Torso" and "TorsoColor3" or "HeadColor3")
	if bc then
		local ok, c = pcall(function()
			return (bc :: any)[prop]
		end)
		if ok and typeof(c) == "Color3" then
			return c
		end
	end
	local head = char:FindFirstChild("Head")
	return (head and head:IsA("BasePart")) and head.Color or Color3.fromRGB(234, 184, 146)
end

local function ghostPart(folder: Folder, torso: BasePart, name: string, color: Color3, mat: Enum.Material, shape: Enum.PartType?): (Part, Weld)
	local g = Instance.new("Part")
	g.Name = name
	g.Color = color
	g.Material = mat
	if shape then
		g.Shape = shape
	end
	g.Size = Vector3.new(0.05, 0.05, 0.05)
	g.CanCollide, g.CanQuery, g.CanTouch, g.Massless, g.CastShadow = false, false, false, true, false
	g.TopSurface, g.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	g.CFrame = torso.CFrame
	local w = Instance.new("Weld")
	w.Part0 = torso
	w.Part1 = g
	w.Parent = g
	g.Parent = folder
	return g, w
end

local function stopGhost(char: Model, key: string)
	local list = ghosts[char]
	local gh = list and list[key]
	if gh then
		list[key] = nil
		gh.folder:Destroy()
	end
end

-- grows a limb (or the head / the chest) on the body over `dur` seconds: the bone first (0 - 40 %), the flesh round it
-- (35 - 75 %), the skin last (70 - 100 %). It sits where the part sits on a body standing straight, fixed to the torso.
local function growGhost(char: Model, key: string, dur: number, metal: boolean)
	stopGhost(char, key)
	local torso = char:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") then
		return
	end
	local S = (typeof(char:GetAttribute("BodyScale")) == "number" and char:GetAttribute("BodyScale") or 1) :: number
	local folder = Instance.new("Folder")
	folder.Name = "Regrow_" .. key
	folder.Parent = char
	token += 1
	local my = token
	local list = ghosts[char] or {}
	ghosts[char] = list
	list[key] = { folder = folder, token = my }
	local skin = metal and Color3.fromRGB(196, 202, 212) or skinOf(char, key)
	local boneC = metal and STEEL or BONE
	local fleshC = metal and CABLE or FLESH
	local def = RigInfo.ByKey[key]
	-- where it grows from (in torso space), which way, how long, how thick
	local top: Vector3, len: number, thick: Vector3, round = Vector3.zero, 2, Vector3.new(1, 2, 1), false
	if def then
		top = def.torsoPivot + Vector3.new(0, def.kind == "Arm" and 0.5 or 0, 0)
		len = 2
		thick = Vector3.new(1, 2, 1)
	elseif key == "Head" then
		top = Vector3.new(0, 1, 0)
		len = 1.25
		thick = Vector3.new(1.25, 1.25, 1.25)
		round = true
	else -- Torso
		top = Vector3.new(0, 1, 0)
		len = 2
		thick = Vector3.new(2, 2, 1)
	end
	top *= S
	len *= S
	thick *= S
	local up = key == "Head" and 1 or -1 -- (a head grows up out of the neck, everything else down)
	local boneP, boneW = ghostPart(folder, torso, "GrowBone", boneC, Enum.Material.SmoothPlastic, round and Enum.PartType.Ball or nil)
	local knob, knobW = ghostPart(folder, torso, "GrowKnob", boneC, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	local fleshP, fleshW = ghostPart(folder, torso, "GrowFlesh", fleshC, metal and Enum.Material.Metal or Enum.Material.SmoothPlastic, round and Enum.PartType.Ball or nil)
	local skinP, skinW = ghostPart(folder, torso, "GrowSkin", skin, metal and Enum.Material.Metal or Enum.Material.SmoothPlastic, round and Enum.PartType.Ball or nil)
	if metal then
		skinP.Reflectance = 0.3
	end
	fleshP.Transparency = 1
	skinP.Transparency = 1
	local function along(k: number, maxLen: number): (number, CFrame)
		local l = math.max(0.05, maxLen * k)
		return l, CFrame.new(top + Vector3.new(0, up * l / 2, 0))
	end
	local function stage(t: number, a: number, b: number): number
		return math.clamp((t - a) / (b - a), 0, 1)
	end
	local t0 = os.clock()
	task.spawn(function()
		while folder.Parent and list[key] and list[key].token == my do
			local t = math.clamp((os.clock() - t0) / dur, 0, 1)
			-- the bone
			local kb = stage(t, 0, 0.4)
			if round then
				local d = math.max(0.05, thick.X * 0.78 * kb)
				boneP.Size = Vector3.new(d, d, d)
				boneW.C0 = CFrame.new(top + Vector3.new(0, up * thick.Y * 0.5, 0))
			else
				local l, at = along(kb, len)
				local w = math.min(thick.X, thick.Z) * 0.3
				boneP.Size = Vector3.new(key == "Torso" and thick.X * 0.25 or w, l, key == "Torso" and thick.Z * 0.25 or w)
				boneW.C0 = at
			end
			local kl, _ = along(kb, len)
			local d = math.min(thick.X, thick.Z) * (round and 0.25 or 0.42)
			knob.Size = Vector3.new(d, d, d)
			knobW.C0 = round and CFrame.new(top) or CFrame.new(top + Vector3.new(0, up * kl, 0))
			-- the flesh
			local kf = stage(t, 0.35, 0.75)
			fleshP.Transparency = kf <= 0 and 1 or 0.08
			if round then
				local dd = math.max(0.05, thick.X * 0.92 * kf)
				fleshP.Size = Vector3.new(dd, dd, dd)
				fleshW.C0 = boneW.C0
			else
				local l, at = along(kf, len * 0.98)
				fleshP.Size = Vector3.new(thick.X * 0.84, l, thick.Z * 0.84)
				fleshW.C0 = at
			end
			-- the skin
			local ks = stage(t, 0.7, 1)
			skinP.Transparency = ks <= 0 and 1 or (1 - ks) * 0.75
			if round then
				local dd = math.max(0.05, thick.X * (0.92 + 0.08 * ks))
				skinP.Size = Vector3.new(dd, dd, dd)
				skinW.C0 = boneW.C0
			else
				local l, at = along(ks, len)
				skinP.Size = Vector3.new(thick.X, l, thick.Z)
				skinW.C0 = at
			end
			if t >= 1 then
				break
			end
			task.wait(0.12)
		end
	end)
end

local function check(p: Player, char: Model, key: string)
	if not char.Parent or char:GetAttribute("Dead") or p.Character ~= char then
		return
	end
	local mine = timers[char] or {}
	timers[char] = mine
	local severed = char:GetAttribute("Severed_" .. key) == true
	local broken = char:GetAttribute("Broken_" .. key) == true
	if not severed and not broken then
		mine[key] = nil
		char:SetAttribute("RegrowAt_" .. key, nil)
		stopGhost(char, key)
		return
	end
	if mine[key] then
		return -- (already on its way)
	end
	local t = tierOf(p)
	local metal = metalArm(p, key)
	local can = (severed and (t >= 2 or metal)) or (not severed and broken and (t >= 1 or metal))
	if not can then
		return
	end
	token += 1
	local my = token
	mine[key] = my
	local dur = rng:NextNumber(Config.RegrowLimb[1], Config.RegrowLimb[2]) * ({ 1, 0.75, 0.5 })[math.max(1, t)]
	char:SetAttribute("RegrowAt_" .. key, workspace:GetServerTimeNow() + dur)
	if severed then
		pcall(growGhost, char, key, dur, metal) -- (v2.8.2) watch it grow: bone, flesh, skin
	end
	task.delay(dur, function()
		if mine[key] ~= my then
			stopGhost(char, key)
			return
		end
		mine[key] = nil
		char:SetAttribute("RegrowAt_" .. key, nil)
		stopGhost(char, key)
		if not char.Parent or char:GetAttribute("Dead") or p.Character ~= char then
			return
		end
		local t2 = tierOf(p)
		local metal2 = metalArm(p, key)
		if char:GetAttribute("Severed_" .. key) == true then
			if t2 >= 2 or metal2 then
				regrow(p, char, key, metal2)
			end
		elseif char:GetAttribute("Broken_" .. key) == true then
			if t2 >= 1 or metal2 then
				mend(char, key)
			end
		end
	end)
end

local function watch(p: Player, char: Model)
	for _, key in LIMBS do
		char:GetAttributeChangedSignal("Broken_" .. key):Connect(function()
			check(p, char, key)
		end)
		char:GetAttributeChangedSignal("Severed_" .. key):Connect(function()
			check(p, char, key)
		end)
		check(p, char, key)
	end
end

-- tier 3: the body grows back where it lies (true = the player comes back that way; the usual respawn is skipped)
local function core(p: Player, model: Model): boolean
	if model:GetAttribute("NoRegrowth") or tierOf(p) < 3 then
		return false
	end
	local mode = workspace:GetAttribute("Mode")
	if typeof(mode) == "string" and mode ~= "" and mode ~= "sandbox" then
		return false -- (a game mode decides who comes back where)
	end
	if os.clock() < (lastCore[p] or -1e9) + Config.RegrowCoreCooldown then
		return false
	end
	local lost = model:GetAttribute("Severed_Head") == true or model:GetAttribute("Broken_Head") == true
		or model:GetAttribute("Broken_Torso") == true
	if not lost then
		return false
	end
	local torso = model:FindFirstChild("Torso")
	if not torso or not torso:IsA("BasePart") or (torso.Position.Y < -150 and not Config.InPit(torso.Position)) then
		return false -- (gone into the void: nothing left to grow)
	end
	lastCore[p] = os.clock()
	local dur = rng:NextNumber(Config.RegrowCore[1], Config.RegrowCore[2])
	model:SetAttribute("RegrowUntil", workspace:GetServerTimeNow() + dur)
	-- (v2.8.2) you watch it grow back on the body where it lies: bone, flesh, skin
	local which = (model:GetAttribute("Severed_Head") == true or model:GetAttribute("Broken_Head") == true) and "Head" or "Torso"
	pcall(growGhost, model, which, dur, false)
	task.delay(dur, function()
		stopGhost(model, which)
		if not p.Parent or p.Character ~= model then
			return
		end
		local t = model:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and (t.Position.Y > -150 or Config.InPit(t.Position)) then
			-- (v2.8.2) the body is whole again IN THE POSE IT LIES IN, and gets up from there (no new body standing next to it)
			local pose: { [string]: CFrame } = {}
			for _, region in RigInfo.Regions do
				local name = RigInfo.RegionPart[region]
				local part = name and model:FindFirstChild(name)
				local def = RigInfo.ByKey[region]
				if model:GetAttribute("Severed_" .. region) == true or not part or not part:IsA("BasePart") then
					-- (cut off: it grows back where it belongs on the torso)
					if def then
						pose[name] = t.CFrame * CFrame.new(def.torsoPivot - def.limbPivot)
					elseif region == "Head" then
						pose["Head"] = t.CFrame * CFrame.new(0, 1.5, 0)
					end
				elseif name then
					pose[name] = part.CFrame
				end
			end
			regrowAt[p] = t.CFrame
			regrowPose[p] = pose
			heal(model, t)
		end
		deps.CharacterService.Spawn(p, true) -- (the old body goes: this is it, whole again)
	end)
	return true
end

function RegrowthService.Init(d: any)
	deps = d
	task.spawn(function()
		while true do
			task.wait(1)
			for _, p in Players:GetPlayers() do
				local ch = p.Character
				local t = tierOf(p)
				if ch and ch.Parent and not ch:GetAttribute("Dead") and t > 0 then
					local off = ch:GetAttribute("ChipsDisabled")
					if typeof(off) == "number" and off > workspace:GetServerTimeNow() then continue end
					for _, key in { "Head", "Torso", "LeftArm", "RightArm", "LeftLeg", "RightLeg" } do
						local hp = ch:GetAttribute("HP_" .. key)
						if typeof(hp) == "number" and hp > 0 and not ch:GetAttribute("Severed_" .. key) and not ch:GetAttribute("Broken_" .. key) then
							ch:SetAttribute("HP_" .. key, math.min(Config.LimbMaxHP, hp + ({ 2, 4, 7 })[t]))
						end
					end
					if t >= 2 then require(script.Parent.DamageService).StopBleeding(ch) end
					for _, key in LIMBS do check(p, ch, key) end
				end
			end
		end
	end)
	local prevSpawned = deps.CharacterService.OnSpawned
	deps.CharacterService.OnSpawned = function(p: Player, model: Model)
		if prevSpawned then
			prevSpawned(p, model)
		end
		watch(p, model)
	end
	local prevHook = deps.CharacterService.RespawnHook
	deps.CharacterService.RespawnHook = function(p: Player, model: Model): boolean
		if prevHook and prevHook(p, model) then
			return true
		end
		return core(p, model)
	end
	-- (v2.8.2) the new body takes the pose the old one lay in (and gets up from it: RegrowGetUp)
	local prevPose = deps.CharacterService.SpawnPose
	deps.CharacterService.SpawnPose = function(p: Player, model: Model)
		if prevPose then
			prevPose(p, model)
		end
		local pose = regrowPose[p]
		if not pose then
			return
		end
		regrowPose[p] = nil
		for name, cf in pose do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.CFrame = cf
			end
		end
		local hrp = model:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") and pose["Torso"] then
			hrp.CFrame = pose["Torso"]
		end
		model:SetAttribute("RegrowGetUp", true)
	end
	local prevOverride = deps.CharacterService.SpawnOverride
	deps.CharacterService.SpawnOverride = function(p: Player): CFrame?
		local cf = regrowAt[p]
		if cf then
			regrowAt[p] = nil
			return cf
		end
		return prevOverride and prevOverride(p) or nil
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			watch(p, p.Character)
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		lastCore[p] = nil
		regrowAt[p] = nil
		regrowPose[p] = nil
	end)
end

-- (tests)
RegrowthService._check = check
RegrowthService._core = core

return RegrowthService
