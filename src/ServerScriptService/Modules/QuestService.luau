--!nonstrict
-- QuestService (v2.0): the Steel Ball Master (Config.SpinMasterName) behind the red brick house and her three quests.
-- She is a tsundere: sharp-tongued, never admits she cares (QuestClient makes her look away, blush and grumble).
-- (v2.0) Her name and everything she says are in Config (SpinMasterName / SpinMasterDialog / SpinMasterQuips).
-- (v2.0) She only talks to you once you touched a SPIN CIRCLE: now and then (Config.SpinCircleEvery, 1 in
-- Config.SpinCircleOdds) one appears somewhere near the players - a notification, no marker. The first player who
-- has not had it yet and steps in gets it: the Spin fills their body, and it is gone. Kept with the quest stage.
--   stage 0  talk to her: quest 1
--   stage 1  quest 1: Config.QuestKills kills with steel balls (players and bots; a dummy does not count) without
--            dying - die and the count starts over
--   stage 2  back to her: quest 2
--   stage 3  quest 2: throw a ball and pick it up again, Config.QuestThrows times in one life
--   stage 4  back to her: quest 3
--   stage 5  quest 3: find the SPIN in the construction site (only you see it while you are on this quest; it hums).
--            Touch it: a short cutscene - your hand reaches for it, your whole body goes limp, floats up and spins
--   stage 6  back to her: she gives you the Spin
--   stage 7  you have the Spin (SteelBallService: green balls, a yellow trail, the one hit spins, the ball comes back)
-- The stage is kept in a DataStore (Config.QuestStoreName). What the client shows comes from player attributes:
-- QuestStage, QuestProg, QuestGoal, HasSpin. Admins can give themselves the Spin / start over (admin menu).

