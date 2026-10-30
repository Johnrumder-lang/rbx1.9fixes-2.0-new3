--!nonstrict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UI = require(script.Parent.UI)
local Input = require(script.Parent.Input)
local Sounds = require(game.ReplicatedStorage.Shared.SoundLibrary)
local Jobs = {}
local player = Players.LocalPlayer
local remote, panel, body, tracker, note, marker
local catalog, active, cooldown = {}, nil, 0
local function close()
	if panel then panel.Visible = false end
	Input.freeCursor = false
end
local function refresh()
	if not body then return end
	body:ClearAllChildren()
	local y = 0
	if active then
		UI.label({ Text = active.name .. "  /  $" .. active.reward .. "\n\n" .. active.objective .. "\n\nPROGRESS " .. active.progress .. " / " .. active.goal, TextSize = 16, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.new(1, -12, 0, 150), Parent = body })
		UI.button({ Text = "CANCEL CONTRACT", Position = UDim2.fromOffset(0, 160), Size = UDim2.new(1, -12, 0, 36), Parent = body }, function() remote:FireServer("cancel") end)
	else
		for _, id in { "assassination", "courier", "cleanup" } do
			local d = catalog[id]
			if d then
				local row = UI.panel({ Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, -8, 0, 110), Parent = body })
				UI.label({ Text = d.name .. "  /  $" .. d.reward, TextSize = 17, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -20, 0, 22), Parent = row })
				UI.label({ Text = d.description, TextSize = 13, TextWrapped = true, TextColor3 = UI.C.dim, Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 36), Parent = row })
				UI.button({ Text = "ACCEPT", TextSize = 13, Position = UDim2.fromOffset(12, 76), Size = UDim2.fromOffset(110, 26), Parent = row }, function() remote:FireServer("accept", id) end)
				y += 118
			end
		end
	end
	body.CanvasSize = UDim2.fromOffset(0, math.max(y, 220))
end
function Jobs.Open()
	panel.Visible = true
	Input.freeCursor = true
	remote:FireServer("list")
	refresh()
end
function Jobs.Init()
	remote = game.ReplicatedStorage.Remotes:WaitForChild("Jobs")
	local gui = UI.make("ScreenGui", { Name = "Contracts", ResetOnSpawn = false, DisplayOrder = 29, Parent = player:WaitForChild("PlayerGui") })
	panel = UI.panel({ Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(510, 480), Parent = gui })
	local scale = UI.make("UIScale", { Name = "Scale", Parent = panel }); scale:SetAttribute("Managed", true)
	local function fit() local v = workspace.CurrentCamera.ViewportSize; scale.Scale = math.min(1, (v.X - 24) / 510, (v.Y - 30) / 480) end
	fit(); workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	UI.label({ Text = "FIXER / CONTRACTS", TextSize = 23, Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(360, 28), Parent = panel })
	UI.button({ Text = "CLOSE", Size = UDim2.fromOffset(75, 28), Position = UDim2.new(1, -92, 0, 16), Parent = panel }, close)
	note = UI.label({ Text = "One contract at a time. Payment on completion.", TextSize = 12, TextColor3 = UI.C.dim, TextWrapped = true, Position = UDim2.fromOffset(18, 50), Size = UDim2.new(1, -36, 0, 34), Parent = panel })
	body = UI.make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, Position = UDim2.fromOffset(18, 94), Size = UDim2.new(1, -36, 1, -112), Parent = panel })
	tracker = UI.label({ Text = "", TextSize = 13, TextColor3 = UI.C.text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 98), Size = UDim2.fromOffset(300, 70), Parent = gui })
	UI.button({ Text = "JOBS", Position = UDim2.new(1, -105, 0, 58), Size = UDim2.fromOffset(85, 30), Parent = gui }, function() if panel.Visible then close() else Jobs.Open() end end)
	remote.OnClientEvent:Connect(function(action, a, message, cd)
		if action == "catalog" then catalog = a
		elseif action == "state" then
			active = a or nil; cooldown = cd or 0
			if marker then marker:Destroy(); marker = nil end
			if active and active.target then
				marker = Instance.new("Highlight"); marker.Adornee = active.target; marker.FillTransparency = 1
				marker.OutlineColor = Color3.new(1, 1, 1); marker.Parent = gui
			end
			if message then note.Text = message; Sounds.Play(string.find(message, "COMPLETE", 1, true) and "questDone" or "beep", nil, 0.6) end
		end
		refresh()
	end)
	RunService.Heartbeat:Connect(function()
		if Input.IsControlled() and panel.Visible then close() end
		if active then
			local point = active.point
			local root = active.target and active.target:FindFirstChild("Torso")
			if root then point = root.Position end
			local mine = player.Character and player.Character:FindFirstChild("Torso")
			local distance = point and mine and (point - mine.Position).Magnitude
			tracker.Text = active.name .. "  " .. active.progress .. "/" .. active.goal .. "\n" .. math.max(0, math.ceil(active.deadline - workspace:GetServerTimeNow())) .. "s" .. (distance and ("  /  " .. math.floor(distance) .. " studs") or "")
			if point and mine then
				local direction = workspace.CurrentCamera.CFrame:VectorToObjectSpace(point - mine.Position)
				tracker.Text ..= "\n" .. (math.abs(direction.X) > math.abs(direction.Z) and (direction.X > 0 and "RIGHT >" or "< LEFT") or (direction.Z < 0 and "AHEAD" or "BEHIND"))
			end
		else tracker.Text = cooldown > workspace:GetServerTimeNow() and ("NEXT CONTRACT IN " .. math.ceil(cooldown - workspace:GetServerTimeNow()) .. "s") or "" end
	end)
	game:GetService("UserInputService").InputBegan:Connect(function(io) if io.KeyCode == Enum.KeyCode.Escape and panel.Visible then close() end end)
		if Input.IsControlled() then return end
	player.CharacterAdded:Connect(close)
	remote:FireServer("list")
end
return Jobs
