--!nonstrict
-- VoteService (v1.9): the community can decide what the owner's menu normally decides.
--   * any player can suggest ONE thing every 10 minutes (the cooldown is for the whole server)
--   * the suggestions: spawn the city, start a game mode, spawn an armed nuke (it keeps its countdown)
--   * everybody votes yes / no for 20 seconds; with MORE than 60 % yes (of the votes cast) it happens
-- State for the clients lives in workspace attributes: VoteText, VoteEnds (server time), VoteYes, VoteNo, VoteBy,
-- VoteNext (when the next suggestion is allowed), VoteNotice + VoteNoticeId (a message for everybody).
-- (v2.0) vote kick: anybody can start a vote to kick a player (not the owner / an admin; needs 3+ players). Everybody
--   but that player votes; with MORE than 70 % yes (Config.VoteKickNeed, at least 2 yes) the player is kicked. It does
--   not use the 10 minute cooldown; each player can start one every Config.VoteKickCooldown seconds.
-- (v2.0) maps: "load the horror / sea / IKEA / valley / sky map / the city" are suggestions like the others.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VoteRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Vote") :: RemoteEvent
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))

local VoteService = {}
-- set by Main: city(), mode(name), nuke(position)
VoteService.Commands = {} :: { city: (() -> ())?, map: ((string) -> ())?, mode: ((string) -> ())?, nuke: ((Vector3) -> ())? }

local COOLDOWN = 600 -- s between suggestions (server wide)
local VOTE_TIME = 20
local NEED = 0.6 -- more than this share of yes

local KINDS = {
	city = "Load the CITY map?",
	map_horror = "Load the HORROR map?",
	map_sea = "Load the SEA map?",
	map_ikea = "Load the IKEA map?",
	map_valley = "Load DUST VALLEY?",
	map_sky = "Load the SKY ISLANDS?",
	monster = "Start MONSTER (everybody against the monster)?",
	zombies = "Start ZOMBIES?",
	gungame = "Start GUN GAME?",
	teamfight = "Start TEAM FIGHT?",
	ffa = "Start FREE FOR ALL?",
	hideseek = "Start HIDE AND SEEK?",
	sniper = "Start SNIPER TOWER (one sniper against everybody)?",
	hotpotato = "Start HOT POTATO?",
	koth = "Start KING OF THE HILL?",
	nuke = "Spawn an ARMED NUKE? (the countdown runs)",
}

type Vote = { kind: string, by: Player, ends: number, yes: { [Player]: boolean }, no: { [Player]: boolean }, id: number, target: Player?, text: string? }
local active: Vote? = nil
local nextAllowed = 0
local counter = 0
local noticeId = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function notice(text: string)
	noticeId += 1
	workspace:SetAttribute("VoteNotice", text)
	workspace:SetAttribute("VoteNoticeId", noticeId)
end

local function count(t: { [Player]: boolean }): number
	local n = 0
	for p in t do
		if p.Parent then
			n += 1
		end
	end
	return n
end

local function publish()
	local v = active
	if v then
		workspace:SetAttribute("VoteText", v.text or KINDS[v.kind])
		workspace:SetAttribute("VoteTarget", v.target and v.target.UserId or nil)
		workspace:SetAttribute("VoteEnds", v.ends)
		workspace:SetAttribute("VoteYes", count(v.yes))
		workspace:SetAttribute("VoteNo", count(v.no))
		workspace:SetAttribute("VoteBy", v.by.DisplayName)
	else
		workspace:SetAttribute("VoteText", nil)
		workspace:SetAttribute("VoteTarget", nil)
		workspace:SetAttribute("VoteEnds", nil)
		workspace:SetAttribute("VoteYes", nil)
		workspace:SetAttribute("VoteNo", nil)
		workspace:SetAttribute("VoteBy", nil)
	end
	workspace:SetAttribute("VoteNext", nextAllowed)
end

local function centre(): Vector3
	local sum, n = Vector3.zero, 0
	for _, p in Players:GetPlayers() do
		local c = p.Character
		local t = c and c:FindFirstChild("Torso")
		if t and t:IsA("BasePart") and not c:GetAttribute("Dead") then
			sum += t.Position
			n += 1
		end
	end
	if n == 0 then
		return Vector3.new(0, 6, 0)
	end
	return sum / n + Vector3.new(0, 4, 0)
end

