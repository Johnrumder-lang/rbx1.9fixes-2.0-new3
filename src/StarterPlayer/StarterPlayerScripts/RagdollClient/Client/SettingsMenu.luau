--!nonstrict
-- SettingsMenu (M, or SET on a phone): two pages.
--   SETTINGS (everybody): blood, gore, big effects, camera shake, red hurt flash, bloom / sun rays,
--     shadows, hallucinations, bullet tracers, volume, field of view. Saved on the server, so they
--     come back next time. The effects themselves ask Settings.Get(...) before they draw.
--   ADMIN (only the game owner): load / remove the city, everybody to the city / to the sandbox,
--     the game modes (team fight, FFA, hide and seek, stop), spawning for everybody on / off, the
--     day / night cycle and the time of day.
-- This module also applies the settings that are not drawn by an effect: the lighting effects,
-- shadows, the volume, and hiding gore parts (wounds, bones, stumps, gibs) on this screen.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared:WaitForChild("Settings"))
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Titles = require(Shared:WaitForChild("Titles"))
local Skins = require(Shared:WaitForChild("Skins"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SettingsRemote = Remotes:WaitForChild("Settings") :: RemoteEvent
local AdminRemote = Remotes:WaitForChild("Admin") :: RemoteEvent

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local UI = require(Modules:WaitForChild("UI"))
local MobileControls = require(Modules:WaitForChild("MobileControls"))
local TutorialClient = require(Modules:WaitForChild("TutorialClient"))
local VoteRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Vote") :: RemoteEvent
local RewardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Reward") :: RemoteEvent

local C = UI.C
local player = Players.LocalPlayer

local SettingsMenu = {}

SettingsMenu.HUD = nil -- set by the client entry (closes the spawn menu)

local gui: ScreenGui
local root: Frame
local pages: { [string]: Frame } = {}
local tabs: { [string]: TextButton } = {}
local open = false
local rowsByKey: { [string]: () -> () } = {}
local adminRefresh: (() -> ())? = nil

------------------------------------------------------------------------
-- applying
------------------------------------------------------------------------

local GORE_NAMES = {
	Gib = true, Bone = true, BoneKnob = true, Flap = true, Marrow = true, Splinter = true, Wound = true,
	StumpSkin = true, StumpFat = true, StumpMuscle = true,
}
local goreParts: { [BasePart]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function hideGore(p: BasePart)
	p.LocalTransparencyModifier = Settings.Get("gore") and 0 or 1
end

local function watchGore(inst: Instance)
	if inst:IsA("BasePart") and GORE_NAMES[inst.Name] then
		goreParts[inst] = true
		if not Settings.Get("gore") then
			hideGore(inst)
		end
	end
end

local function applyAll(key: string?)
	if key == nil or key == "post" then
		local on = Settings.Get("post")
		for _, name in { "Bloom", "SunRays", "ColorCorrection" } do
			local e = Lighting:FindFirstChild(name)
			if e and e:IsA("PostEffect") then
				e.Enabled = on
			end
		end
	end
	if key == nil or key == "shadows" then
		Lighting.GlobalShadows = Settings.Get("shadows")
	end
	if key == nil or key == "volume" then
		SoundLibrary.SetVolume(Settings.Get("volume"))
	end
	if key == nil or key == "gore" then
		for p in goreParts do
			if p.Parent then
				hideGore(p)
			end
		end
	end
end

local saveQueued = false
local function queueSave()
	if saveQueued then
		return
	end
	saveQueued = true
	task.delay(2, function()
		saveQueued = false
		SettingsRemote:FireServer("save", Settings.All())
	end)
end

------------------------------------------------------------------------
-- the menu
------------------------------------------------------------------------

local function row(parent: Instance, y: number, text: string): Frame
	local r = UI.make("Frame", {
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(12, y),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	UI.label({ Text = text, TextSize = 15, Size = UDim2.new(1, -150, 1, 0), Parent = r })
	return r
end

local function buildSettingsPage(page: Frame)
	local y = 8
	for _, d in Settings.List do
		if d.hidden or (Config.Lite and d.key == "experimental") then
			continue
		end
		local r = row(page, y, d.label)
		if d.requires then
			local need = d.requires
			r.Visible = Items.Has(player, need)
			player:GetAttributeChangedSignal("Gift_" .. need):Connect(function()
				r.Visible = Items.Has(player, need)
			end)
		end
		if d.kind == "bool" then
			local b
			local function refresh()
				local on = Settings.Get(d.key)
				b.Text = on and "ON" or "OFF"
				b.BackgroundColor3 = on and C.good or C.panel3
				b.TextColor3 = on and Color3.new(0, 0, 0) or C.dim
			end
			b = UI.button({
				Size = UDim2.fromOffset(90, 26),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				Parent = r,
			}, function()
				Settings.Set(d.key, not Settings.Get(d.key))
			end)
			rowsByKey[d.key] = refresh
			refresh()
		else
			local value = UI.label({
				Text = "",
				Font = UI.FONT_NUM,
				TextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Center,
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -34, 0.5, 0),
				Size = UDim2.fromOffset(56, 26),
				Parent = r,
			})
			local function refresh()
				local v = Settings.Get(d.key)
				value.Text = d.key == "volume" and (tostring(math.floor(v * 100 + 0.5)) .. "%") or tostring(v)
			end
			for i, sgn in { -1, 1 } do
				UI.button({
					Text = sgn < 0 and "-" or "+",
					Size = UDim2.fromOffset(28, 26),
					AnchorPoint = Vector2.new(1, 0.5),
					Position = i == 1 and UDim2.new(1, -92, 0.5, 0) or UDim2.new(1, 0, 0.5, 0),
					Parent = r,
				}, function()
					local v = Settings.Get(d.key) + sgn * (d.step or 1)
					v = math.floor(v / (d.step or 1) + 0.5) * (d.step or 1)
					Settings.Set(d.key, v)
				end)
			end
			rowsByKey[d.key] = refresh
			refresh()
		end
		y += 32
	end
	if UserInputService.TouchEnabled then
		UI.label({ Text = "Touch buttons", TextSize = 15, Position = UDim2.fromOffset(12, y + 2), Size = UDim2.new(1, -150, 0, 30), Parent = page })
		UI.button({
			Text = "EDIT LAYOUT",
			Size = UDim2.fromOffset(120, 26),
			Position = UDim2.new(1, -262, 0, y + 4),
			Parent = page,
		}, function()
			SettingsMenu.Close()
			MobileControls.SetEdit(true)
		end)
		UI.button({
			Text = "RESET",
			Size = UDim2.fromOffset(120, 26),
			Position = UDim2.new(1, -136, 0, y + 4),
			Parent = page,
		}, function()
			MobileControls.ResetLayout()
		end)
		y += 32
	end
	UI.label({ Text = "Tutorial", TextSize = 15, Position = UDim2.fromOffset(12, y + 2), Size = UDim2.new(1, -150, 0, 30), Parent = page })
	UI.button({
		Text = "REPLAY",
		Size = UDim2.fromOffset(120, 26),
		Position = UDim2.new(1, -136, 0, y + 4),
		Parent = page,
	}, function()
		SettingsMenu.Close()
		TutorialClient.Start()
	end)
	y += 32
	-- (v2.8) KEYS: click an action, then press the key it should have
	y += 8
	UI.label({ Text = "KEYS  (click, then press a key; ESC keeps the old one)", Font = UI.FONT_TITLE, TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 18), Parent = page })
	y += 22
	do
		local function readBinds(): { [string]: string }
			local out = {}
			for pair in string.gmatch(Settings.Get("keyBinds") or "", "[^,]+") do
				local a, k = string.match(pair, "^(%w+)=(%w+)$")
				if a and k then
					out[a] = k
				end
			end
			return out
		end
		local function writeBinds(t: { [string]: string })
			local list = {}
			for _, r in Input.REBIND do
				if t[r.action] then
					table.insert(list, r.action .. "=" .. t[r.action])
				end
			end
			Settings.Set("keyBinds", table.concat(list, ","))
		end
		local waiting: string? = nil
		local keyB: { [string]: TextButton } = {}
		local function paint()
			for _, r in Input.REBIND do
				local b = keyB[r.action]
				if b then
					b.Text = waiting == r.action and "PRESS A KEY" or Input.KeyName(r.action)
					b.BackgroundColor3 = waiting == r.action and C.amber or C.panel2
					b.TextColor3 = waiting == r.action and Color3.new(0, 0, 0) or C.text
				end
			end
		end
		for i, r in Input.REBIND do
			local col = (i - 1) % 2
			local ry = y + math.floor((i - 1) / 2) * 30
			UI.label({ Text = r.label, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(12 + col * 272, ry + 3), Size = UDim2.fromOffset(176, 24), Parent = page })
			keyB[r.action] = UI.button({ Text = "", TextSize = 13, Position = UDim2.fromOffset(192 + col * 272, ry + 2), Size = UDim2.fromOffset(80, 24), Parent = page }, function()
				waiting = r.action
				paint()
			end)
		end
		y += math.ceil(#Input.REBIND / 2) * 30
		UI.label({ Text = "Implant keys (the cyber bar): M > CYBER", TextSize = 12, TextColor3 = C.dim, Position = UDim2.fromOffset(12, y + 4), Size = UDim2.fromOffset(300, 20), Parent = page })
		UI.button({ Text = "DEFAULT KEYS", TextSize = 12, Position = UDim2.new(1, -136, 0, y + 2), Size = UDim2.fromOffset(120, 24), Parent = page }, function()
			waiting = nil
			Settings.Set("keyBinds", "")
		end)
		y += 32
		UserInputService.InputBegan:Connect(function(io)
		if Input.IsControlled() then return end
			if not waiting or io.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			local action = waiting
			waiting = nil
			local name = io.KeyCode.Name
			if io.KeyCode ~= Enum.KeyCode.Escape then
				if Input.RESERVED[name] then
					pcall(function()
						game:GetService("StarterGui"):SetCore("SendNotification", { Title = "KEYS", Text = name .. " is already used by the game.", Duration = 3 })
					end)
				else
					local t = readBinds()
					-- (whatever had that key before gets its default back)
					for a, k in t do
						if k == name then
							t[a] = nil
						end
					end
					t[action] = name
					writeBinds(t)
				end
			end
			task.defer(paint)
		end)
		Settings.Changed:Connect(function(key)
			if key == "keyBinds" then
				task.defer(paint)
			end
		end)
		paint()
	end
	-- (v2.0) the admin pass: all admin powers in private servers
	local passId = workspace:GetAttribute("AdminPassId")
	if typeof(passId) == "number" and passId > 0 and not Items.IsOwner(player) then
		UI.label({ Text = "Admin pass (all admin powers in private servers)", TextSize = 15, Position = UDim2.fromOffset(12, y + 2), Size = UDim2.new(1, -150, 0, 30), Parent = page })
		UI.button({
			Text = "GET IT",
			Size = UDim2.fromOffset(120, 26),
			Position = UDim2.new(1, -136, 0, y + 4),
			BackgroundColor3 = C.amber,
			TextColor3 = Color3.new(0, 0, 0),
			Parent = page,
		}, function()
			pcall(function()
				game:GetService("MarketplaceService"):PromptGamePassPurchase(player, passId)
			end)
		end)
		y += 32
	end
	UI.label({
		Text = "Saved for you - they come back next time you play.",
		TextSize = 12,
		TextColor3 = C.dim,
		Position = UDim2.fromOffset(12, y + 4),
		Size = UDim2.new(1, -24, 0, 16),
		Parent = page,
	})
	;(page :: any).CanvasSize = UDim2.fromOffset(0, y + 36) -- (v2.8: the keys made it longer)
end

local function section(page: Frame, y: number, text: string)
	UI.label({ Text = text, Font = UI.FONT_TITLE, TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 18), Parent = page })
end

local function adminButtons(page: Frame, y: number, list: { { string } }, onPress: (string) -> ()): { [string]: TextButton }
	local out = {}
	local n = #list
	local w = (536 - (n - 1) * 8) / n
	for i, entry in list do
		local id, text = entry[1], entry[2]
		out[id] = UI.button({
			Text = text,
			TextSize = 13,
			Size = UDim2.fromOffset(w, 30),
			Position = UDim2.fromOffset(12 + (i - 1) * (w + 8), y),
			Parent = page,
		}, function()
			onPress(id)
		end)
	end
	return out
end

local MAP_NAMES = { city = "CITY", horror = "HORROR", sea = "SEA", ikea = "MEGASTORE", valley = "DUST VALLEY", sky = "SKY ISLANDS" }
local MODE_NAMES = {
	teamfight = "TEAM FIGHT", ffa = "FREE FOR ALL", hideseek = "HIDE AND SEEK", monster = "MONSTER", zombies = "ZOMBIES", gungame = "GUN GAME",
	sniper = "SNIPER TOWER", hotpotato = "HOT POTATO", koth = "KING OF THE HILL",
}

local function buildAdminPage(page: Frame)
	local status = UI.label({
		Text = "",
		RichText = true,
		TextSize = 13,
		TextColor3 = C.dim,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 0, 18),
		Parent = page,
	})
	local y = 30
	section(page, y, "MAP  (one map at a time; the pad by the spawn leads there)")
	local function loadMap(id: string)
		AdminRemote:FireServer("map", id == "unload" and "unload" or ("load:" .. id))
	end
	local mapB = adminButtons(page, y + 20, {
		{ "city", "CITY" }, { "horror", "HORROR" }, { "sea", "SEA" }, { "ikea", "IKEA" },
	}, loadMap)
	local mapB2 = adminButtons(page, y + 54, { { "valley", "DUST VALLEY" }, { "sky", "SKY ISLANDS" }, { "unload", "REMOVE" } }, loadMap)
	for id, b in mapB2 do
		mapB[id] = b
	end
	local moveB = adminButtons(page, y + 88, { { "tomap", "ALL TO THE MAP" }, { "tosandbox", "ALL TO THE SANDBOX" } }, function(id)
		AdminRemote:FireServer("map", id)
	end)
	y += 130
	section(page, y, "GAME MODES  (on the loaded map - who dies waits in the lobby and can watch)")
	local modeB = adminButtons(page, y + 20, {
		{ "teamfight", "TEAM FIGHT" }, { "ffa", "FFA" }, { "hideseek", "HIDE&SEEK" },
	}, function(id)
		AdminRemote:FireServer("mode", id)
	end)
	local modeB2 = adminButtons(page, y + 54, {
		{ "monster", "MONSTER" }, { "zombies", "ZOMBIES" }, { "gungame", "GUN GAME" },
	}, function(id)
		AdminRemote:FireServer("mode", id)
	end)
	local modeB3 = adminButtons(page, y + 88, {
		{ "sniper", "SNIPER TOWER" }, { "hotpotato", "HOT POTATO" }, { "koth", "KING OF HILL" }, { "stop", "STOP" },
	}, function(id)
		AdminRemote:FireServer("mode", id)
	end)
	for id, b in modeB2 do
		modeB[id] = b
	end
	for id, b in modeB3 do
		modeB[id] = b
	end
	y += 130
	section(page, y, "PLAYERS")
	local spawnB = adminButtons(page, y + 20, { { "toggle", "" }, { "bots", "" }, { "botcars", "" } }, function(id)
		if id == "toggle" then
			AdminRemote:FireServer("spawning", workspace:GetAttribute("SpawningLocked") == true)
		elseif id == "botcars" then
			AdminRemote:FireServer("botcars", workspace:GetAttribute("BotCars") ~= true)
		else
			AdminRemote:FireServer("bots", workspace:GetAttribute("BotsEnabled") ~= true)
		end
	end)
	y += 62
	section(page, y, "SERVER")
	local serverB = adminButtons(page, y + 20, {
		{ "timestop", "TIME STOP" }, { "healall", "HEAL ALL" }, { "respawnall", "RESPAWN ALL" }, { "sun", "FIRE SUN CANNON" },
	}, function(id)
		AdminRemote:FireServer(id)
	end)
	local gravB = adminButtons(page, y + 54, {
		{ "moon", "MOON GRAVITY" }, { "low", "LOW" }, { "normal", "NORMAL" }, { "heavy", "HEAVY" },
	}, function(id)
		AdminRemote:FireServer("gravity", id)
	end)
	y += 96
	-- (v2.8.2) cyberpsychosis for the whole server
	section(page, y, "CYBERWARE")
	local cyberB = adminButtons(page, y + 20, { { "psychosis", "" } }, function()
		AdminRemote:FireServer("psychosis", workspace:GetAttribute("PsychosisOff") == true)
	end)
	y += 56
	local ownPsycho = adminButtons(page, y, { { "self", "" } }, function()
		AdminRemote:FireServer("adminpsycho", player:GetAttribute("AdminPsychoEnabled") ~= true)
	end)
	local function ownPsychoText()
		ownPsycho.self.Text = player:GetAttribute("AdminPsychoEnabled") == true and "MY PSYCHOSIS IMMUNITY: OFF" or "MY PSYCHOSIS IMMUNITY: ON"
	end
	ownPsychoText()
	player:GetAttributeChangedSignal("AdminPsychoEnabled"):Connect(ownPsychoText)
	y += 42
	-- (v2.1) items an admin can put in front of himself
	section(page, y, "ITEMS")
	adminButtons(page, y + 20, { { "ledgerspawn", "SPAWN BLACK LEDGER" }, { "sandevistanspawn", "SPAWN SANDEVISTAN" } }, function(id)
		AdminRemote:FireServer(id)
	end)
	y += 62
	if not Config.Lite then
		section(page, y, "WEATHER")
		adminButtons(page, y + 20, { { "auto", "AUTO" }, { "clear", "CLEAR" }, { "rain", "RAIN" }, { "storm", "STORM" }, { "snow", "SNOW" }, { "fog", "FOG" } }, function(id)
			AdminRemote:FireServer("weather", id)
		end)
		y += 62
	end
	section(page, y, "DAY / NIGHT")
	local dayB = adminButtons(page, y + 20, {
		{ "cycle", "" }, { "day", "DAY" }, { "dusk", "DUSK" }, { "night", "NIGHT" },
	}, function(id)
		if id == "cycle" then
			AdminRemote:FireServer("daynight", not workspace:GetAttribute("DayNightCycle"))
		else
			AdminRemote:FireServer("time", id == "day" and 13 or (id == "dusk" and 18.6 or 0.5))
		end
	end)
	y += 62
	-- (v2.0) your own questline (to try the Spin without doing the quests)
	section(page, y, "STEEL BALL QUESTS (YOURS)")
	adminButtons(page, y + 20, { { "spin", "GIVE ME THE SPIN" }, { "reset", "START THE QUESTS OVER" }, { "circle", "SPAWN A SPIN CIRCLE" } }, function(id)
		AdminRemote:FireServer("quest", id)
	end)
	y += 62
	-- (v2.8) the STILLWATER quest (yours)
	section(page, y, "STILLWATER QUEST (YOURS)")
	do
		local SwordRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Sword") :: RemoteEvent
		adminButtons(page, y + 20, { { "give", "GIVE ME STILLWATER" }, { "reset", "START IT OVER" }, { "pit", "TAKE ME TO THE PIT" }, { "rival", "THE PALE HEIR" } }, function(id)
			SwordRemote:FireServer("admin", id)
		end)
	end
	y += 62
	-- (v2.9) wipe everyone's progress (the game's owner only)
	section(page, y, "DANGER ZONE  (THE OWNER ONLY)")
	do
		local armed = false
		local wipeBtn
		wipeBtn = UI.button({
			Text = "WIPE ALL PROGRESS", TextSize = 13, Size = UDim2.fromOffset(536, 30), Position = UDim2.fromOffset(12, y + 20),
			BackgroundColor3 = C.bad, TextColor3 = Color3.new(1, 1, 1), Parent = page,
		}, function()
			if not armed then
				armed = true
				wipeBtn.Text = "CONFIRM GLOBAL WIPE — ALL SAVES + SERVER RESTART"
				wipeBtn.BackgroundColor3 = Color3.fromRGB(255, 180, 40)
				wipeBtn.TextColor3 = Color3.new(0, 0, 0)
				task.delay(4, function()
					if armed and wipeBtn and wipeBtn.Parent then
						armed = false
						wipeBtn.Text = "WIPE ALL PROGRESS"
						wipeBtn.BackgroundColor3 = C.bad
						wipeBtn.TextColor3 = Color3.new(1, 1, 1)
					end
				end)
			else
				armed = false
				AdminRemote:FireServer("wipeall", "WIPE EVERYONE")
				wipeBtn.Text = "WIPE SENT"
				wipeBtn.BackgroundColor3 = C.panel3
				task.delay(2, function()
					if wipeBtn and wipeBtn.Parent then
						wipeBtn.Text = "WIPE ALL PROGRESS"
						wipeBtn.BackgroundColor3 = C.bad
						wipeBtn.TextColor3 = Color3.new(1, 1, 1)
					end
				end)
			end
		end)
		UI.label({ Text = "Clears dollars, skins, titles, kills, quests, cyberware, the sword and chips for EVERYONE in the server, and saves it gone.",
			TextSize = 11, TextWrapped = true, TextColor3 = C.dim, Position = UDim2.fromOffset(12, y + 52), Size = UDim2.new(1, -24, 0, 30), Parent = page })
	end
	y += 90
	-- (v2.0) the free cam: only your camera, nothing on the server
	section(page, y, "CAMERA")
	adminButtons(page, y + 20, { { "freecam", "FREE CAM  (U)" } }, function()
		SettingsMenu.Close()
		local FreeCam = require(Modules:WaitForChild("FreeCam")) :: any
		FreeCam.Set(true)
	end)
	y += 62
	UI.label({
		Text = "Powers: B fly (invincible), N fly speed, L super punch, K laser eyes (flying), P hotdog the player at your crosshair, I time stop, O quickhack mode, U free cam. "
			.. "Spawn menu (T): Kick Hammer (whoever it hits is kicked), Sun Cannon. Players tab: kick / bring / go to / hotdog.",
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = C.dim,
		Position = UDim2.fromOffset(12, y),
		Size = UDim2.new(1, -24, 0, 48),
		Parent = page,
	})
	y += 56
	(page :: any).CanvasSize = UDim2.fromOffset(0, y + 10)
	adminRefresh = function()
		local mapId = workspace:GetAttribute("MapLoaded")
		local mode = workspace:GetAttribute("Mode")
		status.Text = string.format("Map: <b>%s</b>   Game: <b>%s</b>   %s", typeof(mapId) == "string" and (MAP_NAMES[mapId] or mapId) or "none",
			typeof(mode) == "string" and (MODE_NAMES[mode] or mode) or "none", workspace:GetAttribute("PrivateServer") and "<b>PRIVATE SERVER</b>" or "")
		for id, b in mapB do
			local on = mapId == id
			b.BackgroundColor3 = on and C.good or (id == "unload" and C.bad or C.panel2)
			b.TextColor3 = on and Color3.new(0, 0, 0) or C.text
		end
		for _, b in moveB do
			b.TextTransparency = typeof(mapId) == "string" and 0 or 0.5
		end
		for id, b in modeB do
			local on = mode == id
			b.BackgroundColor3 = on and C.good or (id == "stop" and C.bad or C.panel2)
			b.TextColor3 = on and Color3.new(0, 0, 0) or C.text
		end
		local locked = workspace:GetAttribute("SpawningLocked") == true
		spawnB.toggle.Text = locked and ((typeof(mode) == "string") and "SPAWNING OFF (GAME)" or "SPAWNING OFF") or "SPAWNING ON"
		spawnB.toggle.BackgroundColor3 = locked and C.bad or C.good
		spawnB.toggle.TextColor3 = Color3.new(0, 0, 0)
		local bots = workspace:GetAttribute("BotsEnabled") == true
		spawnB.bots.Text = bots and "BOTS FILL GAMES: ON" or "BOTS FILL GAMES: OFF"
		spawnB.bots.BackgroundColor3 = bots and C.good or C.panel3
		spawnB.bots.TextColor3 = bots and Color3.new(0, 0, 0) or C.text
		local botCars = workspace:GetAttribute("BotCars") == true
		spawnB.botcars.Text = botCars and "BOT CARS (CITY): ON" or "BOT CARS (CITY): OFF"
		spawnB.botcars.BackgroundColor3 = botCars and C.good or C.panel3
		spawnB.botcars.TextColor3 = botCars and Color3.new(0, 0, 0) or C.text
		local stopped = workspace:GetAttribute("TimeStop") ~= nil
		serverB.timestop.Text = stopped and "TIME: STOPPED" or "TIME STOP"
		serverB.timestop.BackgroundColor3 = stopped and C.amber or C.panel2
		serverB.timestop.TextColor3 = stopped and Color3.new(0, 0, 0) or C.text
		local grav = workspace:GetAttribute("GravityMode") or "normal"
		for id, b in gravB do
			b.BackgroundColor3 = grav == id and C.good or C.panel2
			b.TextColor3 = grav == id and Color3.new(0, 0, 0) or C.text
		end
		local psyOff = workspace:GetAttribute("PsychosisOff") == true
		cyberB.psychosis.Text = psyOff and "CYBERPSYCHOSIS: OFF" or "CYBERPSYCHOSIS: ON"
		cyberB.psychosis.BackgroundColor3 = psyOff and C.panel3 or C.good
		cyberB.psychosis.TextColor3 = psyOff and C.text or Color3.new(0, 0, 0)
		local cycle = workspace:GetAttribute("DayNightCycle") == true
		dayB.cycle.Text = cycle and "CYCLE: ON" or "CYCLE: OFF"
		dayB.cycle.BackgroundColor3 = cycle and C.good or C.panel3
		dayB.cycle.TextColor3 = cycle and Color3.new(0, 0, 0) or C.text
	end
	for _, attr in { "MapLoaded", "Mode", "SpawningLocked", "DayNightCycle", "BotsEnabled", "BotCars", "TimeStop", "GravityMode", "PrivateServer", "PsychosisOff" } do
		workspace:GetAttributeChangedSignal(attr):Connect(function()
			if adminRefresh then
				adminRefresh()
			end
		end)
	end
	if adminRefresh then
		adminRefresh()
	end
end

------------------------------------------------------------------------
-- (v2.0) PLAYERS (admins): kick, bring, go to, hotdog
------------------------------------------------------------------------

local function buildPlayersPage(page: Frame)
	UI.label({ Text = "Everybody in this server. KICK throws them out of the server (they can join again).", TextSize = 14, TextColor3 = C.dim, TextWrapped = true, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 36), Parent = page })
	local list = UI.make("Frame", { Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), Parent = page })
	local function refresh()
		for _, c in list:GetChildren() do
			c:Destroy()
		end
		local y = 0
		for _, p in Players:GetPlayers() do
			if p == player then
				continue
			end
			UI.label({ Text = p.DisplayName .. ((p:GetAttribute("Admin") or Items.IsGameOwner(p)) and "  (admin)" or ""), Font = UI.FONT_TITLE, TextSize = 15, Position = UDim2.fromOffset(12, y + 4), Size = UDim2.fromOffset(170, 20), Parent = list })
			local acts = { { "kick", "KICK", C.bad }, { "bring", "BRING", C.panel2 }, { "goto", "GO TO", C.panel2 }, { "wipeplayer", "WIPE", C.bad } }
			for i, a in acts do
				local armed, button = false, nil
				button = UI.button({
					Text = a[2],
					TextSize = 12,
					BackgroundColor3 = a[3],
					Size = UDim2.fromOffset(78, 26),
					Position = UDim2.fromOffset(186 + (i - 1) * 84, y),
					Parent = list,
				}, function()
					if a[1] == "wipeplayer" then
						if not armed then
							armed = true; button.Text = "CONFIRM?"
							task.delay(5, function() if button.Parent then armed = false; button.Text = "WIPE" end end)
						else armed = false; button.Text = "SENT"; AdminRemote:FireServer("wipeplayer", p.UserId, "WIPE PLAYER") end
					else AdminRemote:FireServer(a[1], p.UserId) end
				end)
			end
			y += 32
		end
		if y == 0 then
			UI.label({ Text = "Nobody else is here yet.", TextSize = 14, TextColor3 = C.dim, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 20), Parent = list })
		end
		(page :: any).CanvasSize = UDim2.fromOffset(0, math.max(320, y + 60))
	end
	refresh()
	local function watchAdmin(p: Player)
		p:GetAttributeChangedSignal("GiftAdmin"):Connect(function()
			task.defer(refresh)
		end)
		p:GetAttributeChangedSignal("Admin"):Connect(function()
			task.defer(refresh)
		end)
	end
	for _, p in Players:GetPlayers() do
		watchAdmin(p)
	end
	Players.PlayerAdded:Connect(function(p)
		watchAdmin(p)
		task.defer(refresh)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
end

------------------------------------------------------------------------
-- (v1.9) VOTE: suggest something, everybody votes
------------------------------------------------------------------------

local function buildVotePage(page: Frame)
	UI.label({ Text = "Suggest something. Everybody votes yes / no for 20 seconds; more than 60% yes and it happens.", TextSize = 14, TextColor3 = C.dim, TextWrapped = true, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 40), Parent = page })
	local status = UI.label({ Text = "", RichText = true, TextSize = 15, Position = UDim2.fromOffset(12, 52), Size = UDim2.new(1, -24, 0, 22), Parent = page })
	section(page, 84, "MAPS  (one suggestion every 10 minutes for the whole server)")
	local function propose(id: string)
		VoteRemote:FireServer("propose", id)
	end
	local btns = adminButtons(page, 106, { { "city", "CITY" }, { "map_horror", "HORROR" }, { "map_sea", "SEA" }, { "map_ikea", "IKEA" } }, propose)
	local bm2 = adminButtons(page, 140, { { "map_valley", "DUST VALLEY" }, { "map_sky", "SKY ISLANDS" } }, propose)
	section(page, 180, "GAME MODES")
	local b2 = adminButtons(page, 202, { { "teamfight", "TEAM FIGHT" }, { "ffa", "FFA" }, { "hideseek", "HIDE&SEEK" } }, propose)
	local b3 = adminButtons(page, 236, { { "monster", "MONSTER" }, { "zombies", "ZOMBIES" }, { "gungame", "GUN GAME" } }, propose)
	local b4 = adminButtons(page, 270, { { "sniper", "SNIPER TOWER" }, { "hotpotato", "HOT POTATO" }, { "koth", "KING OF THE HILL" } }, propose)
	for _, group in { bm2, b2, b3, b4 } do
		for id, b in group do
			btns[id] = b
		end
	end
	local nukeB = adminButtons(page, 310, { { "nuke", "SPAWN ARMED NUKE (it still counts down)" } }, propose)
	-- (v2.0) vote kick
	section(page, 352, "VOTE KICK  (more than 70% yes kicks the player; needs 3+ players)")
	local kickList = UI.make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 374), Size = UDim2.new(1, 0, 0, 10), Parent = page })
	local function refreshKick()
		for _, c in kickList:GetChildren() do
			c:Destroy()
		end
		local y = 0
		for _, p in Players:GetPlayers() do
			if p ~= player and not p:GetAttribute("Admin") and not Items.IsGameOwner(p) then
				UI.label({ Text = p.DisplayName, TextSize = 15, Position = UDim2.fromOffset(12, y + 2), Size = UDim2.fromOffset(300, 22), Parent = kickList })
				UI.button({ Text = "VOTE KICK", TextSize = 12, BackgroundColor3 = C.bad, Size = UDim2.fromOffset(110, 24), Position = UDim2.new(1, -122, 0, y), Parent = kickList }, function()
					VoteRemote:FireServer("kick", p.UserId)
				end)
				y += 28
			end
		end
		if y == 0 then
			UI.label({ Text = "Nobody to kick.", TextSize = 14, TextColor3 = C.dim, Position = UDim2.fromOffset(12, 2), Size = UDim2.new(1, -24, 0, 20), Parent = kickList })
			y = 24
		end
		(page :: any).CanvasSize = UDim2.fromOffset(0, 384 + y + 20)
	end
	refreshKick()
	Players.PlayerAdded:Connect(function()
		task.defer(refreshKick)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshKick)
	end)
	task.spawn(function()
		while page.Parent do
			task.wait(0.4)
			if page.Visible then
				local now = workspace:GetServerTimeNow()
				local nextAt = workspace:GetAttribute("VoteNext") or 0
				local running = workspace:GetAttribute("VoteText")
				local text
				if running then
					text = "A vote is running."
				elseif now < nextAt then
					local s = math.ceil(nextAt - now)
					text = string.format("Next suggestion in <b>%d:%02d</b>", s // 60, s % 60)
				else
					text = "<font color=\"#8ab056\">You can make a suggestion now.</font>"
				end
				status.Text = text
				local can = not running and now >= nextAt
				local loaded = workspace:GetAttribute("MapLoaded")
				for id, b in btns do
					local already = (id == "city" and loaded == "city") or (string.sub(id, 1, 4) == "map_" and loaded == string.sub(id, 5))
					b.AutoButtonColor = can and not already
					b.TextTransparency = (can and not already) and 0 or 0.55
				end
				for _, b in nukeB do
					b.AutoButtonColor = can
					b.TextTransparency = can and 0 or 0.55
				end
			end
		end
	end)
end

------------------------------------------------------------------------
-- (v1.9) GIFTS: the owner gives single powers to single players
------------------------------------------------------------------------

local GIFT_LABEL = { fly = "FLY", punch = "PUNCH", laser = "LASER", nuke = "NUKE", virus = "VIRUS", physgun = "PHYS", wonder = "WONDER", admin = "ADMIN",
	timestop = "TIME", hotdog = "HOTDOG", sever = "SEVER", sandevistan = "SANDY", colossus = "COLOSS", zerohour = "ZERO H", stillcut = "STILL", freecam = "FREECAM" }

local function buildGiftPage(page: Frame)
	UI.label({ Text = "Give a power to a player (or take it back). Gifts are saved until revoked. FREECAM uses U to fly the camera. ADMIN (game owner only) = every power and the admin menu.", TextSize = 13, TextColor3 = C.dim, TextWrapped = true, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 40), Parent = page })
	local list = UI.make("Frame", { Name = "List", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46), Parent = page })
	local function refresh()
		for _, c in list:GetChildren() do
			c:Destroy()
		end
		local y = 0
		local iAmOwner = Items.IsGameOwner(player)
