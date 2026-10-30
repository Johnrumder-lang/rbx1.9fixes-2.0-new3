--!nonstrict
local Players = game:GetService("Players")
local UI = require(script.Parent.UI)
local Input = require(script.Parent.Input)
local Sounds = require(game.ReplicatedStorage.Shared.SoundLibrary)
local Client = {}
local player = Players.LocalPlayer
local clanRemote, dailyRemote, menu
local clanPage, dailyPage
local clanState, dailyState = {}, {}
local draftName = ""
local initialized, prompted = false, nil
local function label(page, text, y, height, size)
	return UI.label({ Text = text, TextWrapped = true, TextSize = size or 14, Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, height or 28), Parent = page })
end
local function button(page, text, x, y, width, call, confirm)
	local b, armed
	b = UI.button({ Text = text, TextSize = 12, Size = UDim2.fromOffset(width, 28), Position = UDim2.fromOffset(x, y), Parent = page }, function()
		if Input.IsControlled() then return end
		if confirm and not armed then
			armed = true; b.Text = "CONFIRM"
			task.delay(4, function() if b.Parent then armed = false; b.Text = text end end)
			return
		end
		armed = false; b.Text = "..."; call()
	end)
	return b
end
local renderClans, renderDaily
local function request(remote, action, value)
	if remote and not Input.IsControlled() then remote:FireServer(action, value) end
end
renderClans = function()
	local page = clanPage
	if not page or not page.Parent then return end
	page:ClearAllChildren()
	label(page, "CLANS", 6, 28, 22)
	label(page, clanState.error or clanState.message or "Create a clan for $2,500. Membership and your overhead tag are saved.", 38, 42)
	button(page, "REFRESH", 432, 6, 100, function() request(clanRemote, "state") end)
	local clan, y = clanState.clan, 90
	if not clan then
		local box = UI.make("TextBox", { Text = draftName, Name = "ClanName", PlaceholderText = "Clan name (3–24 characters)", ClearTextOnFocus = false, Font = UI.FONT, TextSize = 15, TextColor3 = UI.C.text, PlaceholderColor3 = UI.C.dim, BackgroundColor3 = UI.C.panel2, BorderSizePixel = 0, Position = UDim2.fromOffset(14, y), Size = UDim2.fromOffset(350, 32), Parent = page })
		box:GetPropertyChangedSignal("Text"):Connect(function() draftName = box.Text end)
		button(page, "CREATE · $2,500", 374, y, 158, function() request(clanRemote, "create", box.Text) end, true)
		y += 52; label(page, "INVITATIONS", y, 24, 17); y += 32
		if #((clanState.invites) or {}) == 0 then label(page, "No invitations. A clan leader can invite you from this server.", y, 44); y += 52 end
		for _, invitation in clanState.invites or {} do
			label(page, invitation.name .. " · invited by " .. invitation.by, y, 32)
			button(page, "JOIN", 14, y + 34, 120, function() request(clanRemote, "accept", invitation.id) end)
			button(page, "DECLINE", 144, y + 34, 120, function() request(clanRemote, "decline", invitation.id) end)
			y += 78
		end
	else
		local owner = clan.owner == player.UserId
		label(page, clan.name .. "  ·  " .. #clan.members .. "/50 members", y, 30, 19)
		y += 38
		button(page, owner and "DISBAND CLAN" or "LEAVE CLAN", 14, y, 180, function() request(clanRemote, owner and "disband" or "leave") end, true)
		y += 44
		for _, m in clan.members do
			local name = label(page, (m.display or m.name) .. "  @" .. m.name .. (m.userId == clan.owner and " · LEADER" or ""), y, 30)
			name.Size = UDim2.new(1, -145, 0, 30)
			if owner and m.userId ~= player.UserId then button(page, "REMOVE", 432, y, 100, function() request(clanRemote, "kick", m.userId) end, true) end
			y += 36
		end
		if owner then
			y += 12; label(page, "INVITE FROM THIS SERVER", y, 26, 17); y += 34
			for _, p in Players:GetPlayers() do
				if p ~= player and not p:GetAttribute("ClanId") then
					local name = label(page, p.DisplayName .. "  @" .. p.Name, y, 28); name.Size = UDim2.new(1, -145, 0, 28)
					button(page, "INVITE", 432, y, 100, function() request(clanRemote, "invite", p.UserId) end)
					y += 36
				end
			end
		end
	end
	page.CanvasSize = UDim2.fromOffset(0, y + 20)
end
renderDaily = function()
	local page = dailyPage
	if not page or not page.Parent then return end
	page:ClearAllChildren()
	label(page, "DAILY REWARDS", 6, 28, 22)
	label(page, "Claim once per UTC day. Day 3: 1 skin · Day 7: 3 skins. Missing a day restarts the streak.", 38, 40)
	for day = 1, 7 do
		local active = dailyState.step == day
		local card = UI.panel({ Position = UDim2.fromOffset(14 + (day - 1) * 74, 88), Size = UDim2.fromOffset(68, 96), BackgroundColor3 = active and UI.C.panel2 or UI.C.panel, Parent = page })
		UI.label({ Text = "DAY " .. day, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 20), Parent = card })
		UI.label({ Text = day == 3 and "1\nSKIN" or (day == 7 and "3\nSKINS" or "$25\n–1,000"), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 40), Parent = card })
		if active then UI.label({ Text = dailyState.available and "TODAY" or "CLAIMED", TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 16), Parent = card }) end
	end
	label(page, "Days 1, 2, 4, 5, 6: money + a 0.5% chance of a tier 1 implant case. Skin days award unowned skins; if all are owned, $250 per missing skin.", 196, 44, 12)
	local claim = button(page, dailyState.available and "CLAIM DAY " .. tostring(dailyState.step) or "CLAIMED · NEXT AT 00:00 UTC", 14, 252, 350, function() if dailyState.available then request(dailyRemote, "claim") end end)
	claim.Active = dailyState.available == true; claim.AutoButtonColor = dailyState.available == true
	button(page, "REFRESH", 374, 252, 158, function() request(dailyRemote, "state") end)
	label(page, dailyState.message or "Rewards are saved when claimed. Collect implant cases below when ready.", 290, 44)
	local y = 344
	for _, case in dailyState.cases or {} do
		local name = label(page, case.name .. " · TIER 1", y, 30); name.Size = UDim2.new(1, -150, 0, 30)
		button(page, "TAKE CASE", 412, y, 120, function() request(dailyRemote, "take", case.token) end)
		y += 36
	end
	page.CanvasSize = UDim2.fromOffset(0, y + 16)
