--!nonstrict
-- TitleClient (v2.0): the name tag over every player - their name and, above it, the title they wear (each title
-- has its own colour, the rare ones glow, shine or run through the colours; Shared/Titles). Walls hide the tags
-- (hide and seek stays fair). They use the game's font, show from 50 studs and shrink with distance; bots get one too. Also: the big "NEW TITLE" / "NEW SKIN" banner when you unlock something, and
-- TitleClient.Style for the menu's inventory.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Titles = require(Shared:WaitForChild("Titles"))
local Skins = require(Shared:WaitForChild("Skins"))
local SoundLibrary = require(Shared:WaitForChild("SoundLibrary"))

local Modules = script.Parent
local Input = require(Modules:WaitForChild("Input"))
local UI = require(Modules:WaitForChild("UI"))
local DragPuppets = require(Modules:WaitForChild("DragPuppets"))

local RewardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Reward") :: RemoteEvent

local player = Players.LocalPlayer

local TitleClient = {}

local TEAM_COLORS = {
	Red = Color3.fromRGB(255, 110, 100),
	Blue = Color3.fromRGB(110, 160, 255),
}

------------------------------------------------------------------------
-- how a title looks (also used by the menu)
------------------------------------------------------------------------

type Anim = { def: any, label: TextLabel, stroke: UIStroke?, grad: UIGradient? }
local anims: { [TextLabel]: Anim } = setmetatable({}, { __mode = "k" }) :: any

local function clearStyle(label: TextLabel)
	for _, c in label:GetChildren() do
		if c:IsA("UIStroke") or c:IsA("UIGradient") then
			c:Destroy()
		end
	end
	anims[label] = nil
end

-- dress a TextLabel as title `id` (nil / unknown: plain white)
function TitleClient.Style(label: TextLabel, id: string?, locked: boolean?)
	clearStyle(label)
	local def = id and Titles.ById[id]
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = 1.5
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Transparency = 0.25
	stroke.Parent = label
	if not def or locked then
		label.TextColor3 = locked and Color3.fromRGB(110, 110, 116) or Color3.new(1, 1, 1)
		return
	end
	local a: Anim = { def = def, label = label, stroke = stroke }
	if def.style == "plain" then
		label.TextColor3 = def.color
		return
	elseif def.style == "glow" then
		label.TextColor3 = def.color
		stroke.Color = def.color2 or def.color
		stroke.Thickness = 2
	elseif def.style == "void" then
		label.TextColor3 = def.color
		stroke.Color = def.color2 or Color3.fromRGB(255, 40, 30)
		stroke.Thickness = 2
		stroke.Transparency = 0
	elseif def.style == "shine" or def.style == "rainbow" or def.style == "aurora" then
		label.TextColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(def.color)
		g.Parent = label
		a.grad = g
	end
	anims[label] = a
end

local function rainbow(t: number): ColorSequence
	local kps = {}
	for i = 0, 5 do
		local k = i / 5
		table.insert(kps, ColorSequenceKeypoint.new(k, Color3.fromHSV((t * 0.25 + k * 0.6) % 1, 0.75, 1)))
	end
	return ColorSequence.new(kps)
end

local function aurora(t: number): ColorSequence
	local kps = {}
	for i = 0, 4 do
		local k = i / 4
		local h = 0.5 + 0.38 * (0.5 + 0.5 * math.sin(t * 0.9 + k * 2.4)) -- (cyan .. violet .. pink)
		table.insert(kps, ColorSequenceKeypoint.new(k, Color3.fromHSV(h % 1, 0.55, 1)))
	end
	return ColorSequence.new(kps)
end

local function shine(def: any, t: number): ColorSequence
	-- a bright stripe runs over the letters, then a pause
	local cycle = (t % 2.6) / 1.6
	local base, hi = def.color, def.color2 or Color3.new(1, 1, 1)
	if cycle >= 1 then
		return ColorSequence.new(base)
	end
	local p = -0.2 + cycle * 1.4
	local times = { 0, p - 0.16, p, p + 0.16, 1 }
	local cols = { base, base, hi, base, base }
	local kps = { ColorSequenceKeypoint.new(0, base) }
	local last = 0
	for i = 2, 4 do
		local tt = times[i]
		if tt > last + 0.001 and tt < 0.999 then
			table.insert(kps, ColorSequenceKeypoint.new(tt, cols[i]))
			last = tt
		end
	end
	table.insert(kps, ColorSequenceKeypoint.new(1, base))
	return ColorSequence.new(kps)
end

local function animate(t: number)
	for label, a in anims do
		if not label.Parent then
			anims[label] = nil
			continue
		end
		local style = a.def.style
		if style == "glow" and a.stroke then
			a.stroke.Transparency = 0.35 + math.sin(t * 3) * 0.3
		elseif style == "void" and a.stroke then
			a.stroke.Transparency = 0.15 + math.sin(t * 5) * 0.15
			a.stroke.Thickness = 2 + math.sin(t * 5) * 0.6
		elseif style == "rainbow" and a.grad then
			a.grad.Color = rainbow(t)
		elseif style == "aurora" and a.grad then
			a.grad.Color = aurora(t)
		elseif style == "shine" and a.grad then
			a.grad.Color = shine(a.def, t)
		end
	end