for _, p in Players:GetPlayers() do
			-- (admins the owner made stay in the list: the owner can take it away again). (v2.1) YOU are in the list too: titles and money for yourself
			local isSelf = p == player
			if isSelf or (not Items.IsGameOwner(p) and (not p:GetAttribute("Admin") or p:GetAttribute("GiftAdmin"))) then
				UI.label({ Text = isSelf and "YOU" or (p.DisplayName .. (p:GetAttribute("GiftAdmin") and "  (admin)" or "")), Font = UI.FONT_TITLE, TextSize = 15, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 18), Parent = list })
				local ty = y + 22
				if not isSelf then
					local powers = table.clone(Items.POWERS)
					if iAmOwner then
						table.insert(powers, "admin")
					end
					for i, power in powers do
						local attr = power == "admin" and "GiftAdmin" or ("Gift_" .. power)
						local b
						local function paint()
							local on = p:GetAttribute(attr) == true
							b.BackgroundColor3 = on and C.good or C.panel2
							b.TextColor3 = on and Color3.new(0, 0, 0) or C.text
						end
						b = UI.button({
							Text = GIFT_LABEL[power] or string.upper(power),
							TextSize = 12,
							Size = UDim2.fromOffset(62, 24),
							Position = UDim2.fromOffset(12 + ((i - 1) % 8) * 65, ty + math.floor((i - 1) / 8) * 28), -- (v2.8: 8 a row)
							Parent = list,
						}, function()
							local on = p:GetAttribute(attr) == true
							AdminRemote:FireServer("gift", p.UserId, power .. ":" .. (on and "0" or "1"))
						end)
						paint()
						p:GetAttributeChangedSignal(attr):Connect(paint)
					end
					ty += 30 + math.floor((#powers - 1) / 8) * 28
				end
				-- gift titles: shown over the player's head (he equips it in M > INVENTORY)
				UI.label({ Text = "TITLES", Font = UI.FONT_TITLE, TextSize = 12, TextColor3 = C.dim, Position = UDim2.fromOffset(12, ty), Size = UDim2.fromOffset(60, 14), Parent = list })
				for i, tid in { "creator", "sigma", "evil", "good" } do
					local tb
					local attr = "GiftTitle_" .. tid
					local function paintT()
						local on = p:GetAttribute(attr) == true
						tb.BackgroundColor3 = on and C.amber or C.panel2
						tb.TextColor3 = on and Color3.new(0, 0, 0) or C.text
					end
					tb = UI.button({
						Text = tid == "creator" and "CREATOR" or string.upper(tid),
						Size = UDim2.fromOffset(80, 22),
						Position = UDim2.fromOffset(12 + (i - 1) * 84, ty + 16),
						Parent = list,
					}, function()
						AdminRemote:FireServer("titlegift", p.UserId, tid .. ":" .. (p:GetAttribute(attr) == true and "0" or "1"))
					end)
					paintT()
					p:GetAttributeChangedSignal(attr):Connect(paintT)
				end
				ty += 46
				-- money (dollars for the weapon skins)
				UI.label({ Text = "MONEY", Font = UI.FONT_TITLE, TextSize = 12, TextColor3 = C.dim, Position = UDim2.fromOffset(12, ty), Size = UDim2.fromOffset(60, 14), Parent = list })
				for i, amount in { 100, 1000, 10000, -1000 } do
					UI.button({
						Text = (amount > 0 and "+$" or "-$") .. tostring(math.abs(amount)),
						Size = UDim2.fromOffset(80, 22),
						Position = UDim2.fromOffset(12 + (i - 1) * 84, ty + 16),
						Parent = list,
					}, function()
						AdminRemote:FireServer("cash", p.UserId, amount)
					end)
				end
				y = ty + 52
			end
		end
		if y == 0 then
			UI.label({ Text = "Nobody else is here yet.", TextSize = 14, TextColor3 = C.dim, Position = UDim2.fromOffset(12, 4), Size = UDim2.new(1, -24, 0, 20), Parent = list })
		end
		(page :: any).CanvasSize = UDim2.fromOffset(0, math.max(320, y + 60))
	end
	refresh()
	local function watchAdmin(p: Player)
		p:GetAttributeChangedSignal("GiftAdmin"):Connect(function()
			task.defer(refresh)
		end)
		p:GetAttributeChangedSignal("Admin"):Connect(function()
			task.defer(refresh)
		end)
	end
	for _, p in Players:GetPlayers() do
		watchAdmin(p)
	end
	Players.PlayerAdded:Connect(function(p)
		watchAdmin(p)
		task.defer(refresh)
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(refresh)
	end)
end

------------------------------------------------------------------------
-- (v2.0) CODES: type a code, get a skin / a title (RewardService checks it)
------------------------------------------------------------------------

local codeResult: TextLabel? = nil

local function buildCodesPage(page: Frame)
	section(page, 8, "CODES")
	UI.label({
		Text = "Codes come with the updates (Discord, the game page). Every update brings a new code with a new skin - "
			.. "and the code of the update before stops working. What you unlocked stays yours.",
		TextSize = 13,
		TextWrapped = true,
		TextColor3 = C.dim,
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -24, 0, 36),
		Parent = page,
	})
	local box = UI.make("TextBox", {
		Name = "CodeBox",
		Text = "",
		PlaceholderText = "Type a code ...",
		ClearTextOnFocus = false,
		Font = Enum.Font.Sarpanch,
		TextSize = 17,
		TextColor3 = C.text,
		PlaceholderColor3 = C.dim,
		BackgroundColor3 = C.panel2,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(12, 78),
		Size = UDim2.new(1, -170, 0, 36),
		Parent = page,
	})
	UI.make("UICorner", { CornerRadius = UDim.new(0, 0), Parent = box })
	UI.make("UIPadding", { PaddingLeft = UDim.new(0, 10), Parent = box })
	local function send()
		local text = box.Text
		if string.gsub(text, "%s", "") == "" then
			return
		end
		RewardRemote:FireServer("redeem", text)
		if codeResult then
			codeResult.Text = "Checking ..."
			codeResult.TextColor3 = C.dim
		end
	end
	UI.button({
		Text = "REDEEM",
		TextSize = 15,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 78),
		Size = UDim2.fromOffset(146, 36),
		BackgroundColor3 = C.amber,
		TextColor3 = Color3.new(0, 0, 0),
		Parent = page,
	}, send)
	box.FocusLost:Connect(function(enter)
		if enter then
			send()
		end
	end)
	codeResult = UI.label({
		Text = "",
		Font = Enum.Font.Sarpanch,
		TextSize = 14,
		TextWrapped = true,
		TextColor3 = C.dim,
		Position = UDim2.fromOffset(12, 122),
		Size = UDim2.new(1, -24, 0, 36),
		Parent = page,
	})
	UI.label({
		Text = "Skins appear in the spawn menu (T). Titles: M > INVENTORY - the one you wear shows over your head. "
			.. "More titles come from kills (10, 100, 500, 1000 ...) and from play time (5 h, 24 h, 50 h ...).",
		TextSize = 12,
		TextWrapped = true,
		TextColor3 = C.dim,
		Position = UDim2.fromOffset(12, 170),
		Size = UDim2.new(1, -24, 0, 34),
		Parent = page,
	})
	;(page :: any).CanvasSize = UDim2.fromOffset(0, 220)