end
function Client.BuildClans(page) clanPage = page; renderClans() end
function Client.BuildDaily(page) dailyPage = page; renderDaily() end
function Client.Refresh(name)
	if name == "clans" then request(clanRemote, "state") elseif name == "daily" then request(dailyRemote, "state") end
end
function Client.Init(settingsMenu)
	if initialized then return end
	initialized, menu = true, settingsMenu
	clanRemote = game.ReplicatedStorage.Remotes:WaitForChild("Clans")
	dailyRemote = game.ReplicatedStorage.Remotes:WaitForChild("DailyRewards")
	clanRemote.OnClientEvent:Connect(function(action, data)
		if action == "state" then clanState = data; renderClans()
		elseif action == "invite" then
			pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = "CLAN INVITATION", Text = data .. " invited you. Open M > CLANS to join.", Duration = 8 }) end)
			Sounds.Play("questDing", nil, 0.5)
		end
	end)
	dailyRemote.OnClientEvent:Connect(function(action, data)
		if action == "state" then dailyState = data; renderDaily()
		elseif action == "claimed" then Sounds.Play("questDing", nil, 0.7) end
	end)
	request(clanRemote, "state"); request(dailyRemote, "state")
	task.spawn(function()
		while true do
			task.wait(2)
			local ch = player.Character
			if dailyState.available and prompted ~= dailyState.date and ch and ch:GetAttribute("RagdollRig") and not ch:GetAttribute("Dead") and not Input.IsControlled()
				and not Input.menuOpen and not Input.cutscene and not Input.promptOpen and not Input.freeCam then
				prompted = dailyState.date
				menu.OpenPage("daily")
			end
		end
	end)
end
return Client
