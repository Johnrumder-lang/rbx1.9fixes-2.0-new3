--!nonstrict
-- GameModeService: the game modes the owner / admins start from the menu (M) or everybody votes for. They are
-- played on the loaded map (the city if none is; the MONSTER mode prefers the horror map). Rounds follow each
-- other until the mode is stopped; between two rounds everybody votes for the next map (Config.MapVoteTime).
--   teamfight : two teams (Red / Blue), a random gun each, no friendly fire. A team wiped out loses (time out:
--               the team with more alive wins).
--   ffa       : everybody against everybody, a random gun each; the last one standing wins (time out: most kills).
--   hideseek  : one seeker, the others hide; close-range weapons lie around. The seeker comes in after
--               Config.HideTime with a gun. Hiders win when the time runs out or the seeker dies.
--   monster   : (v2.0) everybody against the Crawler (a strong one): guns for all. Kill it or survive
--               Config.MonsterRoundTime and you win; it wins when nobody is left.
--   zombies   : (v2.0) a few start as zombies (green, no weapons, they bite with F / their fists), the others get
--               guns. Only HEAD shots kill a zombie (shoot its legs off and it crawls on, arms out). A bite: you turn
--               in Config.ZombieBiteTime seconds - unless somebody cures you with a heal dart; killed by a zombie
--               (or while bitten) you rise as one. Zombies come back after they die. Humans alive at the end win.
--   gungame   : (v2.0) everybody against everybody; every kill gives you the next weapon of the ladder (v2.0: random each round, from every weapon; the knife last).
--               The first to get a kill with the last one (the knife) wins. You come back right after you die.
--   sniper    : (v2.0) SNIPER TOWER. One player is the sniper, up on a tower with a long-range sniper (Config.SniperRangeMult,
--               the scope zooms further). Everybody else starts far away with no gun - a blade or their fists - and
--               runs at the tower. Runners come back (at the far end) when they die; they win when the sniper dies, the
--               sniper wins when the time runs out. Maps with a tower: Config.SniperTowerMaps (else the valley is loaded).
--   hotpotato : (v2.0) HOT POTATO. A bomb sticks to one of you; touch somebody and it is theirs. When the fuse runs out
--               it goes off and whoever holds it is out. No weapons, nobody gets hurt otherwise. The last one left wins.
--   koth      : (v2.0) KING OF THE HILL. A glowing ring on the map: one point a second for whoever is in it ALONE (two
--               or more inside: nobody scores). Everybody has a random gun and comes back after dying. The ring moves
--               every Config.HillMoveTime s. First to Config.HillTarget points wins (time out: most points).
-- Whoever dies (and stays out) waits in the lobby - and watches the others (SpectateClient) - until the next
-- round; so does whoever joins during a round (gun game / zombies: you are thrown right in).
-- (v2.0) bots: with BOTS on (owner menu) bots fill each round up to Config.ModeBotFill fighters (zombies: a few
-- zombie bots even without; a lonely monster hunter gets helpers). They fight by the mode's rules.
-- What clients see comes from attributes: workspace "Mode", "ModePhase", "ModeEnds" (server time), "ModeRound",
-- "ModeInfo", "ModeWinner", "MapVote", "MapVote_<id>"; on players "Team", "Role", "InLobby", "GunTier";
-- on bodies "Team", "Role", "Zombie", "BittenUntil".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Items = require(Shared:WaitForChild("Items"))

local Modules = script.Parent
local CharacterService = require(Modules:WaitForChild("CharacterService"))
local DamageService = require(Modules:WaitForChild("DamageService"))
local GoreService = require(Modules:WaitForChild("GoreService"))
local PropService = require(Modules:WaitForChild("PropService"))
local MapService = require(Modules:WaitForChild("MapService"))
local VehicleService = require(Modules:WaitForChild("VehicleService"))
local WorldSetup = require(Modules:WaitForChild("WorldSetup"))
local NPCService = require(Modules:WaitForChild("NPCService"))
local CreatureService = require(Modules:WaitForChild("CreatureService"))
local MapFeatureService = require(Modules:WaitForChild("MapFeatureService"))
local OwnershipService = require(Modules:WaitForChild("OwnershipService"))
local KnockService = require(Modules:WaitForChild("KnockService"))
local ExplosionService = require(Modules:WaitForChild("ExplosionService"))

local ModeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("Mode") :: RemoteEvent

local GameModeService = {}

GameModeService.MODES = {
	teamfight = "TEAM FIGHT",
	ffa = "FREE FOR ALL",
	hideseek = "HIDE AND SEEK",
	monster = "MONSTER",
	zombies = "ZOMBIES",
	gungame = "GUN GAME",
	sniper = "SNIPER TOWER",
	hotpotato = "HOT POTATO",
	koth = "KING OF THE HILL",
}
local PREFERRED_MAP = { monster = "horror", sniper = "valley" }
local BOT_NAMES = { "Rex", "Nova", "Ghost", "Viper", "Echo", "Blaze", "Ash", "Kilo", "Juno", "Orbit", "Mako", "Pixel", "Tango", "Zed", "Ivy", "Bolt" }

local RED = Color3.fromRGB(255, 80, 70)
local BLUE = Color3.fromRGB(80, 140, 255)
local GOLD = Color3.fromRGB(255, 220, 90)
local GREEN = Color3.fromRGB(90, 220, 120)

type PState = {
	key: any, -- the Player, or the bot's model
	bot: Model?,
	name: string,
	team: string?,
	role: string?,
	alive: boolean,
	kills: number,
	spawnCF: CFrame?,
	weapon: string?,
	tier: number,
	bitten: number?,
	points: number, -- (king of the hill)
	isBot: boolean?,
}

local mode: string? = nil
local phase = "idle" -- "idle" | "hiding" | "playing" | "ended"
local round = 0
local endsAt = 0
local token = 0
local states: { [any]: PState } = {}
local roundItems: { Instance } = {}
local itemOwner: { [Instance]: any } = setmetatable({}, { __mode = "k" }) :: any
local startedWith = 0 -- how many played when the round began (alone: a practice round, no winner)
local spawningAllowed = true -- the owner's switch in the menu
local rng = Random.new()
local votedFill = false -- (v2.0) this game was voted for: bots fill every round


-- (v2.0) the gun game's ladder: a fresh random one every round - any weapon in the game can come up (guns, the
-- rocket and lock-on launchers, darts, the harpoon, blades, the chainsaw, steel balls...), the knife is always last
local ladder: { string } = table.clone(Config.GunGameLadder)
local function randomLadder(): { string }
	local pool = table.clone(Config.GunGamePool)
	for k = #pool, 2, -1 do
		local j = rng:NextInteger(1, k)
		pool[k], pool[j] = pool[j], pool[k]
	end
	local out = {}
	for k = 1, math.min(Config.GunGameSteps - 1, #pool) do
		out[k] = pool[k]
	end
	table.insert(out, "knife")
	return out
end

-- (v2.0) hot potato: who holds the bomb, when it goes off; king of the hill: the ring
type Potato = { holder: PState?, model: Model?, ends: number, lockUntil: number, from: PState?, fromUntil: number, nextAt: number?, beepAt: number }
local potato: Potato = { holder = nil, model = nil, ends = 0, lockUntil = 0, from = nil, fromUntil = 0, nextAt = nil, beepAt = 0 }
type Hill = { pos: Vector3?, model: Model?, movesAt: number, spots: { Vector3 }, king: PState?, contested: boolean, index: number }
local hill: Hill = { pos = nil, model = nil, movesAt = 0, spots = {}, king = nil, contested = false, index = 0 }
local lastHillTick = 0

local board: TextLabel? = nil
local monster: Model? = nil
local mapVotes: { [Player]: string } = {}
local nextMap: string? = nil
local botCount = 0

local function now(): number
	return workspace:GetServerTimeNow()
end

local function shuffle<T>(list: { T }): { T }
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function pick<T>(list: { T }): T?
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

local function facingCenter(pos: Vector3): CFrame
	local c = MapService.Center()
	local to = Vector3.new(c.X - pos.X, 0, c.Z - pos.Z)
	if to.Magnitude < 1 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + to.Unit)
end

local function lobbyCF(): CFrame
	local lobby = workspace:FindFirstChild("Lobby")
	local spots = {}
	if lobby then
		for _, d in lobby:GetChildren() do
			if d:IsA("BasePart") and string.match(d.Name, "^LobbySpawn_%d+$") then
				table.insert(spots, d)
			end
		end
	end
	local s = pick(spots)
	if s then
		return CFrame.new(s.Position + Vector3.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5)))
	end
	return CFrame.new(0, 403, -1700)
end

local function stateOfBody(m: Model): PState?
	local p = Players:GetPlayerFromCharacter(m)
	if p then
		return states[p]
	end
	return states[m]
end

