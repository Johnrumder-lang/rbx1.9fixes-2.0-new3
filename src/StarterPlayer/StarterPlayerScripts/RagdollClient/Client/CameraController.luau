--!nonstrict
-- CameraController: over-the-shoulder "shiftlock" camera that follows the ragdoll torso, plus a
-- first-person mode (V) in which your own arms stay visible.
-- With a mouse, holding LMB/RMB frees the cursor (hand control) and the camera stops turning.
-- G (aiming a gun): zoom in, closer over the shoulder, slower turning. Sniper: scope view.
-- Touch: drag on the right side of the screen. Gamepad: right stick.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MathUtil = require(Shared:WaitForChild("MathUtil"))
local Settings = require(Shared:WaitForChild("Settings"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))
local TimeScale = require(Shared:WaitForChild("TimeScale"))

local Input = require(script.Parent:WaitForChild("Input"))

local player = Players.LocalPlayer

local CameraController = {}

-- (v2.9) the time scale this player lives at, taking a LOCAL Sandevistan field into account (slow only when near it)
local function fieldK(): number
	local c = player.Character
	local t = c and c:FindFirstChild("Torso")
	if t and t:IsA("BasePart") then
		return TimeScale.ForField(player.UserId, t.Position)
	end
	return TimeScale.For(player.UserId)
end

