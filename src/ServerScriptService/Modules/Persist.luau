--!nonstrict
-- Persist (v2.1): what a player keeps between sessions besides RewardService's titles - dollars, owned / equipped weapon skins,
-- the Black Ledger quest (kills are per life, but the apples fed and the permanent unlock are saved).
-- DataStore Config.ProfileStoreV2, key "p_<userId>". Without Studio API access everything still works for the session.

local Players = game:GetService("Players")
local SaveGate = require(script.Parent:WaitForChild("SaveGate"))
local ProgressEpoch = require(script.Parent:WaitForChild("ProgressEpoch"))
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Persist = {}

export type Profile = {
	community: any, -- versioned clans + daily rewards, committed atomically with cash/skins
	jobsCompleted: number,
	jobActive: boolean,
	jobFailedUntil: number,
	cash: number,
	owned: { [string]: boolean },
	equipped: { [string]: string },
	ledgerUnlocked: boolean,
	ledgerApples: number,
	cyber: { [string]: number }, -- (v2.8) implants: key ("optics", "titan_L") -> tier
	look: { [string]: string }, -- (v2.8) how they look / are set: "titan_L" -> "finish:model", "howler" -> "shell:color"
	sword: number, -- (v2.8) the STILLWATER quest: 0 not begun, 1..3 the quest that runs, 4 done (SwordQuestService)
	swordProg: number, -- (v2.8) blade kills for quest 1 (they add up)
	codes: { [string]: boolean },
	chips: { any }, -- (v2.9) the cyberdeck chips: { {id, tier, slot, payload, target}, ... } (ChipService; videos excluded)
	loaded: boolean,
	canSave: boolean,
	dirty: boolean,
}

local store: DataStore? = nil
local profiles: { [Player]: Profile } = {}
local waiting: { [Player]: { (Profile) -> () } } = {}
-- fired once a profile is loaded: (player, profile)
Persist.OnLoaded = nil :: ((Player, Profile) -> ())?

local function key(p: Player): string
	return ProgressEpoch.Key(p.UserId)
end

local function copy(value)
	if typeof(value) ~= "table" then return value end
	local result = {}
	for k, v in value do result[k] = copy(v) end
	return result
end
local function community(prof)
	return copy(prof.community or { rev = 0, daily = { date = -1, step = 0, cases = {} } })
end
local function encode(prof: Profile): any
	local owned = {}
	for id in prof.owned do
		table.insert(owned, id)
	end
	table.sort(owned)
	local eq = {}
	for k, v in prof.equipped do
		eq[k] = v
	end
	local cy, lk = {}, {}
	for k, t in prof.cyber do
		cy[k] = t
	end
	for k, v in prof.look do
		lk[k] = v
	end
	local chips = {}
	for _, rec in prof.chips or {} do
		if typeof(rec) == "table" and typeof(rec.id) == "string" then
			table.insert(chips, { id = rec.id, tier = rec.tier, slot = rec.slot, payload = rec.payload, target = rec.target })
		end
	end
	return { v = 1, community = community(prof), jobActive = prof.jobActive == true, jobFailedUntil = prof.jobFailedUntil or 0, jobs = prof.jobsCompleted or 0, cash = math.floor(prof.cash), owned = owned, eq = eq, lu = prof.ledgerUnlocked, la = prof.ledgerApples, cy = cy, lk = lk,
		sw = prof.sword, sp = prof.swordProg, ch = chips, codes = table.clone(prof.codes or {}) }
end

function Persist.Get(p: Player): Profile?
	return profiles[p]
end

-- the profile, once it is loaded (waits up to 'timeout' seconds)
function Persist.Wait(p: Player, timeout: number?): Profile?
	local t0 = os.clock()
	while p.Parent and (not profiles[p] or not profiles[p].loaded) and os.clock() - t0 < (timeout or 20) do
		task.wait(0.2)
	end
	local prof = profiles[p]
	return (prof and prof.loaded) and prof or nil