local function spawnCFs(prefix: string): { CFrame }
	local out = {}
	for _, p in MapService.Points(prefix) do
		table.insert(out, facingCenter(p.Position))
	end
	return shuffle(out)
end

local function anySpawn(prefix: string?): CFrame
	local list = prefix and spawnCFs(prefix) or {}
	if #list == 0 then
		list = spawnCFs("ModeSpawn_")
	end
	local cf = pick(list)
	if cf then
		return cf + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
	end
	local c = MapService.MapSpawn() or MapService.SandboxSpawn()
	return CFrame.new(c + Vector3.new(0, 3, 0))
end

------------------------------------------------------------------------
-- what everybody sees
------------------------------------------------------------------------

local function counts()
	local r = { red = 0, blue = 0, hiders = 0, seekers = 0, humans = 0, zombies = 0, alive = 0, snipers = 0, runners = 0 }
	for _, st in states do
		if st.alive then
			r.alive += 1
			if st.team == "Red" then
				r.red += 1
			elseif st.team == "Blue" then
				r.blue += 1
			end
			if st.role == "Hider" then
				r.hiders += 1
			elseif st.role == "Seeker" then
				r.seekers += 1
			elseif st.role == "Human" then
				r.humans += 1
			elseif st.role == "Zombie" then
				r.zombies += 1
			elseif st.role == "Sniper" then
				r.snipers += 1
			elseif st.role == "Runner" then
				r.runners += 1
			end
		end
	end
	return r
end

local function leader(): PState?
	local best: PState? = nil
	for _, st in states do
		if not best or st.tier > best.tier or (st.tier == best.tier and st.kills > best.kills) then
			best = st
		end
	end
	return best
end

