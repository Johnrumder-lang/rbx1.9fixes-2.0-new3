--!nonstrict
-- Input: keyboard / mouse, gamepad and touch, merged into one state.
--
--   PC:       WASD move · Space jump/climb · Shift run · Q/E grab · LMB/RMB hold = hand to cursor
--             F use (fire / attack / pin / bandage / tie / throw C4 / detonate) - hold F: full auto, beam
--             G aim (gun in hand, hold) / get in or out of a car · B car · C kick · Ctrl crouch
--             X lie down (in the air: dive)
--             reload = touch the gun with your free hand (hold that hand's mouse button, point at the gun)
--             V first person · R go limp · T spawn menu · H help
--   Console:  L-stick move · R-stick camera · A jump/climb · L1/R1 grab · L2/R2 hold = aim hand
--             X use · D-pad left aim gun (hold) / car · B crouch · R3 kick · D-pad down lie down / dive
--             Y first person · D-pad up go limp · L3 run · Select spawn menu · D-pad right help
--   Mobile:   on-screen buttons (MobileControls) feed SetVirtual / FireAction

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Input = {}

Input.mouseLeft = false -- left hand under manual control (mouse / L2 / touch button)
Input.mouseRight = false
Input.menuOpen = false
Input.jumpHeld = false
Input.downHeld = false -- Ctrl / B (gamepad) held: flying down
Input.runHeld = false
Input.runToggle = false
Input.lastDevice = "KeyboardMouse" -- "KeyboardMouse" | "Gamepad" | "Touch"
Input.firstPerson = false
Input.handHolding = false -- a hand under manual control holds something (closed-hand cursor)
Input.useHeld = false -- F / X (gamepad) / USE button held down
Input.aimHeld = false -- G / D-pad left / AIM button held down (aims a gun in your hand)
Input.aiming = false -- set by the character: a gun is being aimed right now (locks the mouse)
Input.promptOpen = false -- a text prompt (boombox) is open: the mouse is free
Input.ledgerOpen = false
-- (v2.x) hooks for other modules: where an arm points (nil = as usual) - cyberware, auto-defense, ...
Input.ArmAimHook = nil :: ((any, string, Vector3, CFrame) -> (Vector3?, boolean?))? -- (v2.1) the Black Ledger's book is open: the mouse is free
Input.freeCursor = false -- a panel you click (lift) is open: the mouse is free, you can still walk
Input.wheelCapture = false -- something else uses the scroll wheel (physics gun distance), not the camera
Input.laserHeld = false -- K held (the owner's laser eyes, while flying)
Input.spectating = false -- (v2.0) J: watching somebody else, your own body does not walk
Input.keysCaptured = false -- (v2.0) the piano is open: the keyboard plays notes, no key does anything else
Input.cutscene = false -- (v2.0) a cutscene runs: no moving, no actions
Input.freeCam = false -- (v2.0) the admin free cam flies: no key / button reaches your body (FreeCam reads its own)

Input.quickhackMode = false
function Input.IsControlled(): boolean
	local ch = Players.LocalPlayer.Character
	return ch ~= nil and not ch:GetAttribute("Dead") and (ch:GetAttribute("ControlActive") == true or (ch:GetAttribute("CrashOut") or 0) > workspace:GetServerTimeNow())
end
local wheel = 0
-- scroll wheel steps since the last call (only collected while wheelCapture is on)
function Input.TakeWheel(): number
	local w = wheel
	wheel = 0
	return w
end

-- (v2.0) the proximity prompts shown right now: their key belongs to them
local shownPrompts: { [ProximityPrompt]: boolean } = {}
local function promptKey(k: Enum.KeyCode): boolean
	for prompt in shownPrompts do
		if prompt.Parent and prompt.Enabled and (prompt.KeyboardKeyCode == k or prompt.GamepadKeyCode == k) then
			return true
		end
	end
	return false
end

local actionEvent = Instance.new("BindableEvent")
Input.Action = actionEvent.Event -- fires (actionName: string)

local KEY_ACTIONS = {
	[Enum.KeyCode.Q] = "GrabLeft",
	[Enum.KeyCode.E] = "GrabRight",
	[Enum.KeyCode.R] = "Ragdoll",
	[Enum.KeyCode.T] = "Menu",
	[Enum.KeyCode.H] = "Help",
	[Enum.KeyCode.Space] = "Jump",
	[Enum.KeyCode.F] = "Fire",
	[Enum.KeyCode.C] = "Kick",
	[Enum.KeyCode.Y] = "TwoHand",
	[Enum.KeyCode.N] = "FlySpeed", -- flying: type a new speed
	[Enum.KeyCode.L] = "SuperPunch", -- game owner
	[Enum.KeyCode.M] = "Settings",
	[Enum.KeyCode.LeftControl] = "Crouch",
	[Enum.KeyCode.RightControl] = "Crouch",
	[Enum.KeyCode.B] = "Car",
	-- the construction lift (while standing on a lift pad): 0 = ground, 1-9 = floors, = roof
	[Enum.KeyCode.Zero] = "Lift0",
	[Enum.KeyCode.One] = "Lift1",
	[Enum.KeyCode.Two] = "Lift2",
	[Enum.KeyCode.Three] = "Lift3",
	[Enum.KeyCode.Four] = "Lift4",
	[Enum.KeyCode.Five] = "Lift5",
	[Enum.KeyCode.Six] = "Lift6",
	[Enum.KeyCode.Seven] = "Lift7",
	[Enum.KeyCode.Eight] = "Lift8",
	[Enum.KeyCode.Nine] = "Lift9",
	[Enum.KeyCode.Equals] = "Lift10",
	[Enum.KeyCode.X] = "Prone",
	[Enum.KeyCode.Z] = "Prone",
	[Enum.KeyCode.V] = "FirstPerson",
	[Enum.KeyCode.LeftAlt] = "Weave", -- (v2.0) slip a punch
	[Enum.KeyCode.P] = "Hotdog", -- (v2.0, admins) the player at your crosshair rides the hotdog
	[Enum.KeyCode.I] = "TimeStop", -- (v2.0, admins) stop / start time for the whole server
	[Enum.KeyCode.G] = "Vehicle",
	[Enum.KeyCode.DPadLeft] = "Vehicle",
	-- gamepad
	[Enum.KeyCode.ButtonA] = "Jump",
	[Enum.KeyCode.ButtonL1] = "GrabLeft",
	[Enum.KeyCode.ButtonR1] = "GrabRight",
	[Enum.KeyCode.ButtonX] = "Fire",
	[Enum.KeyCode.ButtonB] = "Crouch",
	[Enum.KeyCode.ButtonR3] = "Kick",
	[Enum.KeyCode.DPadDown] = "Prone",
	[Enum.KeyCode.ButtonY] = "FirstPerson",
	[Enum.KeyCode.DPadUp] = "Ragdoll",
	[Enum.KeyCode.ButtonSelect] = "Menu",
	[Enum.KeyCode.DPadRight] = "TwoHand",
	[Enum.KeyCode.ButtonStart] = "Help",
}

-- (v2.8) KEYS (M > SETTINGS > KEYS): these actions can have another key on the keyboard. The setting "keyBinds" holds
-- "Action=KeyName,..." (only the changed ones); the controller and touch buttons stay as they are. Keys the game reads
-- directly (moving, jumping, running, crouching, grabbing, F, G, K, 0-9, the cyber bar) can not be taken.
Input.REBIND = {
	{ action = "Kick", label = "Kick (in a jet: missile)" },
	{ action = "Prone", label = "Lie down / dive (in a jet: bomb)" },
	{ action = "Weave", label = "Weave (duck out of a punch)" },
	{ action = "TwoHand", label = "Both hands on the item" },
	{ action = "Car", label = "Car in / out (owner: fly)" },
	{ action = "FirstPerson", label = "First person" },
	{ action = "Ragdoll", label = "Go limp" },
	{ action = "Menu", label = "Spawn menu" },
	{ action = "Settings", label = "This menu" },
	{ action = "Help", label = "Help" },
	{ action = "FlySpeed", label = "Fly speed" },
	{ action = "SuperPunch", label = "Super punch (owner)" },
	{ action = "Hotdog", label = "Hotdog (admins)" },
	{ action = "TimeStop", label = "Time stop (admins)" },
}
Input.RESERVED = {
	W = true, A = true, S = true, D = true, Up = true, Down = true, Left = true, Right = true, Space = true, LeftShift = true,
	RightShift = true, LeftControl = true, RightControl = true, Q = true, E = true, F = true, G = true, K = true, F4 = true, Escape = true,
	Zero = true, One = true, Two = true, Three = true, Four = true, Five = true, Six = true, Seven = true, Eight = true,
	Nine = true, Equals = true, Tab = true, Slash = true, Backquote = true, U = true, J = true, Return = true,
}
local DEFAULT_ACTIONS = table.clone(KEY_ACTIONS)
local function isKeyboard(k: Enum.KeyCode): boolean
	local n = k.Name
	return not (string.match(n, "^Button") or string.match(n, "^DPad") or string.match(n, "^Thumbstick"))
end
local rebindable = {}
for _, r in Input.REBIND do
	rebindable[r.action] = true
end

-- the keyboard key an action has right now (nil: none)
function Input.KeyFor(action: string): Enum.KeyCode?
	local best = nil
	for k, a in KEY_ACTIONS do
		if a == action and isKeyboard(k) and (not best or k.Value < best.Value) then
			best = k
		end
	end
	return best
end

local SHORT = { LeftAlt = "ALT", RightAlt = "ALT", LeftControl = "CTRL", RightControl = "CTRL", LeftShift = "SHIFT", RightShift = "SHIFT" }
-- how a key is written in hints ("C", "ALT")
function Input.KeyName(action: string, fallback: string?): string
	local k = Input.KeyFor(action)
	if not k then
		return fallback or "-"
	end
	return SHORT[k.Name] or string.upper(k.Name)
end

-- "{Kick} / {Prone}" -> "C / X"
function Input.Keyed(text: string): string
	return (string.gsub(text, "{(%w+)}", function(action)
		return Input.KeyName(action)
	end))
end

-- the setting -> the key table
function Input.ApplyBinds(spec: string?)
	table.clear(KEY_ACTIONS)
	for k, a in DEFAULT_ACTIONS do
		KEY_ACTIONS[k] = a
	end
	for pair in string.gmatch(spec or "", "[^,]+") do
		local action, keyName = string.match(pair, "^(%w+)=(%w+)$")
		if action and keyName and rebindable[action] and not Input.RESERVED[keyName] then
			local ok, kc = pcall(function()
				return (Enum.KeyCode :: any)[keyName]
			end)
			if ok and kc then
				for k, a in table.clone(KEY_ACTIONS) do
					if a == action and isKeyboard(k) then
						KEY_ACTIONS[k] = nil
					end
				end
				KEY_ACTIONS[kc] = action -- (the key is taken from whatever had it)
			end
		end
	end
end

local virtual = { AimLeft = false, AimRight = false, Jump = false, Use = false, Aim = false, Laser = false, Down = false }

function Input.FireAction(name: string)
	if Input.IsControlled() then return end
	actionEvent:Fire(name)
end

-- Called only by the local directive driver; ordinary input remains blocked.
function Input.ControlJump()
	if Input.IsControlled() then actionEvent:Fire("Jump") end
end

-- Mobile buttons: held states
function Input.SetVirtual(name: string, down: boolean)
	if Input.IsControlled() then return end
	virtual[name] = down
	if name == "AimLeft" then
		Input.mouseLeft = down
	elseif name == "AimRight" then
		Input.mouseRight = down
	elseif name == "Jump" then
		Input.jumpHeld = down
		if down then
			actionEvent:Fire("Jump")
		end
	elseif name == "Use" then
		Input.useHeld = down
		if down then
			actionEvent:Fire("Fire")
		end
	elseif name == "Aim" then
		Input.aimHeld = down
	elseif name == "Laser" then
		Input.laserHeld = down
	elseif name == "Down" then
		Input.downHeld = down
	end
end

-- Hands follow the mouse cursor only with a mouse in third person; otherwise they aim at the crosshair.
function Input.UsesCursor(): boolean
	return Input.lastDevice == "KeyboardMouse" and not Input.firstPerson and not Input.aiming
end

function Input.HandControlActive(): boolean
	return (Input.mouseLeft or Input.mouseRight) and not Input.menuOpen
end

function Input.CursorFree(): boolean
	if Input.menuOpen or Input.promptOpen or Input.freeCursor or Input.ledgerOpen then
		return true
	end
	if Input.aiming then
		return false -- aiming a gun: the mouse turns the camera
	end
	return Input.HandControlActive() and Input.UsesCursor()
end

local function deviceOf(t: Enum.UserInputType): string?
	if t == Enum.UserInputType.Touch then
		return "Touch"
	end
	if t.Name:match("^Gamepad") then
		return "Gamepad"
	end
	if t == Enum.UserInputType.Keyboard or t.Name:match("^Mouse") then
		return "KeyboardMouse"
	end
	return nil
end

function Input.Init()
	-- (v2.8) your own keys
	do
		local Settings = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Settings"))
		Input.ApplyBinds(Settings.Get("keyBinds"))
		Settings.Changed:Connect(function(key)
			if key == "keyBinds" then
				Input.ApplyBinds(Settings.Get("keyBinds"))
			end
		end)
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		Input.lastDevice = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		Input.lastDevice = "Gamepad"
	end

	local PPS = game:GetService("ProximityPromptService")
	PPS.PromptShown:Connect(function(prompt)
		shownPrompts[prompt] = true
	end)
	PPS.PromptHidden:Connect(function(prompt)
		shownPrompts[prompt] = nil
	end)

	UserInputService.LastInputTypeChanged:Connect(function(t)
		local d = deviceOf(t)
		if d then
			Input.lastDevice = d
		end
	end)

	UserInputService.InputBegan:Connect(function(io, gameProcessed)
		if Input.IsControlled() then return end
		local t = io.UserInputType
		if Input.freeCam then
			return
		end
		if t == Enum.UserInputType.MouseButton1 then
			if not gameProcessed and not Input.menuOpen then
				Input.mouseLeft = true
			end
			return
		elseif t == Enum.UserInputType.MouseButton2 then
			if not gameProcessed and not Input.menuOpen then
				Input.mouseRight = true
			end
			return
		end
		local k = io.KeyCode
		local body = Players.LocalPlayer.Character
		if body and (body:GetAttribute("TemporalFrozenUntil") or 0) > workspace:GetServerTimeNow() then return end
		if Input.quickhackMode and (k == Enum.KeyCode.F or k == Enum.KeyCode.ButtonX) then return end
		if Input.cutscene then
			return
		end
		if Input.keysCaptured and t == Enum.UserInputType.Keyboard then
			return -- (v2.0: playing the piano - H, T, E, F ... used to open the help, the spawn menu, grab, punch)
		end
		if not gameProcessed and promptKey(k) then
			return -- (v2.0: F at a piano / TV / vending machine is for the prompt, not a punch or a shot as well)
		end
		if k == Enum.KeyCode.ButtonL2 then
			Input.mouseLeft = true
			return
		elseif k == Enum.KeyCode.ButtonR2 then
			Input.mouseRight = true
			return
		elseif k == Enum.KeyCode.ButtonL3 then
			Input.runToggle = not Input.runToggle
			return
		end
		if k == Enum.KeyCode.ButtonA and gameProcessed and not Input.menuOpen and not Input.promptOpen then
			-- (v1.9: with a controller the default controls bind A to their own jump, which marks the press as
			-- "already handled" - it never reached us, so you could not jump. A belongs to us when no menu is open.)
			Input.jumpHeld = true
			local jumpAction = KEY_ACTIONS[k]
			if jumpAction then
				actionEvent:Fire(jumpAction)
			end
			return
		end
		-- (v2.0 fix) Roblox's own camera takes I / O (zoom) and marks the press as handled: O (time stop) never
		-- reached us. Those keys are ours as long as nobody types in a text box.
		local sunkByCore = (k == Enum.KeyCode.O or k == Enum.KeyCode.I or KEY_ACTIONS[k] == "TimeStop") and UserInputService:GetFocusedTextBox() == nil
		if gameProcessed and k ~= Enum.KeyCode.ButtonSelect and not sunkByCore then
			return
		end
		if k == Enum.KeyCode.Space or k == Enum.KeyCode.ButtonA then
			Input.jumpHeld = true
		elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift then
			Input.runHeld = true
		elseif k == Enum.KeyCode.LeftControl or k == Enum.KeyCode.RightControl or k == Enum.KeyCode.ButtonB then
			Input.downHeld = true
		elseif k == Enum.KeyCode.F or k == Enum.KeyCode.ButtonX then
			Input.useHeld = true
		elseif k == Enum.KeyCode.G or k == Enum.KeyCode.DPadLeft then
			Input.aimHeld = true
		elseif k == Enum.KeyCode.K then
			Input.laserHeld = true
		end
		local action = KEY_ACTIONS[k]
		if action then
			actionEvent:Fire(action)
		end
	end)

	UserInputService.InputEnded:Connect(function(io)
		if Input.IsControlled() then return end
		local t = io.UserInputType
		local k = io.KeyCode
		if t == Enum.UserInputType.MouseButton1 or k == Enum.KeyCode.ButtonL2 then
			Input.mouseLeft = virtual.AimLeft
		elseif t == Enum.UserInputType.MouseButton2 or k == Enum.KeyCode.ButtonR2 then
			Input.mouseRight = virtual.AimRight
		elseif k == Enum.KeyCode.Space or k == Enum.KeyCode.ButtonA then
			Input.jumpHeld = virtual.Jump
		elseif k == Enum.KeyCode.LeftShift or k == Enum.KeyCode.RightShift then
			Input.runHeld = false
		elseif k == Enum.KeyCode.LeftControl or k == Enum.KeyCode.RightControl or k == Enum.KeyCode.ButtonB then
			Input.downHeld = false
		elseif k == Enum.KeyCode.F or k == Enum.KeyCode.ButtonX then
			Input.useHeld = virtual.Use
		elseif k == Enum.KeyCode.G or k == Enum.KeyCode.DPadLeft then
			Input.aimHeld = virtual.Aim
		elseif k == Enum.KeyCode.K then
			Input.laserHeld = virtual.Laser
		end
	end)

	UserInputService.InputChanged:Connect(function(io, gameProcessed)
		if Input.IsControlled() then return end
		if not gameProcessed and Input.wheelCapture and io.UserInputType == Enum.UserInputType.MouseWheel then
			wheel += io.Position.Z
		end
	end)

	-- losing focus (alt-tab) must not leave buttons stuck
	UserInputService.WindowFocusReleased:Connect(function()
		Input.mouseLeft = false
		Input.mouseRight = false
		Input.jumpHeld = false
		Input.runHeld = false
		Input.useHeld = false
		Input.aimHeld = false
		Input.downHeld = false
		Input.laserHeld = false
	end)
end

function Input.Running(): boolean
	return Input.runHeld or Input.runToggle
end

-- Movement vector in camera space (x = right, z = back), magnitude <= 1.
-- Uses the default ControlModule when available (keyboard, gamepad, touch thumbstick), else WASD.
local controls = nil
task.spawn(function()
	local ok, result = pcall(function()
		local player = Players.LocalPlayer
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		return module and (require(module :: ModuleScript) :: any):GetControls() or nil
	end)
	if ok and result then
		controls = result
	end
end)

function Input.GetMoveVector(): Vector3
	if Input.IsControlled() then
		local ch = Players.LocalPlayer.Character
		local root, goal = ch:FindFirstChild("Torso"), ch:GetAttribute("ControlGoal")
		if root and typeof(goal) == "Vector3" and ch:GetAttribute("ControlMove") then
			local delta = goal - root.Position
			local flat = Vector3.new(delta.X, 0, delta.Z)
			if flat.Magnitude > 1 then
				local camera = workspace.CurrentCamera
				local localDir = camera.CFrame:VectorToObjectSpace(flat.Unit)
				local v = Vector3.new(localDir.X, 0, localDir.Z)
				return v.Magnitude > 0.01 and v.Unit or Vector3.zero
			end
		end
		return Vector3.zero
	end
	if Input.spectating or Input.cutscene or Input.freeCam then
		return Vector3.zero
	end
	if controls then
		local ok, mv = pcall(function()
			return controls:GetMoveVector()
		end)
		if ok and typeof(mv) == "Vector3" then
			return mv.Magnitude > 1 and mv.Unit or mv
		end
	end
	local x, z = 0, 0
	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		z -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		z += 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		x -= 1
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		x += 1
	end
	local v = Vector3.new(x, 0, z)
	return v.Magnitude > 0 and v.Unit or v
end

return Input
