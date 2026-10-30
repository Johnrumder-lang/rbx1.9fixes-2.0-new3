--!nonstrict
-- SwordQuestService (v2.8): the STILLWATER quest - the ritual circle, the hole, the Pit below, three quests and the duel.
--   THE RITUAL (the circle of stones west of the spawn): light the 5 black candles (each burns Config.SwordCandleTime s), then
--     carry a body onto the altar and "Offer" it - the body burns away, the ground tears open (THE PIT, open for
--     Config.SwordHoleTime s) and a voice from below speaks. Whoever made the offering starts quest 1.
--   quest 1  BLOOD FOR THE DOOR : Config.SwordQ1Kills kills with a blade. They add up (dying does not reset them).
--   quest 2  THE DESCENT        : "Knock" at the altar (the door knows you now) and jump into the hole. Down there: the Hollows,
--            and on a small island across a bridge the bone altar with the sheath. Take it, then climb out at the pale
--            light in the south - alive, with the sheath on you. Die and the sheath is gone; take it again.
--   quest 3  THE PALE HEIR      : down again: VESPER CROWE waits (RivalService). Beat her and STILLWATER is yours - for good
--            (you spawn with it, sheathed at your hip; StillCutService) and you know the STILL CUT.
-- Anybody can fall into an open hole; the Pit is a dangerous place for everybody (Hollows, lava). Bodies thrown in go
-- down too. Stage and blade kills are saved (Persist: sword / swordProg). What the client shows comes from player
-- attributes: SwordStage (0..4), SwordProg, SwordGoal, SwordSheath, InPit, HasStillCut, Objective / ObjectiveText.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))

local SwordQuestService = {}

local deps: any = {}
local Remote: RemoteEvent

type St = { stage: number, prog: number, loaded: boolean }
local states: { [Player]: St } = {}

local site: Model? = nil
local pit: Model? = nil
local candles: { BasePart } = {}
local altar: BasePart? = nil
local hole: BasePart? = nil
local rims: { BasePart } = {}
local returnPos = Vector3.new(-300, 4, -40)
local pitCenter = Config.PitCenter
local arrivePos = pitCenter + Vector3.new(0, 4, 40)
local holeUntil = 0
local hollows: { Model } = {}
local lastBlade: { [Model]: { uid: number, t: number } } = setmetatable({}, { __mode = "k" }) :: any
local emptySince = 0
local rivalEmptySince = 0
local nextHollowAt = 0

local PIT_HALF = 175

local BLADE_CAUSES = { "Cut down by", "Chopped by", "Stabbed by", "Speared by", "Severed by", "Cut in the stillness" }

------------------------------------------------------------------------
-- state
------------------------------------------------------------------------

local function stOf(p: Player): St
	local st = states[p]
	if not st then
		st = { stage = 0, prog = 0, loaded = false }
		states[p] = st
	end
	return st
end

local function inPit(pos: Vector3): boolean
	local d = pos - pitCenter
	return math.abs(d.X) < PIT_HALF and math.abs(d.Z) < PIT_HALF and d.Y > -90 and d.Y < 240
end

local function torsoOf(m: Instance?): BasePart?
	local t = m and m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

local function playerInPit(p: Player): boolean
	local char = p.Character
	local t = torsoOf(char)
	return t ~= nil and not (char :: Model):GetAttribute("Dead") and inPit(t.Position)
end

local function sheathAltar(): BasePart?
	local a = pit and pit:FindFirstChild("SheathAltar", true)
	return (a and a:IsA("BasePart")) and a or nil
end

local function exitStone(): BasePart?
	local a = pit and pit:FindFirstChild("HellExitStone", true)
	return (a and a:IsA("BasePart")) and a or nil
end

