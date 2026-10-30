--!nonstrict
-- ShopClient (v2.1d): the SKINS page of the M menu (a tab at the top), the "+$5" messages and the reveal of a new skin.
-- Pick a WEAPON on the left, then a SKIN on the right: EQUIP it when you own it, BUY it for Robux when you do not.
-- Below: a RANDOM skin for dollars or Robux, and ODDS (the fixed chance of every skin).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local WeaponSkins = require(Shared:WaitForChild("WeaponSkins"))
local UI = require(script.Parent:WaitForChild("UI"))
local SkinIcon = require(script.Parent:WaitForChild("SkinIcon"))

local ShopClient = {}

local player = Players.LocalPlayer
local C = UI.C

local ShopRemote: RemoteEvent? = nil
local gui: ScreenGui? = nil
local toastHolder: Frame? = nil
local selected = "pistol"
local page: Frame? = nil
local weaponList: ScrollingFrame
local skinList: ScrollingFrame
local titleLabel: TextLabel
local cashLabel: TextLabel
local randomBtn: TextButton
local oddsFrame: Frame
local oddsBuilt = false

local function remote(): RemoteEvent
	if not ShopRemote then
		ShopRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Shop") :: RemoteEvent
	end
	return ShopRemote :: RemoteEvent
end

local function weaponName(kind: string): string
	local k = Items.Kinds[kind]
	return k and k.name or string.upper(kind)
end

local function owned(id: string): boolean
	if Items.IsOwner(player) then
		return true
	end
	local list = player:GetAttribute("SkinsOwned")
	return typeof(list) == "string" and table.find(string.split(list, ","), id) ~= nil
end

local function ownedCount(kind: string): number
	local n = 0
	for _, s in WeaponSkins.OfKind[kind] do
		if owned(s.id) then
			n += 1
		end
	end
	return n
end

