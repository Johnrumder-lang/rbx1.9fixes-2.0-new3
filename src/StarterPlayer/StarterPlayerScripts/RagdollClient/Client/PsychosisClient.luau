--!nonstrict
-- All echoes and screen interference exist on this client only.
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local UI = require(script.Parent.UI)
local Cam = require(script.Parent.CameraController)
local Sounds = require(game.ReplicatedStorage.Shared.SoundLibrary)
local Settings = require(game.ReplicatedStorage.Shared.Settings)
local Psycho = require(game.ReplicatedStorage.Shared.PsychosisState)
local Client = {}
local player = Players.LocalPlayer
local templates, order = {}, {}
local ghost, expires, episodeEnd, strength = nil, 0, 0, 0
local function clear()
	if ghost then ghost:Destroy(); ghost = nil end
end
local function snapshot(id, source)
	if typeof(source) ~= "Instance" or not source:IsA("Model") then return end
	local old = source.Archivable
	source.Archivable = true
	local ok, copy = pcall(function() return source:Clone() end)
	source.Archivable = old
	if not ok or not copy then return end
	for _, d in copy:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Constraint") or d:IsA("JointInstance") or d:IsA("Sound") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("BillboardGui") then d:Destroy()
		elseif d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanTouch = false; d.CanQuery = false end
	end
	local root = copy:FindFirstChild("Torso")
	if root then
		copy.PrimaryPart = root
		-- Restore the recognizable avatar silhouette after a dismembering kill.
		local offsets = { Head = Vector3.new(0, 1.5, 0), ["Left Arm"] = Vector3.new(-1.5, 0, 0), ["Right Arm"] = Vector3.new(1.5, 0, 0), ["Left Leg"] = Vector3.new(-0.5, -2, 0), ["Right Leg"] = Vector3.new(0.5, -2, 0) }
		for name, offset in offsets do
			local part = copy:FindFirstChild(name)
			if part and part:IsA("BasePart") then part.CFrame = root.CFrame * CFrame.new(offset) end
		end
	end
	templates[id] = copy; table.insert(order, id)
	while #order > 6 do local first = table.remove(order, 1); if templates[first] then templates[first]:Destroy(); templates[first] = nil end end
end
function Client.Init()
	local remote = game.ReplicatedStorage.Remotes:WaitForChild("Psychosis")
	local gui = UI.make("ScreenGui", { Name = "NeuralInterference", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 43, Parent = player.PlayerGui })
	local shade = UI.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 10, Parent = gui })
	local label = UI.label({ Text = "", TextSize = 19, TextColor3 = Color3.new(1, 1, 1), TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromScale(0.2, 0.2), Size = UDim2.fromScale(0.6, 0.1), ZIndex = 12, Parent = gui })
	local bars = {}
	for i = 1, 8 do bars[i] = UI.make("Frame", { Size = UDim2.new(1, 0, 0, i % 3 + 1), BackgroundColor3 = Color3.new(0.8, 0.8, 0.8), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 11, Parent = gui }) end
	local blur = Instance.new("BlurEffect"); blur.Name = "NeuralBlur"; blur.Size = 0; blur.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect"); cc.Name = "NeuralDesaturation"; cc.Parent = Lighting
	local dof = Instance.new("DepthOfFieldEffect"); dof.Name = "NeuralDistance"; dof.Enabled = false; dof.FocusDistance = 8; dof.InFocusRadius = 10; dof.FarIntensity = 0.65; dof.NearIntensity = 0; dof.Parent = Lighting
	remote.OnClientEvent:Connect(function(action, a, b, c)
		if action == "remember" then snapshot(a, b)
		elseif action == "reset" then clear(); episodeEnd, strength = 0, 0
		elseif action == "clear" then clear()
		elseif action == "phantom" then
			if Psycho.Level(player) <= 0 then return end
			clear()
			local template = templates[a]
			if template and typeof(b) == "Vector3" then
				ghost = template:Clone(); ghost.Name = "NeuralEcho"
				local target = player.Character and player.Character:FindFirstChild("Torso")
				local look = target and Vector3.new(target.Position.X, b.Y, target.Position.Z) or (b + Vector3.zAxis)
				ghost:PivotTo(CFrame.lookAt(b, look))
				ghost.Parent = workspace.CurrentCamera
				expires = c
				for _, d in ghost:GetDescendants() do
					if d:IsA("BasePart") and d.Transparency < 1 then d.Transparency = math.max(0.32, d.Transparency); d.Color = d.Color:Lerp(Color3.fromRGB(125, 125, 140), 0.35) end
				end
			end
		elseif action == "episode" then
			if Psycho.Level(player) <= 0 then return end
			strength = a; episodeEnd = workspace:GetServerTimeNow() + b
			label.Text = ({ "MEMORY INTEGRITY LOST", "THEY REMEMBER YOU", "NEURAL FEEDBACK", "TARGET SIGNAL UNRELIABLE" })[math.random(1, 4)]
			Sounds.Play("heartbeat", nil, 0.5)
		elseif action == "fault" then
			label.Text = ({ "CYBERWARE OFFLINE", "LOCOMOTION FAULT", "GRIP SERVO FAILURE" })[a] or "NEURAL FAULT"
			episodeEnd = math.max(episodeEnd, workspace:GetServerTimeNow() + b)
			strength = math.max(strength, 0.7); Sounds.Play("static", nil, 0.35)
		elseif action == "detonate" then
			clear(); Cam.Shake(1.2); label.Text = "NEURAL FEEDBACK / CRITICAL"; episodeEnd = workspace:GetServerTimeNow() + 2
		end
	end)
	local tick = 0
	RunService.RenderStepped:Connect(function(dt)
		local now = workspace:GetServerTimeNow()
		local alive = player.Character and not player.Character:GetAttribute("Dead")
		if Psycho.Level(player) <= 0 then clear(); episodeEnd, strength = 0, 0; blur.Size = 0 end
		if ghost and (now >= expires or not alive) then clear() end
		local fx = now < episodeEnd and alive and strength or 0
		local reduced = Settings.Get("hallucinations") == false
		if reduced then fx *= 0.25 end
		blur.Size += (fx * 13 - blur.Size) * math.min(1, dt * 5)
		cc.Saturation, cc.Contrast = -fx * 0.65, fx * 0.28
		dof.Enabled = ghost ~= nil and not reduced
		shade.BackgroundTransparency = 1 - fx * (0.1 + 0.08 * math.sin(now * 3) ^ 2)
		label.TextTransparency = 1 - fx * 0.8
		tick += dt
		if tick > 0.16 then
			tick = 0
			for _, bar in bars do
				bar.BackgroundTransparency = 1 - fx * math.random() * 0.16
				bar.Position = UDim2.fromScale(math.random() * 0.08, math.random())
			end
		end
	end)
	player.CharacterAdded:Connect(function() clear(); episodeEnd = 0 end)
end
return Client
