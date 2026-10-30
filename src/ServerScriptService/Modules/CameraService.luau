--!nonstrict
-- CameraService (v2.9): the VIDEO CAMERA and the chips it makes.
--   * hold the camera and press F: it starts filming (the red light comes on). From the lens, 10 times a second, it
--     writes down where the lens looks and where every body near it is (their six parts), like the kill replays do.
--   * press F again (or let go / die): it stops, and a VIDEO CHIP pops out into your hand. The clip lives for the session.
--   * a video chip: F in hand plays it full-screen for you (ChipClient, a ViewportFrame scene). Grab somebody + F
--     (chip in the other hand): they watch it. If the video is a TROJAN (a virus baked in at a computer) the payload
--     fires when it ends - unless their firewall is high enough.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ReplayCodec = require(Shared:WaitForChild("ReplayCodec"))
local Items = require(Shared:WaitForChild("Items"))

local CameraService = {}

local deps: any = {}
local Remote: RemoteEvent

local STEP = 0.1
local MAX_TIME = 14
local MAX_BODIES = 6
local RADIUS = 120
local REGIONS = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }

type Rec = { item: Model, t0: number, last: number, frames: { any }, seen: { [Model]: boolean }, lensLast: CFrame }
local recording: { [Player]: Rec } = {}
type Clip = { buf: buffer, slots: number, actors: { any }, center: Vector3, length: number }
local clips: { [string]: Clip } = {}
local counter = 0

local function lensCF(item: Model): CFrame?
	local body = item.PrimaryPart
	if not body then
		return nil
	end
	local look = body.CFrame.LookVector
	local eye = body.Position + look * 1.1
	return CFrame.lookAt(eye, eye + look)
end

local function recLight(item: Model, on: boolean)
	local led = item:FindFirstChild("RecLight")
	if led and led:IsA("BasePart") then
		led.Color = on and Color3.fromRGB(255, 40, 40) or Color3.fromRGB(80, 20, 20)
	end
	item:SetAttribute("Recording", on or nil)
end

local function bodiesNear(pos: Vector3): { Model }
	local out = {}
	for m in deps.DamageService.Bodies() do
		local t = m.Parent and m:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and (t.Position - pos).Magnitude < RADIUS then
			table.insert(out, m)
		end
	end
	return out
end

function CameraService.Start(p: Player, item: Model)
	if recording[p] then
		return
	end
	if deps.OwnershipService.ItemHolder(item) ~= p or Items.Kind(item) ~= "camera" then
		return
	end
	local cf = lensCF(item)
	if not cf then
		return
	end
	recording[p] = { item = item, t0 = os.clock(), last = 0, frames = {}, seen = {}, lensLast = cf }
	recLight(item, true)
	deps.GoreService.Sound("click", item.PrimaryPart, 1)
	Remote:FireClient(p, "cammsg", "RECORDING")
end