end

function Persist.Dirty(p: Player)
	local prof = profiles[p]
	if prof then
		prof.dirty = true
	end
end

local saving = {}
local function save(p: Player)
	if not SaveGate.CanSave() then
		return -- (v2.8) a private server saves nothing
	end
	local prof = profiles[p]
	if not prof or not prof.canSave or not prof.dirty or not store then
		return
	end
	if saving[p] then return end
	saving[p] = true
	prof.dirty = false
	local data = encode(prof)
	local ok, err = pcall(function()
		(store :: DataStore):UpdateAsync(key(p), function(old)
			if typeof(old) == "table" then
				if old.community and (old.community.rev or 0) > (data.community.rev or 0) then return nil end
				-- Keep redemption receipts when older autosaves race a code claim.
				for id in old.codes or {} do data.codes[id] = true end
				-- another server may have saved meanwhile: skins and ledger progress only ever grow
				local merged = {}
				for _, id in old.owned or {} do
					if typeof(id) == "string" then
						merged[id] = true
					end
				end
				for _, id in data.owned do
					merged[id] = true
				end
				data.owned = {}
				for id in merged do
					table.insert(data.owned, id)
				end
				table.sort(data.owned)
				data.lu = data.lu or old.lu == true
				data.la = math.max(data.la, typeof(old.la) == "number" and old.la or 0)
			end
			return data
		end)
	end)
	saving[p] = nil
	if not ok then
		prof.dirty = true
		warn("[Ragdoll] saving the profile failed:", err)
	end
end

-- (v2.8) something bought with Robux is written down at once, on EVERY server (a private one too, where nothing else is
-- saved): only this one owned id is added to what is stored, nothing else changes
function Persist.SavePurchase(p: Player, ownedId: string)
	if not store or p.UserId <= 0 then
		return
	end
	task.spawn(function()
		for attempt = 1, 3 do
			local ok = pcall(function()
				(store :: DataStore):UpdateAsync(key(p), function(old)
					local data = typeof(old) == "table" and old or { v = 1, jobsCompleted = 0, cash = 0, owned = {}, eq = {} }
					data.owned = typeof(data.owned) == "table" and data.owned or {}
					if not table.find(data.owned, ownedId) then
						table.insert(data.owned, ownedId)
					end
					return data
				end)
			end)
			if ok then
				return
			end
			task.wait(attempt * 2)
		end
	end)
end

-- Called with server-generated rewards only. The receipt and all rewards commit together.
function Persist.ClaimCode(p: Player, code: string, cash: number, skinIds: { string }): (boolean, string)
	local prof = profiles[p]
	if not prof or not prof.loaded then return false, "Your profile is still loading." end
	if prof.codes[code] then return false, "You already redeemed this code." end
	if not SaveGate.CanSave() and not game:GetService("RunService"):IsStudio() then return false, "Redeem codes in a public server so rewards can be saved." end
	if saving[p] then return false, "Your profile is saving; try again in a moment." end
	if not game:GetService("RunService"):IsStudio() and (not store or not prof.canSave) then return false, "Saving is unavailable. Try again later." end
	saving[p] = true
	local data = encode(prof)
	data.codes[code] = true
	data.cash += cash
	for _, id in skinIds do if not table.find(data.owned, id) then table.insert(data.owned, id) end end
	local claimed, ok, stale = false, true, false
	if store and prof.canSave and SaveGate.CanSave() then
		ok = pcall(function()
			store:UpdateAsync(key(p), function(old)
				claimed = false
				if typeof(old) == "table" and typeof(old.codes) == "table" and old.codes[code] then return nil end
				if typeof(old) == "table" then
					if old.community and (old.community.rev or 0) > (data.community.rev or 0) then stale = true; return nil end
					for id in old.codes or {} do data.codes[id] = true end
					for _, id in old.owned or {} do if not table.find(data.owned, id) then table.insert(data.owned, id) end end
				end
				claimed = true
				return data
			end)
		end)
	else
		claimed = true -- Studio / private session: follows the existing save policy.
	end
	saving[p] = nil
	if not ok then return false, "Could not save the code reward. Try again." end
	if stale then return false, "Progress changed in another session. Rejoin to synchronize." end
	if not claimed then prof.codes[code] = true; return false, "You already redeemed this code." end
	prof.codes[code] = true
	prof.cash += cash
	for _, id in skinIds do prof.owned[id] = true end
	prof.dirty = true
	return true, "Reward received."
