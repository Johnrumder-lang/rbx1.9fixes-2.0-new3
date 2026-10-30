--!nonstrict
-- SkinService (v2.1d): money + weapon skins (colour and material only - see Shared/WeaponSkins).
--   * Config.KillCash dollars for every kill (player / bot / NPC; a dummy pays nothing)
--   * a RANDOM skin: Config.RandomSkinCost dollars, or Config.RandomSkinRobux Robux (Config.RandomSkinProductId). The odds are FIXED
--     (WeaponSkins.OddsTable, shown in the inventory); a skin you already own pays WeaponSkins.DupeCash back in dollars
--   * a skin of your choice: Config.SkinRobux Robux (Config.SkinProductId): the game remembers which skin was picked
--   * an equipped skin is painted onto the weapon when you pick it up
-- Player attributes (for the UI): Cash, SkinsOwned ("id,id,..."), Eq_<weapon> = skin id

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))
local WeaponSkins = require(Shared:WaitForChild("WeaponSkins"))
local Persist = require(script.Parent:WaitForChild("Persist"))

local SkinService = {}

local ShopRemote: RemoteEvent
local pending: { [number]: string } = {} -- user id -> the skin he picked for the Robux purchase
local lastKillOf: { [Player]: { [Instance]: number } } = {}
local rng = Random.new()

------------------------------------------------------------------------
-- profile <-> attributes
------------------------------------------------------------------------

local function publish(p: Player)
	local prof = Persist.Get(p)
	if not prof then
		return
	end
	p:SetAttribute("Cash", math.floor(prof.cash))
	local ids = {}
	for id in prof.owned do
		table.insert(ids, id)
	end
	table.sort(ids)
	p:SetAttribute("SkinsOwned", table.concat(ids, ","))
	for _, kind in WeaponSkins.Kinds do
		p:SetAttribute("Eq_" .. kind, prof.equipped[kind])
	end
end

local function say(p: Player, text: string, good: boolean?)
	ShopRemote:FireClient(p, "msg", text, good == true)
end

-- may this player wear this skin? (the owner / admins can try every one)
local function canUse(p: Player, id: string): boolean
	local prof = Persist.Get(p)
	return prof ~= nil and WeaponSkins.ById[id] ~= nil and (prof.owned[id] == true or Items.IsOwner(p))
end

------------------------------------------------------------------------
-- painting a weapon: colour + material, nothing else
------------------------------------------------------------------------

local originals: { [Model]: { [BasePart]: { Color: Color3, Material: Enum.Material, Reflectance: number } } } = setmetatable({}, { __mode = "k" }) :: any

local function clear(item: Model)
	local rec = originals[item]
	if not rec then
		return
	end
	originals[item] = nil
	for part, o in rec do
		if part.Parent then
			part.Color = o.Color
			part.Material = o.Material
			part.Reflectance = o.Reflectance
		end
	end
	item:SetAttribute("WSkin", nil)
end

function SkinService.Apply(item: Model, skin: WeaponSkins.Skin?)
	clear(item)
	if not skin or not item.Parent then
		return
	end
	local rec = {}
	originals[item] = rec
	item:SetAttribute("WSkin", skin.id)
	for _, d in item:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.9 and d.Material ~= Enum.Material.Neon and d.Material ~= Enum.Material.ForceField and d.Material ~= Enum.Material.Glass then
			rec[d] = { Color = d.Color, Material = d.Material, Reflectance = d.Reflectance }
			local c = d.Color
			local lum = c.R * 0.3 + c.G * 0.59 + c.B * 0.11
			local color, material, refl = WeaponSkins.Paint(skin.look, lum)
			d.Color = color
			d.Material = material
			d.Reflectance = refl
		end
	end
end

-- the skin this player wears on this weapon (or nil)
local function skinFor(p: Player, kind: string): WeaponSkins.Skin?
	local prof = Persist.Get(p)
	local id = prof and prof.equipped[kind]
	if id and canUse(p, id) then
		return WeaponSkins.ById[id]
	end
	return nil
end