function CameraService.Stop(p: Player)
	local rec = recording[p]
	recording[p] = nil
	if not rec then
		return
	end
	if rec.item.Parent then
		recLight(rec.item, false)
	end
	-- build the actor list and the encoded frames
	local models = {}
	for m in rec.seen do
		if m.Parent then
			table.insert(models, m)
		end
	end
	if #models == 0 or #rec.frames < 2 then
		Remote:FireClient(p, "cammsg", "NOTHING TO SAVE")
		return
	end
	local index: { [Model]: number } = {}
	local actors = {}
	for i, m in models do
		index[m] = i
		local function col(name: string): { number }
			local part = m:FindFirstChild(name)
			local c = (part and part:IsA("BasePart")) and part.Color or Color3.fromRGB(150, 150, 150)
			return { math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255) }
		end
		local who = Players:GetPlayerFromCharacter(m)
		table.insert(actors, { name = who and who.DisplayName or m.Name, head = col("Head"), torso = col("Torso"), arm = col("Left Arm"), leg = col("Left Leg") })
	end
	local slots = #models * 6
	local frames: { ReplayCodec.Frame } = {}
	for _, tk in rec.frames do
		local f: ReplayCodec.Frame = { dt = tk.dt, cam = tk.cam, cfs = {} }
		for m, six in tk.bodies do
			local ai = index[m]
			if ai then
				for r = 1, 6 do
					if six[r] then
						f.cfs[(ai - 1) * 6 + r] = six[r]
					end
				end
			end
		end
		table.insert(frames, f)
	end
	counter += 1
	local code = "V" .. counter
	local center = rec.frames[#rec.frames].cam and rec.frames[#rec.frames].cam.Position or Vector3.zero
	clips[code] = { buf = ReplayCodec.Encode(frames, slots), slots = slots, actors = actors, center = center, length = frames[#frames].dt }
	-- pop the chip out of the camera
	if rec.item.Parent then
		deps.GoreService.Sound("magOut", rec.item.PrimaryPart, 0.9)
	end
	local label = "VIDEO " .. os.date("%H:%M")
	if deps.ChipService then
		deps.ChipService.GiveVideo(p, code, label)
	end
	Remote:FireClient(p, "cammsg", "SAVED TO A CHIP (K: YOUR CHIPS)")
end

function CameraService.Toggle(p: Player, item: Model)
	if recording[p] then
		CameraService.Stop(p)
	else
		CameraService.Start(p, item)
	end
end

-- send a clip to a viewer to play; if trojan, schedule the payload after it ends
function CameraService.Play(viewer: Player, code: string, trojan: any, attacker: Player?)
	local clip = clips[code]
	if not clip then
		Remote:FireClient(attacker or viewer, "cammsg", "THE CLIP IS GONE.")
		return
	end
	Remote:FireClient(viewer, "videostart", { code = code, slots = clip.slots, actors = clip.actors, center = clip.center, length = clip.length, trojan = trojan ~= nil })
	Remote:FireClient(viewer, "videodata", code, clip.buf)
	if trojan and trojan.payload then
		task.delay(clip.length + Config.VirusArmTime, function()
			local v = viewer.Character
			if v and v.Parent and not v:GetAttribute("Dead") and deps.ChipService then
				deps.ChipService.FirePayload(v, trojan, attacker)
			end
		end)
	end
end

function CameraService.Init(d: any)
	deps = d
	Remote = d.ChipService.Remote

	Remote.OnServerEvent:Connect(function(p, action, a)
		if action == "cam" then
			if typeof(a) == "Instance" and a:IsA("Model") and a:IsDescendantOf(workspace) then
				CameraService.Toggle(p, a)
			end
		end
	end)

	-- a camera that leaves the hand (dropped, dead, let go) stops filming
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for p, rec in recording do
			local stop = false
			if not p.Parent or not rec.item.Parent or deps.OwnershipService.ItemHolder(rec.item) ~= p then
				stop = true
			elseif now - rec.t0 > MAX_TIME then
				stop = true
			elseif p.Character and p.Character:GetAttribute("Dead") then
				stop = true
			end
			if stop then
				task.spawn(CameraService.Stop, p)
				continue
			end
			if now - rec.last >= STEP then
				rec.last = now
				local cf = lensCF(rec.item)
				if cf then
					rec.lensLast = cf
					local tick = { dt = now - rec.t0, cam = cf, bodies = {} }
					local nSeen = 0
					for _ in rec.seen do
						nSeen += 1
					end
					for _, m in bodiesNear(cf.Position) do
						local track = rec.seen[m]
						if not track and nSeen < MAX_BODIES then
							rec.seen[m] = true
							nSeen += 1
							track = true
						end
						if track then
							local six = {}
							for i, name in REGIONS do
								local part = m:FindFirstChild(name)
								if part and part:IsA("BasePart") then
									six[i] = part.CFrame
								end
							end
							tick.bodies[m] = six
						end
					end
					table.insert(rec.frames, tick)
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(p)
		recording[p] = nil
	end)
end

return CameraService