-- where the beam on the screen points (TutorialClient draws the line)
local function objective(p: Player)
	local st = stOf(p)
	local here = playerInPit(p)
	local pos, text, name = nil, nil, nil
	if st.stage == 2 then
		if not here then
			pos, text, name = hole and hole.Position, "Knock at the altar and jump into the hole", "THE RITUAL CIRCLE"
		elseif not deps.StillCutService.CarriesSheath(p) then
			local a = sheathAltar()
			pos, text, name = a and a.Position, "Take the sheath from the bone altar", "THE BONE ALTAR"
		else
			local e = exitStone()
			pos, text, name = e and e.Position, "Climb out at the pale light - alive", "THE WAY OUT"
		end
	elseif st.stage == 3 and not here then
		pos, text, name = hole and hole.Position, "Knock at the altar and go down. He is waiting", "THE RITUAL CIRCLE"
	end
	p:SetAttribute("Objective", pos)
	p:SetAttribute("ObjectiveText", pos and text or nil)
	p:SetAttribute("ObjectiveName", pos and name or nil)
end

local function publish(p: Player)
	local st = stOf(p)
	p:SetAttribute("SwordStage", st.stage)
	p:SetAttribute("SwordProg", st.prog)
	p:SetAttribute("SwordGoal", st.stage == 1 and Config.SwordQ1Kills or 0)
	p:SetAttribute("HasStillCut", st.stage >= 4 or nil)
	p:SetAttribute("SwordSheath", (st.stage == 2 and deps.StillCutService.CarriesSheath(p)) or nil)
	objective(p)
end

local function save(p: Player)
	local st = stOf(p)
	local prof = deps.Persist.Get(p)
	if prof and st.loaded then
		prof.sword = st.stage
		prof.swordProg = st.prog
		deps.Persist.Dirty(p)
	end
end

local function setStage(p: Player, stage: number)
	local st = stOf(p)
	st.stage = stage
	if stage ~= 1 then
		st.prog = 0
	end
	save(p)
	publish(p)
end

local function note(p: Player, text: string, kind: string?)
	Remote:FireClient(p, "note", text, kind)
end

