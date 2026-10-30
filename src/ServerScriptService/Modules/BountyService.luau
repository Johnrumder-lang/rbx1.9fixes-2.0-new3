--!nonstrict
-- BountyService (v2.8): BOUNTIES. Put money on somebody's head (M > BOUNTY): whoever kills them gets it.
--   * a bounty only grows: more money from anybody adds up. It is paid out (and gone) when the one with it dies by
--     somebody else's hand.
--   * a kill streak puts a bounty on you by itself: 5 kills in one life = $100, every kill after that +$50.
--   * the amount shows over the head of whoever has one (player attribute Bounty). Not saved: it is for this server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))

local BountyService = {}

local deps: any = {}
local Remote: RemoteEvent
local streak: { [Player]: number } = {}

local function bountyOf(p: Player): number
	local b = p:GetAttribute("Bounty")
	return typeof(b) == "number" and b or 0
end

local function setBounty(p: Player, n: number)
	p:SetAttribute("Bounty", n > 0 and math.floor(n) or nil)
end

local function announce(text: string)
	Remote:FireAllClients("news", text)
end

local function place(by: Player, targetId: any, amount: any)
	if typeof(targetId) ~= "number" or typeof(amount) ~= "number" or amount ~= amount then
		return
	end
	local target = Players:GetPlayerByUserId(targetId)
	amount = math.floor(amount)
	if not target or target == by or amount < Config.BountyMin or amount > Config.BountyMax then
		return
	end
	local prof = deps.Persist.Get(by)
	if not Items.IsOwner(by) then
		if not prof or prof.cash < amount then
			Remote:FireClient(by, "msg", string.format("YOU NEED $%d.", amount))
			return
		end
		deps.SkinService.AddCash(by, -amount, "bounty")
	end
	setBounty(target, bountyOf(target) + amount)
	announce(string.format("%s PUT $%d ON %s. TOTAL: $%d", string.upper(by.DisplayName), amount, string.upper(target.DisplayName), bountyOf(target)))
end

local function onKill(victim: Model, killer: Player?)
	local vp = Players:GetPlayerFromCharacter(victim)
	if vp then
		streak[vp] = 0
	end
	if not killer or not killer.Parent or killer == vp then
		return
	end
	if vp then
		-- the bounty on the dead one is paid
		local b = bountyOf(vp)
		if b > 0 then
			setBounty(vp, 0)
			deps.SkinService.AddCash(killer, b, "bounty")
			announce(string.format("%s COLLECTED THE $%d BOUNTY ON %s", string.upper(killer.DisplayName), b, string.upper(vp.DisplayName)))
		end
		-- the killer's streak
		local n = (streak[killer] or 0) + 1
		streak[killer] = n
		if n == Config.BountyStreak then
			setBounty(killer, bountyOf(killer) + Config.BountyStreakStart)
			announce(string.format("%s IS ON A %d KILL STREAK: $%d ON THEIR HEAD", string.upper(killer.DisplayName), n, bountyOf(killer)))
		elseif n > Config.BountyStreak then
			setBounty(killer, bountyOf(killer) + Config.BountyStreakStep)
			if n % 5 == 0 then
				announce(string.format("%s: %d KILLS IN A ROW. BOUNTY $%d", string.upper(killer.DisplayName), n, bountyOf(killer)))
			end
		end
	end
end

function BountyService.Init(d: any)
	deps = d
	Remote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Bounty") :: RemoteEvent
	Remote.OnServerEvent:Connect(function(p, action, a, b)
		if action == "place" then
			place(p, a, b)
		end
	end)
	local prev = deps.DamageService.OnKill
	deps.DamageService.OnKill = function(model: Model, killer: Player?, state: any)
		if prev then
			prev(model, killer, state)
		end
		pcall(onKill, model, killer)
	end
	Players.PlayerRemoving:Connect(function(p)
		streak[p] = nil
	end)
end

return BountyService
