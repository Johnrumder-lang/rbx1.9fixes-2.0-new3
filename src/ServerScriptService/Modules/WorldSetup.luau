--!nonstrict
-- WorldSetup: runtime-only world bits (clouds, folders, pad labels, teleport pads).
-- (No floating signs above the test areas any more.)

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local WorldSetup = {}

-- set by GameModeService: may this marker item come back now? (no guns in hide and seek)
WorldSetup.CanRestock = nil :: ((string) -> boolean)?

local function ensureFolder(name: string): Folder
	local f = workspace:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = workspace
	end
	return f :: Folder
end

local function surfaceLabel(part: BasePart, face: Enum.NormalId, text: string, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Font = Enum.Font.Sarpanch
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.18, 0)
	pad.PaddingBottom = UDim.new(0.18, 0)
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.Parent = label
end

function WorldSetup.Init()
	ensureFolder("FX")
	ensureFolder("SpawnedProps")
	ensureFolder("Gibs")
	ensureFolder("Corpses")
	ensureFolder("Dummies")

	-- the pool: real (terrain) water inside every WaterVolume
	local terrain = workspace:FindFirstChildOfClass("Terrain")
	local mapFolder = workspace:FindFirstChild("Map")
	if terrain and mapFolder then
		terrain.WaterColor = Color3.fromRGB(28, 104, 128)
		terrain.WaterTransparency = 0.55
		terrain.WaterReflectance = 0.45
		terrain.WaterWaveSize = 0.08
		terrain.WaterWaveSpeed = 6
		for _, d in mapFolder:GetDescendants() do
			if d:IsA("BasePart") and d.Name == "WaterVolume" then
				pcall(function()
					terrain:FillBlock(d.CFrame, d.Size, Enum.Material.Water)
				end)
			end
		end
	end

	-- overcast sky like the reference video
	if terrain and not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.78
		clouds.Density = 0.62
		clouds.Color = Color3.fromRGB(232, 236, 242)
		clouds.Parent = terrain
	end
	Lighting:SetAttribute("SandboxLighting", true)

	local map = workspace:FindFirstChild("Map")
	if map then
		WorldSetup.ProcessMap(map)
	end
end

-- (v2.0) the construction site comes apart: its beams, columns and scaffolding break loose (blasts, rockets, a car
-- at speed) and are put back after a while (ExplosionService); its floor slabs and fences get holes (FractureService)
local SITE_BREAK = { SteelBeam = true, ["Steel Beam"] = true, Column = true, ScaffoldPole = true, ScaffoldRail = true, RoofRail = true, RailPost = true }
local siteN = 0

-- Named parts get their behaviour (used for the sandbox map and for the city when it is loaded).
function WorldSetup.ProcessMap(map: Instance)
	local site = map:FindFirstChild("ConstructionSite", true)
	if site then
		for _, d in site:GetDescendants() do
			if d:IsA("BasePart") and d.Anchored and SITE_BREAK[d.Name] and not d:GetAttribute("Destructible") then
				siteN += 1
				d:SetAttribute("Destructible", "Site" .. siteN)
			end
		end
	end
	-- Drop pads: "DropPad_45" teleports you 45 studs into the air (client handles the teleport)
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			-- spikes: "SpikeTip*" / "Spike*" are needle sharp, "DullSpike*" use their geometry
			if string.match(d.Name, "^SpikeTip") or string.match(d.Name, "^Spike") then
				d:SetAttribute("Sharpness", string.match(d.Name, "^SpikeTip") and 1 or 0.85)
			end
			-- breakable walls: "Brick_<group>_<n>"
			local grp = string.match(d.Name, "^Brick_(%w+)_%d+$")
			if grp then
				d:SetAttribute("Destructible", grp)
			end
			local h = string.match(d.Name, "^DropPad_(%d+)$")
			if h then
				d:SetAttribute("DropHeight", tonumber(h))
				surfaceLabel(d, Enum.NormalId.Top, "DROP " .. h, Color3.fromRGB(255, 255, 255))
			end
			-- shortcuts: "TeleportPad_<key>" takes you to "TeleportTarget_<key>" (client handles it)
			local key = string.match(d.Name, "^TeleportPad_(%w+)$")
			if key then
				local target = map:FindFirstChild("TeleportTarget_" .. key, true)
				if target and target:IsA("BasePart") then
					d:SetAttribute("TeleportTo", target.Position)
					local text = key == "Site" and "TO THE SITE" or (key == "Spawn" and "TO SPAWN" or (key == "Airfield" and "TO THE JETS"
						or (key == "Roof" and "ELEVATOR: ROOF" or (key == "Lobby" and "ELEVATOR: LOBBY" or key:upper()))))
					surfaceLabel(d, Enum.NormalId.Top, text, Color3.fromRGB(255, 255, 255))
				end
			end
			-- (v2.0) "Sign_<TEXT>": a board with that text on its front (underscores are spaces); dark boards get
			-- light letters, light boards dark ones
			local sign = string.match(d.Name, "^Sign_(.+)$")
			if sign and not d:FindFirstChild("Label") then
				local c = d.Color
				local bright = (c.R + c.G + c.B) / 3 > 0.45
				surfaceLabel(d, Enum.NormalId.Front, string.upper((string.gsub(sign, "_", " "))),
					bright and Color3.fromRGB(24, 40, 110) or Color3.fromRGB(245, 240, 225))
			end
			-- construction lift: stand on "LiftPad_<floor>" and pick a floor ("LiftTarget_<floor>")
			local floor = string.match(d.Name, "^LiftPad_(%d+)$")
			if floor then
				d:SetAttribute("LiftFloor", tonumber(floor))
				surfaceLabel(d, Enum.NormalId.Top, "LIFT", Color3.fromRGB(255, 255, 255))
			end
		end
	end