local function execute(kind: string)
	local c = VoteService.Commands
	if kind == "city" then
		if c.map then
			c.map("city")
		elseif c.city then
			c.city()
		end
	elseif string.sub(kind, 1, 4) == "map_" then
		if c.map then
			c.map(string.sub(kind, 5))
		end
	elseif kind == "nuke" then
		if c.nuke then
			c.nuke(centre())
		end
	elseif c.mode then
		c.mode(kind)
	end
end

local function finish(v: Vote)
	if active ~= v then
		return
	end
	local yes, no = count(v.yes), count(v.no)
	local total = yes + no
	local share = total > 0 and yes / total or 0
	active = nil
	publish()
	if v.kind == "kick" then
		local target = v.target
		if target and target.Parent and total > 0 and share > Config.VoteKickNeed and yes >= 2 then
			notice(string.format("VOTE KICK PASSED  -  %s is kicked (%d%% yes)", target.DisplayName, math.floor(share * 100 + 0.5)))
			target:Kick(string.format("You were vote-kicked from the server (%d%% yes).", math.floor(share * 100 + 0.5)))
		else
			notice(string.format("VOTE KICK FAILED  -  %d%% yes, more than %d%% needed", math.floor(share * 100 + 0.5), Config.VoteKickNeed * 100))
		end
		return
	end
	if total > 0 and share > NEED then
		notice(string.format("VOTE PASSED  -  %d%% yes (%d / %d)", math.floor(share * 100 + 0.5), yes, total))
		local ok, err = pcall(execute, v.kind)
		if not ok then
			warn("vote command failed:", err)
		end
	else
		notice(string.format("VOTE FAILED  -  %d%% yes (%d / %d), more than %d%% needed", math.floor(share * 100 + 0.5), yes, total, NEED * 100))
	end
end

local function propose(player: Player, kind: string)
	if not KINDS[kind] then
		return
	end
	if active then
		return
	end
	if now() < nextAllowed then
		return
	end
	-- no point in voting for what already is
	local mapId = kind == "city" and "city" or (string.sub(kind, 1, 4) == "map_" and string.sub(kind, 5) or nil)
	if mapId and workspace:GetAttribute("MapLoaded") == mapId then
		return
	end
	counter += 1
	local v: Vote = { kind = kind, by = player, ends = now() + VOTE_TIME, yes = { [player] = true }, no = {}, id = counter }
	active = v
	nextAllowed = now() + COOLDOWN
	notice(player.DisplayName .. " suggests: " .. KINDS[kind])
	publish()
	task.delay(VOTE_TIME, function()
		finish(v)
	end)
end

local lastKickVote: { [Player]: number } = {}

local function proposeKick(player: Player, userId: number)
	if active then
		return
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player or Items.Unkickable(target) or target:GetAttribute("Admin") then
		return
	end
	if #Players:GetPlayers() < 3 then
		notice("A vote kick needs at least 3 players in the server")
		return
	end
	if os.clock() - (lastKickVote[player] or -1e9) < Config.VoteKickCooldown then
		return
	end
	lastKickVote[player] = os.clock()
	counter += 1
	local v: Vote = {
		kind = "kick",
		by = player,
		ends = now() + VOTE_TIME,
		yes = { [player] = true },
		no = {},
		id = counter,
		target = target,
		text = "KICK " .. string.upper(target.DisplayName) .. " from the server?",
	}
	active = v
	notice(player.DisplayName .. " started a vote to kick " .. target.DisplayName)
	publish()
	task.delay(VOTE_TIME, function()
		finish(v)
	end)
end

local function cast(player: Player, yes: boolean)
	local v = active
	if not v or now() > v.ends then
		return
	end
	if v.target == player then
		return -- (the one it is about does not vote)
	end
	v.yes[player] = yes or nil
	v.no[player] = (not yes) or nil
	publish()
end

function VoteService.Init()
	VoteRemote.OnServerEvent:Connect(function(player, action, value)
		if action == "propose" and typeof(value) == "string" then
			propose(player, value)
		elseif action == "kick" and typeof(value) == "number" then
			proposeKick(player, value)
		elseif action == "vote" and typeof(value) == "boolean" then
			cast(player, value)
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		lastKickVote[p] = nil
		local v = active
		if v then
			v.yes[p] = nil
			v.no[p] = nil
			if v.target == p then
				active = nil -- (they left on their own)
			end
			publish()
		end
	end)
	publish()
end

return VoteService
