--!nonstrict
-- ReplayClient (v2.8 / v2.8.2): the hospital's replay chair. When somebody plugs in, their kill records play - FULL
-- SCREEN for the one in the chair (they relive it), on the wall screen for everybody else in the room.
-- (v2.8.2) The records are the game's own recording (ReplayService on the server): every body as it looked (clothes,
-- hair, armour, implants, the gun in the hand), the cars, the killer's own camera, the shots, the blood and the blasts.
-- The place round the kill is copied from this machine's own map, so it looks like the game because it IS the game.
--   Cyber remote:  "replaystart" (who, how many, screen)  the jack goes in: static, NEURAL LINK
--                  "replay" (who, i, n, record id, screen) one record (nil: NO RECORDS)
--                  "replayend" (who, screen)              END OF RECORD, the link drops
--   Replay remote: "clip" (meta)                          who, victim, the actors, the shots..., how many chunks
--                  "clipdata" (id, chunk, buffer)         the frames, a second at a time (ReplayCodec)
-- And this machine tells the server where its camera looks, 10 times a second (ReplayCam).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local Config = require(Shared:WaitForChild("Config"))
local ReplayCodec = require(Shared:WaitForChild("ReplayCodec"))
local UI = require(script.Parent:WaitForChild("UI"))

local ReplayClient = {}

local player = Players.LocalPlayer
local GREEN = Color3.fromRGB(80, 255, 140)
local RED = Color3.fromRGB(255, 60, 60)
local ENV_RADIUS = 150
local MAX_ENV = 2200
local WAIT_DATA = 2.6 -- s to wait for a record's data before playing what is there

type Display = { root: Instance, bg: Frame, vp: ViewportFrame, title: TextLabel, rec: TextLabel, static: Frame, info: TextLabel, clock: TextLabel, full: boolean }
local displays: { Display } = {}
local token = 0
local clips: { [string]: { meta: any?, chunks: { [number]: buffer }, got: number } } = {}

local okCF = ReplayCodec.OkCF

