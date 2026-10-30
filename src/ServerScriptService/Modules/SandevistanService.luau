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

return SandevistanService