end

------------------------------------------------------------------------
-- (v2.0) INVENTORY: your titles (wear one) and your skins
------------------------------------------------------------------------

local inventoryRefresh: (() -> ())? = nil

local function killsNow(): number
	local ls = player:FindFirstChild("leaderstats")
	local k = ls and ls:FindFirstChild("Kills")
	return (k and k:IsA("IntValue")) and k.Value or 0
end

local function fmtNum(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function buildInventoryPage(page: Frame)
	local TitleClient = require(Modules:WaitForChild("TitleClient")) :: any
	local y = 8
	section(page, y, "TITLES  (the one you wear shows over your head)")
	y += 24
	UI.label({ Text = "WEARING:", Font = Enum.Font.Sarpanch, TextSize = 13, TextColor3 = C.dim, Position = UDim2.fromOffset(12, y), Size = UDim2.fromOffset(80, 26), Parent = page })
	local wearing = UI.label({ Text = "", Font = Enum.Font.Sarpanch, TextSize = 18, Position = UDim2.fromOffset(92, y), Size = UDim2.new(1, -250, 0, 26), Parent = page })
	local takeOff = UI.button({
		Text = "TAKE IT OFF",
		TextSize = 12,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, y),
		Size = UDim2.fromOffset(130, 26),
		Parent = page,
	}, function()
		RewardRemote:FireServer("equip", "")
	end)
	y += 34
	local rows = {}
	for _, def in Titles.List do
		local row = UI.make("Frame", { BackgroundColor3 = C.panel2, BackgroundTransparency = 0.45, BorderSizePixel = 0, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 30), Parent = page })
		local name = UI.label({ Text = def.name, Font = Enum.Font.Sarpanch, TextSize = 16, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(190, 30), Parent = row })
		local info = UI.label({ Text = "", TextSize = 13, TextColor3 = C.dim, Position = UDim2.fromOffset(204, 0), Size = UDim2.new(1, -320, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		local btn = UI.button({
			Text = "",
			TextSize = 12,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			Size = UDim2.fromOffset(104, 24),
			Parent = row,
		}, function()
			local owned = Titles.Decode(player:GetAttribute("TitlesOwned"))
			if owned[def.id] and player:GetAttribute("Title") ~= def.id then
				RewardRemote:FireServer("equip", def.id)
				SoundLibrary.Play("click")
			end
		end)
		table.insert(rows, { def = def, row = row, name = name, info = info, btn = btn, styled = nil })
		y += 34
	end
	local skinHead = UI.label({ Text = "SKINS", Font = UI.FONT_TITLE, TextSize = 13, TextColor3 = C.amber, Position = UDim2.fromOffset(12, y + 8), Size = UDim2.new(1, -24, 0, 18), Parent = page })
	local skinRows = {}
	for _, s in Skins.List do
		local row = UI.make("Frame", { BackgroundColor3 = C.panel2, BackgroundTransparency = 0.45, BorderSizePixel = 0, Size = UDim2.new(1, -24, 0, 30), Parent = page })
		local name = UI.label({ Text = string.upper(s.name), Font = Enum.Font.Sarpanch, TextSize = 16, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(190, 30), Parent = row })
		local info = UI.label({ Text = "", TextSize = 13, TextColor3 = C.dim, Position = UDim2.fromOffset(204, 0), Size = UDim2.new(1, -320, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		local state = UI.label({ Text = "", Font = Enum.Font.Sarpanch, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(100, 30), Parent = row })
		table.insert(skinRows, { skin = s, row = row, name = name, info = info, state = state })
	end
	inventoryRefresh = function()
		local owned = Titles.Decode(player:GetAttribute("TitlesOwned"))
		local worn = player:GetAttribute("Title")
		local wornDef = typeof(worn) == "string" and Titles.ById[worn] or nil
		wearing.Text = wornDef and wornDef.name or "NOTHING"
		TitleClient.Style(wearing, wornDef and worn or nil, wornDef == nil)
		takeOff.Visible = wornDef ~= nil
		local hours = (tonumber(player:GetAttribute("PlayTime")) or 0) / 3600
		local kills = killsNow()
		local yy = 66
		for _, r in rows do
			local def = r.def
			local have = owned[def.id] == true
			r.row.Visible = have or not def.hidden
			if not r.row.Visible then
				continue
			end
			r.row.Position = UDim2.fromOffset(12, yy)
			yy += 34
			local styleKey = have and def.id or "locked"
			if r.styled ~= styleKey then
				r.styled = styleKey
				TitleClient.Style(r.name, def.id, not have)
			end
			if have then
				r.info.Text = def.how
			elseif def.source == "kills" then
				r.info.Text = string.format("%s / %s kills", fmtNum(math.min(kills, def.need)), fmtNum(def.need))
			elseif def.source == "playtime" then
				r.info.Text = string.format("%.1f / %d hours played", math.min(hours, def.need), def.need)
			else
				r.info.Text = def.how
			end
			if not have then
				r.btn.Text = "LOCKED"
				r.btn.BackgroundColor3 = C.panel3
				r.btn.TextColor3 = C.dim
			elseif worn == def.id then
				r.btn.Text = "WEARING"
				r.btn.BackgroundColor3 = C.good
				r.btn.TextColor3 = Color3.new(0, 0, 0)
			else
				r.btn.Text = "WEAR IT"
				r.btn.BackgroundColor3 = C.amber
				r.btn.TextColor3 = Color3.new(0, 0, 0)
			end
		end
		skinHead.Position = UDim2.fromOffset(12, yy + 8)
		yy += 32
		for _, r in skinRows do
			local have = player:GetAttribute("Skin_" .. r.skin.id) == true
			r.row.Position = UDim2.fromOffset(12, yy)
			yy += 34
			r.name.TextColor3 = have and Color3.fromRGB(255, 210, 80) or Color3.fromRGB(110, 110, 116)
			r.info.Text = have and "Spawn it: T > WEAPONS" or r.skin.how
			r.state.Text = have and "OWNED" or "LOCKED"
			r.state.TextColor3 = have and C.good or C.dim
		end
		;(page :: any).CanvasSize = UDim2.fromOffset(0, yy + 10)
	end
	;(inventoryRefresh :: () -> ())()
end

local function showPage(name: string)
	require(Modules.CommunityClient).Refresh(name)
	if name == "inventory" and inventoryRefresh then
		inventoryRefresh()
	end
	for n, p in pages do
		p.Visible = n == name
		local t = tabs[n]
		if t then
			t.BackgroundColor3 = n == name and C.amber or C.panel2
			t.TextColor3 = n == name and Color3.new(0, 0, 0) or C.text
		end
	end
end

local function build()
	gui = UI.make("ScreenGui", {
		Name = "SettingsMenu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Parent = player:WaitForChild("PlayerGui"),
	})
	root = UI.panel({
		Name = "Menu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(560, 470),
		BackgroundTransparency = 0.08,
		Accent = C.amber,
		Visible = false,
		Parent = gui,
	})
	UI.make("UISizeConstraint", { MaxSize = Vector2.new(560, 470), Parent = root })
	UI.make("UIScale", { Name = "Scale", Parent = root }):SetAttribute("Managed", true)
	local tabList = { { "settings", "SETTINGS" }, { "skins", "SKINS" }, { "inventory", "INVENTORY" }, { "cyber", "CYBER" }, { "clans", "CLANS" }, { "daily", "DAILY" }, { "bounty", "BOUNTY" }, { "codes", "CODES" }, { "vote", "VOTE" } }
	if Items.IsOwner(player) then
		table.insert(tabList, { "gifts", "GIFTS" })
		table.insert(tabList, { "giftlog", "GIFT LOG" })
		table.insert(tabList, { "admin", "ADMIN" })
		table.insert(tabList, { "players", "PLAYERS" })
	end
	-- Two readable rows instead of squeezing every admin tab into one narrow strip.
	local columns = 7
	local tabW = 70
	for i, t in tabList do
		tabs[t[1]] = UI.button({
			Text = t[2], TextSize = 11, Size = UDim2.fromOffset(tabW - 4, 28),
			Position = UDim2.fromOffset(12 + ((i - 1) % columns) * tabW, 8 + math.floor((i - 1) / columns) * 32),
			Parent = root,
		}, function() showPage(t[1]) end)
	end
	UI.button({
		Text = "X",
		Size = UDim2.fromOffset(32, 28),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 8),
		BackgroundColor3 = C.bad,
		Parent = root,
	}, function()
		SettingsMenu.Close()
	end)
	for _, t in tabList do
		local page = UI.make("ScrollingFrame", {
			Name = t[1],
			Position = UDim2.fromOffset(0, 78),
			Size = UDim2.new(1, 0, 1, -84),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.fromOffset(0, t[1] == "settings" and (#Settings.List * 32 + 150) or 380),
			Visible = false,
			Parent = root,
		})
		pages[t[1]] = page
		if t[1] == "settings" then
			buildSettingsPage(page)
		elseif t[1] == "vote" then
			buildVotePage(page)
		elseif t[1] == "gifts" then
			buildGiftPage(page)
		elseif t[1] == "clans" then
			require(Modules.CommunityClient).BuildClans(page)
		elseif t[1] == "daily" then
			require(Modules.CommunityClient).BuildDaily(page)
		elseif t[1] == "giftlog" then
			require(Modules.GiftRegistryClient).Build(page)
		elseif t[1] == "players" then
			buildPlayersPage(page)
		elseif t[1] == "codes" then
			buildCodesPage(page)
		elseif t[1] == "inventory" then
			buildInventoryPage(page)
		elseif t[1] == "skins" then
			require(Modules:WaitForChild("ShopClient")).BuildPage(page) -- (v2.1) weapon skins: colour and material
		elseif t[1] == "bounty" then
			require(Modules:WaitForChild("BountyClient")).BuildPage(page) -- (v2.8) bounties
		elseif t[1] == "cyber" then
			require(Modules:WaitForChild("CyberClient")).BuildPage(page) -- (v2.8) your implants, the cyber bar keys, the chips
		else
			buildAdminPage(page)
		end
	end
	showPage("settings")
	-- small screens: scale the menu down
	local function fit()
		local cam = workspace.CurrentCamera
		local vs = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local fitS = math.min((vs.X - 20) / 560, (vs.Y - 20) / 470)
		local s = math.min(1, fitS)
		local scale = root:FindFirstChild("Scale") :: UIScale
		-- (v2.0) the UI size setting, as far as the screen allows
		scale.Scale = math.max(0.5, math.min(s * UI.Global(), math.max(fitS, 0.5)))
	end
	fit()
	Settings.Changed:Connect(function(key)
		if key == "uiScale" then
			fit()
		end
	end)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
end

function SettingsMenu.IsOpen(): boolean
	return open
end

function SettingsMenu.Close()
	if not open then
		return
	end
	open = false
	root.Visible = false
	Input.menuOpen = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(root) then
		GuiService.SelectedObject = nil
	end
end

function SettingsMenu.Toggle()
	if open then
		SettingsMenu.Close()
		return
	end
	-- the spawn menu closes first
	if Input.menuOpen and SettingsMenu.HUD then
		SettingsMenu.HUD.ToggleMenu()
	end
	open = true
	Input.menuOpen = true
	root.Visible = true
	if adminRefresh then
		adminRefresh()
	end
end

function SettingsMenu.OpenPage(name)
	if Input.IsControlled() then return end
	if not open then SettingsMenu.Toggle() end
	showPage(name)
end

function SettingsMenu.Init()
	AdminRemote.OnClientEvent:Connect(function(action, message)
		if action == "reseterror" then
			pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = "PROGRESS RESET", Text = tostring(message), Duration = 8 }) end)
		end
	end)
	build()
	task.spawn(function() require(Modules.CommunityClient).Init(SettingsMenu) end)
	-- (v2.0) codes: the answer; the inventory follows what you own / wear / did
	RewardRemote.OnClientEvent:Connect(function(action, ok, msg)
		if action == "redeemed" and codeResult and typeof(msg) == "string" then
			codeResult.Text = msg
			codeResult.TextColor3 = ok and C.good or C.bad
			SoundLibrary.Play(ok and "questDing" or "click", nil, ok and 0.8 or 0.6, ok and 1 or 0.7)
		end
	end)
	local function refreshInventory()
		if inventoryRefresh and open and pages.inventory and pages.inventory.Visible then
			inventoryRefresh()
		end
	end
	player.AttributeChanged:Connect(function(name)
		if name == "TitlesOwned" or name == "Title" or name == "PlayTime" or string.sub(name, 1, 5) == "Skin_" then
			refreshInventory()
		end
	end)
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 60)
		local k = ls and ls:WaitForChild("Kills", 10)
		if k then
			(k :: IntValue).Changed:Connect(refreshInventory)
		end
	end)
	-- (v2.0) admin rights arrive a moment after joining (private server owner / admin pass): the menu gets the tabs
	player:GetAttributeChangedSignal("Admin"):Connect(function()
		local wasOpen = open
		if open then
			SettingsMenu.Close()
		end
		if gui then
			gui:Destroy()
		end
		table.clear(pages)
		table.clear(tabs)
		adminRefresh = nil
		build()
		if wasOpen then
			SettingsMenu.Toggle()
		end
	end)
	Settings.Changed:Connect(function(key, value)
		if key == "wonder" then
			AdminRemote:FireServer("wonder", value == true)
		end
		applyAll(key)
		local r = rowsByKey[key]
		if r then
			r()
		end
		queueSave()
	end)
	SettingsRemote.OnClientEvent:Connect(function(action, data)
		if action == "load" and typeof(data) == "table" then
			Settings.SetAll(data)
		end
	end)
	SettingsRemote:FireServer("load")
	for _, d in workspace:GetDescendants() do
		watchGore(d)
	end
	workspace.DescendantAdded:Connect(watchGore)
	applyAll(nil)
	Input.Action:Connect(function(action)
		if action == "Settings" then
			SettingsMenu.Toggle()
		end
	end)
end

return SettingsMenu