local watched: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function watchItem(m: Model)
	if watched[m] then
		return
	end
	local kind = m:GetAttribute("Item")
	if typeof(kind) ~= "string" or not WeaponSkins.OfKind[kind] then
		return
	end
	watched[m] = true
	m:GetAttributeChangedSignal("HolderId"):Connect(function()
		local uid = m:GetAttribute("HolderId")
		if typeof(uid) ~= "number" then
			return -- (put down: it keeps its look)
		end
		local p = Players:GetPlayerByUserId(uid)
		if not p or m:GetAttribute("Skin") then
			return -- (a bot, or the old golden version)
		end
		SkinService.Apply(m, skinFor(p, kind))
	end)
end

------------------------------------------------------------------------
-- money, skins
------------------------------------------------------------------------

local function addCash(p: Player, n: number, why: string?)
	local prof = Persist.Get(p)
	if not prof then
		return
	end
	prof.cash = math.max(0, prof.cash + n)
	Persist.Dirty(p)
	p:SetAttribute("Cash", math.floor(prof.cash))
	ShopRemote:FireClient(p, "cash", n, why)
end
SkinService.AddCash = addCash

local function grant(p: Player, id: string): boolean
	local prof = Persist.Get(p)
	if not prof or not WeaponSkins.ById[id] or prof.owned[id] then
		return false
	end
	prof.owned[id] = true
	Persist.Dirty(p)
	publish(p)
	return true
end