local function toast(text: string, color: Color3?)
	if not toastHolder then
		return
	end
	local l = UI.label({
		Text = text, TextSize = 22, Font = UI.FONT_TITLE, TextColor3 = color or C.amber, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, Parent = toastHolder,
	})
	TweenService:Create(l, TweenInfo.new(1.8, Enum.EasingStyle.Quad), { Position = UDim2.new(0, 0, 1, -70), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(1.9, function()
		l:Destroy()
	end)
end

------------------------------------------------------------------------
-- the page
------------------------------------------------------------------------

local refreshSkins: () -> ()
local refreshWeapons: () -> ()

local function card(skin: WeaponSkins.Skin, y: number)
	local rar = WeaponSkins.Rarity[skin.rarity]
	local own = owned(skin.id)
	local equipped = player:GetAttribute("Eq_" .. skin.kind) == skin.id
	local f = UI.panel({ Size = UDim2.new(1, -8, 0, 84), Position = UDim2.fromOffset(0, y), Accent = rar.color, BackgroundColor3 = C.panel2, BackgroundTransparency = 0.1, Parent = skinList })
	local icon = SkinIcon.new(f, skin, UDim2.fromOffset(72, 72))
	icon.Position = UDim2.fromOffset(10, 6)
	UI.make("UIStroke", { Color = rar.color, Thickness = 1.5, Parent = icon })
	UI.label({ Text = skin.name, Font = UI.FONT_TITLE, TextSize = 17, Position = UDim2.fromOffset(92, 6), Size = UDim2.new(1, -210, 0, 20), Parent = f })
	UI.label({ Text = rar.name .. "  -  " .. skin.tag, TextSize = 11, TextColor3 = rar.color, Position = UDim2.fromOffset(92, 27), Size = UDim2.new(1, -210, 0, 14), Parent = f })
	UI.label({ Text = skin.look.matMain.Name .. " - " .. skin.look.matDark.Name .. " - " .. skin.look.matAccent.Name, TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(92, 43), Size = UDim2.new(1, -210, 0, 14), Parent = f })
	UI.label({ Text = string.format("%.2f%% per random roll", skin.odds), TextSize = 11, TextColor3 = C.dim, Position = UDim2.fromOffset(92, 58), Size = UDim2.new(1, -210, 0, 14), Parent = f })
	local label, color, txt
	if own then
		label, color, txt = equipped and "EQUIPPED" or "EQUIP", equipped and C.good or C.panel3, equipped and Color3.new(0, 0, 0) or C.text
	else
		label, color, txt = string.format("BUY  %d R$", Config.SkinRobux), C.accent, Color3.new(0, 0, 0)
	end
	UI.button({
		Text = label, TextSize = 14, BackgroundColor3 = color, TextColor3 = txt, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(100, 38), Parent = f,
	}, function()
		if not own then
			remote():FireServer("robux", skin.id)
		else
			remote():FireServer("equip", skin.kind, equipped and "" or skin.id)
		end
	end)
end

refreshSkins = function()
	if not skinList then
		return
	end
	for _, c in skinList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	titleLabel.Text = weaponName(selected) .. "  -  " .. ownedCount(selected) .. "/" .. #WeaponSkins.OfKind[selected] .. " skins"
	local y = 0
	for _, s in WeaponSkins.OfKind[selected] do
		card(s, y)
		y += 90
	end
	skinList.CanvasSize = UDim2.fromOffset(0, y)
	local cash = player:GetAttribute("Cash")
	cash = typeof(cash) == "number" and cash or 0
	cashLabel.Text = "$ " .. cash
	randomBtn.BackgroundColor3 = cash >= Config.RandomSkinCost and C.amber or C.panel3
	randomBtn.TextColor3 = cash >= Config.RandomSkinCost and Color3.new(0, 0, 0) or C.dim
end

refreshWeapons = function()
	for _, c in weaponList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local y = 0
	for _, kind in WeaponSkins.Kinds do
		local on = kind == selected
		local b = UI.button({
			Text = "", BackgroundColor3 = on and C.accent or C.panel2, Size = UDim2.new(1, -6, 0, 38), Position = UDim2.fromOffset(0, y), Parent = weaponList,
		}, function()
			selected = kind
			refreshWeapons()
			refreshSkins()
		end)
		UI.label({ Text = weaponName(kind), Font = UI.FONT_TITLE, TextSize = 14, TextColor3 = on and Color3.new(0, 0, 0) or C.text, Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 17), Parent = b })
		UI.label({
			Text = ownedCount(kind) .. "/" .. #WeaponSkins.OfKind[kind] .. (player:GetAttribute("Eq_" .. kind) and "  -  skin on" or ""), TextSize = 11,
			TextColor3 = on and Color3.fromRGB(40, 20, 6) or C.dim, Position = UDim2.fromOffset(8, 19), Size = UDim2.new(1, -16, 0, 14), Parent = b,
		})
		y += 41
	end
	weaponList.CanvasSize = UDim2.fromOffset(0, y)
end

local function buildOdds()
	if oddsBuilt then
		return
	end
	oddsBuilt = true
	local list = UI.make("ScrollingFrame", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(12, 44), Size = UDim2.new(1, -24, 1, -52), ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0), Parent = oddsFrame,
	})
	local y = 0
	local function line(text: string, color: Color3?, size: number?, h: number?)
		UI.label({ Text = text, TextSize = size or 13, TextColor3 = color or C.text, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, -8, 0, h or 18), Parent = list })
		y += (h or 18) + 2
	end
	line("RANDOM SKIN ODDS - fixed, they never change", C.text, 15, 22)
	line("Every roll picks ONE of the 69 skins with the chances below. What you own does not change them.", C.dim, 12, 32)
	for _, e in WeaponSkins.OddsTable() do
		local rar = WeaponSkins.Rarity[e.rarity]
		line(string.format("%s   %.1f%% in total   -   %d skins, %.2f%% each", rar.name, e.percent, e.count, e.each), rar.color, 14, 20)
	end
	line("A skin you already own pays dollars back: common $60, rare $120, epic $250, legendary $500, mythic $1000.", C.dim, 12, 32)
	y += 6
	for _, rarity in WeaponSkins.RarityOrder do
		local rar = WeaponSkins.Rarity[rarity]
		local header = false
		for _, s in WeaponSkins.List do
			if s.rarity == rarity then
				if not header then
					header = true
					line(rar.name, rar.color, 14, 22)
				end
				line(string.format("%s  (%s)  -  %.2f%%", s.name, weaponName(s.kind), s.odds), C.text, 12, 16)
			end
		end
	end
	list.CanvasSize = UDim2.fromOffset(0, y + 8)
