--!nonstrict
-- RewardService (v2.0): codes, skins, titles and play time - kept in a DataStore (Config.ProfileStoreName).
--   * codes (M > CODES): every update has its codes. A code gives a skin (Shared/Skins) or a title (Shared/Titles).
--     With every update the skin code of the update before is taken out and a new one with a NEW skin comes in;
--     what people already unlocked stays theirs.
--   * titles: from codes, from kills (the Tab list "Kills", Titles.KillSteps), from play time (Titles.HourSteps),
--     from the Steel Ball Master's questline, and DEV for the game's owner. The first title you get is equipped
--     at once; any other you equip in M > INVENTORY. Everybody sees the equipped one over your head (TitleClient).
--   * play time: counted while you are in the game, saved with the rest.
-- What the clients see: player attributes TitlesOwned ("og,kills_10"), Title (the equipped one), Skin_<id> = true,
-- PlayTime (seconds); "unlocked" / "redeemed" messages on the Reward remote.

local Players = game:GetService("Players")
local SaveGate = require(script.Parent:WaitForChild("SaveGate"))
local ProgressEpoch = require(script.Parent:WaitForChild("ProgressEpoch"))
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local Titles = require(Shared:WaitForChild("Titles"))
local Skins = require(Shared:WaitForChild("Skins"))

local RewardRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Reward") :: RemoteEvent

local RewardService = {}

-- THE CODES OF THIS UPDATE (written in lower case; what people type is lower-cased and trimmed).
-- Next update: take "update2" out, put the new update's code in with the new skin (Shared/Skins). "2.0" (the title
-- OG) goes too: OG is for whoever was there at 2.0.
RewardService.CODES = {
	-- (v2.9) the previous update's skin code is retired; the new one unlocks the NEON RIFLE
	["netrunner"] = { bundle = true },
	["chips"] = { bundle = true },
	["2.0"] = { title = "og" },
} :: { [string]: { skin: string?, title: string?, bundle: boolean? } }

type Profile = {
	codes: { [string]: boolean },
	skins: { [string]: boolean },
	titles: { [string]: boolean },
	title: string?,
	playtime: number,
	loaded: boolean,
	canSave: boolean,
	dirty: boolean,
	lastTick: number,
	lastRedeem: number,
}

local profiles: { [Player]: Profile } = {}
local store: DataStore? = nil
local storeWarned = false

local function warnStore(err: any)
	if not storeWarned then
		storeWarned = true
		warn("[Ragdoll] titles / skins / play time are not saved:", err, "(in Studio: Game Settings > Security > Enable Studio Access to API Services)")
	end
end

local function key(p: Player): string
	return ProgressEpoch.Key(p.UserId)
end

local function publish(p: Player)
	local prof = profiles[p]
	if not prof then
		return
	end
	p:SetAttribute("TitlesOwned", Titles.Encode(prof.titles))
	p:SetAttribute("Title", prof.title)
	for id in prof.skins do
		p:SetAttribute("Skin_" .. id, true)
	end
	p:SetAttribute("PlayTime", math.floor(prof.playtime))
end

-- a title for this player (false: they had it already)
function RewardService.GrantTitle(p: Player, id: string, silent: boolean?): boolean
	local prof = profiles[p]
	if not prof or not Titles.ById[id] or prof.titles[id] then
		return false
	end
	prof.titles[id] = true
	prof.dirty = true
	if not prof.title then
		prof.title = id -- (the first title is worn right away)
	end
	publish(p)
	if not silent then
		RewardRemote:FireClient(p, "unlocked", "title", id)
	end
	return true
end

-- (v2.1) a gift title taken back
function RewardService.RevokeTitle(p: Player, id: string)
	local prof = profiles[p]
	if not prof or not prof.titles[id] then
		return
	end
	prof.titles[id] = nil
	if prof.title == id then
		prof.title = nil
		for _, t in Titles.List do
			if prof.titles[t.id] then
				prof.title = t.id
				break
			end
		end
	end
	prof.dirty = true
	publish(p)