local Players = game:GetService("Players")
local SaveGate = require(script.Parent:WaitForChild("SaveGate"))
local ProgressEpoch = require(script.Parent:WaitForChild("ProgressEpoch"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Modules = script.Parent
local DamageService = require(Modules:WaitForChild("DamageService"))
local BodyFactory = require(Modules:WaitForChild("BodyFactory"))
local SteelBallService = require(Modules:WaitForChild("SteelBallService"))

local QuestRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Quest") :: RemoteEvent

local QuestService = {}

QuestService.NPC_NAME = Config.SpinMasterName

type QState = { stage: number, prog: number, offered: number?, dirty: boolean, loaded: boolean, circle: boolean }

local data: { [Player]: QState } = {}
local store: DataStore? = nil
local npcRoot: BasePart? = nil
local relic: BasePart? = nil
local circle: BasePart? = nil -- (v2.0) the Spin Circle that is out there right now
local circleUntil = 0

local GOALS = { [1] = function()
	return Config.QuestKills
end, [3] = function()
	return Config.QuestThrows
end }

local function goalOf(stage: number): number
	local g = GOALS[stage]
	return g and g() or 0
end

local function publish(p: Player)
	local st = data[p]
	if not st then
		return
	end
	p:SetAttribute("QuestStage", st.stage)
	p:SetAttribute("QuestProg", st.prog)
	p:SetAttribute("QuestGoal", goalOf(st.stage))
	p:SetAttribute("HasSpin", st.stage >= 7 or nil)
	p:SetAttribute("SpinCircle", st.circle or nil)
end

local function notify(p: Player, text: string, kind: string?)
	QuestRemote:FireClient(p, "notify", text, kind or "info")
end

function QuestService.HasSpin(p: Player): boolean
	local st = data[p]
	return st ~= nil and st.stage >= 7
end

local function setStage(p: Player, stage: number)
	local st = data[p]
	if not st then
		return
	end
	st.stage = stage
	st.prog = 0
	st.offered = nil
	st.dirty = true
	publish(p)
	SteelBallService.Refresh(p)
end

------------------------------------------------------------------------
-- saving
------------------------------------------------------------------------

local function key(p: Player): string
	return ProgressEpoch.Key(p.UserId, "q_")
end

local function load(p: Player)
	local st = data[p]
	if not st then
		return
	end
	if store and p.UserId > 0 then
		local ok, saved = pcall(function()
			return (store :: DataStore):GetAsync(key(p))
		end)
		if ok and typeof(saved) == "table" and typeof(saved.stage) == "number" and data[p] == st and st.stage == 0 then
			local s = math.clamp(math.floor(saved.stage), 0, 7)
			-- (a quest that was running starts over: its count was for one life)
			st.stage = s
			st.prog = 0
			-- (v2.0) the Spin Circle; whoever already started the quests before the circles existed had met her anyway
			st.circle = st.circle or saved.circle == true or s >= 1
		end
	end
	st.loaded = true
	publish(p)
end

local function save(p: Player)
	if not SaveGate.CanSave() then
		return -- (v2.8) a private server saves nothing
	end
	local st = data[p]
	if not st or not st.dirty or not st.loaded or not store or p.UserId <= 0 then
		return
	end
	st.dirty = false
	local stage = st.stage
	local touched = st.circle
	pcall(function()
		(store :: DataStore):SetAsync(key(p), { stage = stage, circle = touched, v = 2 })
	end)
end

------------------------------------------------------------------------
-- what the master says
------------------------------------------------------------------------

-- (v2.0) from Config.SpinMasterDialog: {kills} {throws} {prog} filled in
local function fill(text: string, prog: number): string
	local out = string.gsub(text, "{(%a+)}", function(k)
		if k == "kills" then
			return tostring(Config.QuestKills)
		elseif k == "throws" then
			return tostring(Config.QuestThrows)
		elseif k == "prog" then
			return tostring(prog)
		end
		return "{" .. k .. "}"
	end)
	return out
end

local function line(stage: number, prog: number): (string, string?, string)
	local d = Config.SpinMasterDialog[math.clamp(stage, 0, 7)] or Config.SpinMasterDialog[7]
	local text = typeof(d) == "table" and typeof(d.text) == "string" and d.text or "..."
	local accept = typeof(d) == "table" and typeof(d.accept) == "string" and d.accept or nil
	local close = typeof(d) == "table" and typeof(d.close) == "string" and d.close or "Close"
	return fill(text, prog), accept, close
end

local function near(p: Player): boolean
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	return npcRoot ~= nil and t ~= nil and t:IsA("BasePart") and not c:GetAttribute("Dead")
		and (t.Position - (npcRoot :: BasePart).Position).Magnitude <= Config.QuestTalkRange
end

local function talk(p: Player)
	local st = data[p]
	if not st or not near(p) then
		return
	end
	if not st.circle then
		-- (v2.0) no Spin in you: she does not even talk to you (a speech bubble, nothing more)
		local list = Config.SpinMasterDialog.noSpin
		local text = (typeof(list) == "table" and #list > 0) and list[math.random(1, #list)] or "Hmph."
		QuestRemote:FireClient(p, "snub", text)
		return
	end
	local text, accept, close = line(st.stage, st.prog)
	st.offered = accept and st.stage or nil
	QuestRemote:FireClient(p, "dialog", { name = QuestService.NPC_NAME, text = text, accept = accept, close = close, stage = st.stage })
end

local function accept(p: Player)
	local st = data[p]
	if not st or st.offered ~= st.stage or not near(p) then
		return
	end
	local s = st.stage
	if s == 0 then
		setStage(p, 1)
		notify(p, string.format("NEW QUEST: %d steel ball kills without dying", Config.QuestKills), "new")
	elseif s == 2 then
		setStage(p, 3)
		notify(p, string.format("NEW QUEST: throw and pick up a steel ball %d times in one life", Config.QuestThrows), "new")
	elseif s == 4 then
		setStage(p, 5)
		notify(p, "NEW QUEST: find the SPIN in the construction site", "new")
	elseif s == 6 then
		setStage(p, 7)
		QuestRemote:FireClient(p, "learned")
		notify(p, "YOU LEARNED THE SPIN", "done")
	end
end

------------------------------------------------------------------------
-- progress
------------------------------------------------------------------------

local function lifeLost(p: Player)
	local st = data[p]
	if not st or st.prog <= 0 then
		return
	end
	if st.stage == 1 then
		st.prog = 0
		publish(p)
		notify(p, string.format("You died - the steel ball kills start over (0/%d)", Config.QuestKills), "fail")
	elseif st.stage == 3 then
		st.prog = 0
		publish(p)
		notify(p, string.format("You died - the throws start over (0/%d)", Config.QuestThrows), "fail")
	end
end

local function onKill(victim: Model, killer: Player?, state: any)
	local victimPlayer = state and state.player or nil
	if victimPlayer then
		lifeLost(victimPlayer)
	end
	if not killer or killer == victimPlayer then
		return
	end
	local st = data[killer]
	if not st or st.stage ~= 1 then
		return
	end
	local counts = victimPlayer ~= nil or victim:GetAttribute("IsNPC") == true
	if not counts or not SteelBallService.RecentHit(victim, killer) then
		return
	end
	st.prog += 1
	publish(killer)
	if st.prog >= Config.QuestKills then
		setStage(killer, 2)
		notify(killer, "QUEST DONE - go back to the " .. Config.SpinMasterTitle, "done")
	else
		notify(killer, string.format("Steel ball kill %d/%d", st.prog, Config.QuestKills), "step")
	end
end

local function onPickup(p: Player, _item: Model)
	local st = data[p]
	if not st or st.stage ~= 3 then
		return
	end
	st.prog += 1
	publish(p)
	if st.prog >= Config.QuestThrows then
		setStage(p, 4)
		notify(p, "QUEST DONE - go back to the " .. Config.SpinMasterTitle, "done")
	elseif st.prog % 5 == 0 then
		notify(p, string.format("Throws picked up again: %d/%d", st.prog, Config.QuestThrows), "step")
	end
end

local function touchRelic(p: Player)
	local c = p.Character
	if not c or not relic then
		return
	end
	setStage(p, 6)
	-- (nothing hurts you during the cutscene)
	c:SetAttribute("SpawnProtect", workspace:GetServerTimeNow() + Config.CutsceneTime + 0.5)
	QuestRemote:FireClient(p, "cutscene", (relic :: BasePart).Position)
end

------------------------------------------------------------------------
-- (v2.0) the Spin Circle
------------------------------------------------------------------------

local circleParams = RaycastParams.new()
circleParams.FilterType = Enum.RaycastFilterType.Exclude
circleParams.IgnoreWater = false

-- somewhere on the ground near one of these points: flat, dry, room to stand
local function circleSpot(near: { Vector3 }, minD: number, maxD: number): Vector3?
	if #near == 0 then
		return nil
	end
	local ex = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ex, p.Character)
		end
	end
	for _, n in { "FX", "Corpses", "SpawnedProps", "NPCs", "Gibs", "Blood", "DragPuppets" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ex, f)
		end
	end
	circleParams.FilterDescendantsInstances = ex
	local box = OverlapParams.new()
	box.FilterType = Enum.RaycastFilterType.Exclude
	box.FilterDescendantsInstances = ex
	box.RespectCanCollide = true
	for _ = 1, 50 do
		local base = near[math.random(1, #near)]
		local a = math.random() * math.pi * 2
		local d = minD + math.random() * (maxD - minD)
		local from = Vector3.new(base.X + math.cos(a) * d, base.Y + 10, base.Z + math.sin(a) * d)
		local hit = workspace:Raycast(from, Vector3.new(0, -90, 0), circleParams)
		if hit and hit.Normal.Y > 0.85 and hit.Material ~= Enum.Material.Water and (hit.Instance:IsA("Terrain") or hit.Instance.CanCollide) then
			local pos = hit.Position
			local blocked = workspace:GetPartBoundsInBox(CFrame.new(pos + Vector3.new(0, 3.3, 0)), Vector3.new(4, 5.6, 4), box)
			if #blocked == 0 then
				return pos
			end
		end
	end
	return nil
end

local function removeCircle(why: string?)
	local c = circle
	circle = nil
	if c then
		c:Destroy()
		if why then
			QuestRemote:FireAllClients("circle", why)
		end
	end
end

local function spawnCircle(pos: Vector3)
	removeCircle(nil)
	local c = Instance.new("Part")
	c.Name = "SpinCircle"
	c.Anchored = true
	c.CanCollide = false
	c.CanQuery = false
	c.CanTouch = false
	c.Transparency = 1
	c.Size = Vector3.new(Config.SpinCircleRadius * 2, 0.2, Config.SpinCircleRadius * 2)
	c.CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0))
	c:SetAttribute("SpinCircle", true)
	c.Parent = workspace
	circle = c
	circleUntil = os.clock() + Config.SpinCircleLifetime
	QuestRemote:FireAllClients("circle", "spawn") -- (a notification for everybody - where it is, nobody is told)
end

local function alivePositions(): { Vector3 }
	local out = {}
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local t = c and c:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and not c:GetAttribute("Dead") and t.Position.Y > -100 then
			table.insert(out, t.Position)
		end
	end
	return out
end

-- the first player without it who steps in: the Spin fills their body (everybody sees it) and the circle is gone
local function claimCircle(p: Player)
	local st = data[p]
	local c = circle
	if not st or not c then
		return
	end
	circle = nil
	st.circle = true
	st.dirty = true
	publish(p)
	task.spawn(save, p)
	QuestRemote:FireAllClients("spinfill", p.Character, c.Position, p.DisplayName, p.UserId)
	c:Destroy()
end

function QuestService.SpawnCircleNear(p: Player): boolean
	local c = p.Character
	local t = c and c:FindFirstChild("Torso")
	if not t or not t:IsA("BasePart") then
		return false
	end
	local pos = circleSpot({ t.Position }, 10, 28)
	if pos then
		spawnCircle(pos)
		return true
	end
	return false
end

------------------------------------------------------------------------
-- the master herself (v2.0: a plain blocky dummy - the same body as every Roblox avatar - in her colours, with her
-- hair and her eyes: honey-blonde drill curls with green bows, bangs, an ahoge, a steel-ball hairpin; arms crossed.
-- The face is drawn on a SurfaceGui so the clients can change it)
------------------------------------------------------------------------

local SKIN = Color3.fromRGB(246, 214, 190)
local HAIR = Color3.fromRGB(236, 192, 112)
local HAIR_DARK = Color3.fromRGB(198, 146, 78)
local HAIR_LIGHT = Color3.fromRGB(250, 224, 158)
local GOLD = Color3.fromRGB(222, 182, 82)
local RIBBON = Color3.fromRGB(36, 150, 86)
local RIBBON_DARK = Color3.fromRGB(22, 104, 58)
local STEEL = Color3.fromRGB(160, 166, 176)

local FABRIC = Enum.Material.Fabric
local SMOOTH = Enum.Material.SmoothPlastic
local METAL = Enum.Material.Metal
local CYL_UP = CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder's axis is X: this stands it up along Y)

-- her crossed arms (blocky R6 arms turned at the shoulder: forward, then in across the chest; the right one higher)
QuestService.ARMS = {
	{ name = "Right Arm", sx = 1, pitch = math.rad(52), yaw = math.rad(68), fwd = -0.45 },
	{ name = "Left Arm", sx = -1, pitch = math.rad(40), yaw = math.rad(-62), fwd = -0.62 },
}

local function deco(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- a part that turns with her head (QuestClient keeps it where it is relative to the head)
local function headDeco(model: Model, head: BasePart, name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = deco(model, name, size, head.CFrame * off, color, mat, shape)
	p:SetAttribute("OnHead", true)
	return p
end

local function frame(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, corner: number?, rot: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	if corner then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(corner, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

-- her face: big green eyes (a darker top, two shines, a heavy upper lash with a flick at the corner, a fine lower
-- lash), slanted brows, a tiny nose, a small pout with one fang, hatched blush. QuestClient blinks, moves the irises,
-- frowns the brows and turns the blush up (the names below are what it looks for).
local function buildFace(model: Model, head: BasePart)
	local plate = headDeco(model, head, "FacePlate", Vector3.new(1.1, 0.8, 0.05), CFrame.new(0, -0.02, -0.64), SKIN, SMOOTH)
	plate.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.6
	gui.ClipsDescendants = false
	gui.Parent = plate
	local px = function(x: number, y: number): UDim2
		return UDim2.fromOffset(x, y)
	end
	local LASH = Color3.fromRGB(52, 30, 26)
	for _, side in { -1, 1 } do
		local cx = 55 + side * 21
		local eye = frame(gui, side < 0 and "EyeL" or "EyeR", px(26, 32), px(cx, 45), Color3.new(1, 1, 1), 0.45)
		eye.BackgroundTransparency = 1
		local open = frame(eye, "Open", UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.fromRGB(255, 255, 255), 0.45)
		local iris = frame(open, "Iris", UDim2.fromScale(0.72, 0.84), UDim2.fromScale(0.5, 0.56), Color3.fromRGB(52, 172, 100), 0.5)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(20, 92, 52), Color3.fromRGB(120, 230, 150))
		g.Parent = iris
		frame(iris, "Pupil", UDim2.fromScale(0.46, 0.5), UDim2.fromScale(0.5, 0.56), Color3.fromRGB(14, 36, 22), 0.5)
		frame(iris, "Shine", UDim2.fromScale(0.34, 0.26), UDim2.fromScale(0.32, 0.3), Color3.new(1, 1, 1), 0.5)
		frame(iris, "Shine2", UDim2.fromScale(0.16, 0.12), UDim2.fromScale(0.7, 0.74), Color3.new(1, 1, 1), 0.5)
		-- the upper lash: heavy, with a flick out at the outer corner; a fine lower lash
		frame(open, "Lash", UDim2.new(1.18, 0, 0, 5), UDim2.fromScale(0.5, 0.03), LASH, 0.5, side * -8)
		frame(open, "LashFlick", px(9, 4), UDim2.new(0.5 + side * 0.62, 0, 0.1, 0), LASH, 0.5, side * -38)
		frame(open, "LowerLash", UDim2.new(0.6, 0, 0, 2), UDim2.fromScale(0.5 + side * 0.08, 0.98), LASH, 0.5)
		local closed = frame(eye, "Closed", UDim2.new(1.08, 0, 0, 4), UDim2.fromScale(0.5, 0.62), LASH, 0.5, side * -6)
		closed.Visible = false
		frame(gui, side < 0 and "BrowL" or "BrowR", px(19, 3), px(cx - side, 26), HAIR_DARK, 0.5, side * -14)
		local blush = frame(gui, side < 0 and "BlushL" or "BlushR", px(17, 7), px(55 + side * 27, 60), Color3.fromRGB(255, 120, 140), 1)
		blush.BackgroundTransparency = 0.7
		for k = -1, 1 do
			local h = frame(blush, "Hatch", px(2, 7), UDim2.new(0.5, k * 5, 0.5, 0), Color3.fromRGB(230, 80, 110), 0.5, 25)
			h.BackgroundTransparency = 0.35
		end
	end
	frame(gui, "Nose", px(2, 2), px(55, 58), Color3.fromRGB(214, 160, 140), 0.5)
	local mouth = frame(gui, "Mouth", px(10, 3), px(55, 67), Color3.fromRGB(150, 50, 60), 0.5, -4)
	frame(mouth, "Fang", px(3, 3), UDim2.new(0.75, 0, 1, 1), Color3.new(1, 1, 1), nil, 45)
end

local function buildMaster(spot: BasePart)
	local model = BodyFactory.BuildR6({
		name = "SteelBallMaster",
		humanoid = false,
		-- (v2.0) the same colours as the ragdoll dummy that falls over: blue torso, yellow arms, green legs
		colors = {
			Head = SKIN,
			Torso = BodyFactory.DEFAULT_COLORS.Torso,
			Arms = BodyFactory.DEFAULT_COLORS.Arms,
			Legs = BodyFactory.DEFAULT_COLORS.Legs,
		},
	})
	model:PivotTo(spot.CFrame)
	local torso = model:FindFirstChild("Torso") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	local face = head:FindFirstChild("face")
	if face then
		face:Destroy() -- (her own eyes: buildFace)
	end
	-- (v2.0) a normal blocky dummy: the R6 body as it is, only the arms crossed in front of the chest
	local cf = torso.CFrame
	for _, a in QuestService.ARMS do
		local arm = model:FindFirstChild(a.name)
		if arm and arm:IsA("BasePart") then
			arm.CFrame = cf * CFrame.new(a.sx * 1, 0.5, a.fwd) * CFrame.Angles(0, a.yaw, 0) * CFrame.Angles(a.pitch, 0, 0) * CFrame.new(a.sx * 0.5, -0.5, 0)
		end
	end

	-- hair: a full crown, the mass at the back, bangs in strands (lighter streaks), long locks framing the face, an
	-- ahoge, a steel-ball hairpin; two long drill curls on green bows (all of it turns with the head)
	headDeco(model, head, "HairTop", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 0.3, 0.12), HAIR, SMOOTH, Enum.PartType.Ball)
	headDeco(model, head, "HairBack", Vector3.new(1.46, 1.46, 1.46), CFrame.new(0, -0.1, 0.3), HAIR, SMOOTH, Enum.PartType.Ball)
	headDeco(model, head, "HairNape", Vector3.new(1.1, 1.1, 1.1), CFrame.new(0, -0.52, 0.42), HAIR_DARK:Lerp(HAIR, 0.6), SMOOTH, Enum.PartType.Ball)
	local bangs = { { -0.56, 0.52 }, { -0.38, 0.36 }, { -0.2, 0.3 }, { 0.0, 0.26 }, { 0.2, 0.32 }, { 0.38, 0.38 }, { 0.56, 0.5 } } -- (they end above the eyes)
	for i, bg in bangs do
		local x, len = bg[1], bg[2]
		local col = (i % 3 == 0) and HAIR_LIGHT or HAIR
		local strand = CFrame.new(x, 0.52 - len / 2, -0.63 + x * x * 0.35) * CFrame.Angles(math.rad(14), x * 0.6, x * 0.45)
		headDeco(model, head, "Bang", Vector3.new(0.24, len, 0.1), strand, col, SMOOTH)
		headDeco(model, head, "BangTip", Vector3.new(0.12, 0.12, 0.09), strand * CFrame.new(0, -len / 2, 0) * CFrame.Angles(0, 0, math.rad(45)), col, SMOOTH)
	end
	for _, sx in { -1, 1 } do
		local lock = CFrame.new(sx * 0.68, -0.12, -0.22) * CFrame.Angles(0.08, 0, sx * 0.1)
		headDeco(model, head, "SideLock", Vector3.new(0.18, 0.86, 0.32), lock, HAIR, SMOOTH)
		headDeco(model, head, "SideLockTip", Vector3.new(0.26, 0.16, 0.16), lock * CFrame.new(0, -0.48, 0) * CYL_UP, HAIR_LIGHT, SMOOTH, Enum.PartType.Cylinder)
		headDeco(model, head, "Earring", Vector3.new(0.12, 0.12, 0.12), CFrame.new(sx * 0.64, -0.36, 0.04), GOLD, METAL, Enum.PartType.Ball)
	end
	headDeco(model, head, "Ahoge", Vector3.new(0.07, 0.38, 0.07), CFrame.new(0.08, 1.06, -0.02) * CFrame.Angles(0, 0, -0.55), HAIR, SMOOTH)
	headDeco(model, head, "AhogeTip", Vector3.new(0.06, 0.24, 0.06), CFrame.new(0.26, 1.26, -0.02) * CFrame.Angles(0, 0, 0.55), HAIR, SMOOTH)
	headDeco(model, head, "HairPinBar", Vector3.new(0.34, 0.06, 0.06), CFrame.new(-0.5, 0.56, -0.42) * CFrame.Angles(0, 0.5, 0.4), GOLD, METAL)
	local pin = headDeco(model, head, "HairPinBall", Vector3.new(0.2, 0.2, 0.2), CFrame.new(-0.62, 0.62, -0.36), STEEL, METAL, Enum.PartType.Ball)
	pin.Reflectance = 0.3
	for _, sx in { -1, 1 } do
		-- (TailPivot: where the curl hangs from, in head space - QuestClient swings the curl round it)
		local base = CFrame.new(sx * 0.82, 0.28, 0.36)
		local function tailPart(name: string, size: Vector3, off: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?)
			local t = headDeco(model, head, name, size, off, color, mat, shape)
			t:SetAttribute("Tail", sx)
			t:SetAttribute("TailPivot", base.Position)
			return t
		end
		tailPart("TailKnot", Vector3.new(0.5, 0.5, 0.5), base, HAIR_DARK, SMOOTH, Enum.PartType.Ball)
		-- the bow: two loops up and out, two ends hanging, a knot with a gold bead
		for _, lz in { -1, 1 } do
			tailPart("Ribbon", Vector3.new(0.12, 0.4, 0.34), base * CFrame.new(sx * 0.14, 0.24, lz * 0.2) * CFrame.Angles(lz * 0.75, 0, sx * -0.35), RIBBON, FABRIC)
			tailPart("RibbonInner", Vector3.new(0.14, 0.22, 0.16), base * CFrame.new(sx * 0.17, 0.2, lz * 0.17) * CFrame.Angles(lz * 0.75, 0, sx * -0.35), RIBBON_DARK, FABRIC)
			tailPart("RibbonEnd", Vector3.new(0.1, 0.46, 0.15), base * CFrame.new(sx * 0.2, -0.2, lz * 0.12) * CFrame.Angles(lz * -0.4, 0, sx * 0.25), RIBBON, FABRIC)
		end
		tailPart("RibbonKnot", Vector3.new(0.22, 0.22, 0.22), base * CFrame.new(sx * 0.22, 0.1, 0), RIBBON_DARK, FABRIC, Enum.PartType.Ball)
		tailPart("RibbonBead", Vector3.new(0.1, 0.1, 0.1), base * CFrame.new(sx * 0.33, 0.1, 0), GOLD, METAL, Enum.PartType.Ball)
		-- the drill: coils that wind down and get thinner, each with a ridge at an angle
		local coils = 11
		for k = 1, coils do
			local f = (k - 1) / (coils - 1)
			local size = 0.66 - 0.4 * f
			local ang = k * 1.9
			local r = 0.05 + 0.06 * f
			local off = Vector3.new(sx * (0.1 + 0.42 * f) + math.cos(ang) * r, -0.3 - k * 0.25, 0.08 + math.sin(ang) * r)
			local c = base * CFrame.new(off)
			tailPart("Drill", Vector3.new(size, size, size), c, (k % 2 == 0) and HAIR or HAIR_LIGHT:Lerp(HAIR, 0.5), SMOOTH, Enum.PartType.Ball)
			tailPart("DrillRidge", Vector3.new(0.09, size * 1.06, size * 1.06), c * CFrame.Angles(0, ang, 0) * CFrame.Angles(0.42, 0, 0) * CYL_UP, HAIR_DARK, SMOOTH, Enum.PartType.Cylinder)
		end
		tailPart("DrillTip", Vector3.new(0.18, 0.18, 0.18), base * CFrame.new(sx * 0.54, -0.3 - (coils + 0.7) * 0.25, 0.1), HAIR_DARK, SMOOTH, Enum.PartType.Ball)
	end
	buildFace(model, head)

	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = d.Name == "Torso" or d.Name == "Left Leg" or d.Name == "Right Leg"
		end
	end
	model:SetAttribute("QuestGiver", true)
	-- talk: F
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "QuestPrompt"
	prompt.ActionText = "Talk"
	prompt.ObjectText = Config.SpinMasterTitle
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = torso
	model.Parent = spot.Parent
	npcRoot = torso
	-- her sign
	local sign = spot.Parent and spot.Parent:FindFirstChild("MasterSign")
	if sign and sign:IsA("BasePart") then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "SignText"
		gui.Face = Enum.NormalId.Right -- (she faces +X, away from the house)
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0.3
		gui.Parent = sign
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Sarpanch
		t.TextScaled = true
		t.TextColor3 = Color3.fromRGB(40, 26, 14)
		t.Text = "STEEL BALL SCHOOL\nno idiots allowed"
		t.Parent = gui
	end
end

------------------------------------------------------------------------

-- the admin menu: "spin" = give me the Spin, "reset" = start the questline over
function QuestService.Admin(p: Player, what: string)
	if not data[p] then
		return
	end
	if what == "spin" then
		setStage(p, 7)
		QuestRemote:FireClient(p, "learned")
		notify(p, "YOU HAVE THE SPIN (admin)", "done")
	elseif what == "circle" then
		if not QuestService.SpawnCircleNear(p) then
			notify(p, "No free ground for a Spin Circle here", "fail")
		end
	elseif what == "reset" then
		setStage(p, 0)
		notify(p, "Questline reset - talk to the " .. Config.SpinMasterTitle .. " behind the red house", "info")
	end
end

function QuestService.Init()
	local ok, result = pcall(function()
		return ProgressEpoch.Store(Config.QuestStoreName)
	end)
	if ok then
		store = result
	end
	local map = workspace:FindFirstChild("Map")
	local spot = map and map:FindFirstChild("QuestGiverSpot", true)
	if spot and spot:IsA("BasePart") then
		buildMaster(spot)
	else
		warn("[Ragdoll] no QuestGiverSpot in the map")
	end
	local r = map and map:FindFirstChild("SpinRelic", true)
	relic = (r and r:IsA("BasePart")) and r or nil

	SteelBallService.HasSpin = QuestService.HasSpin
	SteelBallService.OnPickup = onPickup
	local prevKill = DamageService.OnKill
	DamageService.OnKill = function(victim: Model, killer: Player?, state)
		if prevKill then
			prevKill(victim, killer, state)
		end
		onKill(victim, killer, state)
	end

	QuestRemote.OnServerEvent:Connect(function(p, action)
		if action == "talk" then
			talk(p)
		elseif action == "accept" then
			accept(p)
		end
	end)

	local function added(p: Player)
		if data[p] then
			return
		end
		data[p] = { stage = 0, prog = 0, dirty = false, loaded = false, circle = false }
		publish(p)
		task.spawn(load, p)
	end
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		data[p] = nil
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			save(p)
		end
	end)

	-- (v2.0) a new map: a circle out there is gone
	workspace:GetAttributeChangedSignal("MapLoaded"):Connect(function()
		removeCircle("gone")
	end)
	-- the Spin in the construction site: touched by whoever is on quest 3; saving now and then
	-- (v2.0) the Spin Circle: a roll every Config.SpinCircleEvery s, touched by the first player without it
	task.spawn(function()
		local acc = 0
		local nextRoll = os.clock() + Config.SpinCircleEvery
		while true do
			local dt = task.wait(0.2)
			acc += dt
			local now = os.clock()
			if now >= nextRoll then
				nextRoll = now + Config.SpinCircleEvery
				if not circle and math.random(1, math.max(1, Config.SpinCircleOdds)) == 1 then
					local pos = circleSpot(alivePositions(), Config.SpinCircleMinDist, Config.SpinCircleMaxDist)
					if pos then
						spawnCircle(pos)
					end
				end
			end
			local cp = circle
			if cp then
				if now > circleUntil then
					removeCircle("gone")
				else
					for p, st in data do
						if not st.circle then
							local c = p.Character
							local t = c and c:FindFirstChild("Torso")
							if t and t:IsA("BasePart") and not c:GetAttribute("Dead") then
								local d = t.Position - cp.Position
								if Vector2.new(d.X, d.Z).Magnitude <= Config.SpinCircleRadius and d.Y > -2 and d.Y < 5 then
									claimCircle(p)
									break
								end
							end
						end
					end
				end
			end
			local rp = relic
			if rp then
				for p, st in data do
					if st.stage == 5 then
						local c = p.Character
						local t = c and c:FindFirstChild("Torso")
						if t and t:IsA("BasePart") and not c:GetAttribute("Dead") and (t.Position - rp.Position).Magnitude <= Config.RelicTouchRadius then
							touchRelic(p)
						end
					end
				end
			end
			if acc > 20 then
				acc = 0
				for p in data do
					task.spawn(save, p)
				end
			end
		end
	end)
end

return QuestService