end

------------------------------------------------------------------------
-- the tags over the players
------------------------------------------------------------------------

type Tag = { gui: BillboardGui, title: TextLabel, name: TextLabel, titleId: string?, char: Model?, adornee: BasePart? }
local tags: { [Player]: Tag } = {}
local npcTags: { [Model]: Tag } = {} -- (v2.0) the bots get a name tag too (the same: walls hide it)

-- (v2.0) the tags use the game's font, are seen from closer, and get smaller the further away they are
local TAG_FONT = UI.FONT_TITLE
local TAG_RANGE = 50 -- studs: further away, no tag
local NAME_SIZE = 18
local TITLE_SIZE = 20

local function makeTag(text: string): Tag
	local pg = player:WaitForChild("PlayerGui")
	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag_" .. text
	bb.Size = UDim2.fromOffset(260, 54)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	bb.MaxDistance = TAG_RANGE
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false -- (walls hide it)
	bb.ResetOnSpawn = false
	bb.Enabled = false
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0, 1)
	title.Size = UDim2.new(1, 0, 0.5, 0)
	title.Position = UDim2.fromScale(0, 0.5)
	title.Font = TAG_FONT
	title.TextSize = TITLE_SIZE
	title.TextYAlignment = Enum.TextYAlignment.Bottom
	title.Text = ""
	title.Parent = bb
	local name = Instance.new("TextLabel")
	name.Name = "PlayerName"
	name.BackgroundTransparency = 1
	name.AnchorPoint = Vector2.new(0, 1)
	name.Position = UDim2.fromScale(0, 1)
	name.Size = UDim2.new(1, 0, 0.5, 0)
	name.Font = TAG_FONT
	name.TextSize = NAME_SIZE
	name.TextYAlignment = Enum.TextYAlignment.Center
	name.TextColor3 = Color3.new(1, 1, 1)
	name.Text = text
	name.Parent = bb
	local ns = Instance.new("UIStroke")
	ns.Thickness = 1.5
	ns.Transparency = 0.25
	ns.Parent = name
	bb.Parent = pg
	return { gui = bb, title = title, name = name, titleId = nil, char = nil, adornee = nil }
end

local function place(tag: Tag, char: Model?)
	local shown = (char and DragPuppets.Of(char)) or char -- (v2.0) a dragged body: the copy at the hand
	local head = shown and shown:FindFirstChild("Head")
	local torso = shown and (shown:FindFirstChild("Torso") or shown.PrimaryPart)
	local headOk = head and head:IsA("BasePart") and not (char :: Model):GetAttribute("Severed_Head") and head.Transparency < 1
	local adornee = (headOk and head) or ((torso and torso:IsA("BasePart")) and torso or nil)
	tag.gui.Adornee = adornee
	tag.adornee = adornee
	tag.gui.StudsOffsetWorldSpace = Vector3.new(0, adornee == head and 2.1 or 3.3, 0)
	return adornee
end

local function updateTag(p: Player)
	local tag = tags[p]
	if not tag then
		tag = makeTag(p.DisplayName)
		tags[p] = tag
	end
	local char = p.Character
	local adornee = place(tag, char)
	-- (v2.8.1) a cloaked body (GHOSTSKIN) has no name over it either: fully invisible
	local cl = char and char:GetAttribute("Cloaked")
	local cloaked = p ~= player and typeof(cl) == "number" and workspace:GetServerTimeNow() < cl
	local hide = not char or char:GetAttribute("Dead") == true or adornee == nil or cloaked
		or (p == player and (Input.firstPerson or Input.spectating))
	tag.gui.Enabled = not hide
	-- the title
	local id = p:GetAttribute("Title")
	id = (typeof(id) == "string" and Titles.ById[id]) and id or nil
	if id ~= tag.titleId then
		tag.titleId = id
		local def = id and Titles.ById[id]
		tag.title.Text = def and def.name or ""
		TitleClient.Style(tag.title, id)
	end
	-- the name: team colour in a team game, green for a zombie
	local team = p:GetAttribute("Team")
	local role = p:GetAttribute("Role")
	tag.name.Text = p.DisplayName
	tag.name.TextColor3 = (role == "Zombie" and Color3.fromRGB(140, 230, 110)) or (typeof(team) == "string" and TEAM_COLORS[team]) or Color3.new(1, 1, 1)
end

