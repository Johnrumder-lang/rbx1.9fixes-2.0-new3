--!nonstrict
local Players = game:GetService("Players")
local CAS = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Input = require(script.Parent.Input)
local Client = {}
function Client.Init()
	local previousAim = Input.ArmAimHook
	Input.ArmAimHook = function(controller, side, shoulder, heading)
		if Input.IsControlled() then
			local ch = Players.LocalPlayer.Character
			local goal = ch and ch:GetAttribute("ControlAim")
			if typeof(goal) == "Vector3" and (goal - shoulder).Magnitude > 0.01 then return (goal - shoulder).Unit, true end
		end
		if previousAim then return previousAim(controller, side, shoulder, heading) end
		return nil, nil
	end
	local keys = {}
	for _, key in Enum.KeyCode:GetEnumItems() do if key ~= Enum.KeyCode.Unknown then table.insert(keys, key) end end
	table.insert(keys, Enum.UserInputType.MouseButton1)
	table.insert(keys, Enum.UserInputType.MouseButton2)
	table.insert(keys, Enum.UserInputType.MouseWheel)
	CAS:BindActionAtPriority("NeuralControlLock", function()
		return Input.IsControlled() and Enum.ContextActionResult.Sink or Enum.ContextActionResult.Pass
	end, false, 10000, table.unpack(keys))
	local was, nextJump = false, 0
	RunService.PreSimulation:Connect(function()
		local active = Input.IsControlled()
		if active then
			if not was then
				require(script.Parent.FreeCam).Set(false)
				require(script.Parent.SettingsMenu).Close()
				require(script.Parent.ChipClient).CloseDeck()
				require(script.Parent.ChipClient).CloseComputer()
				if Input.menuOpen then require(script.Parent.HUD).ToggleMenu() end
				Input.menuOpen, Input.promptOpen, Input.freeCursor, Input.keysCaptured = false, false, false, false
			end
			for _, key in { "mouseLeft", "mouseRight", "useHeld", "aimHeld", "jumpHeld", "runHeld", "runToggle", "downHeld", "laserHeld" } do Input[key] = false end
			local ch = Players.LocalPlayer.Character
			local jumping = ch and ch:GetAttribute("ControlJump") == true
			Input.jumpHeld = jumping
			if jumping and os.clock() >= nextJump then nextJump = os.clock() + 0.8; Input.ControlJump() end
		end
		was = active
	end)
end
return Client