local function makeDisplay(parent: Instance, full: boolean): Display
	local bg = UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(4, 6, 8), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = parent })
	local vp = UI.make("ViewportFrame", {
		BackgroundColor3 = Color3.fromRGB(150, 178, 205), BorderSizePixel = 0,
		Position = full and UDim2.fromScale(0, 0) or UDim2.fromOffset(10, 44), Size = full and UDim2.fromScale(1, 1) or UDim2.new(1, -20, 1, -54),
		Ambient = Color3.fromRGB(150, 150, 160), LightColor = Color3.fromRGB(255, 250, 240), LightDirection = Vector3.new(-0.4, -1, -0.3),
		Visible = false, Parent = bg,
	})
	local title = UI.label({ Text = "", TextSize = full and 30 or 26, TextColor3 = GREEN, TextStrokeTransparency = full and 0.4 or 1,
		Position = UDim2.fromOffset(full and 28 or 12, full and 20 or 6), Size = UDim2.new(1, -40, 0, 34), ZIndex = 3, Parent = bg })
	local rec = UI.label({ Text = "REC", TextSize = 22, TextColor3 = RED, AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, full and -28 or -14, 0, full and 22 or 8), Size = UDim2.fromOffset(80, 28), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Visible = false, Parent = bg })
	local clock = UI.label({ Text = "", TextSize = full and 22 or 18, TextColor3 = GREEN, AnchorPoint = Vector2.new(1, 1), TextStrokeTransparency = full and 0.5 or 1,
		Position = UDim2.new(1, full and -28 or -14, 1, full and -20 or -8), Size = UDim2.fromOffset(160, 26), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = bg })
	local info = UI.label({ Text = "", TextSize = full and 40 or 34, TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -40, 0, 80), TextWrapped = true, ZIndex = 4, Parent = bg })
	-- static: thin bright lines that jump about
	local static = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 5, Visible = false, Parent = bg })
	for i = 1, 18 do
		UI.make("Frame", { BackgroundColor3 = i % 3 == 0 and Color3.new(1, 1, 1) or Color3.fromRGB(120, 255, 170), BackgroundTransparency = 0.6,
			BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 2), Position = UDim2.fromScale(0, i / 19), ZIndex = 5, Parent = static })
	end
	-- scanlines over everything (the old CRT look)
	for i = 0, 23 do
		UI.make("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.86, BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromScale(0, i / 24), ZIndex = 6, Parent = bg })
	end
	return { root = parent, bg = bg, vp = vp, title = title, rec = rec, static = static, info = info, clock = clock, full = full }
end

local function clearDisplays()
	for _, d in displays do
		if d.root and d.root.Parent then
			d.root:Destroy()
		end
	end
	displays = {}
end

-- the one in the chair sees it full screen; everybody else on the wall screen
local function openDisplays(by: number, screen: Instance?)
	clearDisplays()
	if typeof(screen) ~= "Instance" then
		local map = workspace:FindFirstChild("Map")
		screen = map and map:FindFirstChild("ReplayScreen", true)
	end
	if by == player.UserId then
		local g = UI.make("ScreenGui", { Name = "NeuralLink", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, Parent = player:WaitForChild("PlayerGui") })
		table.insert(displays, makeDisplay(g, true))
	elseif typeof(screen) == "Instance" and screen:IsA("BasePart") then
		local old = screen:FindFirstChild("Replay")
		if old then
			old:Destroy()
		end
		local g = Instance.new("SurfaceGui")
		g.Name = "Replay"
		g.Face = Enum.NormalId.Front
		g.CanvasSize = Vector2.new(800, 480)
		g.LightInfluence = 0
		g.Brightness = 1.4
		g.MaxDistance = 90
		g.Adornee = screen
		g.Parent = player:WaitForChild("PlayerGui")
		table.insert(displays, makeDisplay(g, false))
	end
end

local function staticBurst(seconds: number)
	local t0 = os.clock()
	task.spawn(function()
		while os.clock() - t0 < seconds do
			for _, d in displays do
				d.static.Visible = true
				for _, b in d.static:GetChildren() do
					if b:IsA("Frame") then
						b.Position = UDim2.fromScale(0, math.random())
						b.Size = UDim2.new(1, 0, 0, math.random(1, 6))
						b.BackgroundTransparency = 0.35 + math.random() * 0.6
					end
				end
			end
			task.wait(0.04)
		end
		for _, d in displays do
			d.static.Visible = false
		end
	end)
end

local function setText(field: string, text: string)
	for _, d in displays do
		(d :: any)[field].Text = text
	end
end

------------------------------------------------------------------------
-- building the scene
------------------------------------------------------------------------

local KEEP_CHILD = { SpecialMesh = true, BlockMesh = true, CylinderMesh = true, FileMesh = true, Decal = true, Texture = true, SurfaceAppearance = true }

local function bare(c: Instance)
	for _, d in c:GetDescendants() do
		if not KEEP_CHILD[d.ClassName] then
			pcall(function()
				d:Destroy()
			end)
		end
	end
end

-- the sky and the light of the place (day, night, the Pit)
local function lightUp(vp: ViewportFrame, center: Vector3)
	local clock = Lighting.ClockTime
	local day = math.clamp(1 - math.abs(clock - 13) / 7, 0, 1)
	local sky = Color3.fromRGB(22, 26, 44):Lerp(Color3.fromRGB(150, 182, 220), day)
	local amb = Color3.fromRGB(70, 74, 92):Lerp(Color3.fromRGB(165, 165, 172), day)
	if Config.InPit and Config.InPit(center) then
		sky = Color3.fromRGB(46, 10, 8)
		amb = Color3.fromRGB(120, 60, 50)
	end
	vp.BackgroundColor3 = sky
	vp.Ambient = amb
	vp.LightColor = Color3.fromRGB(255, 248, 236):Lerp(Color3.fromRGB(150, 160, 200), 1 - day)
	local sun = Lighting:GetSunDirection()
	vp.LightDirection = sun.Y > 0 and -sun or Vector3.new(-0.4, -1, -0.3)
end

-- the map round the kill, copied from this machine's own world
local function buildEnv(vp: ViewportFrame, center: Vector3, my: number)
	local map = workspace:FindFirstChild("Map")
	if not map then
		return
	end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = { map }
	local ok, parts = pcall(function()
		return workspace:GetPartBoundsInRadius(center, ENV_RADIUS, op)
	end)
	if not ok then
		return
	end
	local list = {}
	for _, p in parts do
		if p:IsA("BasePart") and p.Transparency < 0.95 and not p:IsA("Terrain") then
			table.insert(list, { p = p, score = (p.Position - center).Magnitude - p.Size.Magnitude * 0.6 })
		end
	end
	table.sort(list, function(a, b)
		return a.score < b.score
	end)
	for i = 1, math.min(MAX_ENV, #list) do
		if my ~= token then
			return
		end
		local okc, c = pcall(function()
			return list[i].p:Clone()
		end)
		if okc and c then
			bare(c)
			c.Anchored = true
			c.Parent = vp
		end
		if i % 300 == 0 then
			task.wait()
		end
	end
end

type Piece = { part: BasePart, slot: number, off: CFrame, t: number, head: boolean }

-- the bodies and cars of the record, from the copies the server made at the moment of the kill
local function buildActors(vp: ViewportFrame, meta: any): { Piece }
	local pieces: { Piece } = {}
	local liveFolder = ReplicatedStorage:WaitForChild("ReplayLive", 2)
	local folder = liveFolder and liveFolder:WaitForChild(meta.id, 1.5)
	if not folder then
		return pieces
	end
	local base = 0
	for i, kind in meta.kinds do
		local m = folder:FindFirstChild("A" .. i)
		if m then
			for _, src in m:GetChildren() do
				if src:IsA("BasePart") then
					local r = src:GetAttribute("R")
					local o = src:GetAttribute("O")
					if typeof(r) == "number" and typeof(o) == "CFrame" then
						local c = src:Clone()
						c.Parent = vp
						local t = src:GetAttribute("T")
						table.insert(pieces, { part = c, slot = base + r, off = o, t = typeof(t) == "number" and t or 0, head = src:GetAttribute("H") == true })
					end
				end
			end
		end
		base += kind == "car" and 1 or 6
	end
	return pieces
end

------------------------------------------------------------------------
-- shots, blood, blasts
------------------------------------------------------------------------

type Fx = { parts: { BasePart }, t0: number, life: number, step: (number) -> () }

local function spawnFx(vp: ViewportFrame, e: any, list: { Fx })
	local now = os.clock()
	if e.k == "shot" and typeof(e.a) == "Vector3" and typeof(e.b) == "Vector3" then
		local len = (e.b - e.a).Magnitude
		if len < 0.1 then
			return
		end
		local tr = Instance.new("Part")
		tr.Anchored = true
		tr.Material = Enum.Material.Neon
		tr.Color = Color3.fromRGB(255, 230, 150)
		tr.Size = Vector3.new(0.12, 0.12, len)
		tr.CFrame = CFrame.lookAt((e.a + e.b) / 2, e.b)
		tr.Parent = vp
		local fl = Instance.new("Part")
		fl.Anchored = true
		fl.Shape = Enum.PartType.Ball
		fl.Material = Enum.Material.Neon
		fl.Color = Color3.fromRGB(255, 200, 90)
		fl.Size = Vector3.new(0.9, 0.9, 0.9)
		fl.CFrame = CFrame.new(e.a)
		fl.Parent = vp
		table.insert(list, { parts = { tr, fl }, t0 = now, life = 0.09, step = function(k)
			tr.Transparency = k
			fl.Transparency = math.min(1, k * 2)
		end })
	elseif e.k == "flash" and typeof(e.a) == "Vector3" then
		local fl = Instance.new("Part")
		fl.Anchored = true
		fl.Shape = Enum.PartType.Ball
		fl.Material = Enum.Material.Neon
		fl.Color = Color3.fromRGB(255, 200, 90)
		fl.Size = Vector3.new(0.9, 0.9, 0.9)
		fl.CFrame = CFrame.new(e.a)
		fl.Parent = vp
		table.insert(list, { parts = { fl }, t0 = now, life = 0.06, step = function(k)
			fl.Transparency = k
		end })
	elseif e.k == "blood" and typeof(e.a) == "Vector3" then
		local drops = {}
		local vels = {}
		local d = typeof(e.b) == "Vector3" and e.b or Vector3.yAxis
		if d.Magnitude < 1e-3 then
			d = Vector3.yAxis
		end
		for i = 1, math.clamp(math.floor((tonumber(e.n) or 6) / 2), 3, 9) do
			local p = Instance.new("Part")
			p.Anchored = true
			p.Shape = Enum.PartType.Ball
			p.Material = Enum.Material.SmoothPlastic
			p.Color = Color3.fromRGB(120 + math.random(0, 30), 8, 10)
			local s = 0.18 + math.random() * 0.2
			p.Size = Vector3.new(s, s, s)
			p.CFrame = CFrame.new(e.a)
			p.Parent = vp
			drops[i] = p
			vels[i] = d.Unit * (8 + math.random() * 10) + Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5) * 9
		end
		table.insert(list, { parts = drops, t0 = now, life = 0.7, step = function(k)
			local t = k * 0.7
			for i, p in drops do
				p.CFrame = CFrame.new(e.a + vels[i] * t + Vector3.new(0, -0.5 * 60 * t * t, 0))
				p.Transparency = math.max(0, k * 1.3 - 0.3)
			end
		end })
	elseif e.k == "boom" and typeof(e.a) == "Vector3" then
		local r = math.clamp(tonumber(e.n) or 6, 1, 40)
		local b = Instance.new("Part")
		b.Anchored = true
		b.Shape = Enum.PartType.Ball
		b.Material = Enum.Material.Neon
		b.Color = Color3.fromRGB(255, 150, 50)
		b.CFrame = CFrame.new(e.a)
		b.Size = Vector3.one
		b.Parent = vp
		local smoke = Instance.new("Part")
		smoke.Anchored = true
		smoke.Shape = Enum.PartType.Ball
		smoke.Material = Enum.Material.SmoothPlastic
		smoke.Color = Color3.fromRGB(40, 38, 36)
		smoke.CFrame = CFrame.new(e.a)
		smoke.Size = Vector3.one
		smoke.Transparency = 1
		smoke.Parent = vp
		table.insert(list, { parts = { b, smoke }, t0 = now, life = 1.2, step = function(k)
			local fire = math.clamp(k / 0.4, 0, 1)
			b.Size = Vector3.one * (1 + fire * r * 2)
			b.Transparency = 0.1 + fire * 0.9
			local s = math.clamp((k - 0.15) / 0.85, 0, 1)
			smoke.Size = Vector3.one * (r * (1.2 + s * 1.4))
			smoke.CFrame = CFrame.new(e.a + Vector3.new(0, s * r * 0.8, 0))
			smoke.Transparency = 0.35 + s * 0.65
		end })
	end
end

------------------------------------------------------------------------
-- one record
------------------------------------------------------------------------

local function waitForClip(id: string, my: number): any
	local t0 = os.clock()
	while os.clock() - t0 < WAIT_DATA do
		if my ~= token then
			return nil
		end
		local c = clips[id]
		if c and c.meta and c.got >= (c.meta.chunks or 1) then
			return c
		end
		task.wait(0.05)
	end
	return clips[id]
end

local function playRecord(by: number, i: number, n: number, id: any, my: number)
	local who = Players:GetPlayerByUserId(by)
	local whoName = who and who.DisplayName or "?"
	if typeof(id) ~= "string" then
		setText("title", string.upper(whoName))
		setText("info", "NO RECORDS\nNO KILLS IN THIS LIFE ON THIS SERVER")
		return
	end
	setText("info", "LOADING MEMORY " .. i .. " / " .. n)
	staticBurst(0.4)
	local started = os.clock()
	local clip = waitForClip(id, my)
	if my ~= token then
		return
	end
	if not clip or not clip.meta then
		setText("info", "SIGNAL LOST")
		return
	end
	local meta = clip.meta
	local frames: { ReplayCodec.Frame } = {}
	for c = 1, meta.chunks or 1 do
		local b = clip.chunks[c]
		if b then
			for _, f in ReplayCodec.Decode(b, meta.slots) do
				table.insert(frames, f)
			end
		end
	end
	if #frames < 2 then
		setText("info", "SIGNAL LOST")
		return
	end
	-- the scene, once per display
	local scenes = {}
	for _, d in displays do
		d.vp:ClearAllChildren()
		d.title.Text = string.format("%s  -  KILL %d / %d: %s", string.upper(whoName), i, n, string.upper(tostring(meta.victim)))
		local cam = Instance.new("Camera")
		cam.FieldOfView = 70
		cam.Parent = d.vp
		d.vp.CurrentCamera = cam
		lightUp(d.vp, meta.center)
		buildEnv(d.vp, meta.center, my)
		if my ~= token then
			return
		end
		local pieces = buildActors(d.vp, meta)
		table.insert(scenes, { d = d, cam = cam, pieces = pieces, fx = {}, fired = {} })
	end
	-- the server gives everybody the same time to build: start together
	local wait = (meta.startAt or (workspace:GetServerTimeNow() + 1.8 - (os.clock() - started))) - workspace:GetServerTimeNow()
	if wait > 0 then
		task.wait(wait)
	end
	if my ~= token then
		return
	end
	setText("info", "")
	staticBurst(0.15)
	for _, sc in scenes do
		sc.d.vp.Visible = true
		sc.d.rec.Visible = true
	end
	local events = typeof(meta.events) == "table" and meta.events or {}
	local fired = {}
	local length = frames[#frames].dt
	local killShown = false
	local t0 = meta.startAt or workspace:GetServerTimeNow()
	local fi = 1
	local slots = meta.slots
	local lastCam: CFrame? = nil
	while true do
		if my ~= token then
			return
		end
		local t = math.max(0, workspace:GetServerTimeNow() - t0)
		if t > length then
			break
		end
		while frames[fi + 1] and frames[fi + 1].dt <= t do
			fi += 1
		end
		local a = frames[fi]
		local b = frames[fi + 1] or a
		local k = b.dt > a.dt and math.clamp((t - a.dt) / (b.dt - a.dt), 0, 1) or 0
		local cam = (okCF(a.cam) and okCF(b.cam) and a.cam:Lerp(b.cam, k)) or a.cam or b.cam or lastCam
		lastCam = cam
		local at: { [number]: CFrame } = {}
		for s = 1, slots do
			local ca, cb = a.cfs[s], b.cfs[s]
			at[s] = (ca and cb and ca:Lerp(cb, k)) or ca or cb
		end
		for _, sc in scenes do
			if cam then
				sc.cam.CFrame = cam
			end
			for _, pc in sc.pieces do
				local cf = at[pc.slot]
				if cf then
					pc.part.CFrame = cf * pc.off
					local hide = pc.head and cam ~= nil and (cf.Position - cam.Position).Magnitude < 2.6
					pc.part.Transparency = hide and 1 or pc.t
				else
					pc.part.Transparency = 1
				end
			end
			-- shots, blood, blasts
			for ei, e in events do
				if not sc.fired[ei] and typeof(e) == "table" and (tonumber(e.dt) or 0) <= t then
					sc.fired[ei] = true
					spawnFx(sc.d.vp, e, sc.fx)
				end
			end
			for fxi = #sc.fx, 1, -1 do
				local fx = sc.fx[fxi]
				local kk = (os.clock() - fx.t0) / fx.life
				if kk >= 1 then
					for _, p in fx.parts do
						p:Destroy()
					end
					table.remove(sc.fx, fxi)
				else
					fx.step(kk)
				end
			end
			sc.d.rec.Visible = (os.clock() % 1) < 0.6
			sc.d.clock.Text = string.format("T%+.1f", t - (meta.killAt or 0))
		end
		-- the moment of the kill
		if not killShown and t >= (meta.killAt or 0) then
			killShown = true
			for _, sc in scenes do
				sc.d.info.TextColor3 = RED
				sc.d.info.Text = "ELIMINATED: " .. string.upper(tostring(meta.victim))
				local f = UI.make("Frame", { BackgroundColor3 = RED, BackgroundTransparency = 0.55, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = sc.d.bg })
				TweenService:Create(f, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
				task.delay(0.55, function()
					f:Destroy()
				end)
			end
			task.delay(1.1, function()
				if my == token then
					for _, sc in scenes do
						sc.d.info.Text = ""
						sc.d.info.TextColor3 = GREEN
					end
				end
			end)
		end
		RunService.RenderStepped:Wait()
	end
	for _, sc in scenes do
		sc.d.rec.Visible = false
		sc.d.clock.Text = ""
	end
	staticBurst(0.3)
	clips[id] = nil
end

function ReplayClient.Init()
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local Remote = remotes:WaitForChild("Cyber") :: RemoteEvent
	local DataRemote = remotes:WaitForChild("Replay", 10) :: RemoteEvent?
	local CamRemote = remotes:WaitForChild("ReplayCam", 10)

	-- where this machine looks, for the recording (10 times a second)
	if CamRemote then
		task.spawn(function()
			while true do
				task.wait(0.1)
				local cam = workspace.CurrentCamera
				if cam and okCF(cam.CFrame) then
					pcall(function()
						(CamRemote :: any):FireServer(cam.CFrame)
					end)
				end
			end
		end)
	end

	if DataRemote then
		DataRemote.OnClientEvent:Connect(function(action, a, b, c)
			if action == "clip" and typeof(a) == "table" and typeof(a.id) == "string" then
				local cl = clips[a.id] or { meta = nil, chunks = {}, got = 0 }
				cl.meta = a
				clips[a.id] = cl
			elseif action == "clipdata" and typeof(a) == "string" and typeof(b) == "number" and typeof(c) == "buffer" then
				local cl = clips[a] or { meta = nil, chunks = {}, got = 0 }
				if not cl.chunks[b] then
					cl.chunks[b] = c
					cl.got += 1
				end
				clips[a] = cl
			end
		end)
	end

	Remote.OnClientEvent:Connect(function(action, by, a, b, c, d)
		if action == "replaystart" then
			token += 1
			-- (a = how many, b = the screen)
			openDisplays(tonumber(by) or 0, b)
			setText("info", "NEURAL LINK")
			setText("title", "BOOTING...")
			staticBurst(1.2)
			if by == player.UserId then
				SoundLibrary.Play("static", nil, 0.5)
				SoundLibrary.Play("click", nil, 1, 0.7)
				-- the jack goes in: a white flash
				for _, dd in displays do
					if dd.full then
						local f = UI.make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 10, Parent = dd.bg })
						TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
						task.delay(0.65, function()
							f:Destroy()
						end)
					end
				end
			end
		elseif action == "replay" then
			-- (by, i, n, record id, screen)
			if #displays == 0 then
				openDisplays(tonumber(by) or 0, d)
			end
			token += 1
			local my = token
			task.spawn(function()
				local ok, err = pcall(playRecord, tonumber(by) or 0, tonumber(a) or 0, tonumber(b) or 0, c, my)
				if not ok then
					warn("[Ragdoll] replay:", err)
					setText("info", "SIGNAL LOST")
				end
			end)
		elseif action == "replayend" then
			if #displays == 0 then
				return
			end
			token += 1
			setText("info", "END OF RECORD")
			for _, dd in displays do
				dd.vp.Visible = false
				dd.rec.Visible = false
				dd.vp:ClearAllChildren()
			end
			staticBurst(0.6)
			local mine = displays
			local endToken = token
			task.delay(2.2, function()
				if displays == mine and token == endToken then
					clearDisplays()
				end
			end)
		end
	end)
end

return ReplayClient