end

function ShopClient.BuildPage(parent: Frame)
	page = parent
	UI.label({ Text = "WEAPON SKINS", Font = UI.FONT_TITLE, TextSize = 16, TextColor3 = C.dim, Position = UDim2.fromOffset(10, 4), Size = UDim2.fromOffset(150, 18), Parent = parent })
	weaponList = UI.make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(8, 26), Size = UDim2.fromOffset(150, 296), ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0), Parent = parent })
	titleLabel = UI.label({ Text = "", Font = UI.FONT_TITLE, TextSize = 16, Position = UDim2.fromOffset(168, 4), Size = UDim2.fromOffset(250, 20), Parent = parent })
	cashLabel = UI.label({ Text = "$ 0", Font = UI.FONT_TITLE, TextSize = 18, TextColor3 = C.amber, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -150, 0, 4), Size = UDim2.fromOffset(130, 20), Parent = parent })
	skinList = UI.make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(166, 28), Size = UDim2.new(1, -176, 0, 296), ScrollBarThickness = 4, CanvasSize = UDim2.fromOffset(0, 0), Parent = parent })
	randomBtn = UI.button({ Text = string.format("RANDOM SKIN   $%d", Config.RandomSkinCost), TextSize = 14, Size = UDim2.fromOffset(190, 34), Position = UDim2.fromOffset(8, 332), BackgroundColor3 = C.panel3, Parent = parent }, function()
		remote():FireServer("random")
	end)
	UI.button({ Text = string.format("RANDOM SKIN   %d R$", Config.RandomSkinRobux), TextSize = 14, Size = UDim2.fromOffset(190, 34), Position = UDim2.fromOffset(204, 332), BackgroundColor3 = C.accent, TextColor3 = Color3.new(0, 0, 0), Parent = parent }, function()
		remote():FireServer("robuxrandom")
	end)
	UI.button({ Text = "ODDS", TextSize = 14, Size = UDim2.fromOffset(70, 34), Position = UDim2.fromOffset(402, 332), Parent = parent }, function()
		buildOdds()
		oddsFrame.Visible = true
	end)
	UI.label({ Text = string.format("Every kill = $%d", Config.KillCash), TextSize = 12, TextColor3 = C.dim, Position = UDim2.fromOffset(478, 332), Size = UDim2.fromOffset(76, 34), TextWrapped = true, Parent = parent })

	oddsFrame = UI.make("Frame", { Visible = false, Size = UDim2.new(1, 0, 0, 380), BackgroundColor3 = C.panel, BorderSizePixel = 0, Parent = parent })
	UI.button({ Text = "CLOSE", TextSize = 13, Size = UDim2.fromOffset(80, 28), Position = UDim2.new(1, -92, 0, 8), BackgroundColor3 = C.bad, Parent = oddsFrame }, function()
		oddsFrame.Visible = false
	end)

	local function again()
		refreshWeapons()
		refreshSkins()
	end
	again()
	player:GetAttributeChangedSignal("Cash"):Connect(refreshSkins)
	player:GetAttributeChangedSignal("SkinsOwned"):Connect(again)
	for _, kind in WeaponSkins.Kinds do
		player:GetAttributeChangedSignal("Eq_" .. kind):Connect(again)
	end
end

------------------------------------------------------------------------
-- messages and the reveal of a new skin
------------------------------------------------------------------------