local function updateNpcTags()
	local npcs = workspace:FindFirstChild("NPCs")
	local seen = {}
	if npcs then
		for _, m in npcs:GetChildren() do
			local dn = m:GetAttribute("DisplayName")
			if m:IsA("Model") and typeof(dn) == "string" and dn ~= "" then
				seen[m] = true
				local tag = npcTags[m]
				if not tag then
					tag = makeTag(dn)
					npcTags[m] = tag
				end
				local adornee = place(tag, m)
				tag.gui.Enabled = adornee ~= nil and not m:GetAttribute("Dead")
				tag.name.Text = dn
				local team = m:GetAttribute("Team")
				local role = m:GetAttribute("Role")
				tag.name.TextColor3 = (role == "Zombie" and Color3.fromRGB(140, 230, 110)) or (typeof(team) == "string" and TEAM_COLORS[team]) or Color3.fromRGB(225, 225, 225)
			end
		end
	end
	for m, tag in npcTags do
		if not seen[m] then
			tag.gui:Destroy()
			npcTags[m] = nil
		end
	end
end

-- every frame: the further away, the smaller (full size up to 16 studs, then shrinking down to 40 %)
local function sizeTags()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local eye = cam.CFrame.Position
	local function size(tag: Tag)
		if not tag.gui.Enabled or not tag.adornee then
			return
		end
		local d = (tag.adornee.Position - eye).Magnitude
		local k = math.clamp(16 / math.max(d, 1), 0.4, 1)
		local hasTitle = tag.title.Text ~= ""
		tag.name.TextSize = math.floor(NAME_SIZE * k + 0.5)
		tag.title.TextSize = math.floor(TITLE_SIZE * k + 0.5)
		tag.title.Visible = hasTitle
		local h = (hasTitle and (TITLE_SIZE + NAME_SIZE + 10) or (NAME_SIZE + 6)) * k
		tag.gui.Size = UDim2.fromOffset(math.floor(260 * k), math.floor(h))
		tag.name.Size = hasTitle and UDim2.new(1, 0, NAME_SIZE / (TITLE_SIZE + NAME_SIZE), 0) or UDim2.fromScale(1, 1)
		tag.title.Size = UDim2.new(1, 0, TITLE_SIZE / (TITLE_SIZE + NAME_SIZE), 0)
		tag.title.Position = UDim2.fromScale(0, TITLE_SIZE / (TITLE_SIZE + NAME_SIZE))
	end
	for _, tag in tags do
		size(tag)
	end
	for _, tag in npcTags do
		size(tag)
	end
end

local function removeTag(p: Player)
	local tag = tags[p]
	if tag then
		tag.gui:Destroy()
		tags[p] = nil
	end
end

------------------------------------------------------------------------
-- unlocked!
------------------------------------------------------------------------

local bannerGui: ScreenGui? = nil
local queue: { { kind: string, id: string } } = {}
local showing = false

local function showNext()
	if showing or #queue == 0 then
		return
	end
	showing = true
	local item = table.remove(queue, 1) :: { kind: string, id: string }
	if not bannerGui then
		bannerGui = UI.make("ScreenGui", { Name = "Unlocks", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 30, Parent = player:WaitForChild("PlayerGui") })
	end
	local p = UI.panel({
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -120),
		Size = UDim2.fromOffset(420, 96),
		BackgroundTransparency = 0.1,
		Accent = UI.C.amber,
		Parent = bannerGui,
	})
	UI.label({
		Text = item.kind == "title" and "NEW TITLE" or "NEW SKIN",
		Font = UI.FONT_TITLE,
		TextSize = 14,
		TextColor3 = UI.C.dim,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = p,
	})
	local big = UI.label({
		Text = "",
		Font = Enum.Font.Sarpanch,
		TextSize = 30,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 28),
		Size = UDim2.new(1, 0, 0, 36),
		Parent = p,
	})
	local sub = UI.label({
		Text = "",
		TextSize = 13,
		TextColor3 = UI.C.text,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 68),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = p,
	})
	if item.kind == "title" then
		local def = Titles.ById[item.id]
		big.Text = def and def.name or item.id
		TitleClient.Style(big, item.id)
		sub.Text = (player:GetAttribute("Title") == item.id) and "You wear it now - everybody sees it over your head" or "Equip it: M > INVENTORY"
	else
		local s = Skins.ById[item.id]
		big.Text = string.upper(s and s.name or item.id)
		big.TextColor3 = Color3.fromRGB(255, 210, 80)
		sub.Text = "Spawn it: T > WEAPONS"
	end
	SoundLibrary.Play("questDone", nil, 0.9)
	TweenService:Create(p, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	task.delay(4.2, function()
		TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, 0, 0, -120) }):Play()
		task.wait(0.4)
		p:Destroy()
		showing = false
		showNext()
	end)
end

function TitleClient.Init()
	RewardRemote.OnClientEvent:Connect(function(action, a, b)
		if action == "unlocked" and typeof(a) == "string" and typeof(b) == "string" then
			table.insert(queue, { kind = a, id = b })
			showNext()
		end
	end)
	Players.PlayerRemoving:Connect(removeTag)
	-- the tags: refreshed 4 times a second (cheap), the colours every frame
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			for _, p in Players:GetPlayers() do
				updateTag(p)
			end
			updateNpcTags()
		end
		sizeTags()
		animate(os.clock())
	end)
end

return TitleClient