end

-- (v2.1) gift titles follow the gift store (AdminService sets the player attribute GiftTitle_<id>)
local function syncGiftTitles(p: Player)
	local prof = profiles[p]
	if not prof or not prof.loaded then
		return
	end
	for _, t in Titles.List do
		if t.source == "gift" then
			local has = p:GetAttribute("GiftTitle_" .. t.id) == true
			if has and not prof.titles[t.id] then
				RewardService.GrantTitle(p, t.id)
			elseif not has and prof.titles[t.id] then
				RewardService.RevokeTitle(p, t.id)
			end
		end
	end
end

function RewardService.GrantSkin(p: Player, id: string, silent: boolean?): boolean
	local prof = profiles[p]
	if not prof or not Skins.ById[id] or prof.skins[id] then
		return false
	end
	prof.skins[id] = true
	prof.dirty = true
	publish(p)
	if not silent then
		RewardRemote:FireClient(p, "unlocked", "skin", id)
	end
	return true
end

function RewardService.HasSkin(p: Player, id: string): boolean
	local prof = profiles[p]
	return (prof ~= nil and prof.skins[id] == true) or Items.IsOwner(p)
end

local function killsOf(p: Player): number
	local ls = p:FindFirstChild("leaderstats")
	local k = ls and ls:FindFirstChild("Kills")
	return (k and k:IsA("IntValue")) and k.Value or 0
end

-- kills, play time, the Spin, the owner: everything earned so far
local function checkAll(p: Player)
	local prof = profiles[p]
	if not prof or not prof.loaded then
		return
	end
	for _, id in Titles.Earned("kills", killsOf(p)) do
		RewardService.GrantTitle(p, id)
	end
	for _, id in Titles.Earned("playtime", prof.playtime / 3600) do
		RewardService.GrantTitle(p, id)
	end
	if p:GetAttribute("HasSpin") == true then
		RewardService.GrantTitle(p, "spin")
	end
	if p:GetAttribute("HasStillCut") == true then
		RewardService.GrantTitle(p, "stillwater") -- (v2.8)
	end
	if Items.IsGameOwner(p) then
		RewardService.GrantTitle(p, "dev", true)
	end
end

------------------------------------------------------------------------
-- saving
------------------------------------------------------------------------

local function list(set: { [string]: boolean }): { string }
	local out = {}
	for id, on in set do
		if on then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

local function merge(set: { [string]: boolean }, saved: any)
	if typeof(saved) == "table" then
		for _, id in saved do
			if typeof(id) == "string" and #id <= 40 then
				set[id] = true
			end
		end
	end
end

local function load(p: Player)
	local prof = profiles[p]
	if not prof then
		return
	end
	if store and p.UserId > 0 then
		for attempt = 1, 3 do
			local ok, data = pcall(function()
				return (store :: DataStore):GetAsync(key(p))
			end)
			if ok then
				if typeof(data) == "table" then
					merge(prof.codes, data.c)
					merge(prof.skins, data.s)
					merge(prof.titles, data.t)
					if typeof(data.e) == "string" and prof.titles[data.e] then
						prof.title = data.e
					end
					if typeof(data.pt) == "number" and data.pt == data.pt then
						prof.playtime += math.max(0, data.pt)
					end
				end
				prof.canSave = true
				break
			end
			warnStore(data)
			task.wait(attempt * 2)
		end
	end
	if profiles[p] ~= prof then
		return -- (left meanwhile)
	end
	prof.loaded = true
	-- (clean up: titles / skins that no longer exist)
	for id in prof.titles do
		if not Titles.ById[id] then
			prof.titles[id] = nil
		end
	end
	if prof.title and not prof.titles[prof.title] then
		prof.title = nil
	end
	publish(p)
	checkAll(p)
end