local function infoText(): string
	if not mode then
		return ""
	end
	local c = counts()
	if mode == "teamfight" then
		return string.format("RED %d  vs  BLUE %d", c.red, c.blue)
	elseif mode == "ffa" then
		return string.format("%d PLAYERS LEFT", c.alive)
	elseif mode == "hideseek" then
		if phase == "hiding" then
			return string.format("HIDE! %d HIDERS", c.hiders)
		end
		return string.format("%d HIDERS LEFT", c.hiders)
	elseif mode == "monster" then
		local hp, maxHp = 0, 1
		if monster and monster.Parent then
			hp = monster:GetAttribute("HP") or 0
			maxHp = monster:GetAttribute("MaxHP") or 1
		end
		return string.format("%d FIGHTERS  -  MONSTER %d%%", c.alive, math.floor(hp / math.max(1, maxHp) * 100 + 0.5))
	elseif mode == "zombies" then
		return string.format("HUMANS %d  vs  ZOMBIES %d", c.humans, c.zombies)
	elseif mode == "gungame" then
		local l = leader()
		if l then
			return string.format("LEADER %s  %d/%d", string.upper(l.name), math.min(l.tier, #ladder), #ladder)
		end
	elseif mode == "sniper" then
		local sn = nil
		for _, st in states do
			if st.role == "Sniper" then
				sn = st
			end
		end
		return string.format("SNIPER %s  -  %d RUNNERS", sn and string.upper(sn.name) or "?", c.runners)
	elseif mode == "hotpotato" then
		local h = potato.holder
		if h and h.alive then
			return string.format("%d LEFT  -  BOMB: %s %ds", c.alive, string.upper(h.name), math.max(0, math.ceil(potato.ends - now())))
		end
		return string.format("%d LEFT", c.alive)
	elseif mode == "koth" then
		local best: PState? = nil
		for _, st in states do
			if not best or st.points > best.points then
				best = st
			end
		end
		local ring = hill.contested and "CONTESTED" or (hill.king and ("KING " .. string.upper(hill.king.name)) or "THE RING IS EMPTY")
		if best and best.points > 0 then
			return string.format("%s  -  BEST %s %d/%d", ring, string.upper(best.name), best.points, Config.HillTarget)
		end
		return ring
	end
	return ""
end

local function publish()
	workspace:SetAttribute("Mode", mode)
	workspace:SetAttribute("ModePhase", mode and phase or nil)
	workspace:SetAttribute("ModeEnds", mode and endsAt or nil)
	workspace:SetAttribute("ModeRound", mode and round or nil)
	workspace:SetAttribute("ModeInfo", mode and infoText() or nil)
	workspace:SetAttribute("SpawningLocked", (mode ~= nil) or not spawningAllowed)
	workspace:SetAttribute("PotatoEnds", (mode == "hotpotato" and potato.holder) and potato.ends or nil)
	workspace:SetAttribute("HillPos", (mode == "koth") and hill.pos or nil)
	workspace:SetAttribute("HillRadius", (mode == "koth") and Config.HillRadius or nil)
	for _, p in Players:GetPlayers() do
		local st = states[p]
		p:SetAttribute("Team", mode and st and st.team or nil)
		p:SetAttribute("Role", mode and st and st.role or nil)
		p:SetAttribute("InLobby", (mode ~= nil and (not st or not st.alive)) or nil)
		p:SetAttribute("GunTier", (mode == "gungame" and st) and st.tier or nil)
		p:SetAttribute("Points", (mode == "koth" and st) and st.points or nil)
		if p.Character then
			p.Character:SetAttribute("Team", mode and st and st.team or nil)
			p.Character:SetAttribute("Role", mode and st and st.role or nil)
		end
	end
	for _, st in states do
		if st.bot and st.bot.Parent then
			st.bot:SetAttribute("Team", st.team)
			st.bot:SetAttribute("Role", st.role)
		end
	end
	if board then
		if mode then
			local title = GameModeService.MODES[mode] or mode
			local w = workspace:GetAttribute("ModeWinner")
			board.Text = string.format("%s  -  ROUND %d\n%s%s", title, round, infoText(),
				(phase == "ended" and typeof(w) == "string") and ("\n" .. w) or "")
		else
			board.Text = "NO GAME RUNNING"
		end
	end
end

local function banner(text: string, color: Color3?, who: { Player }?)
	for _, p in who or Players:GetPlayers() do
		ModeRemote:FireClient(p, "banner", text, color or Color3.fromRGB(255, 255, 255))
	end
end

local function bannerTo(st: PState, text: string, color: Color3?)
	if not st.bot then
		banner(text, color, { st.key :: Player })
	end
end

------------------------------------------------------------------------
-- the map vote between two rounds
------------------------------------------------------------------------

local function publishVotes()
	for _, id in MapService.ORDER do
		local n = 0
		for p, v in mapVotes do
			if v == id and p.Parent then
				n += 1
			end
		end
		workspace:SetAttribute("MapVote_" .. id, n)
	end
end

local function openMapVote()
	table.clear(mapVotes)
	workspace:SetAttribute("MapVote", true)
	publishVotes()
end

-- the map with the most votes (a tie: the loaded one if it is among them, else one of them); nil = no votes
local function closeMapVote(): string?
	workspace:SetAttribute("MapVote", nil)
	local tally: { [string]: number } = {}
	for p, v in mapVotes do
		if p.Parent then
			tally[v] = (tally[v] or 0) + 1
		end
	end
	table.clear(mapVotes)
	local best, top = {}, 0
	for id, n in tally do
		if n > top then
			best, top = { id }, n
		elseif n == top then
			table.insert(best, id)
		end
	end
	if top == 0 then
		return nil
	end
	local cur = MapService.Current()
	if cur and table.find(best, cur) then
		return cur
	end
	return pick(best)
end

-- a community vote / the menu picked a map while a mode runs: it is played from the next round on
function GameModeService.SetNextMap(id: string)
	if MapService.MAPS[id] then
		nextMap = id
		banner("NEXT ROUND: " .. MapService.MAPS[id].label, GOLD)
	end
end

------------------------------------------------------------------------
-- items, bots, the monster
------------------------------------------------------------------------

local function clearItems()
	for _, inst in roundItems do
		if inst.Parent then
			inst:Destroy()
		end
	end
	table.clear(roundItems)
	-- a mode gun somebody still carries (or that lies on a corpse)
	local props = workspace:FindFirstChild("SpawnedProps")
	if props then
		for _, inst in props:GetChildren() do
			if inst:GetAttribute("ModeItem") then
				inst:Destroy()
			end
		end
	end
end

local function itemsOf(key: any)
	for _, inst in roundItems do
		if inst.Parent and itemOwner[inst] == key then
			inst:Destroy()
		end
	end
end

-- hide and seek: only the seeker has a gun (the gun store in the city is emptied for the round)
local function isGunId(id: string): boolean
	local kind = Items.Kinds[id]
	return (kind ~= nil and kind.gun == true) or table.find(Config.ModeGuns, id) ~= nil
end

local function removeLooseGuns()
	local props = workspace:FindFirstChild("SpawnedProps")
	if not props then
		return
	end
	for _, inst in props:GetChildren() do
		if inst:IsA("Model") and not inst:GetAttribute("ModeItem") and Items.IsGun(inst) then
			inst:Destroy()
		end
	end
end

local function give(player: Player, model: Model, id: string, tok: number)
	task.wait(Config.ModeGiveDelay)
	if tok ~= token or player.Character ~= model or model:GetAttribute("Dead") then
		return
	end
	local arm = model:FindFirstChild("Right Arm")
	if not arm or not arm:IsA("BasePart") then
		arm = model:FindFirstChild("Torso")
	end
	if not arm or not arm:IsA("BasePart") then
		return
	end
	local inst = PropService.Place(id, arm.CFrame * CFrame.new(0, -1.4, 0), player)
	if not inst then
		return
	end
	inst:SetAttribute("ModeItem", true)
	-- (v2.0) the sniper's rifle reaches much further (the server and the shooter's screen both read this)
	local st = states[player]
	if mode == "sniper" and st and st.role == "Sniper" then
		inst:SetAttribute("RangeMult", Config.SniperRangeMult)
		inst:SetAttribute("ScopeExtra", true)
	end
	table.insert(roundItems, inst)
	itemOwner[inst] = player
	ModeRemote:FireClient(player, "give", inst)
end

local function respawnFresh(player: Player)
	pcall(VehicleService.Exit, player)
	pcall(VehicleService.ExitPassenger, player)
	CharacterService.Spawn(player, true)
end

local function removeBots()
	for key, st in states do
		if st.bot then
			if st.bot.Parent then
				st.bot:Destroy()
			end
			states[key] = nil
		end
	end
	for _, m in NPCService.All() do
		if m:GetAttribute("ModeBot") then
			m:Destroy()
		end
	end
end

local function removeMonster()
	if monster then
		CreatureService.Despawn(monster) -- (v2.0: it lets go and fades out)
		monster = nil
	end
	MapFeatureService.ModeMonster = false
end

-- a bot's body for its state (a new one: a respawn, a human bot that turned)
local function spawnBotBody(st: PState, cf: CFrame): Model?
	local zombie = st.role == "Zombie"
	local weapon = if zombie then nil else st.weapon
	if mode == "gungame" then
		weapon = ladder[math.min(st.tier, #ladder)]
	end
	local kind = weapon and (Config.Guns[weapon] and "gun" or "melee") or "gun"
	if mode == "hotpotato" then
		kind, weapon = "boxer", nil -- (no weapons: fists that are only for show)
	end
	local m = NPCService.Spawn(kind, cf, nil, {
		weapon = weapon,
		team = st.team,
		zombie = zombie,
		bot = true,
		name = (zombie and "ZOMBIE " or "BOT ") .. string.upper(st.name),
	})
	if not m then
		return nil
	end
	m:SetAttribute("ModeBot", true)
	m:SetAttribute("Role", st.role)
	if st.bot and states[st.bot] == st then
		states[st.bot] = nil
	end
	st.bot = m
	st.key = m
	states[m] = st
	return m
end

local function zombifyBody(m: Model)
	m:SetAttribute("Zombie", true)
	m:SetAttribute("BittenUntil", nil)
	local bc = m:FindFirstChildOfClass("BodyColors")
	if bc then
		for _, prop in { "HeadColor3", "LeftArmColor3", "RightArmColor3", "LeftLegColor3", "RightLegColor3" } do
			(bc :: any)[prop] = Config.ZombieColor
		end
	end
	for _, n in { "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" } do
		local p = m:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			p.Color = Config.ZombieColor
		end
	end
	local head = m:FindFirstChild("Head")
	local face = head and head:FindFirstChild("face")
	if face and face:IsA("Decal") then
		face.Color3 = Color3.fromRGB(255, 60, 40)
	end
end

local function makeZombie(st: PState)
	st.role = "Zombie"
	st.bitten = nil
	st.alive = true
	if st.bot then
		local old = st.bot
		local cf = old and old.Parent and old:GetPivot() or anySpawn("ZombieSpawn_")
		if old and old.Parent then
			states[old] = nil
			old:Destroy()
		end
		spawnBotBody(st, cf + Vector3.new(0, 1, 0))
	else
		local p = st.key :: Player
		local c = p.Character
		if c and not c:GetAttribute("Dead") then
			OwnershipService.ReleaseAll(p)
			itemsOf(p)
			zombifyBody(c)
			DamageService.StopBleeding(c)
		end
	end
	banner(string.upper(st.name) .. " TURNED INTO A ZOMBIE", GREEN)
	publish()
end

-- the body somebody in the round plays with right now (nil: dead / waiting)
local function bodyOf(st: PState?): Model?
	if not st or not st.alive then
		return nil
	end
	local m: Model? = if st.bot then st.bot else (st.key :: Player).Character
	if m and m.Parent and not m:GetAttribute("Dead") then
		return m
	end
	return nil
end

local function torsoOf(st: PState?): BasePart?
	local m = bodyOf(st)
	local t = m and m:FindFirstChild("Torso")
	return (t and t:IsA("BasePart")) and t or nil
end

------------------------------------------------------------------------
-- (v2.0) hot potato: the bomb
------------------------------------------------------------------------

local function potatoPart(m: Model, name: string, size: Vector3, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = mat
	if shape then
		p.Shape = shape
	end
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = m
	return p
end

-- (v2.8.1) a time bomb strapped to the chest: three red sticks taped together, a timer box with red digits on the
-- front, wires from the timer into the sticks, a blinking light; the time over it for everybody
local function buildPotato(): Model
	local m = Instance.new("Model")
	m.Name = "HotPotato"
	local plate = potatoPart(m, "Bomb", Vector3.new(1.7, 1.2, 0.12), Color3.fromRGB(30, 30, 34), Enum.Material.Fabric)
	m.PrimaryPart = plate
	local function weld(q: BasePart, off: CFrame)
		q.CFrame = plate.CFrame * off
		local w = Instance.new("WeldConstraint")
		w.Part0 = plate
		w.Part1 = q
		w.Parent = q
	end
	local Y = CFrame.Angles(0, 0, math.rad(90))
	for i, x in { -0.46, 0, 0.46 } do
		local stick = potatoPart(m, "Stick", Vector3.new(1.15, 0.44, 0.44), Color3.fromRGB(196, 36, 32), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weld(stick, CFrame.new(x, 0, -0.29) * Y)
		local tip = potatoPart(m, "StickTip", Vector3.new(0.06, 0.38, 0.38), Color3.fromRGB(230, 210, 170), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		weld(tip, CFrame.new(x, 0.6, -0.29) * Y)
		local _ = i
	end
	for _, y in { -0.33, 0.33 } do
		local tape = potatoPart(m, "Tape", Vector3.new(1.42, 0.13, 0.5), Color3.fromRGB(16, 16, 18), Enum.Material.Fabric)
		weld(tape, CFrame.new(0, y, -0.29))
	end
	local box = potatoPart(m, "TimerBox", Vector3.new(0.9, 0.5, 0.24), Color3.fromRGB(24, 26, 30), Enum.Material.Metal)
	weld(box, CFrame.new(0, 0.02, -0.62))
	local face = potatoPart(m, "TimerFace", Vector3.new(0.72, 0.3, 0.02), Color3.fromRGB(10, 10, 12), Enum.Material.SmoothPlastic)
	weld(face, CFrame.new(-0.04, 0.02, -0.745))
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Digits"
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(140, 60)
	sg.LightInfluence = 0
	sg.Brightness = 2
	local dl = Instance.new("TextLabel")
	dl.Name = "Text"
	dl.Size = UDim2.fromScale(1, 1)
	dl.BackgroundTransparency = 1
	dl.Font = Enum.Font.Sarpanch
	dl.TextScaled = true
	dl.TextColor3 = Color3.fromRGB(255, 40, 40)
	dl.Text = "00.0"
	dl.Parent = sg
	sg.Parent = face
	local led = potatoPart(m, "Led", Vector3.new(0.12, 0.12, 0.12), Color3.fromRGB(255, 30, 30), Enum.Material.Neon, Enum.PartType.Ball)
	weld(led, CFrame.new(0.37, 0.16, -0.75))
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 50, 40)
	light.Range = 7
	light.Brightness = 2
	light.Parent = led
	-- the wires: red, blue and yellow, from the timer down into the sticks
	for i, col in { Color3.fromRGB(220, 30, 30), Color3.fromRGB(40, 90, 220), Color3.fromRGB(230, 200, 40) } do
		local x = -0.46 + (i - 1) * 0.46
		local a = Vector3.new(-0.3 + (i - 1) * 0.3, -0.2, -0.66)
		local b = Vector3.new(x, -0.45, -0.5)
		local wire = potatoPart(m, "Wire", Vector3.new(0.05, 0.05, (b - a).Magnitude), col, Enum.Material.SmoothPlastic)
		weld(wire, CFrame.lookAt((a + b) / 2, b))
	end
	-- the blink
	task.spawn(function()
		local on = true
		while led.Parent do
			on = not on
			led.Transparency = on and 0 or 0.85
			light.Enabled = on
			task.wait(0.35)
		end
	end)
	-- the time left, over the bomb, for everybody
	local bb = Instance.new("BillboardGui")
	bb.Name = "Timer"
	bb.Size = UDim2.fromOffset(90, 40)
	bb.StudsOffset = Vector3.new(0, 2.2, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 220
	bb.LightInfluence = 0
	local tl = Instance.new("TextLabel")
	tl.Name = "Text"
	tl.Size = UDim2.fromScale(1, 1)
	tl.BackgroundTransparency = 1
	tl.Font = Enum.Font.Sarpanch
	tl.TextScaled = true
	tl.TextColor3 = Color3.fromRGB(255, 80, 60)
	tl.TextStrokeTransparency = 0.2
	tl.Text = ""
	tl.Parent = bb
	bb.Parent = plate
	return m
end

local function dropPotato()
	local old = potato.holder
	if old then
		local b = old.bot or (not old.isBot and (old.key :: Player).Character) or nil
		if b then
			b:SetAttribute("PotatoHolder", nil)
		end
	end
	potato.holder = nil
	if potato.model then
		potato.model:Destroy()
		potato.model = nil
	end
end

-- the bomb is stuck to this one now (front of the chest)
local function givePotato(st: PState, from: PState?)
	local body = bodyOf(st)
	local torso = torsoOf(st)
	if not body or not torso then
		return
	end
	local fresh = potato.holder == nil and from == nil
	local ends = potato.ends
	dropPotato()
	potato.holder = st
	potato.from = from
	potato.fromUntil = now() + Config.PotatoNoPassBack
	potato.lockUntil = now() + Config.PotatoPassLock
	if fresh then
		ends = now() + rng:NextNumber(Config.PotatoFuse[1], Config.PotatoFuse[2])
	end
	potato.ends = ends
	local m = buildPotato()
	local ball = m.PrimaryPart :: BasePart
	m:PivotTo(torso.CFrame * CFrame.new(0, 0.1, -0.56))
	local w = Instance.new("Weld")
	w.Part0 = torso
	w.Part1 = ball
	w.C0 = CFrame.new(0, 0.1, -0.56) -- (v2.8.1: strapped flat on the chest)
	w.Parent = ball
	m:SetAttribute("ModeItem", true)
	m:SetAttribute("PotatoOf", body.Name)
	-- (not inside the body: nothing that looks through a body's parts must ever find the bomb)
	m.Parent = workspace:FindFirstChild("FX") or workspace
	potato.model = m
	body:SetAttribute("PotatoHolder", true)
	GoreService.Sound(fresh and "beep" or "punch", torso, 1)
	if fresh then
		banner(string.upper(st.name) .. " HAS THE BOMB!", RED)
	end
	bannerTo(st, "YOU HAVE THE BOMB - TOUCH SOMEBODY!", RED)
	if from then
		bannerTo(from, "PASSED IT TO " .. string.upper(st.name), GREEN)
	end
	publish()
end

-- the fuse ran out: whoever holds it is out
local function blowUp()
	local st = potato.holder
	local torso = torsoOf(st)
	local body = bodyOf(st)
	dropPotato()
	potato.nextAt = now() + Config.PotatoNextBomb
	if not st or not torso or not body then
		return
	end
	local pos = torso.Position
	ExplosionService.Explode(pos, { radius = 10, damage = 0, power = 70, cause = "The hot potato went off", kind = "grenade" })
	GoreService.Gibs(pos, 10, 46)
	DamageService.Kill(body, "The hot potato went off")
	banner(string.upper(st.name) .. " WENT BOOM", RED)
end

-- who is closest to this one (that the bomb may go to)
local function nearestTo(st: PState, except: PState?): (PState?, number)
	local t = torsoOf(st)
	local best, bestD = nil, math.huge
	if not t then
		return nil, bestD
	end
	for _, o in states do
		if o ~= st and o ~= except and o.alive then
			local ot = torsoOf(o)
			if ot then
				local d = (ot.Position - t.Position).Magnitude
				if d < bestD then
					best, bestD = o, d
				end
			end
		end
	end
	return best, bestD
end

------------------------------------------------------------------------
-- (v2.0) king of the hill: the ring
------------------------------------------------------------------------

local function hillSpots(): { Vector3 }
	local out = {}
	local list = MapService.Points("HillSpot_")
	if #list == 0 then
		list = MapService.Points("ModeSpawn_")
	end
	for _, p in list do
		table.insert(out, p.Position)
	end
	return shuffle(out)
end

local function buildHill(pos: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "ModeHill"
	-- stand it on whatever is under the point
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, n in { "SpawnedProps", "NPCs", "Corpses", "FX" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(ignore, f)
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	rp.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), rp)
	local g = hit and hit.Position or (pos - Vector3.new(0, 3, 0))
	local R = Config.HillRadius
	local function piece(name: string, size: Vector3, cf: CFrame, color: Color3, transp: number, mat: Enum.Material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Cylinder
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Transparency = transp
		p.Material = mat
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = m
		return p
	end
	local up = CFrame.Angles(0, 0, math.rad(90))
	piece("Ring", Vector3.new(0.12, R * 2, R * 2), CFrame.new(g + Vector3.new(0, 0.08, 0)) * up, Color3.fromRGB(255, 210, 70), 0.55, Enum.Material.Neon)
	piece("Inner", Vector3.new(0.14, R * 2 - 1.2, R * 2 - 1.2), CFrame.new(g + Vector3.new(0, 0.1, 0)) * up, Color3.fromRGB(40, 34, 20), 0.6, Enum.Material.SmoothPlastic)
	local beam = piece("Beam", Vector3.new(80, 2.2, 2.2), CFrame.new(g + Vector3.new(0, 40, 0)) * up, Color3.fromRGB(255, 220, 90), 0.72, Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 90)
	light.Range = 26
	light.Brightness = 1.4
	light.Parent = beam
	m:SetAttribute("Ground", g)
	m.Parent = workspace
	return m
end

local function moveHill()
	if #hill.spots == 0 then
		hill.spots = hillSpots()
	end
	if #hill.spots == 0 then
		return
	end
	hill.index = hill.index % #hill.spots + 1
	local pos = hill.spots[hill.index]
	if hill.model then
		hill.model:Destroy()
	end
	local ring = buildHill(pos)
	hill.model = ring
	table.insert(roundItems, ring)
	local g = ring:GetAttribute("Ground")
	hill.pos = typeof(g) == "Vector3" and g or pos
	hill.movesAt = now() + Config.HillMoveTime
	hill.king = nil
	hill.contested = false
	publish()
end

local function clearHill()
	if hill.model then
		hill.model:Destroy()
	end
	hill.model = nil
	hill.pos = nil
	hill.king = nil
	hill.contested = false
	table.clear(hill.spots)
	hill.index = 0
end

------------------------------------------------------------------------
-- rounds
------------------------------------------------------------------------

local endRound: (string, Color3?) -> ()

local function checkWin()
	if not mode or (phase ~= "playing" and phase ~= "hiding") then
		return
	end
	publish()
	if startedWith < 2 then
		return -- alone: a practice round, it only ends when the time runs out
	end
	local c = counts()
	if mode == "teamfight" then
		if c.red == 0 and c.blue == 0 then
			endRound("DRAW")
		elseif c.red == 0 then
			endRound("BLUE TEAM WINS", BLUE)
		elseif c.blue == 0 then
			endRound("RED TEAM WINS", RED)
		end
	elseif mode == "ffa" then
		if c.alive <= 1 then
			local winner = nil
			for _, st in states do
				if st.alive then
					winner = st
				end
			end
			endRound(winner and (string.upper(winner.name) .. " WINS") or "NOBODY WINS", GOLD)
		end
	elseif mode == "hideseek" then
		if c.hiders == 0 then
			endRound("THE SEEKER WINS", RED)
		elseif c.seekers == 0 and phase == "playing" then
			endRound("THE HIDERS WIN", GREEN)
		end
	elseif mode == "monster" then
		if c.alive == 0 then
			endRound("THE MONSTER WINS", RED)
		end
	elseif mode == "zombies" then
		if c.humans == 0 then
			endRound("THE ZOMBIES WIN", GREEN)
		end
	elseif mode == "sniper" then
		if c.snipers == 0 then
			endRound("THE SNIPER IS DOWN - THE RUNNERS WIN", GREEN)
		end
	elseif mode == "hotpotato" then
		if c.alive <= 1 then
			local winner = nil
			for _, st in states do
				if st.alive then
					winner = st
				end
			end
			endRound(winner and (string.upper(winner.name) .. " SURVIVED THE HOT POTATO") or "NOBODY SURVIVED", GOLD)
		end
	end
end

local function timeUp()
	local c = counts()
	if mode == "teamfight" then
		if c.red > c.blue then
			endRound("TIME! RED TEAM WINS", RED)
		elseif c.blue > c.red then
			endRound("TIME! BLUE TEAM WINS", BLUE)
		else
			endRound("TIME! DRAW")
		end
	elseif mode == "ffa" then
		local best, bestK = nil, -1
		for _, st in states do
			if st.alive and st.kills > bestK then
				best, bestK = st, st.kills
			end
		end
		endRound(best and ("TIME! " .. string.upper(best.name) .. " WINS") or "TIME!", GOLD)
	elseif mode == "hideseek" then
		endRound("TIME! THE HIDERS WIN", GREEN)
	elseif mode == "monster" then
		endRound(c.alive > 0 and "TIME! YOU SURVIVED - THE FIGHTERS WIN" or "THE MONSTER WINS", c.alive > 0 and GREEN or RED)
	elseif mode == "zombies" then
		endRound(c.humans > 0 and "TIME! THE HUMANS SURVIVED" or "THE ZOMBIES WIN", c.humans > 0 and BLUE or GREEN)
	elseif mode == "gungame" then
		local l = leader()
		endRound(l and ("TIME! " .. string.upper(l.name) .. " WINS GUN GAME") or "TIME!", GOLD)
	elseif mode == "sniper" then
		endRound("TIME! THE SNIPER HELD THE TOWER", RED)
	elseif mode == "hotpotato" then
		-- the last bomb goes off now; everybody else left wins
		if potato.holder then
			blowUp()
		end
		local names = {}
		for _, st in states do
			if st.alive then
				table.insert(names, string.upper(st.name))
			end
		end
		endRound(#names > 0 and ("TIME! " .. table.concat(names, ", ", 1, math.min(#names, 4)) .. (#names > 4 and " AND MORE" or "") .. " SURVIVED") or "TIME! NOBODY SURVIVED", GOLD)
	elseif mode == "koth" then
		local best: PState? = nil
		for _, st in states do
			if st.points > 0 and (not best or st.points > best.points) then
				best = st
			end
		end
		endRound(best and string.format("TIME! %s WINS WITH %d POINTS", string.upper(best.name), best.points) or "TIME! NOBODY HELD THE RING", GOLD)
	end
end

local function newState(key: any, name: string, bot: boolean): PState
	return { key = key, bot = nil, name = name, team = nil, role = nil, alive = true, kills = 0, tier = 1, points = 0, isBot = bot }
end

local function startRound()
	if not mode then
		return
	end
	token += 1
	round += 1
	dropPotato()
	potato.nextAt = nil
	clearHill()
	clearItems()
	removeBots()
	removeMonster()
	workspace:SetAttribute("ModeWinner", nil)
	workspace:SetAttribute("ModeSummary", nil)
	-- the map: the vote's winner, else what is loaded, else the mode's own
	local voted = nextMap
	nextMap = nil
	local want = voted or MapService.Current() or PREFERRED_MAP[mode] or "city"
	-- (v2.0) the sniper needs a tower: a map without one is swapped for the valley
	if mode == "sniper" and not table.find(Config.SniperTowerMaps, want) then
		if voted then
			banner("NO TOWER ON " .. (MapService.MAPS[want] and MapService.MAPS[want].label or want) .. " - TO THE VALLEY", GOLD)
		end
		want = PREFERRED_MAP.sniper
	end
	if MapService.Current() ~= want then
		MapService.Load(want)
	end
	if not MapService.IsLoaded() then
		MapService.Load("city")
	end
	local players = shuffle(Players:GetPlayers())
	table.clear(states)
	-- bots fill the round up
	local nBots = 0
	if (workspace:GetAttribute("BotsEnabled") == true or votedFill) and mode ~= "hideseek" then
		-- (owner's BOTS switch, or (v2.0) a game the community voted for: always full)
		nBots = math.max(0, Config.ModeBotFill - #players)
		if mode == "monster" then
			nBots = math.max(0, 4 - #players)
		end
	end
	-- (v2.0) these need somebody to play against: a few bots even with the switch off
	if mode == "sniper" or mode == "hotpotato" or mode == "koth" then
		nBots = math.max(nBots, 4 - #players)
	end
	-- (v2.0) ZOMBIES: on top of everybody, a few zombie bots start every round
	local extraZombies = mode == "zombies" and Config.ZombieExtraBots or 0
	-- everybody who plays: players first, then the bots (their bodies come below)
	local list: { PState } = {}
	for _, p in players do
		local st = newState(p, p.DisplayName, false)
		states[p] = st
		table.insert(list, st)
	end
	local botStates: { PState } = {}
	local extraSet: { [PState]: boolean } = {}
	for i = 1, nBots + extraZombies do
		botCount += 1
		local st = newState(nil, BOT_NAMES[(botCount - 1) % #BOT_NAMES + 1], true)
		table.insert(list, st)
		table.insert(botStates, st)
		if i > nBots then
			extraSet[st] = true
		end
	end
	startedWith = #list
	local guns = Config.ModeGuns
	if mode == "teamfight" then
		local red, blue = spawnCFs("ModeSpawn_Red_"), spawnCFs("ModeSpawn_Blue_")
		for i, st in list do
			st.team = (i % 2 == 1) and "Red" or "Blue"
			local l = st.team == "Red" and red or blue
			local base = l[((i - 1) // 2) % math.max(1, #l) + 1]
			st.weapon = pick(guns)
			st.spawnCF = base and base + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)) or nil
		end
	elseif mode == "ffa" or mode == "gungame" then
		if mode == "gungame" then
			ladder = randomLadder()
		end
		local spots = spawnCFs("ModeSpawn_")
		for i, st in list do
			st.spawnCF = spots[(i - 1) % math.max(1, #spots) + 1]
			st.weapon = mode == "ffa" and pick(guns) or nil
		end
	elseif mode == "hideseek" then
		local spots = spawnCFs("HideSpawn_")
		for i, st in list do
			if i == 1 then
				-- the seeker waits in the lobby while the others hide
				st.role = "Seeker"
				st.alive = false
			else
				st.role = "Hider"
				st.spawnCF = spots[(i - 2) % math.max(1, #spots) + 1]
			end
		end
		removeLooseGuns()
		-- close-range weapons all over the map
		for _, spot in MapService.Points("HideWeapon_") do
			local id = pick(Config.HideWeapons)
			if id then
				local cf = CFrame.new(spot.Position) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0) * CFrame.Angles(0, 0, math.rad(90))
				local inst = PropService.Place(id, cf)
				if inst then
					inst:SetAttribute("ModeItem", true)
					table.insert(roundItems, inst)
				end
			end
		end
	elseif mode == "monster" then
		local spots = spawnCFs("ModeSpawn_")
		for i, st in list do
			st.role = "Fighter"
			st.weapon = pick(guns)
			st.spawnCF = spots[(i - 1) % math.max(1, #spots) + 1]
		end
	elseif mode == "zombies" then
		local zSpots, hSpots = spawnCFs("ZombieSpawn_"), spawnCFs("ModeSpawn_")
		-- (v2.0) more players, more zombies among them (a share of the players), plus the extra zombie bots
		local nZ = math.max(1, math.floor(#players * Config.ZombieStart + 0.5))
		if #players == 1 then
			-- alone: you are the human, the bots are the zombies
			for _, st in list do
				st.role = st.isBot and "Zombie" or "Human"
			end
		else
			for i, st in list do
				st.role = (extraSet[st] or i <= nZ) and "Zombie" or "Human"
			end
		end
		local zi, hi = 0, 0
		for _, st in list do
			if st.role == "Zombie" then
				zi += 1
				st.spawnCF = zSpots[(zi - 1) % math.max(1, #zSpots) + 1] or hSpots[1]
			else
				hi += 1
				st.weapon = pick(guns)
				st.spawnCF = hSpots[(hi - 1) % math.max(1, #hSpots) + 1]
			end
		end
	elseif mode == "sniper" then
		-- the sniper: one of the players (the list starts with them, shuffled); everybody else runs
		local runSpots = spawnCFs("RunnerSpawn_")
		local towerSpots = MapService.Points("SniperSpawn_")
		local runMid = Vector3.zero
		for _, cf in runSpots do
			runMid += cf.Position / #runSpots
		end
		for i, st in list do
			if i == 1 then
				st.role = "Sniper"
				st.weapon = "sniper"
				local tp = towerSpots[1]
				if tp then
					local to = Vector3.new(runMid.X - tp.Position.X, 0, runMid.Z - tp.Position.Z)
					st.spawnCF = (#runSpots > 0 and to.Magnitude > 1) and CFrame.lookAt(tp.Position, tp.Position + to.Unit) or CFrame.new(tp.Position)
				end
			else
				st.role = "Runner"
				st.weapon = pick(Config.SniperRunnerWeapons)
				st.spawnCF = runSpots[(i - 2) % math.max(1, #runSpots) + 1]
			end
		end
		removeLooseGuns()
	elseif mode == "hotpotato" then
		local spots = spawnCFs("ModeSpawn_")
		for i, st in list do
			st.spawnCF = spots[(i - 1) % math.max(1, #spots) + 1]
		end
		removeLooseGuns()
		potato.nextAt = now() + 6 -- (everybody gets a moment to spread out)
	elseif mode == "koth" then
		local spots = spawnCFs("ModeSpawn_")
		for i, st in list do
			st.weapon = pick(guns)
			st.spawnCF = spots[(i - 1) % math.max(1, #spots) + 1]
		end
		lastHillTick = 0
		moveHill()
	end
	phase = mode == "hideseek" and "hiding" or "playing"
	local roundTime = Config.ModeRoundTime
	if mode == "hideseek" then
		roundTime = Config.HideTime
	elseif mode == "monster" then
		roundTime = Config.MonsterRoundTime
	elseif mode == "zombies" then
		roundTime = Config.ZombieRoundTime
	elseif mode == "gungame" then
		roundTime = Config.GunGameRoundTime
	elseif mode == "sniper" then
		roundTime = Config.SniperRoundTime
	elseif mode == "hotpotato" then
		roundTime = Config.PotatoRoundTime
	elseif mode == "koth" then
		roundTime = Config.HillRoundTime
	end
	endsAt = now() + roundTime
	-- the bots' bodies
	for _, st in botStates do
		spawnBotBody(st, (st.spawnCF or anySpawn()) + Vector3.new(0, 0.3, 0))
	end
	if mode == "monster" then
		MapFeatureService.ModeMonster = true
		CreatureService.RemoveWhere(function(c)
			return c.kind == "crawler"
		end)
		monster = MapFeatureService.SpawnCrawler(true, Config.MonsterHP + Config.MonsterHPPerPlayer * math.max(1, startedWith))
	end
	publish()
	for _, p in players do
		task.spawn(respawnFresh, p)
	end
	local title = GameModeService.MODES[mode] or mode
	local mapDef = MapService.Def(MapService.Current())
	local where = mapDef and ("  -  " .. mapDef.label) or ""
	if mode == "teamfight" then
		for p, st in states do
			if not st.isBot then
				banner(string.format("ROUND %d - YOU ARE %s", round, string.upper(st.team or "")), st.team == "Red" and RED or BLUE, { p })
			end
		end
	elseif mode == "hideseek" then
		for p, st in states do
			if st.isBot then
				continue
			end
			if st.role == "Seeker" then
				banner(string.format("YOU SEEK! WAIT %d SECONDS", Config.HideTime), RED, { p })
			else
				banner("HIDE! THE SEEKER COMES IN " .. Config.HideTime .. " SECONDS", GREEN, { p })
			end
		end
	elseif mode == "zombies" then
		for p, st in states do
			if not st.isBot then
				banner(st.role == "Zombie" and "YOU ARE A ZOMBIE - BITE THEM (F)" or "SURVIVE! ONLY HEAD SHOTS KILL THEM", st.role == "Zombie" and GREEN or BLUE, { p })
			end
		end
	elseif mode == "monster" then
		banner("THE CRAWLER IS COMING - KILL IT OR SURVIVE" .. where, RED)
	elseif mode == "gungame" then
		banner(string.format("GUN GAME - %d WEAPONS - EVERY KILL IS THE NEXT", #ladder), GOLD)
	elseif mode == "sniper" then
		for p, st in states do
			if not st.isBot then
				if st.role == "Sniper" then
					banner("YOU ARE THE SNIPER - HOLD THE TOWER", RED, { p })
				else
					banner("RUN! KILL THE SNIPER ON THE TOWER", GREEN, { p })
				end
			end
		end
	elseif mode == "hotpotato" then
		banner("HOT POTATO - DO NOT HOLD THE BOMB WHEN IT GOES OFF", GOLD)
	elseif mode == "koth" then
		banner(string.format("KING OF THE HILL - STAND IN THE RING ALONE - %d POINTS WIN", Config.HillTarget), GOLD)
	else
		banner(string.format("%s - ROUND %d - FIGHT!%s", title, round, where), GOLD)
	end
end

-- hide and seek: the hiding time is over, the seeker comes in with a gun
local function releaseSeeker()
	phase = "playing"
	endsAt = now() + Config.HideSeekTime
	local spots = spawnCFs("ModeSpawn_")
	for p, st in states do
		if st.role == "Seeker" and not st.isBot and p.Parent then
			st.alive = true
			st.weapon = pick(Config.ModeGuns)
			st.spawnCF = spots[1]
			task.spawn(respawnFresh, p)
		end
	end
	publish()
	banner("THE SEEKER IS COMING!", RED)
end

endRound = function(text: string, color: Color3?)
	if phase == "ended" then
		return
	end
	phase = "ended"
	endsAt = now() + Config.MapVoteTime
	workspace:SetAttribute("ModeWinner", text)
	-- (v2.8.1) the round's board: everybody's kills (and points on the hill), best first; the best one is the MVP
	local list = {}
	for _, st in states do
		table.insert(list, st)
	end
	table.sort(list, function(a, b)
		local sa, sb = a.kills * 10 + a.points, b.kills * 10 + b.points
		if sa ~= sb then
			return sa > sb
		end
		return a.name < b.name
	end)
	local rows = {}
	for i = 1, math.min(6, #list) do
		local st = list[i]
		local nm = string.gsub(string.upper(st.name), "[=;]", "")
		table.insert(rows, nm .. "=" .. st.kills .. "=" .. st.points .. "=" .. (st.team or "") .. "=" .. (st.isBot and "1" or "0"))
	end
	workspace:SetAttribute("ModeSummary", table.concat(rows, ";"))
	-- (v2.0) the bomb is gone, the ring stops scoring
	dropPotato()
	potato.nextAt = nil
	-- (v2.0) the round is over: the monster goes (it no longer hunts the lobby during the vote)
	if monster then
		CreatureService.Despawn(monster)
		monster = nil
	end
	openMapVote()
	publish()
	banner(text, color)
	local tok = token
	task.delay(Config.MapVoteTime, function()
		if tok == token and mode then
			local winner = closeMapVote()
			if winner and winner ~= MapService.Current() then
				nextMap = winner
				banner("NEXT MAP: " .. (MapService.MAPS[winner] and MapService.MAPS[winner].label or winner), GOLD)
			end
			startRound()
		end
	end)
end

-- (v2.0) the bomb and the ring, every tick of the clock
local function potatoStep()
	if mode ~= "hotpotato" or phase ~= "playing" then
		return
	end
	local t = now()
	local h = potato.holder
	if h and (not h.alive or not bodyOf(h)) then
		-- (gone some other way: off the map, left the game) - a new one comes
		dropPotato()
		potato.nextAt = t + Config.PotatoNextBomb
		h = nil
	end
	if not h then
		if potato.nextAt and t >= potato.nextAt then
			potato.nextAt = nil
			local alive = {}
			for _, st in states do
				if st.alive and bodyOf(st) then
					table.insert(alive, st)
				end
			end
			local who = pick(alive)
			if who and #alive >= (startedWith >= 2 and 2 or 1) then
				givePotato(who, nil)
			end
		end
		return
	end
	-- the fuse
	local left = potato.ends - t
	local m = potato.model
	local bb = m and m.PrimaryPart and m.PrimaryPart:FindFirstChild("Timer")
	local tl = bb and bb:FindFirstChild("Text")
	if tl and tl:IsA("TextLabel") then
		tl.Text = string.format("%.1f", math.max(0, left))
	end
	local face = m and m:FindFirstChild("TimerFace")
	local dg = face and face:FindFirstChild("Digits")
	local dt = dg and dg:FindFirstChild("Text")
	if dt and dt:IsA("TextLabel") then
		dt.Text = string.format("%04.1f", math.max(0, left))
	end
	if t >= potato.beepAt and m and m.PrimaryPart then
		potato.beepAt = t + math.clamp(left / 7, 0.11, 1)
		GoreService.Sound("beep", m.PrimaryPart, left < 4 and 1 or 0.7)
	end
	if left <= 0 then
		blowUp()
		checkWin()
		return
	end
	-- the pass: whoever comes close enough gets it
	if t < potato.lockUntil then
		return
	end
	local except = (t < potato.fromUntil) and potato.from or nil
	local o, d = nearestTo(h, except)
	if o and d <= Config.PotatoTagRange then
		givePotato(o, h)
	end
end

local function hillStep()
	if mode ~= "koth" or phase ~= "playing" or not hill.pos then
		return
	end
	local t = now()
	if t >= hill.movesAt then
		moveHill()
		banner("THE RING MOVED!", GOLD)
		return
	end
	if t - lastHillTick < 1 then
		return
	end
	lastHillTick = t
	local inside = {}
	for _, st in states do
		local torso = torsoOf(st)
		if torso then
			local d = torso.Position - (hill.pos :: Vector3)
			if Vector3.new(d.X, 0, d.Z).Magnitude <= Config.HillRadius and d.Y > -4 and d.Y < 9 then
				table.insert(inside, st)
			end
		end
	end
	hill.contested = #inside > 1
	hill.king = (#inside == 1) and inside[1] or nil
	local k = hill.king
	if k then
		k.points += 1
		if k.points >= Config.HillTarget then
			endRound(string.upper(k.name) .. " IS THE KING OF THE HILL", GOLD)
			return
		end
		if k.points % 10 == 0 then
			bannerTo(k, string.format("%d / %d", k.points, Config.HillTarget), GOLD)
		end
	end
	publish()
end

------------------------------------------------------------------------
-- deaths, kills, bites
------------------------------------------------------------------------

-- the bot / player behind a kill: a player (DamageService's kill credit), or a bot that hurt them a moment ago
local function killerState(killer: Player?, state: any): PState?
	if killer and states[killer] then
		return states[killer]
	end
	local lb = state and state.lastBot
	if lb and os.clock() - lb.t <= Config.KillCreditTime and states[lb.model] then
		return states[lb.model]
	end
	return nil
end

local function tierUp(st: PState)
	st.tier += 1
	if st.tier > #ladder then
		endRound(string.upper(st.name) .. " WINS GUN GAME", GOLD)
		return
	end
	local id = ladder[st.tier]
	if st.bot then
		NPCService.SetWeapon(st.bot, id)
	else
		local p = st.key :: Player
		local c = p.Character
		itemsOf(p)
		if c and not c:GetAttribute("Dead") then
			task.spawn(give, p, c, id, token)
		end
		local def = Items.Kinds[id]
		bannerTo(st, string.format("LEVEL %d/%d: %s", st.tier, #ladder, def and def.name or string.upper(id)), GOLD)
	end
	publish()
end

-- somebody in the round died (a player or a bot)
local function died(st: PState, killedByZombie: boolean)
	if not mode or phase == "ended" then
		return
	end
	if mode == "gungame" then
		-- back in a moment (players: CharacterService respawns them on a mode spawn; bots: here)
		itemsOf(st.key)
		if st.bot then
			local old = st.bot
			task.delay(Config.ModeRespawnTime, function()
				if mode == "gungame" and states[old] == st and phase == "playing" then
					spawnBotBody(st, anySpawn("ModeSpawn_"))
					publish()
				end
			end)
		end
		publish()
		return
	end
	if mode == "koth" or (mode == "sniper" and st.role == "Runner") then
		-- back in a moment (players: CharacterService respawns them; bots: here) - runners at the far end again
		itemsOf(st.key)
		local sniperMode = mode == "sniper"
		st.weapon = sniperMode and pick(Config.SniperRunnerWeapons) or pick(Config.ModeGuns)
		if not st.bot then
			st.spawnCF = sniperMode and pick(spawnCFs("RunnerSpawn_")) or nil
		else
			local old = st.bot
			local wait = sniperMode and Config.SniperRunnerRespawn or Config.ModeRespawnTime
			task.delay(wait, function()
				if mode and states[old] == st and phase == "playing" then
					spawnBotBody(st, anySpawn(sniperMode and "RunnerSpawn_" or "ModeSpawn_"))
					publish()
				end
			end)
		end
		publish()
		return
	end
	if mode == "zombies" then
		if st.role == "Zombie" then
			-- zombies come back
			if st.bot then
				local old = st.bot
				task.delay(Config.ModeRespawnTime + 2, function()
					if mode == "zombies" and states[old] == st and phase == "playing" then
						spawnBotBody(st, anySpawn("ZombieSpawn_"))
						publish()
					end
				end)
			end
			publish()
			return
		end
		if killedByZombie or st.bitten then
			-- they rise again as one of them
			st.role = "Zombie"
			st.bitten = nil
			banner(string.upper(st.name) .. " TURNED INTO A ZOMBIE", GREEN)
			if st.bot then
				local old = st.bot
				task.delay(Config.ModeRespawnTime, function()
					if mode == "zombies" and states[old] == st and phase == "playing" then
						spawnBotBody(st, (old.Parent and old:GetPivot() or anySpawn("ZombieSpawn_")) + Vector3.new(0, 2, 0))
						publish()
					end
				end)
			end
			checkWin()
			publish()
			return
		end
	end
	st.alive = false
	checkWin()
	publish()
end

local function bite(victim: Model)
	if mode ~= "zombies" or phase ~= "playing" then
		return
	end
	local vst = stateOfBody(victim)
	if not vst or not vst.alive or vst.role ~= "Human" or vst.bitten then
		return
	end
	vst.bitten = now() + Config.ZombieBiteTime
	victim:SetAttribute("BittenUntil", vst.bitten)
	bannerTo(vst, string.format("YOU WERE BITTEN!  %d s  -  A HEAL DART CURES YOU", Config.ZombieBiteTime), RED)
	local tok = token
	task.delay(Config.ZombieBiteTime, function()
		if tok == token and mode == "zombies" and vst.bitten and vst.alive and vst.role == "Human" then
			makeZombie(vst)
			checkWin()
		end
	end)
end

------------------------------------------------------------------------

function GameModeService.Mode(): string?
	return mode
end

function GameModeService.Start(newMode: string, voted: boolean?)
	if not GameModeService.MODES[newMode] then
		return
	end
	votedFill = voted == true
	mode = newMode
	round = 0
	startRound()
end

function GameModeService.Stop()
	if not mode then
		return
	end
	mode = nil
	phase = "idle"
	token += 1
	dropPotato()
	potato.nextAt = nil
	clearHill()
	clearItems()
	removeBots()
	removeMonster()
	table.clear(states)
	workspace:SetAttribute("ModeWinner", nil)
	workspace:SetAttribute("MapVote", nil)
	publish()
	banner("GAME OVER - BACK TO THE SANDBOX")
	for _, p in Players:GetPlayers() do
		task.spawn(respawnFresh, p)
	end
end

function GameModeService.SetSpawning(on: boolean)
	spawningAllowed = on
	publish()
end

-- may this player spawn props right now? (the owner always may)
function GameModeService.CanSpawn(player: Player): boolean
	if Items.IsOwner(player) then
		return true
	end
	return mode == nil and spawningAllowed
end

-- no friendly fire, nobody in the lobby hurts or gets hurt
function GameModeService.CanHurt(attacker: Player, victim: Player): boolean
	if not mode or attacker == victim then
		return true
	end
	local a, v = states[attacker], states[victim]
	if not a or not v or not a.alive or not v.alive then
		return false
	end
	if mode == "teamfight" and a.team == v.team then
		return false
	end
	if (mode == "hideseek" or mode == "zombies") and a.role == v.role then
		return false
	end
	if mode == "monster" or mode == "hotpotato" then
		return false -- (all on the same side / only the bomb hurts)
	end
	if mode == "sniper" and a.role == v.role then
		return false -- (runners do not fight each other)
	end
	return true
end

function GameModeService.Init()
	local lobby = workspace:FindFirstChild("Lobby")
	local boardPart = lobby and lobby:FindFirstChild("LobbyBoard")
	if boardPart and boardPart:IsA("BasePart") then
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Board"
		gui.Face = Enum.NormalId.Back
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = boardPart
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromRGB(255, 230, 140)
		label.TextScaled = true
		label.Font = Enum.Font.Sarpanch
		label.Text = "NO GAME RUNNING"
		label.Parent = gui
		board = label
	end

	CharacterService.SpawnOverride = function(player: Player): CFrame?
		if not mode then
			return nil
		end
		local st = states[player]
		if not st or not st.alive then
			return lobbyCF()
		end
		local cf = st.spawnCF
		st.spawnCF = nil
		if cf then
			return cf + Vector3.new(0, 0.2, 0)
		end
		if mode == "zombies" and st.role == "Zombie" then
			return anySpawn("ZombieSpawn_")
		elseif mode == "teamfight" and st.team then
			return anySpawn(st.team == "Red" and "ModeSpawn_Red_" or "ModeSpawn_Blue_")
		end
		return anySpawn("ModeSpawn_")
	end
	CharacterService.OnSpawned = function(player: Player, model: Model)
		local st = states[player]
		if mode and st and st.alive then
			if mode == "zombies" and st.role == "Zombie" then
				zombifyBody(model)
			elseif mode == "gungame" then
				task.spawn(give, player, model, ladder[math.min(st.tier, #ladder)], token)
			elseif st.weapon then
				local id = st.weapon
				st.weapon = nil
				task.spawn(give, player, model, id, token)
			end
		end
		publish()
	end
	CharacterService.OnDied = function(player: Player, model: Model)
		local st = states[player]
		if mode and st and st.alive and phase ~= "ended" then
			local ds = DamageService.Get(model)
			local byZombie = false
			if ds then
				local lb = (ds :: any).lastBot
				if lb and os.clock() - lb.t <= Config.KillCreditTime and lb.model:GetAttribute("Zombie") then
					byZombie = true
				end
				local la = ds.lastAttacker
				if la and os.clock() - la.t <= Config.KillCreditTime and la.player.Character and la.player.Character:GetAttribute("Zombie") then
					byZombie = true
				end
			end
			died(st, byZombie)
		end
	end
	DamageService.CanHurt = GameModeService.CanHurt
	WorldSetup.CanRestock = function(id: string): boolean
		return (mode ~= "hideseek" and mode ~= "sniper" and mode ~= "hotpotato") or not isGunId(id)
	end
	PropService.CanSpawn = GameModeService.CanSpawn
	local prevKill = DamageService.OnKill
	DamageService.OnKill = function(victim: Model, killer: Player?, state)
		if prevKill then
			prevKill(victim, killer, state)
		end
		if not mode or phase ~= "playing" then
			return
		end
		local vst = stateOfBody(victim)
		local kst = killerState(killer, state)
		if kst and vst ~= kst and kst.alive then
			kst.kills += 1
			if mode == "gungame" then
				tierUp(kst)
			end
		end
		-- a bot died (players: CharacterService.OnDied)
		if vst and vst.isBot and vst.bot == victim and vst.alive then
			local byZombie = kst ~= nil and kst.role == "Zombie"
			died(vst, byZombie)
		end
	end
	-- the zombies' bites: a player zombie's punch, a zombie bot's teeth
	KnockService.OnPunch = function(player: Player, body: Model, region: string)
		local c = player.Character
		if c and c:GetAttribute("Zombie") and not body:GetAttribute("Zombie") then
			-- (v2.0) a bite hurts: much more than a punch
			local part = body:FindFirstChild("Torso")
			local point = (part and part:IsA("BasePart")) and part.Position or Vector3.zero
			DamageService.ApplyDamage(body, region == "Head" and "Head" or "Torso", Config.ZombieBiteDamage, point, {
				cause = "Eaten by " .. player.DisplayName,
				allowSever = false,
				attacker = player,
				bleed = 0.9,
				bleedTime = 14,
			})
			GoreService.Sound("zombieBite", point, 1)
			GoreService.Burst(point, Vector3.yAxis, 14, 12)
			bite(body)
		end
	end
	NPCService.OnZombieBite = function(_npc: Model, victim: Model)
		bite(victim)
	end
	-- a heal dart cures a bite
	local prevHeal = DamageService.OnHeal
	DamageService.OnHeal = function(model: Model)
		if prevHeal then
			prevHeal(model)
		end
		local st = stateOfBody(model)
		if st and st.bitten then
			st.bitten = nil
			model:SetAttribute("BittenUntil", nil)
			bannerTo(st, "CURED! THE BITE IS GONE", BLUE)
		end
	end
	-- zombies hold nothing; gun game: only your own gun
	OwnershipService.CanHold = function(player: Player, item: Model): boolean
		local c = player.Character
		if c and c:GetAttribute("Zombie") then
			return false
		end
		if mode == "gungame" and item:GetAttribute("ModeItem") and itemOwner[item] ~= player then
			return false
		end
		-- (v2.0) runners and hot potato players: no guns (nothing that shoots)
		local st = states[player]
		local kind = Items.Kind(item)
		local shoots = kind ~= nil and (Config.Guns[kind] ~= nil or isGunId(kind))
		if shoots and st and ((mode == "sniper" and st.role == "Runner") or mode == "hotpotato") then
			return false
		end
		if mode == "hotpotato" and Items.Melee(item) then
			return false
		end
		return true
	end
	-- bots and creatures: who goes for whom
	NPCService.CanTarget = function(npcModel: Model, target: Model): boolean
		local nst = states[npcModel]
		if not mode or not nst then
			-- a sandbox hostile: players only
			return Players:GetPlayerFromCharacter(target) ~= nil and not target:GetAttribute("Zombie")
		end
		if not nst.alive then
			return false
		end
		if target:GetAttribute("Creature") then
			return mode == "monster" and target == monster
		end
		local tst = stateOfBody(target)
		if not tst or not tst.alive then
			return false
		end
		if mode == "teamfight" then
			return tst.team ~= nst.team
		elseif mode == "zombies" then
			return (tst.role == "Zombie") ~= (nst.role == "Zombie")
		elseif mode == "monster" or mode == "hotpotato" then
			return false
		elseif mode == "sniper" then
			return tst.role ~= nst.role
		end
		return true
	end
	-- (v2.0) where a bot has to be: runners go for the sniper wherever it is, the bomb's holder runs at the closest
	-- one, the others run from it, everybody heads for the ring
	NPCService.ModeGoal = function(npcModel: Model): any
		local st = states[npcModel]
		if not mode or phase ~= "playing" or not st or not st.alive then
			return nil
		end
		if mode == "sniper" and st.role == "Runner" then
			for _, o in states do
				if o.role == "Sniper" then
					local b = bodyOf(o)
					return b and { kind = "chase", target = b } or nil
				end
			end
		elseif mode == "hotpotato" then
			local h = potato.holder
			if h == st then
				local except = (now() < potato.fromUntil) and potato.from or nil
				local o = nearestTo(st, except)
				local b = bodyOf(o)
				return b and { kind = "tag", target = b } or { kind = "idle" }
			elseif h then
				local hb = bodyOf(h)
				return hb and { kind = "flee", from = hb } or { kind = "idle" }
			end
			return { kind = "idle" }
		elseif mode == "koth" and hill.pos then
			return { kind = "goto", pos = hill.pos, radius = Config.HillRadius * 0.55 }
		end
		return nil
	end
	NPCService.ExtraTargets = function(): { Model }
		local list = {}
		for _, st in states do
			if st.bot and st.bot.Parent and st.alive then
				table.insert(list, st.bot)
			end
		end
		if monster and monster.Parent then
			table.insert(list, monster)
		end
		return list
	end
	CreatureService.CanTarget = function(c, m: Model): boolean
		if not mode then
			return not c.mode
		end
		local st = stateOfBody(m)
		return st ~= nil and st.alive
	end
	CreatureService.OnDeath = function(c, _by: Player?)
		if c.mode and mode == "monster" and phase == "playing" and c.model == monster then
			endRound("THE MONSTER IS DEAD - THE FIGHTERS WIN", GREEN)
		end
	end

	ModeRemote.OnServerEvent:Connect(function(player, action, value)
		if action == "mapvote" and phase == "ended" and typeof(value) == "string" and MapService.MAPS[value] then
			mapVotes[player] = value
			publishVotes()
		end
	end)
	Players.PlayerAdded:Connect(function(p)
		if mode then
			local st = newState(p, p.DisplayName, false)
			if mode == "gungame" and phase == "playing" then
				st.alive = true -- (thrown right in)
			elseif mode == "zombies" and phase == "playing" then
				st.alive = true
				st.role = "Zombie"
			elseif mode == "sniper" and phase == "playing" then
				st.alive = true -- (one more runner, from the far end)
				st.role = "Runner"
				st.weapon = pick(Config.SniperRunnerWeapons)
				st.spawnCF = pick(spawnCFs("RunnerSpawn_"))
			elseif mode == "koth" and phase == "playing" then
				st.alive = true
				st.weapon = pick(Config.ModeGuns)
			else
				st.alive = false -- waits in the lobby for the next round
			end
			states[p] = st
		end
		publish()
	end)
	Players.PlayerRemoving:Connect(function(p)
		mapVotes[p] = nil
		if states[p] then
			states[p] = nil
			checkWin()
		end
		publish()
	end)

	-- (v2.0) the bomb and the ring want a faster clock
	task.spawn(function()
		while true do
			task.wait(0.1)
			if mode == "hotpotato" then
				local ok, err = pcall(potatoStep)
				if not ok then
					warn("[Ragdoll] hot potato:", err)
				end
			elseif mode == "koth" then
				local ok, err = pcall(hillStep)
				if not ok then
					warn("[Ragdoll] king of the hill:", err)
				end
			end
		end
	end)
	-- the clock
	task.spawn(function()
		while true do
			task.wait(0.5)
			if mode and now() >= endsAt then
				if phase == "hiding" then
					releaseSeeker()
				elseif phase == "playing" then
					timeUp()
				end
			end
			if mode == "monster" or mode == "gungame" or mode == "hotpotato" or mode == "sniper" then
				publish() -- (the monster's health, the leader, the bomb's fuse)
			end
		end
	end)
	publish()
end

return GameModeService