end

-- Only server services call this. A single receipt/revision commits rewards or clan costs
-- with the profile. Duplicate callbacks, concurrent sessions and stale autosaves cannot
-- replay a daily claim or restore a consumed implant voucher / old clan membership.
function Persist.Community(p: Player)
	local prof = profiles[p]
	return prof and prof.loaded and community(prof)
end
function Persist.CommitCommunity(p: Player, change, reserve: number?): (boolean, string)
	local prof = profiles[p]
	if not prof or not prof.loaded then return false, "Your profile is still loading." end
	local studio = game:GetService("RunService"):IsStudio()
	if not studio and (not SaveGate.CanSave() or not store or not prof.canSave) then return false, "Use a public server with saving available." end
	if saving[p] then return false, "Your profile is saving; try again shortly." end
	reserve = reserve or 0
	if prof.cash < reserve then return false, "You need $" .. reserve .. "." end
	-- Hold the cost before the first yield so other shops cannot spend it meanwhile.
	prof.cash -= reserve
	p:SetAttribute("Cash", math.floor(prof.cash))
	saving[p] = true
	local snapshot = encode(prof)
	local expected = snapshot.community.rev or 0
	local result, reason, latest = nil, "Could not save. Please retry.", nil
	local function transform(old)
		result = nil
		local prior = typeof(old) == "table" and old or {}
		latest = prior.community
		if latest and (latest.rev or 0) ~= expected then reason = "Progress changed in another session. Rejoin to synchronize."; return nil end
		local data = copy(snapshot)
		for id in prior.codes or {} do data.codes[id] = true end
		for _, id in prior.owned or {} do if not table.find(data.owned, id) then table.insert(data.owned, id) end end
		local accepted, message = change(data.community, data)
		if not accepted then reason = message or "Request rejected."; return nil end
		data.community.rev = expected + 1
		result = data; reason = message or "Saved."
		return data
	end
	local ok = pcall(function()
		if store and prof.canSave and SaveGate.CanSave() then store:UpdateAsync(key(p), transform)
		else transform(nil) end
	end)
	saving[p] = nil
	if not ok or not result then
		prof.cash += reserve
		p:SetAttribute("Cash", math.floor(prof.cash))
		return false, ok and reason or "Saving failed. Nothing was claimed or charged."
	end
	prof.community = result.community
	prof.cash += result.cash - snapshot.cash
	for _, id in result.owned do prof.owned[id] = true end
	prof.dirty = true
	p:SetAttribute("Cash", math.floor(prof.cash))
	return true, reason
end

function Persist.SaveNow(p: Player)
	task.spawn(save, p)
end