local function reveal(id: string, dupe: boolean, back: number)
	local skin = WeaponSkins.ById[id]
	if not skin or not gui then
		return
	end
	local rar = WeaponSkins.Rarity[skin.rarity]
	local f = UI.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })
	TweenService:Create(f, TweenInfo.new(0.25), { BackgroundTransparency = 0.4 }):Play()
	UI.label({ Text = dupe and "YOU ALREADY HAD IT" or "NEW SKIN", TextSize = 20, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.fromOffset(340, 24), ZIndex = 52, Parent = f })
	local holder = UI.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromOffset(0, 0), BackgroundColor3 = rar.color, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 51, Parent = f })
	local icon = SkinIcon.new(holder, skin, UDim2.new(1, -8, 1, -8))
	icon.Position = UDim2.fromOffset(4, 4)
	icon.ZIndex = 52
	TweenService:Create(holder, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(190, 190) }):Play()
	UI.label({ Text = skin.name, Font = UI.FONT_TITLE, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.7), Size = UDim2.fromOffset(440, 34), ZIndex = 52, Parent = f })
	UI.label({ Text = weaponName(skin.kind) .. "  -  " .. rar.name .. "  -  " .. skin.tag, TextSize = 16, TextColor3 = rar.color, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.75), Size = UDim2.fromOffset(480, 22), ZIndex = 52, Parent = f })
	if dupe then
		UI.label({ Text = string.format("+$%d paid back", back), TextSize = 18, TextColor3 = C.good, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromOffset(300, 24), ZIndex = 52, Parent = f })
	end
	task.delay(3, function()
		TweenService:Create(f, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		for _, d in f:GetDescendants() do
			if d:IsA("TextLabel") then
				TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			end
		end
		task.wait(0.35)
		f:Destroy()
	end)
end

function ShopClient.Init()
	local pg = player:WaitForChild("PlayerGui")
	gui = UI.make("ScreenGui", { Name = "ShopGui", ResetOnSpawn = false, DisplayOrder = 40, IgnoreGuiInset = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = pg })
	toastHolder = UI.make("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(300, 80), Parent = gui })
	-- (v2.1) the state of your body armor: one bar per piece (H helmet, V vest, AL / AR arms, LL / LR legs), a bar empties as the piece takes hits
	do
		local frame = UI.make("Frame", { Visible = false, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.62, 0), Size = UDim2.fromOffset(222, 58), BackgroundColor3 = C.panel, BackgroundTransparency = 0.2, BorderSizePixel = 0, Parent = gui })
		UI.make("UIStroke", { Color = C.dim, Thickness = 1, Parent = frame })
		local keys = { "H", "V", "AL", "AR", "LL", "LR" }
		local fills = {}
		for i, k in keys do
			local cell = UI.make("Frame", { Position = UDim2.fromOffset(8 + (i - 1) * 35, 6), Size = UDim2.fromOffset(28, 30), BackgroundColor3 = C.panel2, BorderSizePixel = 0, Parent = frame })
			fills[k] = UI.make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.good, BorderSizePixel = 0, Parent = cell })
			UI.label({ Text = k, TextSize = 13, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(8 + (i - 1) * 35, 38), Size = UDim2.fromOffset(28, 16), Parent = frame })
		end
		local function refresh()
			local s = player:GetAttribute("ArmorStatus")
			if typeof(s) ~= "string" then
				frame.Visible = false
				return
			end
			frame.Visible = true
			for _, item in string.split(s, ",") do
				local k, n = string.match(item, "^(%a+)(%d+)$")
				if k and fills[k] then
					local f = math.clamp((tonumber(n) or 0) / 30, 0, 1)
					fills[k].Size = UDim2.fromScale(1, f)
					fills[k].BackgroundColor3 = f > 0.5 and C.good or (f > 0.2 and C.amber or C.bad)
				end
			end
		end
		player:GetAttributeChangedSignal("ArmorStatus"):Connect(refresh)
		refresh()
	end
	remote().OnClientEvent:Connect(function(kind, a, b, c)
		if kind == "msg" then
			toast(tostring(a), b and C.good or C.bad)
		elseif kind == "cash" then
			if typeof(a) == "number" then
				toast((a >= 0 and "+$" or "-$") .. tostring(math.abs(a)), a >= 0 and C.good or C.bad)
			end
		elseif kind == "rolled" then
			reveal(tostring(a), b == true, tonumber(c) or 0)
		end
	end)
end

return ShopClient
