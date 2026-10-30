--!nonstrict
-- RAGDOLL SANDBOX - client entry point.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local Modules = script:WaitForChild("Client")

local Input = require(Modules:WaitForChild("Input"))
local CameraController = require(Modules:WaitForChild("CameraController"))
local CharacterController = require(Modules:WaitForChild("CharacterController"))
local BloodFX = require(Modules:WaitForChild("BloodFX"))
local HUD = require(Modules:WaitForChild("HUD"))
local MobileControls = require(Modules:WaitForChild("MobileControls"))
local VehicleClient = require(Modules:WaitForChild("VehicleClient"))
local DragClient = require(Modules:WaitForChild("DragClient"))
local DragPuppets = require(Modules:WaitForChild("DragPuppets"))
local LaserFX = require(Modules:WaitForChild("LaserFX"))
local Hallucinations = require(Modules:WaitForChild("Hallucinations"))
local SettingsMenu = require(Modules:WaitForChild("SettingsMenu"))
local ModeClient = require(Modules:WaitForChild("ModeClient"))

local TVClient = require(Modules:WaitForChild("TVClient"))
local ExperimentalLighting = require(Modules:WaitForChild("ExperimentalLighting"))
local VoteClient = require(Modules:WaitForChild("VoteClient"))
local SpectateClient = require(Modules:WaitForChild("SpectateClient"))
local WeatherClient = require(Modules:WaitForChild("WeatherClient"))
local PianoClient = require(Modules:WaitForChild("PianoClient"))
local BoomboxClient = require(Modules:WaitForChild("BoomboxClient"))
local TutorialClient = require(Modules:WaitForChild("TutorialClient"))
local LeaderboardClient = require(Modules:WaitForChild("LeaderboardClient"))
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SoundLibrary = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SoundLibrary"))
local Events = require(Modules:WaitForChild("Events"))
local GearHUD = require(Modules:WaitForChild("GearHUD"))
local SuperFX = require(Modules:WaitForChild("SuperFX"))
local JetClient = require(Modules:WaitForChild("JetClient"))
local SteelBallFX = require(Modules:WaitForChild("SteelBallFX"))
local QuestClient = require(Modules:WaitForChild("QuestClient"))
local CreatureFX = require(Modules:WaitForChild("CreatureFX"))
local MapMood = require(Modules:WaitForChild("MapMood"))
local FreeCam = require(Modules:WaitForChild("FreeCam"))
local TitleClient = require(Modules:WaitForChild("TitleClient"))
local ToolFX = require(Modules:WaitForChild("ToolFX"))

local ResetRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Reset") :: RemoteEvent

local current = nil

Input.Init()
CameraController.Init()
HUD.Init()
MobileControls.Init(HUD.GetGui())
BloodFX.Init()
VehicleClient.Init()
DragClient.Init()
DragPuppets.Init() -- (v2.0) dragged players hang from the hand on every other screen
require(Modules:WaitForChild("WoundHoles")).Init(Events) -- (v2.0) holes you can look through
LaserFX.Init()
Hallucinations.Init()
TVClient.Init()
SettingsMenu.Init()
if not Config.Lite then
	ExperimentalLighting.Init()
end
VoteClient.Init()
if not Config.Lite then
	SpectateClient.Init()
end
if not Config.Lite then
	WeatherClient.Init()
end
if not Config.Lite then
	PianoClient.Init()
