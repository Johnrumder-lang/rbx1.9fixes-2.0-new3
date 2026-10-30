--!nonstrict
-- LeaderboardClient (v1.9.1): the five players with the most kills, always on screen (top right).
-- (The normal Tab list needs Roblox's CoreGui; this one is part of the game and hides with "Hide the whole HUD".)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared:WaitForChild("Settings"))
local UI = require(script.Parent:WaitForChild("UI"))

local C = UI.C
local player = Players.LocalPlayer

local LeaderboardClient = {}

function LeaderboardClient.Init()
	local gui = UI.make("ScreenGui", { Name = "Leaderboard", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8, Parent = player:WaitForChild("PlayerGui") })
	local panel = UI.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.fromOffset(190, 28 + 5 * 20 + 8),
		Accent = C.accent,
		Parent = gui,
	})
	local scale = UI.make("UIScale", { Parent = panel })
	scale:SetAttribute("Managed", true)
	UI.label({ Text = "TOP KILLS", Font = UI.FONT_TITLE, TextSize = 14, TextColor3 = C.amber, Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(120, 18), Parent = panel })
	local rows = {}
	for i = 1, 5 do
		local name = UI.label({ Text = "", TextSize = 14, Position = UDim2.fromOffset(12, 26 + (i - 1) * 20), Size = UDim2.fromOffset(120, 18), Parent = panel })
		local kills = UI.label({ Text = "", Font = UI.FONT_NUM, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -62, 0, 26 + (i - 1) * 20), Size = UDim2.fromOffset(50, 18), Parent = panel })
		rows[i] = { name = name, kills = kills }
	end
	task.spawn(function()
		while gui.Parent do
			task.wait(1)
			local cam = workspace.CurrentCamera
			scale.Scale = (cam and math.clamp(cam.ViewportSize.X / 1280, 0.6, 1) or 1) * UI.Global()
			gui.Enabled = Settings.Get("hideAll") ~= true
			local list = {}
			for _, p in Players:GetPlayers() do
				local ls = p:FindFirstChild("leaderstats")
				local k = ls and ls:FindFirstChild("Kills")
				if k and k:IsA("IntValue") then
					table.insert(list, { p = p, n = k.Value })
				end
			end
			table.sort(list, function(a, b)
				if a.n ~= b.n then
					return a.n > b.n
				end
				return a.p.UserId < b.p.UserId
			end)
			for i = 1, 5 do
				local e = list[i]
				local r = rows[i]
				if e then
					r.name.Text = e.p.DisplayName
					r.kills.Text = tostring(e.n)
					local me = e.p == player
					r.name.TextColor3 = me and C.amber or C.text
					r.kills.TextColor3 = me and C.amber or C.text
				else
					r.name.Text = ""
					r.kills.Text = ""
				end
			end
		end
	end)
end

return LeaderboardClient