-- lines of his: to one player, or to everybody in the Pit (nil)
local function voice(key: string, to: Player?)
	local lines = Config.RivalLines[key]
	if typeof(lines) ~= "table" then
		return
	end
	local list = lines
	if key == "taunt" or key == "stillcut" then
		list = { lines[math.random(1, #lines)] }
	end
	if to then
		Remote:FireClient(to, "say", Config.RivalName, list)
		return
	end
	for _, p in Players:GetPlayers() do
		if playerInPit(p) then
			Remote:FireClient(p, "say", Config.RivalName, list)
		end
	end
end

------------------------------------------------------------------------
-- the ritual circle
------------------------------------------------------------------------

local function lit(c: BasePart): boolean
	local untilT = c:GetAttribute("LitUntil")
	return typeof(untilT) == "number" and workspace:GetServerTimeNow() < untilT
end

local function setFlame(c: BasePart, on: boolean)
	local f = c:FindFirstChild("CandleFlame")
	if on and not f then
		local flame = Instance.new("Part")
		flame.Name = "CandleFlame"
		flame.Shape = Enum.PartType.Ball
		flame.Size = Vector3.new(0.35, 0.55, 0.35)
		flame.Color = Color3.fromRGB(255, 120, 40)
		flame.Material = Enum.Material.Neon
		flame.Anchored = true
		flame.CanCollide = false
		flame.CanQuery = false
		flame.CanTouch = false
		flame.CastShadow = false
		flame.CFrame = c.CFrame * CFrame.new(0, c.Size.Y / 2 + 0.3, 0)
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 120, 50)
		light.Range = 10
		light.Brightness = 1.6
		light.Parent = flame
		local fire = Instance.new("Fire")
		fire.Size = 1.2
		fire.Heat = 4
		fire.Color = Color3.fromRGB(255, 110, 40)
		fire.SecondaryColor = Color3.fromRGB(120, 10, 10)
		fire.Parent = flame
		flame.Parent = c
	elseif not on and f then
		f:Destroy()
	end
end

local function allLit(): boolean
	if #candles == 0 then
		return false
	end
	for _, c in candles do
		if not lit(c) then
			return false
		end
	end
	return true
end

local function holeOpen(): boolean
	return os.clock() < holeUntil
end

local function openHole()
	holeUntil = os.clock() + Config.SwordHoleTime
	workspace:SetAttribute("PitOpen", workspace:GetServerTimeNow() + Config.SwordHoleTime)
	if hole then
		hole.Transparency = 0
		deps.GoreService.Sound("groundCrack", hole, 1.5)
		deps.GoreService.Sound("thunder", hole, 0.8)
		deps.GoreService.FX({ t = "pitopen", p = hole.Position })
	end
	for _, r in rims do
		r.Transparency = 0
	end
end

local function closeHole()
	holeUntil = 0
	workspace:SetAttribute("PitOpen", nil)
	if hole then
		hole.Transparency = 1
	end
	for _, r in rims do
		r.Transparency = 1
	end
end

local function offer(p: Player)
	if not altar then
		return
	end
	if not allLit() then
		note(p, "THE CANDLES. ALL FIVE MUST BURN.")
		return
	end
	local body = deps.OwnershipService.HeldBody(p)
	local bt = torsoOf(body)
	if not body or not bt then
		note(p, "THE ALTAR WANTS A BODY. CARRY ONE HERE.")
		return
	end
	if (bt.Position - altar.Position).Magnitude > 14 then
		return
	end
	deps.OwnershipService.ReleaseAll(p)
	-- the body burns away (a living player is sacrificed)
	deps.GoreService.FX({ t = "offering", p = altar.Position + Vector3.new(0, 2, 0) })
	deps.GoreService.Sound("fireWhoosh", altar, 1.4)
	local victim = Players:GetPlayerFromCharacter(body)
	if victim then
		body:SetAttribute("ForceKill", true)
		deps.DamageService.Kill(body, "Offered on the altar by " .. p.DisplayName)
	else
		pcall(deps.GoreService.Gibs, bt.Position, 6, 18)
		body:Destroy()
	end
	for _, c in candles do
		c:SetAttribute("LitUntil", nil)
		setFlame(c, false)
	end
	openHole()
	local st = stOf(p)
	if st.stage == 0 then
		setStage(p, 1)
		voice("ritual", p)
		note(p, "QUEST 1/3  -  BLOOD FOR THE DOOR", "new")
	else
		note(p, "THE GROUND OPENS.")
	end
end

local function knock(p: Player)
	local st = stOf(p)
	if st.stage < 2 then
		note(p, st.stage == 1 and "THE DOOR DOES NOT ANSWER YET. BLOOD FIRST." or "THE DOOR DOES NOT KNOW YOU. LIGHT THE CANDLES AND MAKE AN OFFERING.")
		return
	end
	if holeOpen() then
		note(p, "IT IS OPEN. JUMP.")
		return
	end
	openHole()
	note(p, "THE DOOR KNOWS YOU. IT OPENS.")
end

------------------------------------------------------------------------
-- the Pit
------------------------------------------------------------------------

local function descend(p: Player)
	local char = p.Character
	if not char or char:GetAttribute("Dead") or char:GetAttribute("PitFalling") then
		return
	end
	char:SetAttribute("PitFalling", true)
	Remote:FireClient(p, "fall")
	task.delay(0.6, function()
		if p.Character == char and char.Parent then
			deps.MapService.Teleport(p, arrivePos + Vector3.new(math.random(-6, 6), 0, math.random(-4, 4)))
		end
		task.delay(1.5, function()
			if char.Parent then
				char:SetAttribute("PitFalling", nil)
			end
		end)
	end)
end

local function spawnHollow(at: Vector3)
	local weapons = { "blade", "axe", "machete", "spear", "katana" }
	local m = deps.NPCService.Spawn("melee", CFrame.new(at), nil, {
		weapon = weapons[math.random(1, #weapons)],
		name = "Hollow",
		hellborn = true,
		colors = {
			Head = Color3.fromRGB(58, 40, 40),
			Torso = Color3.fromRGB(36, 22, 24),
			Arms = Color3.fromRGB(58, 40, 40),
			Legs = Color3.fromRGB(28, 18, 20),
		},
	})
	if not m then
		return
	end
	m:SetAttribute("Hellborn", true)
	m:SetAttribute("Hollow", true)
	local head = m:FindFirstChild("Head")
	local mask = m:FindFirstChild("Mask")
	if mask then
		mask:Destroy()
	end
	if head and head:IsA("BasePart") then
		local face = head:FindFirstChild("face")
		if face and face:IsA("Decal") then
			face.Transparency = 1
		end
		local function bit(name: string, size: Vector3, off: CFrame, color: Color3, material: Enum.Material)
			local b = Instance.new("Part")
			b.Name = name
			b.Size = size
			b.Color = color
			b.Material = material
			b.CanCollide = false
			b.CanQuery = false
			b.CanTouch = false
			b.Massless = true
			b.CFrame = head.CFrame * off
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = b
			w.Parent = b
			b.Parent = m
		end
		for _, sx in { -1, 1 } do
			bit("Horn", Vector3.new(0.22, 0.9, 0.22), CFrame.new(sx * 0.45, 0.85, 0.05) * CFrame.Angles(0, 0, math.rad(-sx * 24)), Color3.fromRGB(28, 24, 22), Enum.Material.Slate)
			bit("HornTip", Vector3.new(0.14, 0.45, 0.14), CFrame.new(sx * 0.66, 1.4, 0.05) * CFrame.Angles(0, 0, math.rad(-sx * 46)), Color3.fromRGB(20, 18, 16), Enum.Material.Slate)
			bit("Eye", Vector3.new(0.2, 0.1, 0.05), CFrame.new(sx * 0.24, 0.12, -0.61), Color3.fromRGB(255, 120, 30), Enum.Material.Neon)
		end
		bit("Maw", Vector3.new(0.6, 0.12, 0.05), CFrame.new(0, -0.28, -0.61), Color3.fromRGB(255, 60, 20), Enum.Material.Neon)
	end
	table.insert(hollows, m)
end

local function spawnPoints(): { Vector3 }
	local out = {}
	if pit then
		for _, d in pit:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 10) == "HellSpawn_" then
				table.insert(out, d.Position + Vector3.new(0, 3, 0))
			end
		end
	end
	return out
end

local function pitBodies(): { Model }
	local out = {}
	for _, p in Players:GetPlayers() do
		if playerInPit(p) then
			table.insert(out, p.Character :: Model)
		end
	end
	return out
end

local function tickPit()
	-- who is down there
	local anyone = false
	local questers = {}
	for _, p in Players:GetPlayers() do
		local here = playerInPit(p)
		local was = p:GetAttribute("InPit") == true
		if here ~= was then
			p:SetAttribute("InPit", here or nil)
			publish(p)
			if here then
				local st = stOf(p)
				if st.stage == 2 and not deps.StillCutService.CarriesSheath(p) then
					voice("pit", p)
				end
			end
		end
		if here then
			anyone = true
			if stOf(p).stage == 3 then
				table.insert(questers, p)
			end
		end
	end
	local now = os.clock()
	-- the Hollows
	for i = #hollows, 1, -1 do
		local m = hollows[i]
		if not m.Parent or m:GetAttribute("Dead") then
			table.remove(hollows, i)
		end
	end
	if anyone then
		emptySince = now
		-- (v2.8.1) fewer of them, one at a time every few seconds - and none at all while the Pale Heir fights (the ones
		-- left crumble when she comes)
		local duel = deps.RivalService.Active() ~= nil
		local want = duel and 0 or Config.SwordHollows
		if duel and #hollows > 0 then
			for _, m in hollows do
				if m.Parent and not m:GetAttribute("Dead") then
					local t = m:FindFirstChild("Torso")
					if t and t:IsA("BasePart") then
						deps.GoreService.FX({ t = "blink", a = t.Position, b = t.Position + Vector3.new(0, 12, 0) })
					end
					m:Destroy()
				end
			end
			table.clear(hollows)
		end
		if #hollows < want and now >= nextHollowAt then
			local pts = spawnPoints()
			if #pts > 0 then
				spawnHollow(pts[math.random(1, #pts)])
				nextHollowAt = now + Config.SwordHollowEvery
			end
		end
	elseif now - emptySince > 30 then
		for _, m in hollows do
			if m.Parent then
				m:Destroy()
			end
		end
		table.clear(hollows)
	end
	-- the Pale Heir
	local r = deps.RivalService.Active()
	if #questers > 0 then
		rivalEmptySince = now
		if not r then
			local spot = pit and pit:FindFirstChild("HellRival", true)
			local at = (spot and spot:IsA("BasePart")) and spot.Position + Vector3.new(0, 3, 0) or pitCenter + Vector3.new(0, 4, -30)
			local qt = torsoOf(questers[1].Character)
			local look = qt and Vector3.new(qt.Position.X, at.Y, qt.Position.Z) or (at + Vector3.new(0, 0, 1))
			if (look - at).Magnitude < 0.5 then
				look = at + Vector3.new(0, 0, 1)
			end
			r = deps.RivalService.Spawn(CFrame.lookAt(at, look))
			if r then
				deps.GoreService.FX({ t = "blink", a = at + Vector3.new(0, 30, 0), b = at })
				for _, q in questers do
					voice("intro", q)
				end
			end
		end
	elseif r and now - rivalEmptySince > 25 then
		deps.RivalService.Despawn()
	end
end

local function onDefeated(_rival: Model, by: Player?)
	task.wait(2.5)
	for _, p in Players:GetPlayers() do
		local st = stOf(p)
		local char = p.Character
		local alive = char and not char:GetAttribute("Dead")
		if st.stage == 3 and (playerInPit(p) or (by == p and alive)) then
			setStage(p, 4)
			pcall(deps.RewardService.GrantTitle, p, "stillwater")
			if alive then
				p:SetAttribute("StillwaterSummoned", nil)
			end
			Remote:FireClient(p, "learned")
		end
	end
end

local function climbOut(p: Player)
	local st = stOf(p)
	local carries = deps.StillCutService.CarriesSheath(p)
	deps.MapService.Teleport(p, returnPos + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4)))
	if st.stage == 2 and carries then
		setStage(p, 3)
		voice("q2done", p)
		note(p, "QUEST 3/3  -  THE PALE HEIR", "new")
	end
	task.delay(1, function()
		publish(p)
	end)
end

local function takeSheath(p: Player)
	local st = stOf(p)
	if st.stage ~= 2 then
		note(p, st.stage >= 3 and "IT IS ALREADY YOURS." or "IT DOES NOT ANSWER TO YOU.")
		return
	end
	if deps.StillCutService.CarriesSheath(p) then
		note(p, "YOU HAVE IT. NOW GET OUT.")
		return
	end
	if deps.StillCutService.GiveSheath(p) then
		deps.GoreService.Sound("questDing", sheathAltar() or Vector3.zero, 1)
		voice("sheath", p)
		publish(p)
	end
end

------------------------------------------------------------------------
-- quest 1: blade kills
------------------------------------------------------------------------

local function bladeHit(model: Model, _region: string, _dmg: number, opts: any)
	local by = opts and opts.attacker
	if typeof(by) ~= "Instance" or not by:IsA("Player") then
		return
	end
	local cause = typeof(opts.cause) == "string" and opts.cause or ""
	for _, c in BLADE_CAUSES do
		if string.sub(cause, 1, #c) == c then
			lastBlade[model] = { uid = by.UserId, t = os.clock() }
			return
		end
	end
end

local function onKill(victim: Model, killer: Player?)
	if not killer or not killer.Parent then
		return
	end
	local st = stOf(killer)
	if st.stage ~= 1 then
		return
	end
	if victim:GetAttribute("IsDummy") or not (Players:GetPlayerFromCharacter(victim) or victim:GetAttribute("IsNPC")) then
		return
	end
	local rec = lastBlade[victim]
	if not rec or rec.uid ~= killer.UserId or os.clock() - rec.t > Config.KillCreditTime + 1 then
		return
	end
	st.prog += 1
	if st.prog >= Config.SwordQ1Kills then
		setStage(killer, 2)
		voice("q1done", killer)
		note(killer, "QUEST 2/3  -  THE DESCENT", "new")
	else
		save(killer)
		publish(killer)
		note(killer, string.format("BLADE KILL %d / %d", st.prog, Config.SwordQ1Kills))
	end
end

------------------------------------------------------------------------
-- admin / setup
------------------------------------------------------------------------

function SwordQuestService.Admin(p: Player, what: string)
	if not Items.IsOwner(p) then
		return
	end
	if what == "give" then
		setStage(p, 4)
		p:SetAttribute("StillwaterSummoned", nil)
		Remote:FireClient(p, "learned")
	elseif what == "reset" then
		setStage(p, 0)
		deps.StillCutService.ClearGear(p)
	elseif what == "pit" then
		descend(p)
	elseif what == "rival" then
		local spot = pit and pit:FindFirstChild("HellRival", true)
		local at = (spot and spot:IsA("BasePart")) and spot.Position + Vector3.new(0, 3, 0) or pitCenter + Vector3.new(0, 4, -30)
		deps.RivalService.Spawn(CFrame.new(at))
		rivalEmptySince = os.clock() + 60
	elseif what == "open" then
		openHole()
	end
end

function SwordQuestService.Stage(p: Player): number
	return stOf(p).stage
end

local function prompt(parent: BasePart, action: string, object: string, hold: number, key: Enum.KeyCode?, offset: number?): ProximityPrompt
	local pr = Instance.new("ProximityPrompt")
	pr.ActionText = action
	pr.ObjectText = object
	pr.HoldDuration = hold
	pr.MaxActivationDistance = 10
	pr.RequiresLineOfSight = false
	if key then
		pr.KeyboardKeyCode = key
	end
	if offset then
		pr.UIOffset = Vector2.new(0, offset)
	end
	pr.Parent = parent
	return pr
end

local function setupWorld()
	local map = workspace:WaitForChild("Map", 30)
	if not map then
		return
	end
	site = map:FindFirstChild("RitualSite") :: Model?
	pit = map:FindFirstChild("ThePit") :: Model?
	if site then
		for _, d in site:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "RitualCandle" then
					table.insert(candles, d)
				elseif d.Name == "RitualAltar" then
					altar = d
				elseif d.Name == "HellHole" then
					hole = d
				elseif d.Name == "HellRim" then
					table.insert(rims, d)
				elseif d.Name == "RitualReturn" then
					returnPos = d.Position + Vector3.new(0, 3, 0)
				end
			end
		end
	end
	if pit then
		local c = pit:FindFirstChild("PitCenter", true)
		if c and c:IsA("BasePart") then
			pitCenter = c.Position
		end
		local a = pit:FindFirstChild("HellArrive", true)
		if a and a:IsA("BasePart") then
			arrivePos = a.Position + Vector3.new(0, 3, 0)
		end
	end
	for _, c in candles do
		local pr = prompt(c, "Light the candle", "Black candle", 0.6, nil, nil)
		pr.MaxActivationDistance = 7
		pr.Triggered:Connect(function()
			c:SetAttribute("LitUntil", workspace:GetServerTimeNow() + Config.SwordCandleTime)
			setFlame(c, true)
			deps.GoreService.Sound("ignite", c, 0.8)
			task.delay(Config.SwordCandleTime + 0.2, function()
				if not lit(c) then
					setFlame(c, false)
				end
			end)
		end)
	end
	if altar then
		prompt(altar, "Offer the body", "Altar (carry a body)", 1.2, Enum.KeyCode.E, nil).Triggered:Connect(offer)
		prompt(altar, "Knock", "Altar", 0.8, Enum.KeyCode.R, 70).Triggered:Connect(knock)
	end
	closeHole()
	local sa = sheathAltar()
	if sa then
		-- the sheath that waits there (only to look at; the real one is given to you)
		local show = deps.PropBuilders.sheath(sa.CFrame * CFrame.new(0, sa.Size.Y / 2 + 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)))
		show.Name = "WaitingSheath"
		for _, d in show:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		show:SetAttribute("Item", nil)
		show:SetAttribute("Sheath", nil)
		show.Parent = sa.Parent
		prompt(sa, "Take the sheath", "Bone altar", 1, nil, nil).Triggered:Connect(takeSheath)
	end
	local ex = exitStone()
	if ex then
		prompt(ex, "Climb out", "The pale light", 0.8, nil, nil).Triggered:Connect(climbOut)
	end
	-- the lava burns
	if pit then
		for _, d in pit:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "HellLava" then
				d.Touched:Connect(function(hit)
					local body = deps.DamageService.BodyOf(hit)
					if body and not body:GetAttribute("Dead") then
						body:SetAttribute("ForceKill", true)
						deps.DamageService.Kill(body, "Burned in the Pit")
						pcall(deps.FireService.SetOnFire, body, 8, nil)
					end
				end)
			end
		end
	end
end

local function loadInto(p: Player)
	local prof = deps.Persist.Wait(p, 30)
	if not p.Parent then
		return
	end
	local st = stOf(p)
	if prof then
		st.stage = math.clamp(prof.sword or 0, 0, 4)
		st.prog = prof.swordProg or 0
	end
	st.loaded = true
	publish(p)

end

function SwordQuestService.Init(d: any)
	deps = d
	Remote = d.Remote
	deps.StillCutService.Knows = function(p: Player): boolean
		return stOf(p).stage >= 4
	end
	deps.StillCutService.Owns = function(p: Player): boolean
		return stOf(p).stage >= 4
	end
	local lastSummon = {}
	Remote.OnServerEvent:Connect(function(p, action)
		if action ~= "summon" or stOf(p).stage < 4 then return end
		if os.clock() - (lastSummon[p] or -100) < 2 then return end
		lastSummon[p] = os.clock()
		if p:GetAttribute("StillwaterSummoned") then
			deps.StillCutService.ClearGear(p)
			p:SetAttribute("StillwaterSummoned", nil)
		else
			local ch = p.Character
			if not ch or ch:GetAttribute("Dead") then return end
			deps.StillCutService.GiveGear(p)
			p:SetAttribute("StillwaterSummoned", true)
		end
	end)
	Players.PlayerRemoving:Connect(function(p) lastSummon[p] = nil end)
	deps.RivalService.Targets = pitBodies
	deps.RivalService.Say = function(key: string)
		voice(key, nil)
	end
	deps.RivalService.OnDefeated = onDefeated
	table.insert(deps.DamageService.AfterDamage, bladeHit)
	local prevKill = deps.DamageService.OnKill
	deps.DamageService.OnKill = function(model: Model, killer: Player?, state: any)
		if prevKill then
			prevKill(model, killer, state)
		end
		pcall(onKill, model, killer)
	end
	-- the Pale Heir and the Hollows only go for the people down there (and he always for the closest)
	local prevGoal = deps.NPCService.ModeGoal
	deps.NPCService.ModeGoal = function(model: Model): any
		if model:GetAttribute("Hellborn") then
			local mt = torsoOf(model)
			local best, bestD = nil, math.huge
			for _, b in pitBodies() do
				local t = torsoOf(b)
				if mt and t then
					local dd = (t.Position - mt.Position).Magnitude
					if dd < bestD then
						best, bestD = b, dd
					end
				end
			end
			if best then
				return { kind = "chase", target = best }
			end
			return { kind = "idle" }
		end
		return prevGoal and prevGoal(model) or nil
	end
	Players.PlayerAdded:Connect(function(p)
		task.spawn(loadInto, p)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(loadInto, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		states[p] = nil
	end)
	task.spawn(setupWorld)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		-- the hole: whoever is in it falls (bodies thrown in too)
		if holeOpen() and hole then
			local hp = hole.Position
			local r = hole.Size.Y / 2 - 0.3 -- (a flat cylinder: its round face is Y x Z)
			for body in deps.DamageService.Bodies() do
				local t = torsoOf(body)
				if t and body.Parent then
					local flat = Vector3.new(t.Position.X - hp.X, 0, t.Position.Z - hp.Z).Magnitude
					if flat < r and t.Position.Y < hp.Y + 4.5 then
						local p = Players:GetPlayerFromCharacter(body)
						if p then
							descend(p)
						elseif not body:GetAttribute("PitFalling") then
							body:SetAttribute("PitFalling", true)
							body:PivotTo(CFrame.new(arrivePos + Vector3.new(math.random(-8, 8), 2, math.random(-8, 8))))
							task.delay(2, function()
								if body.Parent then
									body:SetAttribute("PitFalling", nil)
								end
							end)
						end
					end
				end
			end
		elseif hole and hole.Transparency < 1 then
			closeHole()
		end
		-- candles that burned down
		for _, c in candles do
			if c:FindFirstChild("CandleFlame") and not lit(c) then
				setFlame(c, false)
			end
		end
		local ok, err = pcall(tickPit)
		if not ok then
			warn("[Ragdoll] pit:", err)
		end
	end)
end

return SwordQuestService
