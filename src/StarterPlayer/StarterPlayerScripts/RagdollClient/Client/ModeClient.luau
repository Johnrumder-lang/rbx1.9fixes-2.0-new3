--!nonstrict
-- ModeClient: the game modes on this screen.
--   * the bar at the top: mode, round, time left, who is left, your team / role
--   * big announcements ("ROUND 2 - YOU ARE RED", "THE SEEKER IS COMING!", "BLUE TEAM WINS")
--   * "you are in the lobby" while you wait for the next round
--   * your team mates get a coloured outline (team fight) so you do not shoot them
--   * the server hands you a gun ("give"): it goes straight into your hand
--   * the server moves you somewhere ("teleport": city <-> sandbox): out of the car first

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local ModeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Mode") :: RemoteEvent

local Modules = script.Parent
local UI = require(Modules:WaitForChild("UI"))
local VehicleClient = require(Modules:WaitForChild("VehicleClient"))

local C = UI.C
local player = Players.LocalPlayer

local ModeClient = {}

local controller = nil
local gui: ScreenGui
local bar: Frame
local titleL: TextLabel
local infoL: TextLabel
local timeL: TextLabel
local badge: TextLabel
local lobbyNote: TextLabel
local bannerL: TextLabel
local highlights: { [Model]: Highlight } = {}

local NAMES = {
	teamfight = "TEAM FIGHT", ffa = "FREE FOR ALL", hideseek = "HIDE AND SEEK", monster = "MONSTER", zombies = "ZOMBIES", gungame = "GUN GAME",
	sniper = "SNIPER TOWER", hotpotato = "HOT POTATO", koth = "KING OF THE HILL",
}
-- (v2.0) the map vote between two rounds (ids and names as in MapService)
local MAPS = {
	{ "city", "THE CITY" }, { "horror", "BLACKWOOD ASYLUM" }, { "sea", "THE OPEN SEA" },
	{ "ikea", "THE MEGASTORE" }, { "valley", "DUST VALLEY" }, { "sky", "SKY ISLANDS" },
}
local votePanel: Frame
local summaryPanel: Frame
local summaryRows: Frame
local shownSummary = ""
local voteButtons: { [string]: TextButton } = {}
local myVote: string? = nil
local bittenL: TextLabel
local bombL: TextLabel

local function build()
	gui = UI.make("ScreenGui", {
		Name = "GameMode",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 8,
		Parent = player:WaitForChild("PlayerGui"),
	})
	bar = UI.panel({
		Name = "Bar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(380, 62),
		Accent = C.amber,
		Visible = false,
		Parent = gui,
	})
	titleL = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 14, TextColor3 = C.amber, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -120, 0, 18), Parent = bar })
	infoL = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 20, Position = UDim2.fromOffset(14, 26), Size = UDim2.new(1, -120, 0, 28), Parent = bar })
	timeL = UI.label({
		Text = "",
		Font = UI.FONT_NUM,
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 6),
		Size = UDim2.fromOffset(100, 30),
		Parent = bar,
	})
	badge = UI.label({
		Text = "",
		Font = UI.FONT_TITLE,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 38),
		Size = UDim2.fromOffset(110, 18),
		Parent = bar,
	})
	lobbyNote = UI.label({
		Text = "YOU ARE IN THE LOBBY - YOU PLAY AGAIN NEXT ROUND",
		Font = UI.FONT_TITLE,
		TextSize = 16,
		TextColor3 = C.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.5,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 82),
		Size = UDim2.fromOffset(520, 22),
		Visible = false,
		Parent = gui,
	})
	-- (v2.0) bitten: the countdown until you turn
	bittenL = UI.label({
		Text = "",
		Font = UI.FONT_TITLE,
		TextSize = 22,
		TextColor3 = C.bad,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 112),
		Size = UDim2.fromOffset(620, 28),
		Visible = false,
		Parent = gui,
	})
	-- (v2.0) hot potato: you hold the bomb
	bombL = UI.label({
		Text = "",
		Font = UI.FONT_TITLE,
		TextSize = 26,
		TextColor3 = C.bad,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.2,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 146),
		Size = UDim2.fromOffset(640, 32),
		Visible = false,
		Parent = gui,
	})
	-- (v2.8.1) the round's board: who did best (MVP first), shown while the next map is voted for
	summaryPanel = UI.panel({ Name = "RoundBoard", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 190), Size = UDim2.fromOffset(380, 60), Accent = C.amber, Visible = false, Parent = gui })
	UI.make("UIScale", { Scale = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 24) / 380), Parent = summaryPanel })
	UI.label({ Text = "ROUND BOARD", Font = UI.FONT_TITLE, TextSize = 14, TextColor3 = C.amber, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 18), Parent = summaryPanel })
	summaryRows = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -28, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = summaryPanel })
	UI.make("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = summaryRows })
	-- (v2.0) the map vote
	-- (three a row)
	local rows = math.ceil(#MAPS / 3)
	votePanel = UI.panel({ Name = "MapVote", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -120), Size = UDim2.fromOffset(460, 38 + rows * 52), Accent = C.amber, Visible = false, Parent = gui })
	UI.make("UIScale", { Scale = math.min(1, (workspace.CurrentCamera.ViewportSize.X - 24) / 460), Parent = votePanel })
	UI.label({ Text = "VOTE FOR THE NEXT MAP", Font = UI.FONT_TITLE, TextSize = 15, TextColor3 = C.amber, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 18), Parent = votePanel })
	for i, m in MAPS do
		local id = m[1]
		local col, row = (i - 1) % 3, (i - 1) // 3
		local b = UI.button({ Text = m[2], TextSize = 13, Size = UDim2.fromOffset(138, 46), Position = UDim2.fromOffset(12 + col * 147, 30 + row * 52), Parent = votePanel }, function()
			myVote = id
			ModeRemote:FireServer("mapvote", id)
		end)
		voteButtons[id] = b
	end
	bannerL = UI.label({
		Text = "",
		Font = UI.FONT_TITLE,
		TextSize = 40,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.3,
		TextWrapped = true,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.9, 0, 0, 100),
		TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0),
		Parent = gui,
	})