function SkinService.RedeemBundle(p: Player, code: string): (boolean, string)
	local prof = Persist.Get(p)
	if not prof or not prof.loaded then return false, "Your profile is still loading." end
	local count = code == "chips" and rng:NextInteger(1, 2) or 1
	local cash = code == "chips" and rng:NextInteger(1, 500) or 200
	local pool, ids, names = {}, {}, {}
	for _, skin in WeaponSkins.List do if not prof.owned[skin.id] then table.insert(pool, skin) end end
	for _ = 1, count do
		if #pool == 0 then break end
		local skin = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(ids, skin.id); table.insert(names, skin.name)
	end
	local ok, why = Persist.ClaimCode(p, code, cash, ids)
	if not ok then return false, why end
	publish(p)
	ShopRemote:FireClient(p, "cash", cash, "code " .. code)
	return true, "$" .. cash .. " + " .. (#ids > 0 and table.concat(names, ", ") or "all skins already owned")
end

local function equip(p: Player, kind: string, id: string)
	local prof = Persist.Get(p)
	if not prof or not WeaponSkins.OfKind[kind] then
		return
	end
	if id == "" then
		prof.equipped[kind] = nil
	else
		local skin = WeaponSkins.ById[id]
		if not skin or skin.kind ~= kind or not canUse(p, id) then
			return
		end
		prof.equipped[kind] = id
	end
	Persist.Dirty(p)
	p:SetAttribute("Eq_" .. kind, prof.equipped[kind])
	-- what he holds right now changes at once
	local OwnershipService = SkinService.Ownership
	if OwnershipService then
		for _, item in OwnershipService.HeldItems(p) do
			if Items.Kind(item) == kind and not item:GetAttribute("Skin") then
				SkinService.Apply(item, skinFor(p, kind))
			end
		end
	end
end

-- one roll (paid for already): fixed odds. A skin you own pays dollars back.
local function rollFor(p: Player): string?
	local prof = Persist.Get(p)
	if not prof then
		return
	end
	local skin = WeaponSkins.Roll(rng)
	if prof.owned[skin.id] then
		local back = WeaponSkins.DupeCash[skin.rarity]
		addCash(p, back, "duplicate")
		ShopRemote:FireClient(p, "rolled", skin.id, true, back)
	else
		grant(p, skin.id)
		equip(p, skin.kind, skin.id)
		ShopRemote:FireClient(p, "rolled", skin.id, false, 0)
	end
	Persist.SaveNow(p)
	return skin.id
end

local function onShop(p: Player, action: any, a: any, b: any)
	if typeof(action) ~= "string" then
		return
	end
	local prof = Persist.Get(p)
	if not prof or not prof.loaded then
		return
	end
	if action == "equip" and typeof(a) == "string" and typeof(b) == "string" then
		equip(p, a, b)
	elseif action == "random" then
		if prof.cash < Config.RandomSkinCost then
			say(p, string.format("You need $%d for a random skin.", Config.RandomSkinCost))
			return
		end
		prof.cash -= Config.RandomSkinCost
		p:SetAttribute("Cash", math.floor(prof.cash))
		Persist.Dirty(p)
		rollFor(p)
	elseif action == "robuxrandom" then
		if Config.RandomSkinProductId == 0 then
			say(p, "Random skins for Robux are not set up yet.")
			return
		end
		MarketplaceService:PromptProductPurchase(p, Config.RandomSkinProductId)
	elseif action == "robux" and typeof(a) == "string" then
		local skin = WeaponSkins.ById[a]
		if not skin or prof.owned[a] then
			return
		end
		if Config.SkinProductId == 0 then
			if RunService:IsStudio() then
				grant(p, a) -- (testing in Studio: free)
				equip(p, skin.kind, a)
				ShopRemote:FireClient(p, "rolled", a, false, 0)
			else
				say(p, "Buying one skin for Robux is not set up yet (the developer must set Config.SkinProductId).")
			end
			return
		end
		pending[p.UserId] = a
		MarketplaceService:PromptProductPurchase(p, Config.SkinProductId)
	end
end

local function receipt(info: any)
	local p = Players:GetPlayerByUserId(info.PlayerId)
	if not p then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local prof = Persist.Wait(p, 10)
	if not prof then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if info.ProductId == Config.RandomSkinProductId and Config.RandomSkinProductId ~= 0 then
		local got = rollFor(p)
		if got then
			Persist.SavePurchase(p, got) -- (v2.8: paid for - kept even on a private server)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	elseif info.ProductId == Config.SkinProductId and Config.SkinProductId ~= 0 then
		local id = pending[info.PlayerId]
		pending[info.PlayerId] = nil
		if not id or prof.owned[id] then
			local got = rollFor(p) -- (the server restarted between the click and the purchase: he gets a roll, he did pay)
			if got then
				Persist.SavePurchase(p, got)
			end
		else
			grant(p, id)
			equip(p, WeaponSkins.ById[id].kind, id)
			ShopRemote:FireClient(p, "rolled", id, false, 0)
			Persist.SaveNow(p)
			Persist.SavePurchase(p, id) -- (v2.8: paid for - kept even on a private server)
		end
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

------------------------------------------------------------------------

SkinService.Ownership = nil :: any

function SkinService.Init(DamageService: any, OwnershipService: any)
	SkinService.Ownership = OwnershipService
	local Remotes = ReplicatedStorage:WaitForChild("Remotes")
	ShopRemote = Remotes:FindFirstChild("Shop") :: RemoteEvent
	if not ShopRemote then
		local r = Instance.new("RemoteEvent")
		r.Name = "Shop"
		r.Parent = Remotes
		ShopRemote = r
	end
	ShopRemote.OnServerEvent:Connect(onShop)
	MarketplaceService.ProcessReceipt = receipt
	-- the admin menu gives (or takes) dollars
	require(script.Parent:WaitForChild("AdminService")).GiveCash = function(target: Player, n: number)
		local prof = Persist.Get(target)
		if prof then
			addCash(target, math.max(n, -math.floor(prof.cash)), "gift")
		end
	end

	local function onPlayer(p: Player)
		task.spawn(function()
			if Persist.Wait(p, 30) then
				publish(p)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end

	workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Model") and d:GetAttribute("Item") ~= nil then
			watchItem(d)
		end
	end)
	task.spawn(function()
		for _, d in workspace:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("Item") ~= nil then
				watchItem(d)
			end
		end
	end)

	-- every kill pays
	local prev = DamageService.OnKill
	DamageService.OnKill = function(model: Model, killer: Player?, state: any)
		if prev then
			prev(model, killer, state)
		end
		if not killer or not killer.Parent or model:GetAttribute("IsDummy") then
			return
		end
		if state and state.player == killer then
			return
		end
		local seen = lastKillOf[killer] or {}
		lastKillOf[killer] = seen
		if os.clock() - (seen[model] or -99) < 8 then
			return
		end
		seen[model] = os.clock()
		addCash(killer, Config.KillCash, "kill")
	end
	Players.PlayerRemoving:Connect(function(p)
		lastKillOf[p] = nil
		pending[p.UserId] = nil
	end)
end

return SkinService
