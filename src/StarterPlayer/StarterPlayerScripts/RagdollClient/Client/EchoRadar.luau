--!nonstrict
-- EchoRadar (v2.8): ECHO EARS (an implant). A small square radar on the left of the screen while the implant is in:
-- you in the middle, up = where your camera looks. Whoever MOVES within range shows as a dot (footsteps: standing still
-- people make no noise). Tier 1: players within 45 studs. Tier 2: 75 studs, bots and NPCs too (orange). Tier 3: 120 studs,
-- and a dot above / below you gets a small mark (a line over / under it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Settings = require(Shared:WaitForChild("Settings"))

local UI = require(script.Parent:WaitForChild("UI"))

local EchoRadar = {}

local player = Players.LocalPlayer
local SIZE = 140
local panel: Frame
local field: Frame
local dots: { Frame } = {}
local rangeL: TextLabel

local function dot(i: number): Frame
	local d = dots[i]
	if not d then
		d = UI.make("Frame", { Size = UDim2.fromOffset(7, 7), AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0, Visible = false, ZIndex = 3, Parent = field })
		UI.make("Frame", { Name = "Up", Size = UDim2.fromOffset(9, 2), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 3, Parent = d })
		UI.make("Frame", { Name = "Down", Size = UDim2.fromOffset(9, 2), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 2), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Visible = false, ZIndex = 3, Parent = d })
		dots[i] = d
	end
	return d
end

local function torsoOf(m: Instance?): BasePart?
	local t = m and m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

local function update()
	local char = player.Character
	local tier = char and char:GetAttribute("CyEcho")
	local me = torsoOf(char)
	local cam = workspace.CurrentCamera
	if typeof(tier) ~= "number" or tier <= 0 or not me or not cam or Settings.Get("hideAll") == true or Settings.Get("cyberHud") == false then
		panel.Visible = false
		return
	end
	panel.Visible = true
	local range = Config.EchoRange[math.clamp(tier, 1, 3)]
	rangeL.Text = string.format("ECHO  %d", range)
	local look = cam.CFrame.LookVector
	local fwd = Vector3.new(look.X, 0, look.Z)
	fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-fwd.Z, 0, fwd.X)
	local list = {}
	local function consider(m: Instance, npc: boolean)
		local t = torsoOf(m)
		if not t or m == char or (m :: any):GetAttribute("Dead") then
			return
		end
		local d = t.Position - me.Position
		local flat = Vector3.new(d.X, 0, d.Z)
		if flat.Magnitude > range or t.AssemblyLinearVelocity.Magnitude < 2 then
			return -- (too far, or standing still: no footsteps)
		end
		table.insert(list, { x = flat:Dot(right) / range, y = -flat:Dot(fwd) / range, h = d.Y, npc = npc })
	end
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			consider(p.Character, false)
		end
	end
	if tier >= 2 then
		local npcs = workspace:FindFirstChild("NPCs")
		for _, m in (npcs and npcs:GetChildren() or {}) do
			consider(m, true)
		end
	end
	for i, e in list do
		local d = dot(i)
		d.Visible = true
		d.Position = UDim2.fromScale(0.5 + e.x * 0.47, 0.5 + e.y * 0.47)
		d.BackgroundColor3 = e.npc and Color3.fromRGB(255, 160, 40) or Color3.fromRGB(255, 50, 50)
		local up = d:FindFirstChild("Up") :: Frame
		local down = d:FindFirstChild("Down") :: Frame
		up.Visible = tier >= 3 and e.h > 8
		down.Visible = tier >= 3 and e.h < -8
	end
	for i = #list + 1, #dots do
		dots[i].Visible = false
	end
end

function EchoRadar.Init()
	local gui = UI.make("ScreenGui", { Name = "EchoRadar", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 6, Parent = player:WaitForChild("PlayerGui") })
	panel = UI.panel({ Name = "Radar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, -20), Size = UDim2.fromOffset(SIZE, SIZE + 18), Accent = Color3.fromRGB(255, 170, 40), Visible = false, Parent = gui })
	rangeL = UI.label({ Text = "ECHO", Font = UI.FONT_TITLE, TextSize = 12, TextColor3 = Color3.fromRGB(255, 190, 90), Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -14, 0, 14), Parent = panel })
	field = UI.make("Frame", { Name = "Field", BackgroundColor3 = Color3.fromRGB(8, 10, 12), BackgroundTransparency = 0.25, BorderSizePixel = 0, Position = UDim2.fromOffset(6, 18), Size = UDim2.fromOffset(SIZE - 10, SIZE - 10), ClipsDescendants = true, Parent = panel })
	-- the cross and the rings (squares: the game's boxes have hard corners)
	UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(255, 170, 40), BackgroundTransparency = 0.75, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 1, 1, 0), Parent = field })
	UI.make("Frame", { BackgroundColor3 = Color3.fromRGB(255, 170, 40), BackgroundTransparency = 0.75, BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1), Parent = field })
	local mid = UI.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5), Parent = field })
	UI.make("UIStroke", { Color = Color3.fromRGB(255, 170, 40), Transparency = 0.7, Parent = mid })
	UI.make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(5, 5), ZIndex = 2, Parent = field })
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		update()
	end)
end

return EchoRadar
