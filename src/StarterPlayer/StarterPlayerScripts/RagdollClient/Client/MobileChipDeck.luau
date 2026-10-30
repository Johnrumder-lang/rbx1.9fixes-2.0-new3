--!nonstrict
-- Touch inventory: readable rows, scrollable pages, and no keyboard-only actions.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Chips = require(Shared:WaitForChild("Chips"))
local UI = require(script.Parent:WaitForChild("UI"))
local Settings = require(Shared:WaitForChild("Settings"))

local MobileChipDeck = {}

function MobileChipDeck.new(parentGui: ScreenGui, actions: any)
	-- Respect the device and Roblox top-bar insets, including after rotation.
	local gui = UI.make("ScreenGui", { Name = "MobileChipInventory", ResetOnSpawn = false, IgnoreGuiInset = false,
		DisplayOrder = parentGui.DisplayOrder - 1, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = parentGui.Parent })
	gui:SetAttribute("NoGlobalScale", true)
	local root = UI.make("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = UI.C.panel,
		BackgroundTransparency = 0.2, BorderSizePixel = 0, Active = true, Visible = false, Parent = gui })
	local panel = UI.panel({ Name = "Inventory", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Parent = root })
	local scale = UI.make("UIScale", { Parent = panel })
	scale:SetAttribute("Managed", true)
	local function fit()
		local size = root.AbsoluteSize
		if size.X < 1 or size.Y < 1 then return end
		local width, height = math.max(1, size.X - 16), math.max(1, size.Y - 16)
		-- Keep touch targets at least 44 px on ordinary phone/tablet viewports.
		scale.Scale = math.min(math.clamp(UI.Global(), 1, 1.35), width / 280, height / 240)
		panel.Size = UDim2.fromOffset(math.min(560, width / scale.Scale), math.min(640, height / scale.Scale))
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	Settings.Changed:Connect(function(key) if key == "uiScale" then fit() end end)
	fit()
	UI.label({ Text = "CHIP INVENTORY", TextSize = 20, Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -106, 0, 26), Parent = panel })
	local cash = UI.label({ Text = "", TextSize = 13, TextColor3 = UI.C.dim, Position = UDim2.fromOffset(12, 38), Size = UDim2.new(1, -106, 0, 20), Parent = panel })
	UI.button({ Name = "Close", Text = "CLOSE", Size = UDim2.fromOffset(80, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Parent = panel }, actions.close)
	local lists, tabs = {}, {}
	local selected = "Bag"
	local function selectPage(name)
		selected = name
		for key, list in lists do
			list.Visible = key == name
			tabs[key].BackgroundColor3 = key == name and UI.C.panel3 or UI.C.panel2
		end
	end
	for i, key in { "Bag", "Slots" } do
		tabs[key] = UI.button({ Name = key .. "Tab", Text = key == "Bag" and "CHIPS" or "SLOTS", TextSize = 16,
			Position = UDim2.new((i - 1) * 0.5, i == 1 and 12 or 4, 0, 66), Size = UDim2.new(0.5, -16, 0, 44), Parent = panel }, function() selectPage(key) end)
		local list = UI.make("ScrollingFrame", { Name = key, BackgroundTransparency = 1, BorderSizePixel = 0, Active = true,
			Position = UDim2.fromOffset(12, 118), Size = UDim2.new(1, -24, 1, -182), ScrollBarThickness = 6,
			ScrollingDirection = Enum.ScrollingDirection.Y, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.fromOffset(0, 0), Parent = panel })
		UI.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		lists[key] = list
	end
	UI.button({ Name = "StoreHeld", Text = "STORE HELD CHIP", TextSize = 16, AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 44), Parent = panel }, function()
		selectPage("Bag")
		actions.storeHeld()
	end)
	selectPage(selected)
	local function row(list, order, title, subtitle)
		local r = UI.make("Frame", { Name = "Row" .. order, LayoutOrder = order, BackgroundColor3 = UI.C.panel2,
			BorderSizePixel = 0, Size = UDim2.new(1, -10, 0, 104), Parent = list })
		UI.label({ Text = title, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 24), Parent = r })
		UI.label({ Text = subtitle, TextSize = 12, TextColor3 = UI.C.dim, TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(8, 28), Size = UDim2.new(1, -16, 0, 18), Parent = r })
		return r
	end
	local function rowButton(r, name, text, right, fn)
		return UI.button({ Name = name, Text = text, TextSize = 14, Position = UDim2.new(right and 0.5 or 0, right and 4 or 8, 0, 52),
			Size = UDim2.new(0.5, -12, 0, 44), Parent = r }, fn)
	end
	local function describe(chip)
		local def = Chips.ById[chip.id]
		return chip.name or (def and def.name) or chip.id,
			chip.video and (chip.trojan and "VIDEO / TROJAN" or "VIDEO") or (string.upper(chip.kind or "chip") .. " / T" .. (chip.tier or 1))
	end
	local function refresh(deck, cashText, scanOn, zoomOn)
		cash.Text = cashText
		for _, list in lists do
			for _, child in list:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
		end
		local occupied = 0
		for i = 1, Config.ChipSlots do
			local chip = deck.slots[i]
			local title, sub = "EMPTY SLOT", "Choose SLOT on a chip in your bag."
			if chip then title, sub = describe(chip); occupied += 1 end
			local r = row(lists.Slots, i, i .. " / " .. title, sub)
			if chip then
				if chip.id == "scan" or chip.id == "zoom" then
					local on = (chip.id == "scan" and scanOn) or (chip.id == "zoom" and zoomOn)
					rowButton(r, "Toggle", on and "TURN OFF" or "TURN ON", false, function() actions.toggle(i) end)
				end
				rowButton(r, "Eject", "EJECT", true, function() actions.eject(i) end)
			end
		end
		tabs.Slots.Text = "SLOTS " .. occupied .. "/" .. Config.ChipSlots
		tabs.Bag.Text = "CHIPS " .. #deck.bag
		for i, chip in deck.bag do
			local title, sub = describe(chip)
			local r = row(lists.Bag, i, title, sub)
			rowButton(r, "Take", "TAKE", false, function() actions.take(chip.uid) end)
			if chip.video or chip.kind == "video" then
				rowButton(r, "Play", "PLAY", true, function() actions.play(chip.uid) end)
			else
				rowButton(r, "Slot", "SLOT", true, function() actions.install(chip.uid) end)
			end
		end
		if #deck.bag == 0 then
			UI.label({ Text = "No chips in your bag.\nHold a chip and tap STORE HELD CHIP, or buy one at a computer.", TextSize = 16,
				TextWrapped = true, Size = UDim2.new(1, -10, 0, 100), Parent = lists.Bag })
		end
	end
	return { panel = root, refresh = refresh }
end

return MobileChipDeck
