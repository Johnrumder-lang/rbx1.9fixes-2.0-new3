--!nonstrict
-- BountyClient (v2.8): M > BOUNTY (the bounties now, put money on somebody's head), "BOUNTY $..." over the heads, the news.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI = require(script.Parent:WaitForChild("UI"))

local BountyClient = {}

local player = Players.LocalPlayer
local C = UI.C
local RED = Color3.fromRGB(255, 60, 60)
local Remote: RemoteEvent
local gui: ScreenGui
local news: TextLabel

local function remote(): RemoteEvent
	if not Remote then
		Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bounty") :: RemoteEvent
	end
	return Remote
end

local function bountyOf(p: Player): number
	local b = p:GetAttribute("Bounty")
	return typeof(b) == "number" and b or 0
end

function BountyClient.BuildPage(page: ScrollingFrame)
	page.CanvasSize = UDim2.fromOffset(0, 600)
	UI.label({ Text = "BOUNTIES NOW", TextSize = 15, TextColor3 = RED, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 20), Parent = page })
	local listL = UI.label({ Text = "", TextSize = 13, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 130), Parent = page })
	UI.label({ Text = "PUT MONEY ON SOMEBODY'S HEAD (whoever kills them gets it)", TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(14, 164), Size = UDim2.new(1, -28, 0, 18), Parent = page })
	local who: Player? = nil
	local amount = Config.BountyMin
	local whoRow = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 186), Size = UDim2.new(1, -28, 0, 150), Parent = page })
	UI.make("UIGridLayout", { CellSize = UDim2.fromOffset(124, 26), CellPadding = UDim2.fromOffset(4, 4), Parent = whoRow })
	local amountL = UI.label({ Text = "", TextSize = 16, TextColor3 = C.amber, Position = UDim2.fromOffset(14, 342), Size = UDim2.fromOffset(240, 22), Parent = page })
	for i, add in { 50, 100, 500, 1000 } do
		UI.button({ Text = "+$" .. add, TextSize = 12, Position = UDim2.fromOffset(14 + (i - 1) * 84, 368), Size = UDim2.fromOffset(80, 26), Parent = page }, function()
			amount = math.min(Config.BountyMax, amount + add)
			amountL.Text = "AMOUNT: $" .. amount
		end)
	end
	UI.button({ Text = "RESET", TextSize = 12, Position = UDim2.fromOffset(14 + 4 * 84, 368), Size = UDim2.fromOffset(70, 26), Parent = page }, function()
		amount = Config.BountyMin
		amountL.Text = "AMOUNT: $" .. amount
	end)
	local placeB = UI.button({ Text = "PLACE THE BOUNTY", TextSize = 14, BackgroundColor3 = Color3.fromRGB(150, 20, 30), Position = UDim2.fromOffset(14, 402), Size = UDim2.fromOffset(250, 32), Parent = page }, function()
		if who then
			remote():FireServer("place", who.UserId, amount)
		end
	end)
	local function refresh()
		local rows = {}
		local all = Players:GetPlayers()
		table.sort(all, function(a, b)
			return bountyOf(a) > bountyOf(b)
		end)
		for _, p in all do
			if bountyOf(p) > 0 then
				table.insert(rows, string.upper(p.DisplayName) .. "  -  $" .. bountyOf(p))
			end
		end
		listL.Text = #rows > 0 and table.concat(rows, "\n") or "Nobody has a bounty. A 5 kill streak puts one on you."
		for _, c in whoRow:GetChildren() do
			if c:IsA("GuiButton") then
				c:Destroy()
			end
		end
		for _, p in Players:GetPlayers() do
			if p ~= player then
				UI.button({ Text = p.DisplayName, TextSize = 12, BackgroundColor3 = p == who and Color3.fromRGB(150, 20, 30) or C.panel2, Parent = whoRow }, function()
					who = p
					refresh()
				end)
			end
		end
		amountL.Text = "AMOUNT: $" .. amount
		placeB.Text = who and ("PLACE $" .. amount .. " ON " .. string.upper(who.DisplayName)) or "PICK SOMEBODY"
	end
	page:GetPropertyChangedSignal("Visible"):Connect(refresh)
	Players.PlayerAdded:Connect(refresh)
	Players.PlayerRemoving:Connect(function(p)
		if who == p then
			who = nil
		end
		task.defer(refresh)
	end)
	refresh()
	task.spawn(function()
		while page.Parent do
			task.wait(2)
			if page.Visible then
				local text = listL.Text
				refresh()
				local _ = text
			end
		end
	end)
end

-- "BOUNTY $..." over every head that has one
local tags: { [Player]: BillboardGui } = {}
local function updateTags()
	for _, p in Players:GetPlayers() do
		local b = bountyOf(p)
		local ch = p.Character
		local head = ch and ch:FindFirstChild("Head")
		local tag = tags[p]
		if b > 0 and head then
			if not tag or tag.Adornee ~= head then
				if tag then
					tag:Destroy()
				end
				tag = Instance.new("BillboardGui")
				tag.Name = "BountyTag"
				tag.Size = UDim2.fromOffset(160, 22)
				tag.StudsOffset = Vector3.new(0, 4.4, 0)
				tag.MaxDistance = 140
				tag.LightInfluence = 0
				tag.Adornee = head
				UI.label({ Name = "T", Text = "", TextSize = 16, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3, Size = UDim2.fromScale(1, 1), Parent = tag })
				tag.Parent = gui
				tags[p] = tag
			end
			local t = tag:FindFirstChild("T") :: TextLabel
			t.Text = "BOUNTY $" .. b
			tag.Enabled = not (ch and ch:GetAttribute("CloakSeen"))
		elseif tag then
			tag:Destroy()
			tags[p] = nil
		end
	end
end

function BountyClient.Init()
	gui = UI.make("ScreenGui", { Name = "BountyGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 8, Parent = player:WaitForChild("PlayerGui") })
	news = UI.label({ Text = "", TextSize = 18, TextColor3 = RED, TextTransparency = 1, TextStrokeTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(760, 24), Parent = gui })
	remote().OnClientEvent:Connect(function(action, text)
		if action == "news" or action == "msg" then
			news.Text = tostring(text)
			news.TextTransparency = 0
			news.TextStrokeTransparency = 0.4
			TweenService:Create(news, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		if tags[p] then
			tags[p]:Destroy()
			tags[p] = nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			updateTags()
		end
	end)
end

return BountyClient
