--!nonstrict
-- GrabOutline (v2.8): a thin white outline round an item you can pick up (weapons, tools - anything with "Item": not held
-- by anybody, not in a pocket, not bound to somebody else). (v2.8.1) Only the item a free hand is close enough to take:
-- the next Q / E takes exactly the outlined one (the hands' own grab search decides). M > SETTINGS "White outline on
-- things you can grab" switches it off.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Settings = require(Shared:WaitForChild("Settings"))
local Items = require(Shared:WaitForChild("Items"))

local GrabOutline = {}

local player = Players.LocalPlayer

local shown: { [Model]: Highlight } = {}

local function grabbable(m: Model): boolean
	if m:GetAttribute("HolderId") ~= nil or m:GetAttribute("StowedBy") ~= nil or m:GetAttribute("NPCHeld") then
		return false
	end
	local bound = m:GetAttribute("BoundTo")
	if typeof(bound) == "number" and bound ~= player.UserId then
		return false
	end
	if Items.IsOwnerOnly(m) and not Items.MayUse(player, m) then
		return false
	end
	return m.PrimaryPart ~= nil
end

local function clearAll()
	for m, h in shown do
		h:Destroy()
		shown[m] = nil
	end
end

local controller: any = nil

function GrabOutline.SetController(c: any)
	controller = c
end

local function update()
	if Settings.Get("grabOutline") == false then
		clearAll()
		return
	end
	local char = player.Character
	if not char or char:GetAttribute("Dead") or not controller or not controller.ready or not controller.GrabCandidate then
		clearAll()
		return
	end
	local keep = {}
	for _, side in { "Left", "Right" } do
		local hand = controller.hands and controller.hands[side]
		if hand and not hand.grip then
			local ok, part = pcall(controller.GrabCandidate, controller, side, 0.35)
			local m = ok and part and Items.ModelOf(part)
			if m and m:GetAttribute("Item") ~= nil and grabbable(m) then
				keep[m] = true
			end
		end
	end
	for m, h in shown do
		if not keep[m] or not m.Parent then
			h:Destroy()
			shown[m] = nil
		end
	end
	for m in keep do
		if not shown[m] then
			local h = Instance.new("Highlight")
			h.Name = "GrabOutline"
			h.Adornee = m
			h.FillTransparency = 1
			h.OutlineColor = Color3.fromRGB(255, 255, 255)
			h.OutlineTransparency = 0.25
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Parent = m -- (only on this screen: a local child)
			shown[m] = h
		end
	end
end

function GrabOutline.Init()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.08 then
			return
		end
		acc = 0
		update()
	end)
	Settings.Changed:Connect(function(key)
		if key == "grabOutline" then
			update()
		end
	end)
end

return GrabOutline
