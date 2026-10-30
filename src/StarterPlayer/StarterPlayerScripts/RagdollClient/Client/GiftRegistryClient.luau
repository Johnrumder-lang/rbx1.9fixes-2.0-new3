--!nonstrict
local UI = require(script.Parent.UI)
local Client = {}
function Client.Build(page)
	local remote = game.ReplicatedStorage.Remotes:WaitForChild("GiftRegistry")
	local status = UI.label({ Text = "Browse saved gifts, including offline recipients. Owners can manage all gifts.", TextSize = 13, TextWrapped = true, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 36), Parent = page })
	local box = UI.make("TextBox", { PlaceholderText = "User ID", Text = "", ClearTextOnFocus = false, TextSize = 14, Font = UI.FONT, BackgroundColor3 = UI.C.panel2, Size = UDim2.fromOffset(145, 28), Position = UDim2.fromOffset(12, 46), Parent = page })
	local function ask(action, id) status.Text = "Loading saved gifts..."; remote:FireServer(action, id) end
	UI.button({ Text = "FIND", Position = UDim2.fromOffset(164, 46), Size = UDim2.fromOffset(80, 28), Parent = page }, function() local id = tonumber(box.Text); if id then ask("lookup", id) end end)
	UI.button({ Text = "REFRESH", Position = UDim2.fromOffset(252, 46), Size = UDim2.fromOffset(100, 28), Parent = page }, function() ask("list") end)
	local nextButton = UI.button({ Text = "NEXT PAGE", Position = UDim2.fromOffset(360, 46), Size = UDim2.fromOffset(120, 28), Parent = page }, function() ask("next") end)
	local list = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 86), Size = UDim2.new(1, -24, 0, 10), Parent = page })
	local connection
	connection = remote.OnClientEvent:Connect(function(action, entries, more, message)
		if not page.Parent then connection:Disconnect(); return end
		if action == "result" then status.Text = tostring(more); return end
		if action ~= "list" then return end
		status.Text = message or "Saved gifts"
		nextButton.Visible = more == true
		list:ClearAllChildren()
		local y = 0
		for _, record in entries do
			UI.label({ Text = record.name .. " / " .. record.userId .. (record.online and " / ONLINE" or " / OFFLINE"), TextSize = 14, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 24), Parent = list })
			y += 28
			for i, gift in record.gifts do
				local armed, button = false, nil
				local label = "REMOVE " .. string.upper((gift:gsub("^%a+:", "")))
				button = UI.button({ Text = label, TextSize = 11, Position = UDim2.fromOffset(((i - 1) % 3) * 168, y + math.floor((i - 1) / 3) * 32), Size = UDim2.fromOffset(160, 28), Parent = list }, function()
					if not armed then
						armed = true; button.Text = "CONFIRM REMOVE"
						task.delay(5, function() if button.Parent then armed = false; button.Text = label end end)
					else remote:FireServer("revoke", record.userId, gift); armed = false; button.Text = "SAVING..." end
				end)
			end
			y += math.ceil(#record.gifts / 3) * 32 + 14
		end
		list.Size = UDim2.new(1, -24, 0, y)
		page.CanvasSize = UDim2.fromOffset(0, y + 100)
	end)
	page.Destroying:Connect(function() connection:Disconnect() end)
	ask("list")
end
return Client