local function load(p: Player)
	local prof: Profile = {
		jobsCompleted = 0, jobActive = false, jobFailedUntil = 0, cash = 0, owned = {}, equipped = {}, ledgerUnlocked = false, ledgerApples = 0, cyber = {}, look = {}, sword = 0, swordProg = 0,
		chips = {}, codes = {}, community = { rev = 0, daily = { date = -1, step = 0, cases = {} } },
		loaded = false, canSave = false, dirty = false,
	}
	profiles[p] = prof
	if store and p.UserId > 0 then
		for attempt = 1, 3 do
			local ok, data = pcall(function()
				return (store :: DataStore):GetAsync(key(p))
			end)
			if ok then
				if typeof(data) == "table" then
					prof.jobsCompleted = typeof(data.jobs) == "number" and math.clamp(math.floor(data.jobs), 0, 1000000) or 0
					prof.jobActive = data.jobActive == true
					prof.jobFailedUntil = typeof(data.jobFailedUntil) == "number" and math.clamp(data.jobFailedUntil, 0, os.time() + 180) or 0
					if typeof(data.community) == "table" then prof.community = data.community end
					prof.codes = typeof(data.codes) == "table" and data.codes or {}
					prof.cash = typeof(data.cash) == "number" and math.max(0, data.cash) or 0
					for _, id in data.owned or {} do
						if typeof(id) == "string" and #id < 40 then
							prof.owned[id] = true
						end
					end
					for k, v in data.eq or {} do
						if typeof(k) == "string" and typeof(v) == "string" then
							prof.equipped[k] = v
						end
					end
					prof.ledgerUnlocked = data.lu == true
					prof.ledgerApples = typeof(data.la) == "number" and math.clamp(math.floor(data.la), 0, 999) or 0
					-- (v2.8) implants, their looks, the sword quest
					if typeof(data.cy) == "table" then
						for k, t in data.cy do
							if typeof(k) == "string" and #k < 24 and typeof(t) == "number" then
								prof.cyber[k] = math.clamp(math.floor(t), 1, 3)
							end
						end
					end
					if typeof(data.lk) == "table" then
						for k, v in data.lk do
							if typeof(k) == "string" and #k < 24 and typeof(v) == "string" and #v < 40 then
								prof.look[k] = v
							end
						end
					end
					prof.sword = typeof(data.sw) == "number" and math.clamp(math.floor(data.sw), 0, 4) or 0
					prof.swordProg = typeof(data.sp) == "number" and math.clamp(math.floor(data.sp), 0, 999) or 0
					if typeof(data.ch) == "table" then
						for _, rec in data.ch do
							if typeof(rec) == "table" and typeof(rec.id) == "string" and #rec.id < 24 then
								table.insert(prof.chips, { id = rec.id, tier = typeof(rec.tier) == "number" and rec.tier or 1, slot = rec.slot, payload = rec.payload, target = rec.target })
							end
						end
					end
				end
				prof.canSave = true
				break
			end
			warn("[Ragdoll] loading the profile failed:", data)
			task.wait(attempt * 2)
		end
	else
		prof.canSave = false -- (Studio without API access / a guest: the profile lives for this session only)
	end
	if profiles[p] ~= prof then
		return
	end
	prof.loaded = true
	if Persist.OnLoaded then
		task.spawn(Persist.OnLoaded, p, prof)
	end
end

-- (v2.9) the admin "WIPE ALL PROGRESS": dollars, skins, cyberware, the sword quest and chips are cleared and saved gone
function Persist.Reset(p: Player)
	local prof = profiles[p]
	if not prof then
		return
	end
	prof.cash = 0
	prof.owned = {}
	prof.equipped = {}
	prof.ledgerUnlocked = false
	prof.ledgerApples = 0
	prof.cyber = {}
	prof.look = {}
	prof.sword = 0
	prof.swordProg = 0
	prof.chips = {}
	prof.codes = {}
	prof.community = { rev = 0, daily = { date = -1, step = 0, cases = {} } }
	prof.dirty = true
	p:SetAttribute("Cash", 0)
	p:SetAttribute("SkinsOwned", "")
	p:SetAttribute("LedgerUnlocked", nil)
	task.spawn(save, p)
end

function Persist.Init()
	local ok, result = pcall(function()
		return ProgressEpoch.Store(Config.ProfileStoreV2)
	end)
	if ok then
		store = result
	end
	local function added(p: Player)
		if not profiles[p] then
			task.spawn(load, p)
		end
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		save(p)
		profiles[p] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(45)
			for _, p in Players:GetPlayers() do
				save(p)
			end
		end
	end)
	game:BindToClose(function()
		for _, p in Players:GetPlayers() do
			task.spawn(save, p)
		end
		task.wait(2)
	end)
end

return Persist