end

local bannerToken = 0
local function showBanner(text: string, color: Color3?)
	bannerToken += 1
	local tok = bannerToken
	bannerL.Text = text
	bannerL.TextColor3 = color or C.text
	bannerL.TextTransparency = 0
	bannerL.TextStrokeTransparency = 0.3
	SoundLibrary.Play("notify", nil, 1) -- (v2.8.2)
	task.delay(3.5, function()
		if tok == bannerToken then
			TweenService:Create(bannerL, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function fmtTime(s: number): string
	s = math.max(0, math.floor(s))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function teamColor(team: any): Color3?
	if team == "Red" then
		return C.red
	elseif team == "Blue" then
		return C.blue
	end
	return nil
end

local function updateHighlights(mode: any)
	local myTeam = player:GetAttribute("Team")
	local want: { [Model]: Color3 } = {}
	if mode == "teamfight" and myTeam then
		for _, p in Players:GetPlayers() do
			if p ~= player and p:GetAttribute("Team") == myTeam and not p:GetAttribute("InLobby") and p.Character then
				want[p.Character] = teamColor(myTeam) or C.text
			end
		end
	end
	-- (v2.0) bots on your side; in ZOMBIES the humans see each other, the zombies see each other
	local npcs = workspace:FindFirstChild("NPCs")
	local myRole = player:GetAttribute("Role")
	if npcs and (mode == "teamfight" or mode == "zombies" or mode == "monster") then
		for _, m in npcs:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("ModeBot") and not m:GetAttribute("Dead") then
				if mode == "teamfight" and myTeam and m:GetAttribute("Team") == myTeam then
					want[m] = teamColor(myTeam) or C.text
				elseif (mode == "zombies" or mode == "monster") and myRole and m:GetAttribute("Role") == myRole then
					want[m] = myRole == "Zombie" and C.good or C.blue
				end
			end
		end
	end
	-- (v2.0) the runners always see where the sniper is; everybody sees who holds the bomb
	if mode == "sniper" and myRole == "Runner" then
		for _, p in Players:GetPlayers() do
			if p:GetAttribute("Role") == "Sniper" and p.Character and not p:GetAttribute("InLobby") then
				want[p.Character] = C.bad
			end
		end
	elseif mode == "hotpotato" then
		for _, p in Players:GetPlayers() do
			if p ~= player and p.Character and p.Character:GetAttribute("PotatoHolder") then
				want[p.Character] = C.bad
			end
		end
		if npcs then
			for _, m in npcs:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("PotatoHolder") and not m:GetAttribute("Dead") then
					want[m] = C.bad
				end
			end
		end
	end
	if (mode == "zombies" or mode == "monster") and myRole then
		for _, p in Players:GetPlayers() do
			if p ~= player and p:GetAttribute("Role") == myRole and not p:GetAttribute("InLobby") and p.Character then
				want[p.Character] = myRole == "Zombie" and C.good or C.blue
			end
		end
	end
	for m, h in highlights do
		if not want[m] or not m.Parent then
			h:Destroy()
			highlights[m] = nil
		end
	end
	for m, col in want do
		if not highlights[m] then
			local h = Instance.new("Highlight")
			h.Name = "TeamMate"
			h.FillTransparency = 1
			h.OutlineColor = col
			h.OutlineTransparency = 0.1
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Adornee = m
			h.Parent = gui
			highlights[m] = h
		end
	end
end

local function update()
	local mode = workspace:GetAttribute("Mode")
	if typeof(mode) ~= "string" then
		bar.Visible = false
		summaryPanel.Visible = false
		lobbyNote.Visible = false
		bombL.Visible = false
		bittenL.Visible = false
		votePanel.Visible = false
		updateHighlights(nil)
		return
	end
	bar.Visible = true
	local phase = workspace:GetAttribute("ModePhase")
	local round = workspace:GetAttribute("ModeRound") or 1
	-- (v2.8.1) the round board
	local sum = workspace:GetAttribute("ModeSummary")
	if phase == "ended" and typeof(sum) == "string" and sum ~= "" then
		if sum ~= shownSummary then
			shownSummary = sum
			for _, c in summaryRows:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			local n = 0
			for row in string.gmatch(sum, "[^;]+") do
				n += 1
				local f = string.split(row, "=")
				local name, kills, pts, team = f[1] or "?", tonumber(f[2]) or 0, tonumber(f[3]) or 0, f[4] or ""
				local col = n == 1 and C.amber or (team == "Red" and Color3.fromRGB(255, 110, 100) or (team == "Blue" and Color3.fromRGB(110, 160, 255) or C.text))
				local text = string.format("%d   %s%s", n, name, n == 1 and "   MVP" or "")
				local line = UI.make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = n, Parent = summaryRows })
				UI.label({ Text = text, TextSize = n == 1 and 17 or 15, TextColor3 = col, Size = UDim2.new(0.7, 0, 1, 0), Parent = line })
				UI.label({ Text = kills .. " KILLS" .. (pts > 0 and ("  " .. pts .. " PTS") or ""), TextSize = 14, TextColor3 = col,
					TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.5, 0, 1, 0), Parent = line })
			end
			summaryPanel.Size = UDim2.fromOffset(380, 36 + n * 24)
		end
		summaryPanel.Visible = true
	else
		summaryPanel.Visible = false
	end
	titleL.Text = string.format("%s  -  ROUND %d", NAMES[mode] or string.upper(mode), round)
	local info = workspace:GetAttribute("ModeInfo") or ""
	if phase == "ended" then
		local w = workspace:GetAttribute("ModeWinner")
		info = typeof(w) == "string" and w or info
	end
	infoL.Text = info
	local ends = workspace:GetAttribute("ModeEnds")
	if typeof(ends) == "number" then
		local left = ends - workspace:GetServerTimeNow()
		timeL.Text = fmtTime(left)
		timeL.TextColor3 = (left < 15 and phase ~= "ended") and C.bad or C.text
	else
		timeL.Text = ""
	end
	local team = player:GetAttribute("Team")
	local role = player:GetAttribute("Role")
	if team then
		badge.Text = "TEAM " .. string.upper(team)
		badge.TextColor3 = teamColor(team) or C.text
	elseif role then
		badge.Text = string.upper(role)
		badge.TextColor3 = (role == "Seeker" or role == "Zombie" or role == "Sniper") and C.bad or C.good
	elseif mode == "koth" then
		local pts = player:GetAttribute("Points")
		badge.Text = typeof(pts) == "number" and string.format("YOU: %d", pts) or ""
		badge.TextColor3 = C.amber
	elseif mode == "gungame" then
		local tier = player:GetAttribute("GunTier")
		badge.Text = typeof(tier) == "number" and string.format("WEAPON %d", tier) or ""
		badge.TextColor3 = C.amber
	else
		badge.Text = ""
	end
	-- (v2.0) bitten
	local char = player.Character
	local bitten = char and char:GetAttribute("BittenUntil")
	if typeof(bitten) == "number" and not char:GetAttribute("Zombie") then
		local left = bitten - workspace:GetServerTimeNow()
		bittenL.Visible = left > 0
		bittenL.Text = string.format("BITTEN - YOU TURN IN %d s - A HEAL DART CURES YOU", math.max(0, math.ceil(left)))
	else
		bittenL.Visible = false
	end
	-- (v2.0) hot potato: you hold the bomb
	local holding = mode == "hotpotato" and char ~= nil and char:GetAttribute("PotatoHolder") == true
	bombL.Visible = holding
	if holding then
		local pe = workspace:GetAttribute("PotatoEnds")
		local left = typeof(pe) == "number" and math.max(0, pe - workspace:GetServerTimeNow()) or 0
		bombL.Text = string.format("YOU HAVE THE BOMB  %.1f s  -  TOUCH SOMEBODY!", left)
		bombL.TextTransparency = (left < 5 and os.clock() % 0.4 < 0.2) and 0.5 or 0
	end
	-- (v2.0) the map vote between two rounds
	local voting = phase == "ended" and workspace:GetAttribute("MapVote") == true
	votePanel.Visible = voting
	if voting then
		for id, b in voteButtons do
			local n = workspace:GetAttribute("MapVote_" .. id) or 0
			local name = ""
			for _, m in MAPS do
				if m[1] == id then
					name = m[2]
				end
			end
			b.Text = string.format("%s\n%d VOTE%s", name, n, n == 1 and "" or "S")
			local loaded = workspace:GetAttribute("MapLoaded") == id
			b.BackgroundColor3 = myVote == id and C.amber or (loaded and C.panel3 or C.panel2)
			b.TextColor3 = myVote == id and Color3.new(0, 0, 0) or C.text
		end
	else
		myVote = nil
	end
	local inLobby = player:GetAttribute("InLobby") == true
	lobbyNote.Visible = inLobby
	if inLobby then
		if phase == "hiding" and role == "Seeker" then
			lobbyNote.Text = "YOU ARE THE SEEKER - YOU GO IN WHEN THE HIDING TIME IS OVER"
		elseif phase == "ended" then
			lobbyNote.Text = "NEXT ROUND STARTS SOON"
		else
			lobbyNote.Text = "YOU ARE IN THE LOBBY - YOU PLAY AGAIN NEXT ROUND"
		end
	end
	updateHighlights(mode)