end

-- a text on top of a pad (replaces the old one)
function WorldSetup.Label(part: BasePart, text: string?)
	local old = part:FindFirstChild("Label")
	if old then
		old:Destroy()
	end
	if text then
		surfaceLabel(part, Enum.NormalId.Top, text, Color3.fromRGB(255, 255, 255))
	end
end

local function positionOf(inst: Instance): Vector3
	if inst:IsA("Model") then
		return inst:GetPivot().Position
	elseif inst:IsA("BasePart") then
		return inst.Position
	end
	return Vector3.zero
end

-- Props that need server builders (guns, spears, cars, ...) are placed on "Marker_<itemId>" parts.
-- The armory restocks: when an item was taken away (or used up, or a car wrecked), a new one
-- appears on its marker after a while (at most a few copies of each).
-- Returns a handle: handle.Stop() ends the restocking and removes everything it put there that
-- nobody carried away (used when the city is unloaded).
export type MarkerHandle = { Stop: () -> (), items: { Instance } }

function WorldSetup.SpawnMarkers(PropService, root: Instance?): MarkerHandle?
	local map = root or workspace:FindFirstChild("Map")
	if not map then
		return nil
	end
	local markers = {}
	local handle: MarkerHandle
	local placed: { Instance } = {}
	local stopped = false
	handle = {
		items = placed,
		Stop = function()
			stopped = true
			for _, inst in placed do
				if inst.Parent then
					inst:Destroy()
				end
			end
			for _, rec in markers do
				for _, c in rec.copies do
					if c.Parent then
						c:Destroy()
					end
				end
			end
			table.clear(placed)
		end,
	}
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			-- "Place_<id>": put there once (furniture), no restocking
			local once = string.match(d.Name, "^Place_([%w_]+)$")
			if once then
				local inst = PropService.Place(once, d.CFrame)
				if inst then
					table.insert(placed, inst)
				end
			end
			local id = string.match(d.Name, "^Marker_([%w_]+)$")
			if id then
				local rec = { id = id, part = d, copies = {} }
				table.insert(markers, rec)
				local inst = PropService.Place(id, d.CFrame)
				if inst then
					table.insert(rec.copies, inst)
				end
			end
		end
	end
	task.spawn(function()
		while not stopped do
			task.wait(Config.MarkerRestock)
			if stopped then
				break
			end
			for _, rec in markers do
				if WorldSetup.CanRestock and not WorldSetup.CanRestock(rec.id) then
					continue
				end
				for i = #rec.copies, 1, -1 do
					local c = rec.copies[i]
					if not c.Parent or c:GetAttribute("Wrecked") or c:GetAttribute("Dead") then
						table.remove(rec.copies, i)
					end
				end
				local reach = (rec.id == "car") and 10 or (rec.id == "jet" and 24 or (rec.id == "dummy" and 8 or 4))
				local home = false
				for _, c in rec.copies do
					if (positionOf(c) - rec.part.Position).Magnitude < reach then
						home = true
					end
				end
				local cap = (rec.id == "car" or rec.id == "dummy") and 2 or (rec.id == "jet" and 1 or Config.MarkerMaxCopies)
				if not home and #rec.copies < cap then
					local inst = PropService.Place(rec.id, rec.part.CFrame)
					if inst then
						table.insert(rec.copies, inst)
					end
				end
			end
		end
	end)
	return handle
end

return WorldSetup
