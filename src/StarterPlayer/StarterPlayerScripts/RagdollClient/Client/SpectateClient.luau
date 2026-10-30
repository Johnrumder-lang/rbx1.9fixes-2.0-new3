--!nonstrict
-- SpectateClient: watch the others.
--   * automatically while you wait in the lobby (a round is running and you are out / dead) (v1.9)
--   * (v2.0) any time with J (or the SPECTATE button in the menu): your body stays where it is and does not
--     move while you watch. J again (or Backspace) ends it.
-- Left / right arrow (gamepad: shoulder buttons, phone: the two buttons) switch between the players who are
-- still in the game and the monsters / sharks that are out (models with the "Spectatable" attribute); the
-- camera follows them and you can still turn it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local UI = require(script.Parent:WaitForChild("UI"))
local Cam = require(script.Parent:WaitForChild("CameraController"))
local Input = require(script.Parent:WaitForChild("Input"))

local C = UI.C
local player = Players.LocalPlayer

local SpectateClient = {}

local gui: ScreenGui
local bar: Frame
local nameLabel: TextLabel
local infoLabel: TextLabel
local index = 0
local manual = false

local function alive(m: Instance?): boolean
	return m ~= nil and m.Parent ~= nil and not m:GetAttribute("Dead")
end

-- who can be watched: alive players in the game, then spectatable creatures
local function candidates(): { Model }
	local list: { Model } = {}
	local ps = Players:GetPlayers()
	table.sort(ps, function(a, b)
		return a.UserId < b.UserId
	end)
	for _, p in ps do
		local c = p.Character
		if p ~= player and c and alive(c) and not p:GetAttribute("InLobby") and c:FindFirstChild("Torso") then
			table.insert(list, c)
		end
	end
	local folder = workspace:FindFirstChild("Creatures")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Spectatable") and alive(m) and m.PrimaryPart then
				table.insert(list, m)
			end
		end
	end
	return list
end

local function step(dir: number)
	local list = candidates()
	if #list == 0 then
		Cam.spectate = nil
		index = 0
		return
	end
	-- keep watching the same one if it is still in the list
	local cur = Cam.spectate
	local at = cur and table.find(list, cur) or nil
	if at and dir == 0 then
		index = at
		return
	end
	index = (((at or index) - 1 + dir) % #list) + 1
	Cam.spectate = list[index]
end

local function nameOf(m: Model): string
	local p = Players:GetPlayerFromCharacter(m)
	if p then
		return p.DisplayName
	end
	local n = m:GetAttribute("DisplayName")
	return typeof(n) == "string" and n or m.Name
end

local function healthOf(m: Model): string
	local blood = m:GetAttribute("Blood")
	if typeof(blood) == "number" then
		return string.format("BLOOD %d%%", math.floor(blood + 0.5))
	end
	local hp = m:GetAttribute("HP")
	if typeof(hp) == "number" then
		return string.format("HP %d", math.floor(hp + 0.5))
	end
	return ""
end

function SpectateClient.IsManual(): boolean
	return manual
end

-- (v2.0) spectating is for the lobby while a game mode runs (dead or late); not in the sandbox
local function allowed(): boolean
	return typeof(workspace:GetAttribute("Mode")) == "string" and player:GetAttribute("InLobby") == true
end

function SpectateClient.Toggle()
	if not manual and not allowed() then
		return
	end
	manual = not manual
	Input.spectating = manual
	if manual then
		step(1)
	else
		Cam.spectate = nil
		index = 0
	end
end

function SpectateClient.Init()
	gui = UI.make("ScreenGui", { Name = "Spectate", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 13, Enabled = false, Parent = player:WaitForChild("PlayerGui") })
	bar = UI.panel({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -22),
		Size = UDim2.fromOffset(420, 58),
		Accent = C.amber,
		Parent = gui,
	})
	UI.button({ Text = "<", Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(9, 9), Parent = bar }, function()
		step(-1)
	end)
	UI.button({ Text = ">", Size = UDim2.fromOffset(40, 40), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -9, 0, 9), Parent = bar }, function()
		step(1)
	end)
	nameLabel = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(56, 6), Size = UDim2.new(1, -112, 0, 24), Parent = bar })
	infoLabel = UI.label({ Text = "", TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(56, 30), Size = UDim2.new(1, -112, 0, 20), Parent = bar })

	Input.Action:Connect(function(action)
		if action == "Spectate" then
			SpectateClient.Toggle()
		end
	end)
	UserInputService.InputBegan:Connect(function(io, processed)
		if Input.IsControlled() then return end
		if processed then
			return
		end
		local k = io.KeyCode
		if Input.keysCaptured or Input.cutscene then
			return -- (v2.0: J on the piano is a note)
		end
		if k == Enum.KeyCode.J then
			SpectateClient.Toggle()
			return
		end
		if not gui.Enabled then
			return
		end
		if k == Enum.KeyCode.Left or k == Enum.KeyCode.ButtonL1 then
			step(-1)
		elseif k == Enum.KeyCode.Right or k == Enum.KeyCode.ButtonR1 then
			step(1)
		elseif k == Enum.KeyCode.Backspace and manual then
			SpectateClient.Toggle()
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local ok = allowed()
		if manual and not ok then
			manual = false -- (back in the game, or the mode is over)
			Input.spectating = false
		end
		local on = ok
		if not on then
			if gui.Enabled then
				gui.Enabled = false
				Cam.spectate = nil
				index = 0
			end
			return
		end
		if not gui.Enabled then
			gui.Enabled = true
			acc = 1
		end
		acc += dt
		if acc > 0.4 then
			acc = 0
			local spec = Cam.spectate
			if not alive(spec) then
				step(1) -- the one we watched is out: next one
			end
			local watching = Cam.spectate
			if watching then
				nameLabel.Text = "SPECTATING  " .. string.upper(nameOf(watching))
				infoLabel.Text = healthOf(watching) .. (manual and "    [J] stop   [<] [>] switch" or "    [<] [>] switch")
			else
				nameLabel.Text = "NOBODY LEFT TO WATCH"
				infoLabel.Text = manual and "[J] stop" or ""
			end
		end
	end)
end

return SpectateClient