CameraController.yaw = 0
CameraController.pitch = -0.25
CameraController.distance = Config.CameraDistance
CameraController.extra = 0 -- added distance (e.g. while driving)
CameraController.aiming = false -- set by the character every frame (G with a gun)
CameraController.scope = false -- aiming a gun with a scope
CameraController.scopeExtra = false -- (v2.0) the scope has one more zoom step (the sniper mode's rifle)
CameraController.scopeStep = 1 -- (v2.0) which of Config.ScopeZoom (the mouse wheel)
CameraController.fovOverride = nil :: number? -- (v2.0) a sight with its own zoom (the lock-on launcher's seeker)
CameraController.zoomFov = nil :: number? -- (v2.9) ZOOM OPTICS (a chip): pulls the field of view in whenever it is on
CameraController.roll = 0 -- extra tilt of the picture (radians; hallucinations)
CameraController.fovOffset = 0 -- added field of view (hallucinations)
CameraController.override = nil :: ((number) -> CFrame?)? -- (v2.0) a cutscene flies the camera itself
local extraNow = 0
local aimNow = 0
local fovNow = Config.CameraFOV

local subjectFn: (() -> Vector3?)? = nil
-- something to keep in view (the player dragging you): the camera turns towards it
local watchFn: (() -> Vector3?)? = nil
local lastLook = 0
local watchExtra = 0
local headFn: (() -> BasePart?)? = nil
local ignoreFn: (() -> { Instance })? = nil
local focus: Vector3? = nil
local shake = 0
local rng = Random.new()
local gameSettings = UserSettings():GetService("UserGameSettings")
local hiddenParts: { [Instance]: boolean } = {}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

function CameraController.SetSubject(fn: () -> Vector3?, ignore: (() -> { Instance })?, head: (() -> BasePart?)?)
	subjectFn = fn
	ignoreFn = ignore
	headFn = head
end

-- (v1.9) spectating: follow somebody else's body (nil = back to your own)
CameraController.spectate = nil :: Model?

function CameraController.SetWatch(fn: (() -> Vector3?)?)
	watchFn = fn
end

function CameraController.SnapYaw(yaw: number)
	CameraController.yaw = yaw
	focus = nil
end

function CameraController.Shake(amount: number)
	if not Settings.Get("shake") then
		return
	end
	shake = math.min(1.6, math.max(shake, amount))
end

function CameraController.Rotation(): CFrame
	return CFrame.Angles(0, CameraController.yaw, 0) * CFrame.Angles(CameraController.pitch, 0, 0)
end

function CameraController.LookVector(): Vector3
	return CameraController.Rotation().LookVector
end

function CameraController.SetFirstPerson(on: boolean)
	Input.firstPerson = on
end

-- hide head + accessories in first person (LocalTransparencyModifier is local only)
-- (v2.8.2) an implant part on the face (WARDEN OPTICS, the cortex jack, a visor, a helmet...): anything in a "Cy_" folder
-- on the head, or close enough to the eye to fill the view
local function faceImplant(d: BasePart, head: BasePart?): boolean
	local f = d.Parent
	if not f or string.sub(f.Name, 1, 3) ~= "Cy_" then
		return false
	end
	if f.Parent and f.Parent.Name == "Head" then
		return true
	end
	if head then
		local bs = head.Parent and (head.Parent :: Instance):GetAttribute("BodyScale")
		local k = typeof(bs) == "number" and bs or 1
		return (d.Position - head.Position).Magnitude < 1.5 * k
	end
	return false
end

local function setFirstPersonVisibility(on: boolean)
	local char = player.Character
	if not char then
		return
	end
	local headPart = char:FindFirstChild("Head")
	local head = (headPart and headPart:IsA("BasePart")) and headPart or nil
	for _, d in char:GetDescendants() do
		local hide = false
		if on then
			if d:IsA("BasePart") and (d.Name == "Head" or d:FindFirstAncestorOfClass("Accessory")) then
				hide = true
			elseif d:IsA("BasePart") and faceImplant(d, head) then
				hide = true -- (v2.8.2) face implants: you look out of them, not at them
			elseif d:IsA("BasePart") and head and d:IsDescendantOf(head) then
				hide = true -- (a helmet, a mask: anything worn on the head)
			elseif d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
				hide = true
			elseif d:IsA("BasePart") and d.Parent and d.Parent.Name == "Gore" and d.Parent.Parent and d.Parent.Parent.Name == "Head" then
				hide = true
			end
		end
		if d:IsA("BasePart") or d:IsA("Decal") then
			if hide then
				(d :: any).LocalTransparencyModifier = 1
				hiddenParts[d] = true
			elseif hiddenParts[d] then
				(d :: any).LocalTransparencyModifier = 0
				hiddenParts[d] = nil
			end
		end
	end
end

local wasFirstPerson = false

-- (v2.0) in the jet's cockpit (first person) your own arms and torso are hidden too: only the cockpit is in view
CameraController.cockpitFn = nil :: (() -> CFrame?)?
local cockpitHidden: { [Instance]: boolean } = {}
local cockpitOn = false
local function setCockpitBody(on: boolean)
	if on == cockpitOn and not on then
		return
	end
	cockpitOn = on
	local char = player.Character
	if on and char then
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "Torso" or string.find(d.Name, "Arm") ~= nil or d.Parent and d.Parent:IsA("Accessory")) then
				(d :: any).LocalTransparencyModifier = 1
				cockpitHidden[d] = true
			end
		end
	else
		for d in cockpitHidden do
			if d.Parent then
				(d :: any).LocalTransparencyModifier = 0
			end
		end
		table.clear(cockpitHidden)
	end
end

-- (v2.0) how far the scope zooms in right now (x)
function CameraController.ScopeZoomFactor(): number
	local steps = Config.ScopeZoom
	local n = #steps + (CameraController.scopeExtra and 1 or 0)
	local i = math.clamp(CameraController.scopeStep, 1, n)
	return i > #steps and Config.ScopeZoomSniperMode or steps[i]
end

local function step(dt: number)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	local free = Input.CursorFree()
	UserInputService.MouseBehavior = free and Enum.MouseBehavior.Default or Enum.MouseBehavior.LockCenter
	-- while LMB / RMB moves an arm the HUD draws a hand as the cursor (see HUD)
	UserInputService.MouseIconEnabled = free and (Input.menuOpen or not Input.HandControlActive())

	if not CameraController.scope then
		CameraController.scopeStep = 1 -- (every new look through the scope starts zoomed out)
	end
	local zoom = CameraController.scope and CameraController.ScopeZoomFactor() or 1
	local aimSens = CameraController.scope and Config.AimSensitivity * 0.35 / zoom ^ 0.7 or (CameraController.aiming and Config.AimSensitivity or 1)
	if fieldK() < 1 then
		aimSens *= Config.SlowMoCamera -- (v2.8) somebody's Sandevistan runs: you turn very slowly
	end
	if not free and not Input.IsControlled() then
		local d = UserInputService:GetMouseDelta()
		if d.Magnitude > 2 then
			lastLook = os.clock()
		end
		local sens = Config.MouseSensitivity * (gameSettings.MouseSensitivity or 1) * aimSens
		CameraController.yaw -= d.X * sens
		CameraController.pitch = math.clamp(CameraController.pitch - d.Y * sens, -1.45, 1.35)
	end

	for _, io in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if io.KeyCode == Enum.KeyCode.Thumbstick2 and io.Position.Magnitude > 0.15 then
			CameraController.yaw -= io.Position.X * dt * 3 * aimSens
			CameraController.pitch = math.clamp(CameraController.pitch + io.Position.Y * dt * 2.2 * aimSens, -1.45, 1.35)
		end
	end

	if Input.IsControlled() then
		local ch = Players.LocalPlayer.Character
		local root = ch and ch:FindFirstChild("Torso")
		local goal = ch and ch:GetAttribute("ControlAim")
		if root and typeof(goal) == "Vector3" then
			local d = goal - (root.Position + Vector3.new(0, 1.5, 0))
			if d.Magnitude > 0.01 then
				CameraController.yaw = math.atan2(-d.X, -d.Z)
				CameraController.pitch = math.clamp(math.asin(d.Unit.Y), -1.2, 1.2)
			end
		end
	end
	-- the scope is looked through with the eye (first person view while it is up)
	local fp = Input.firstPerson or CameraController.scope
	aimNow += ((CameraController.aiming and 1 or 0) - aimNow) * math.min(1, dt * 12)
	local fovWant = CameraController.zoomFov or (CameraController.aiming and CameraController.fovOverride) or CameraController.scope and Config.ScopeFOV / zoom
		or (CameraController.aiming and Config.AimFOV or (fp and (Settings.Get("fov") + Config.FirstPersonFOV - Config.CameraFOV) or Settings.Get("fov")))
	fovNow += (fovWant - fovNow) * math.min(1, dt * 14)
	if fp ~= wasFirstPerson then
		wasFirstPerson = fp
		if not fp then
			setFirstPersonVisibility(false)
		end
	end
	if fp then
		setFirstPersonVisibility(true)
	end

	local target = subjectFn and subjectFn()
	local spec = CameraController.spectate
	if spec then
		local t = spec.Parent and (spec:FindFirstChild("Torso") or spec.PrimaryPart)
		if t and t:IsA("BasePart") then
			target = t.Position + Vector3.new(0, 1.2, 0)
		else
			CameraController.spectate = nil
		end
	end
	local watch = watchFn and watchFn()
	if target and watch and (watch - target).Magnitude < 60 then
		-- keep both in the picture: look past yourself at the one who drags you
		local toW = watch - target
		local mid = target:Lerp(watch, 0.35)
		if os.clock() - lastLook > 1.2 and toW.Magnitude > 0.5 and not Input.freeCam then
			local want = math.atan2(-toW.X, -toW.Z)
			local diff = (want - CameraController.yaw + math.pi) % (2 * math.pi) - math.pi
			CameraController.yaw += diff * math.min(1, dt * 2.5)
			CameraController.pitch += (-0.3 - CameraController.pitch) * math.min(1, dt * 1.5)
		end
		watchExtra = math.clamp(toW.Magnitude * 0.4, 0, 6)
		target = mid
	else
		watchExtra = 0
	end
	if target then
		if not focus or (focus - target).Magnitude > 40 then
			focus = target
		else
			focus = focus:Lerp(target, MathUtil.Alpha(fp and 30 or 18, dt))
		end
	end
	if not focus then
		return
	end

	local rot = CameraController.Rotation()
	local shakeCF = CFrame.identity
	local camPos: Vector3
	if shake > 0.001 then
		local s = shake * shake
		shakeCF = CFrame.Angles(rng:NextNumber(-1, 1) * 0.03 * s, rng:NextNumber(-1, 1) * 0.03 * s, rng:NextNumber(-1, 1) * 0.02 * s)
		shake = math.max(0, shake - dt * 2.2)
	end

	local cockpit = fp and CameraController.cockpitFn and CameraController.cockpitFn() or nil
	if cockpit then
		-- (v2.0) first person in the jet: a steady eye in the cockpit that banks with the jet (no head bob, no
		-- looking through your own arms); a wider view
		camPos = cockpit.Position
		camera.FieldOfView = fovNow + 8
		setCockpitBody(true)
		local _, _, roll = cockpit:ToOrientation()
		camera.CFrame = CFrame.new(camPos) * rot * CFrame.Angles(0, 0, roll * 0.85) * shakeCF
		return
	end
	setCockpitBody(false)
	if fp then
		local head = headFn and headFn()
		local eye = head and head.Parent and (head.Position + Vector3.new(0, 0.15, 0)) or (focus + Vector3.new(0, 0.3, 0))
		camPos = eye + rot.LookVector * 0.35
		camera.FieldOfView = fovNow
	else
		local ignore = { workspace:FindFirstChild("FX") }
		if player.Character then
			table.insert(ignore, player.Character)
		end
		if ignoreFn then
			for _, i in ignoreFn() do
				table.insert(ignore, i)
			end
		end
		rayParams.FilterDescendantsInstances = ignore

		-- (v2.8) a bigger body (BULK FRAME / COLOSSUS): the camera sits further out
		local ch = player.Character
		local bs = ch and ch:GetAttribute("BodyScale")
		local S = typeof(bs) == "number" and math.clamp(bs, 0.5, 4) or 1
		local offset = Config.CameraShoulderOffset * S
		local pivot = focus + rot:VectorToWorldSpace(Vector3.new(offset.X, 0, 0)) + Vector3.new(0, offset.Y, 0)
		local toPivot = pivot - focus
		local hit = workspace:Raycast(focus, toPivot, rayParams)
		if hit then
			pivot = focus + toPivot.Unit * math.max(0, hit.Distance - 0.35)
		end
		extraNow += (CameraController.extra + watchExtra - extraNow) * math.min(1, dt * 3)
		local dist = CameraController.distance * S + extraNow
		dist += (math.min(dist, 6 * S) - dist) * aimNow -- aiming: closer over the shoulder
		local back = -rot.LookVector * dist
		camPos = pivot + back
		local ok, sweep = pcall(function()
			return workspace:Spherecast(pivot, 0.45, back, rayParams)
		end)
		if ok and sweep then
			camPos = pivot + back.Unit * math.max(0.6, sweep.Distance)
		end
		if shake > 0.001 then
			camPos += Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)) * 0.2 * shake
		end
		camera.FieldOfView = fovNow
		camera.Focus = CFrame.new(pivot)
	end

	if math.abs(CameraController.fovOffset) > 0.01 then
		camera.FieldOfView = math.clamp(camera.FieldOfView + CameraController.fovOffset, 5, 120)
	end
	local ov = CameraController.override
	if ov then
		local ok, cf = pcall(ov, dt)
		if ok and typeof(cf) == "CFrame" then
			camera.CFrame = cf * shakeCF
			return
		end
	end
	camera.CFrame = CFrame.new(camPos) * rot * CFrame.Angles(0, 0, CameraController.roll) * shakeCF