end
BoomboxClient.Init()
TutorialClient.Init()
LeaderboardClient.Init()
ModeClient.Init()
GearHUD.Init()
SuperFX.Init()
JetClient.Init()
SteelBallFX.Init()
QuestClient.Init()
CreatureFX.Init()
MapMood.Init()
FreeCam.Init()
TitleClient.Init()
-- (v2.1) weapon skins: the SKINS page of the M menu (colour and material only), the +$ messages
require(Modules:WaitForChild("ShopClient")).Init()
require(Modules:WaitForChild("SandevistanClient")).Init() -- (v2.1) the Sandevistan: green screen, afterimages, the implant bar
local LedgerClient = require(Modules:WaitForChild("LedgerClient"))
LedgerClient.Init() -- (v2.1) the Black Ledger: Kuro, the book
ToolFX.Init()
local CyberClient = require(Modules:WaitForChild("CyberClient"))
CyberClient.Init() -- (v2.8) cyberware: the cyber bar, the ripperdoc, implant effects
local ChipClient = require(Modules:WaitForChild("ChipClient"))
ChipClient.Init() -- (v2.9) the cyberdeck: chips, the netrunner interface, the video camera, computers, the Blackwall
require(Modules:WaitForChild("ReplayClient")).Init() -- (v2.8) the hospital's replay chair screen
require(Modules:WaitForChild("BountyClient")).Init() -- (v2.8) bounties
require(Modules:WaitForChild("SwordClient")).Init() -- (v2.8) the STILLWATER quest, the Pit, the Pale Heir, the STILL CUT
local GrabOutline = require(Modules:WaitForChild("GrabOutline"))
GrabOutline.Init() -- (v2.8) a white outline on the item a free hand is close enough to take
require(Modules:WaitForChild("EchoRadar")).Init() -- (v2.8) ECHO EARS: the footstep radar
do
	-- (v2.0) the UI size setting; one font for every text (menus, signs, prompts, chat)
	local UIm = require(Modules:WaitForChild("UI"))
	UIm.InitGlobalScale(player:WaitForChild("PlayerGui"))
	UIm.EnforceFont(player:WaitForChild("PlayerGui"))
	UIm.EnforceFont(workspace)
	UIm.ChatFont()
	require(Modules:WaitForChild("PromptUI")).Init()
end
Events.On("dragsnap", DragClient.Follow) -- (v2.0: carried by another machine - my screen follows the body)
-- one menu at a time: the spawn menu (T) and the settings / admin menu (M)
SettingsMenu.HUD = HUD
HUD.CloseOther = SettingsMenu.Close

-- a flash grenade: how blind you get depends on how close it is and whether you looked at it
local flashParams = RaycastParams.new()
flashParams.FilterType = Enum.RaycastFilterType.Exclude
local function onFlash(pos: Vector3, r: number)
	local cam = workspace.CurrentCamera
	local char = player.Character
	if not cam or not char or char:GetAttribute("Dead") then
		return
	end
	local camPos = cam.CFrame.Position
	local to = pos - camPos
	local d = to.Magnitude
	if d > r then
		return
	end
	flashParams.FilterDescendantsInstances = { char, workspace:FindFirstChild("FX") or char }
	local hit = workspace:Raycast(camPos, to, flashParams)
	local k = 1 - d / r
	if hit and (hit.Position - pos).Magnitude > 1.5 then
		SoundLibrary.Muffle(1 + 1.5 * k, 0.5) -- behind a wall: only the bang
		return
	end
	local facing = d > 0.1 and cam.CFrame.LookVector:Dot(to.Unit) or 1
	local look = math.clamp((facing + 0.3) / 1.3, 0, 1)
	local strength = math.clamp(k * (0.35 + 0.65 * look) * 1.4, 0, 1)
	HUD.Blind(strength, 0.6 + Config.FlashMaxBlind * strength)
	SoundLibrary.Muffle(1 + 4 * k, 0.6 + 0.4 * k)
	if k > 0.3 then
		SoundLibrary.Play("ringing", nil, k)
	end
	CameraController.Shake(0.4 + k)
end