local function save(p: Player)
	if not SaveGate.CanSave() then
		return -- (v2.8) a private server saves nothing
	end
	local prof = profiles[p]
	if not prof or not prof.canSave or not prof.dirty or not store then
		return
	end
	prof.dirty = false
	local codes, skins, titles = list(prof.codes), list(prof.skins), list(prof.titles)
	-- (v2.1) gift titles are never saved here (the union below would bring a taken-back one back): the gift store owns them
	do
		local keep = {}
		for _, id in titles do
			local t = Titles.ById[id]
			if t and t.source ~= "gift" then
				table.insert(keep, id)
			end
		end
		titles = keep
	end
	local equipped, playtime = prof.title, math.floor(prof.playtime)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			-- (another server may have saved meanwhile: keep the union of both)
			local new = { v = 1, c = {}, s = {}, t = {}, e = equipped, pt = playtime }
			local sets = { c = {}, s = {}, t = {} }
			for _, k in { "c", "s", "t" } do
				if typeof(old) == "table" then
					merge(sets[k], old[k])
				end
			end
			merge(sets.c, codes)
			merge(sets.s, skins)
			merge(sets.t, titles)
			for id in sets.t do
				local t = Titles.ById[id]
				if t and t.source == "gift" then
					sets.t[id] = nil
				end
			end
			new.c, new.s, new.t = list(sets.c), list(sets.s), list(sets.t)
			if typeof(old) == "table" and typeof(old.pt) == "number" then
				new.pt = math.max(new.pt, old.pt)
			end
			return new
		end)
	end)
	if not ok then
		prof.dirty = true
		warnStore(err)
	end
end

------------------------------------------------------------------------
-- codes, equipping
------------------------------------------------------------------------

local function trim(s: string): string
	return (string.gsub(s, "^%s*(.-)%s*$", "%1"))
end

local function redeem(p: Player, text: any)
	local prof = profiles[p]
	if not prof or typeof(text) ~= "string" then
		return
	end
	local now = os.clock()
	if now - prof.lastRedeem < 1.2 then
		return
	end
	prof.lastRedeem = now
	local code = string.lower(trim(string.sub(text, 1, 40)))
	if not prof.loaded then
		RewardRemote:FireClient(p, "redeemed", false, "Your data is still loading - try again in a moment.")
		return
	end
	local def = RewardService.CODES[code]
	if code == "" or not def then
		RewardRemote:FireClient(p, "redeemed", false, "That code does not exist - or it expired.")
		return
	end
	if def.bundle then
		local ok, msg = require(script.Parent:WaitForChild("SkinService")).RedeemBundle(p, code)
		RewardRemote:FireClient(p, "redeemed", ok, msg)
		return
	end
	if prof.codes[code] then
		RewardRemote:FireClient(p, "redeemed", false, "You already redeemed this code.")
		return
	end
	prof.codes[code] = true
	prof.dirty = true
	local msg = "Code redeemed!"
	if def.skin then
		RewardService.GrantSkin(p, def.skin)
		local s = Skins.ById[def.skin]
		msg = string.format("%s unlocked! Spawn it: T > WEAPONS", string.upper(s and s.name or def.skin))
	end
	if def.title then
		RewardService.GrantTitle(p, def.title)
		local t = Titles.ById[def.title]
		msg = string.format("Title %s unlocked! Equip it: M > INVENTORY", t and t.name or def.title)
	end
	RewardRemote:FireClient(p, "redeemed", true, msg)
	task.spawn(save, p)
end

local function equip(p: Player, id: any)
	local prof = profiles[p]
	if not prof or not prof.loaded or typeof(id) ~= "string" then
		return
	end
	if id == "" then
		prof.title = nil
	elseif prof.titles[id] then
		prof.title = id
	else
		return
	end
	prof.dirty = true
	publish(p)
end

------------------------------------------------------------------------