end

function CameraController.Init()
	RunService:BindToRenderStep("RagdollSandboxCamera", Enum.RenderPriority.Camera.Value + 1, step)

	UserInputService.InputChanged:Connect(function(io, gameProcessed)
		if Input.IsControlled() then return end
		if gameProcessed then
			return
		end
		if io.UserInputType == Enum.UserInputType.MouseWheel then
			if Input.wheelCapture or Input.quickhackMode then
				return -- the physics gun uses the wheel
			end
			-- (v2.0) through a scope the wheel zooms
			if CameraController.scope then
				local n = #Config.ScopeZoom + (CameraController.scopeExtra and 1 or 0)
				local was = CameraController.scopeStep
				CameraController.scopeStep = math.clamp(was + (io.Position.Z > 0 and 1 or -1), 1, n)
				if CameraController.scopeStep ~= was then
					SoundLibrary.Play("click", nil, 0.5)
				end
				return
			end
			if Input.firstPerson and io.Position.Z < 0 then
				Input.firstPerson = false
				CameraController.distance = Config.CameraMinDistance
				return
			end
			local newDist = CameraController.distance - io.Position.Z * 1.6
			if newDist < Config.CameraMinDistance - 0.5 and not Input.firstPerson then
				Input.firstPerson = true -- scroll all the way in = first person
				return
			end
			CameraController.distance = math.clamp(newDist, Config.CameraMinDistance, Config.CameraMaxDistance)
		end
	end)

	-- touch: drag anywhere that is not a button to look around
	local touches: { [InputObject]: boolean } = {}
	UserInputService.TouchStarted:Connect(function(io, gameProcessed)
		if gameProcessed then
			return
		end
		local cam = workspace.CurrentCamera
		if cam and io.Position.X > cam.ViewportSize.X * 0.4 then
			touches[io] = true
		end
	end)
	UserInputService.TouchMoved:Connect(function(io)
		if touches[io] then
			local sens = Config.TouchSensitivity * (fieldK() < 1 and Config.SlowMoCamera or 1)
			CameraController.yaw -= io.Delta.X * sens
			CameraController.pitch = math.clamp(CameraController.pitch - io.Delta.Y * sens, -1.45, 1.35)
		end
	end)
	UserInputService.TouchEnded:Connect(function(io)
		touches[io] = nil
	end)

	Input.Action:Connect(function(action)
		if action == "FirstPerson" then
			Input.firstPerson = not Input.firstPerson
		end
	end)
end

return CameraController
