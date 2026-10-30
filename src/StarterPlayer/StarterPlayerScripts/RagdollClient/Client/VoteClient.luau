--!nonstrict
-- VoteClient (v1.9): the panel of a running community vote (top, under the mode bar), the messages about its
-- result, and the toasts when the owner gives you a power (or takes it back).
-- Keys: [.] yes, [,] no. On a phone / with the mouse free: the buttons.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Items = require(Shared:WaitForChild("Items"))
local UI = require(script.Parent:WaitForChild("UI"))
local Input = require(script.Parent:WaitForChild("Input"))

local C = UI.C
local player = Players.LocalPlayer
local VoteRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Vote") :: RemoteEvent

local VoteClient = {}

local GIFT_LABEL = { fly = "FLY", punch = "SUPER PUNCH", laser = "LASER EYES", nuke = "NUKE", virus = "VIRUS", physgun = "PHYSICS GUN", wonder = "CALAMITY SPEC",
	-- (v2.8 fix: these showed their raw ids)
	timestop = "TIME STOP", hotdog = "HOTDOG", sever = "SEVER", sandevistan = "SANDEVISTAN", colossus = "COLOSSUS PROTOCOL", zerohour = "ZERO HOUR",
	stillcut = "STILLWATER (STILL CUT)" }

local gui: ScreenGui
local panel: Frame
local title: TextLabel
local sub: TextLabel
local clock: TextLabel
local yesBar: Frame
local noBar: Frame
local counts: TextLabel
local yesB: TextButton
local noB: TextButton
local toastBox: Frame
local myVote: boolean? = nil
local lastEnds = 0

local function toast(text: string, color: Color3?)
	local l = UI.label({
		Text = text,
		Font = UI.FONT_TITLE,
		TextSize = 22,
		TextColor3 = color or C.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0.25,
		BackgroundColor3 = C.panel,
		Size = UDim2.new(1, 0, 0, 34),
		Parent = toastBox,
	})
	task.delay(5, function()
		if l.Parent then
			TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			task.wait(0.7)
			l:Destroy()
		end
	end)
end

local function cast(yes: boolean)
	if not workspace:GetAttribute("VoteText") then
		return
	end
	myVote = yes
	VoteRemote:FireServer("vote", yes)
end

local function build()
	gui = UI.make("ScreenGui", { Name = "VoteGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 14, Parent = player:WaitForChild("PlayerGui") })
	toastBox = UI.make("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 190),
		Size = UDim2.fromOffset(620, 200),
		Parent = gui,
	})
	UI.make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = toastBox })
	panel = UI.panel({
		Name = "VotePanel",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.fromOffset(400, 98),
		Accent = C.amber,
		Visible = false,
		Parent = gui,
	})
	UI.make("UIScale", { Name = "Scale", Parent = panel }):SetAttribute("Managed", true)
	title = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 20, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -90, 0, 24), Parent = panel })
	clock = UI.label({ Text = "", Font = UI.FONT_NUM, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -76, 0, 4), Size = UDim2.fromOffset(64, 26), Parent = panel })
	sub = UI.label({ Text = "", TextSize = 13, TextColor3 = C.dim, Position = UDim2.fromOffset(12, 30), Size = UDim2.new(1, -24, 0, 16), Parent = panel })
	local barBack = UI.make("Frame", { BackgroundColor3 = C.panel2, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 50), Size = UDim2.new(1, -24, 0, 8), Parent = panel })
	yesBar = UI.make("Frame", { BackgroundColor3 = C.good, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = barBack })
	noBar = UI.make("Frame", { BackgroundColor3 = C.bad, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0, 1), Parent = barBack })
	counts = UI.label({ Text = "", TextSize = 13, Position = UDim2.fromOffset(12, 64), Size = UDim2.fromOffset(120, 24), Parent = panel })
	yesB = UI.button({ Text = "YES  [.]", Size = UDim2.fromOffset(110, 26), Position = UDim2.new(1, -236, 0, 64), Parent = panel }, function()
		cast(true)
	end)
	noB = UI.button({ Text = "NO  [,]", Size = UDim2.fromOffset(110, 26), Position = UDim2.new(1, -118, 0, 64), Parent = panel }, function()
		cast(false)
	end)
end

function VoteClient.Init()
	build()
	-- small screens: smaller panel
	local function fit()
		local cam = workspace.CurrentCamera
		local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local s = math.min(1, (vs.X - 20) / 400)
		local sc = panel:FindFirstChild("Scale") :: UIScale
		sc.Scale = math.max(0.55, s) * (Input.lastDevice == "Touch" and 0.85 or 1) * UI.Global()
	end
	fit()

	RunService.Heartbeat:Connect(function()
		local text = workspace:GetAttribute("VoteText")
		local ends = workspace:GetAttribute("VoteEnds")
		if typeof(text) ~= "string" or typeof(ends) ~= "number" then
			panel.Visible = false
			return
		end
		local left = ends - workspace:GetServerTimeNow()
		if left <= 0 then
			panel.Visible = false
			return
		end
		if ends ~= lastEnds then
			lastEnds = ends
			myVote = nil
			fit()
		end
		panel.Visible = true
		local yes = workspace:GetAttribute("VoteYes") or 0
		local no = workspace:GetAttribute("VoteNo") or 0
		local total = math.max(1, yes + no)
		title.Text = text
		local kickVote = workspace:GetAttribute("VoteTarget") ~= nil
		local aboutMe = workspace:GetAttribute("VoteTarget") == player.UserId
		sub.Text = (kickVote and "started by " or "suggested by ") .. tostring(workspace:GetAttribute("VoteBy") or "?")
			.. (kickVote and "  -  more than 70% yes kicks" or "  -  more than 60% yes passes")
		yesB.Visible = not aboutMe
		noB.Visible = not aboutMe
		clock.Text = string.format("%d", math.ceil(left))
		yesBar.Size = UDim2.fromScale(yes / total, 1)
		noBar.Size = UDim2.fromScale(no / total, 1)
		counts.Text = string.format("yes %d    no %d", yes, no)
		yesB.BackgroundColor3 = myVote == true and C.good or C.panel2
		noB.BackgroundColor3 = myVote == false and C.bad or C.panel2
	end)

	UserInputService.InputBegan:Connect(function(io, processed)
		if processed or not workspace:GetAttribute("VoteText") then
			return
		end
		if io.KeyCode == Enum.KeyCode.Period then
			cast(true)
		elseif io.KeyCode == Enum.KeyCode.Comma then
			cast(false)
		end
	end)

	-- messages: a suggestion, a result
	local lastNotice = workspace:GetAttribute("VoteNoticeId") or 0
	workspace:GetAttributeChangedSignal("VoteNoticeId"):Connect(function()
		local id = workspace:GetAttribute("VoteNoticeId")
		if id == lastNotice then
			return
		end
		lastNotice = id
		local msg = workspace:GetAttribute("VoteNotice")
		if typeof(msg) == "string" then
			local failed = string.find(msg, "FAILED", 1, true) ~= nil
			local passed = string.find(msg, "PASSED", 1, true) ~= nil
			toast(msg, failed and C.bad or (passed and C.good or C.amber))
		end
	end)

	-- gifts from the owner
	for _, power in Items.POWERS do
		local attr = "Gift_" .. power
		local was = player:GetAttribute(attr) == true
		player:GetAttributeChangedSignal(attr):Connect(function()
			local now = player:GetAttribute(attr) == true
			if now ~= was then
				was = now
				toast((now and "You got: " or "Taken away: ") .. (GIFT_LABEL[power] or power), now and C.good or C.bad)
			end
		end)
	end
end

return VoteClient