local function added(p: Player)
	if profiles[p] then
		return
	end
	profiles[p] = {
		codes = {},
		skins = {},
		titles = {},
		title = nil,
		playtime = 0,
		loaded = false,
		canSave = false,
		dirty = false,
		lastTick = os.clock(),
		lastRedeem = 0,
	}
	-- kills: a new kill (or the saved total arriving) can earn a title
	task.spawn(function()
		local ls = p:WaitForChild("leaderstats", 30)
		local k = ls and ls:WaitForChild("Kills", 10)
		if k and k:IsA("IntValue") then
			k.Changed:Connect(function()
				local prof = profiles[p]
				if prof and prof.loaded then
					for _, id in Titles.Earned("kills", k.Value) do
						RewardService.GrantTitle(p, id)
					end
				end
			end)
		end
	end)
	-- (v2.1) gift titles (the owner's GIFTS page)
	for _, t in Titles.List do
		if t.source == "gift" then
			p:GetAttributeChangedSignal("GiftTitle_" .. t.id):Connect(function()
				syncGiftTitles(p)
			end)
		end
	end
	task.spawn(function()
		for _ = 1, 40 do
			task.wait(1.5)
			if not p.Parent then
				return
			end
			syncGiftTitles(p) -- (the saved profile / the saved gifts arrive in their own time)
		end
	end)
	-- the Spin (QuestService sets HasSpin)
	p:GetAttributeChangedSignal("HasSpin"):Connect(function()
		if p:GetAttribute("HasSpin") == true then
			RewardService.GrantTitle(p, "spin")
		end
	end)
	-- (v2.8) STILLWATER (SwordQuestService sets HasStillCut)
	p:GetAttributeChangedSignal("HasStillCut"):Connect(function()
		if p:GetAttribute("HasStillCut") == true then
			RewardService.GrantTitle(p, "stillwater")
		end
	end)
	task.spawn(load, p)
end

-- (v2.9) the admin "WIPE ALL PROGRESS": this player's codes, skins, titles and play time are cleared (and saved so)
function RewardService.Reset(p: Player)
	local prof = profiles[p]
	if not prof then
		return
	end
	-- the Skin_ attributes come off
	for id in prof.skins do
		p:SetAttribute("Skin_" .. id, nil)
	end
	prof.codes = {}
	prof.skins = {}
	prof.titles = {}
	prof.title = nil
	prof.playtime = 0
	prof.dirty = true
	publish(p)
	checkAll(p)
	task.spawn(save, p)
end

function RewardService.Init()
	local ok, result = pcall(function()
		return ProgressEpoch.Store(Config.ProfileStoreName)
	end)
	if ok then
		store = result
	else
		warnStore(result)
	end
	RewardRemote.OnServerEvent:Connect(function(p, action, a)
		if action == "redeem" then
			redeem(p, a)
		elseif action == "equip" then
			equip(p, a)
		end
	end)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerAdded:Connect(added)
	Players.PlayerRemoving:Connect(function(p)
		local prof = profiles[p]
		if prof then
			prof.playtime += os.clock() - prof.lastTick
			prof.lastTick = os.clock()
			prof.dirty = true
			save(p)
		end
		profiles[p] = nil
	end)
	-- play time: counted every 30 s (and the hour titles checked), saved every 2 minutes
	task.spawn(function()
		local sinceSave = 0
		while true do
			task.wait(30)
			sinceSave += 30
			local now = os.clock()
			for p, prof in profiles do
				if prof.loaded then
					prof.playtime += now - prof.lastTick
					prof.lastTick = now
					prof.dirty = true
					p:SetAttribute("PlayTime", math.floor(prof.playtime))
					for _, id in Titles.Earned("playtime", prof.playtime / 3600) do
						RewardService.GrantTitle(p, id)
					end
				else
					prof.lastTick = now
				end
			end
			if sinceSave >= 120 then
				sinceSave = 0
				for p in profiles do
					task.spawn(save, p)
				end
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		for p, prof in profiles do
			prof.playtime += os.clock() - prof.lastTick
			prof.lastTick = os.clock()
			prof.dirty = true
			task.spawn(save, p)
		end
		task.wait(2)
	end)
end

return RewardService