end

local function give(item: Instance)
	if typeof(item) ~= "Instance" or not item:IsA("Model") then
		return
	end
	-- wait until the gun is here and the body is ready
	-- (the new body's controller, not the old one's)
	local function ready(): boolean
		return item.PrimaryPart ~= nil and controller ~= nil and controller.ready == true
			and controller.character == player.Character and not controller.dead
	end
	for _ = 1, 50 do
		if ready() then
			break
		end
		task.wait(0.1)
	end
	if not ready() or not item.Parent then
		return
	end
	local side = "Right"
	if controller.hands and controller.hands.Right and controller.hands.Right.grip then
		side = "Left"
		if controller.hands.Left and controller.hands.Left.grip then
			return
		end
	end
	pcall(function()
		controller:_gripItem(side, item)
	end)
end

local function teleport(pos: Vector3)
	if typeof(pos) ~= "Vector3" or not controller or controller.dead then
		return
	end
	if VehicleClient.Leave() then
		task.wait(0.35)
	end
	if controller and not controller.dead then
		SoundLibrary.Play("teleport", controller.torso, 1)
		controller:_teleportTo(pos + Vector3.new(0, 3.2, 0), true)
		controller.airTime = 0
	end
end

function ModeClient.SetController(c)
	controller = c
end

function ModeClient.Init()
	build()
	ModeRemote.OnClientEvent:Connect(function(action, a, b)
		if action == "give" then
			task.spawn(give, a)
		elseif action == "teleport" then
			task.spawn(teleport, a)
		elseif action == "banner" and typeof(a) == "string" then
			showBanner(a, typeof(b) == "Color3" and b or nil)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			update()
		end
	end)
	update()
end

return ModeClient