BloodFX.SetHooks({
	onFlash = onFlash,
	onHurt = function(amount: number, _region: string)
		HUD.Flash(amount)
		CameraController.Shake(math.clamp(amount / 60, 0.3, 1.5))
	end,
	onKnock = function(region: string?, impulse: Vector3?, ragdollTime: number?, point: Vector3?, all: Vector3?)
		if current and current.ready then
			current:Knock(region, impulse, ragdollTime, point, all)
		end
	end,
	-- another player grabbed my body: their client carries it until they let go
	onDrag = function(payload)
		DragClient.Start(payload)
		-- keep the one who drags you in view
		CameraController.SetWatch(function()
			local char = player.Character
			local id = char and char:GetAttribute("DraggedBy")
			local by = typeof(id) == "number" and Players:GetPlayerByUserId(id) or nil
			local t = by and by.Character and by.Character:FindFirstChild("Torso")
			return (t and t:IsA("BasePart")) and t.Position or nil
		end)
	end,
	onUndrag = function(body, snap)
		DragClient.Stop(body, snap)
		CameraController.SetWatch(nil)
	end,
	onDragMove = function(payload)
		DragClient.Move(payload)
	end,
	onBoom = function(_pos: Vector3, shake: number)
		if shake > 0.05 then
			CameraController.Shake(shake)
		end
	end,
	onNukeWarn = function(n: number, pos: Vector3?)
		HUD.NukeWarn(n, pos)
	end,
	onSleep = function(d: number)
		if current and current.ready then
			current:Sleep(d)
		end
	end,
	onWake = function()
		if current then
			current:Wake()
		end
		HUD.Wake()
	end,
	onOther = Events.Dispatch,
})

-- (v2.0) things that happen to my body
Events.On("tased", function(payload)
	if current and current.ready then
		current:_tased(typeof(payload.d) == "number" and payload.d or 4)
	end
end)
Events.On("limb", function(payload)
	if current and current.ready and payload.body == player.Character and typeof(payload.key) == "string" then
		current:_rebindLimb(payload.key)
	end
end)

-- the Roblox reset button kills the ragdoll through the server
task.spawn(function()
	local bindable = Instance.new("BindableEvent")
	bindable.Event:Connect(function()
		ResetRemote:FireServer()
	end)
	for _ = 1, 30 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", bindable)
		end)
		if ok then
			break
		end
		task.wait(1)
	end
end)

-- (v2.8.2) a black sleep screen never outlives the sleep, whatever kept the "awake" from coming
task.spawn(function()
	local since: number? = nil
	while true do
		task.wait(0.5)
		if HUD.IsSleeping() and current and not current:IsAsleep() then
			since = since or os.clock()
			if os.clock() - (since :: number) > 1.5 then
				HUD.Wake()
				since = nil
			end
		else
			since = nil
		end
	end
end)

local function onCharacter(character: Model)
	if current then
		current:Destroy()
		current = nil
	end
	current = CharacterController.new(character)
	current.onLocalShot = BloodFX.LocalShot
	current.onBoombox = HUD.OpenBoombox
	current.onSleep = HUD.Sleep
	current.onWake = HUD.Wake
	current.onLiftPad = HUD.ShowLift
	current.onDrown = HUD.SetDrown
	current.onBubbles = BloodFX.Bubbles
	-- (v2.8.2) REGROWTH: this body was laid out the way the old one lay - it gets up from there
	if character:GetAttribute("RegrowGetUp") then
		local c = current
		task.delay(0.25, function()
			if current == c and not c.dead then
				c:Ragdoll(1.4)
			end
		end)
	end
	HUD.Wake()
	HUD.ShowLift(nil)
	HUD.SetDrown(0)
	CameraController.SetWatch(nil)
	HUD.SetController(current)
	GrabOutline.SetController(current)
	LaserFX.SetController(current)
	ModeClient.SetController(current)
	VehicleClient.SetController(current)
	TutorialClient.SetController(current)
	GearHUD.SetController(current)
	SuperFX.SetController(current)
	SteelBallFX.SetController(current)
	QuestClient.SetController(current)
	CreatureFX.SetController(current)
	FreeCam.SetController(current)
	ToolFX.SetController(current)
	LedgerClient.SetController(current)
	CyberClient.SetController(current)
	ChipClient.SetController(current)
end

player.CharacterAdded:Connect(onCharacter)
if player.Character then
	onCharacter(player.Character)
end

task.spawn(function() require(script.Client:WaitForChild("JobsClient")).Init() end)

task.spawn(function() require(script.Client:WaitForChild("PsychosisClient")).Init() end)
