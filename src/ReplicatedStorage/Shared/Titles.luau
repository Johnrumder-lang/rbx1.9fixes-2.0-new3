--!nonstrict
-- Titles (v2.0): what can be shown over your head (equip one in the menu: M > INVENTORY).
-- RewardService (server) hands them out, TitleClient draws them. Where they come from:
--   code     : a code typed in the menu (M > CODES)
--   kills    : players you killed in total (the Tab list "Kills"), at Titles.KillSteps
--   playtime : hours played in total, at Titles.HourSteps
--   quest    : the Steel Ball Master's questline (the Spin)
--   owner    : the game's owner
--   gift     : (v2.1) given by the owner / admins (M > GIFTS): content creator, sigma, evil, good
-- Every title has its own colour; the rare ones are animated:
--   plain   : the colour, dark outline
--   glow    : the outline glows in the colour and pulses
--   shine   : a bright stripe runs over the letters (gold)
--   rainbow : the colours run through the letters
--   aurora  : cyan, violet and pink drift through the letters
--   void    : dark letters with a burning red outline

local Titles = {}

export type Title = {
	id: string,
	name: string,
	color: Color3,
	color2: Color3?, -- second colour (shine / glow)
	style: string, -- "plain" | "glow" | "shine" | "rainbow" | "aurora" | "void"
	source: string, -- "code" | "kills" | "playtime" | "quest" | "owner"
	need: number?, -- kills / hours
	how: string, -- shown on a locked title
	hidden: boolean?, -- not listed until you have it
	order: number?,
}

local function c(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Titles.List = {
	{ id = "dev", name = "DEV", color = c(255, 255, 255), color2 = c(255, 50, 50), style = "glow", source = "owner", how = "The game's owner", hidden = true },
	{ id = "og", name = "OG", color = c(255, 200, 40), color2 = c(255, 250, 210), style = "shine", source = "code", how = "Retired update 2.0 reward" },
	{ id = "spin", name = "SPIN ADEPT", color = c(70, 230, 120), color2 = c(255, 214, 70), style = "glow", source = "quest", how = "Learn the Spin from the Steel Ball Master" },
	{ id = "stillwater", name = "STILLWATER", color = c(150, 210, 255), color2 = c(255, 255, 255), style = "glow", source = "quest", how = "Beat the Pale Heir in the Pit" }, -- (v2.8)

	-- (v2.1) gift titles: the owner gives them in M > GIFTS, they stay until the owner takes them back
	{ id = "creator", name = "CONTENT CREATOR", color = c(255, 70, 70), color2 = c(255, 255, 255), style = "glow", source = "gift", how = "Given by the owner", hidden = true },
	{ id = "sigma", name = "SIGMA", color = c(176, 190, 214), color2 = c(255, 255, 255), style = "shine", source = "gift", how = "Given by the owner", hidden = true },
	{ id = "evil", name = "EVIL", color = c(22, 14, 18), color2 = c(255, 30, 30), style = "void", source = "gift", how = "Given by the owner", hidden = true },
	{ id = "good", name = "GOOD", color = c(255, 238, 160), color2 = c(255, 255, 255), style = "aurora", source = "gift", how = "Given by the owner", hidden = true },

	{ id = "kills_10", name = "BRAWLER", color = c(210, 145, 95), style = "plain", source = "kills", need = 10, how = "10 kills" },
	{ id = "kills_100", name = "HUNTER", color = c(90, 190, 255), style = "plain", source = "kills", need = 100, how = "100 kills" },
	{ id = "kills_500", name = "EXECUTIONER", color = c(255, 130, 40), style = "plain", source = "kills", need = 500, how = "500 kills" },
	{ id = "kills_1000", name = "WARLORD", color = c(230, 40, 40), color2 = c(255, 120, 90), style = "glow", source = "kills", need = 1000, how = "1,000 kills" },
	{ id = "kills_2500", name = "REAPER", color = c(160, 70, 235), color2 = c(220, 170, 255), style = "glow", source = "kills", need = 2500, how = "2,500 kills" },
	{ id = "kills_5000", name = "DEATH ITSELF", color = c(24, 20, 22), color2 = c(255, 40, 30), style = "void", source = "kills", need = 5000, how = "5,000 kills" },
	{ id = "kills_10000", name = "GOD OF RAGDOLLS", color = c(255, 255, 255), style = "rainbow", source = "kills", need = 10000, how = "10,000 kills" },

	{ id = "time_5", name = "REGULAR", color = c(120, 220, 140), style = "plain", source = "playtime", need = 5, how = "Play 5 hours" },
	{ id = "time_24", name = "ADDICTED", color = c(255, 130, 200), style = "plain", source = "playtime", need = 24, how = "Play 24 hours" },
	{ id = "time_50", name = "VETERAN", color = c(40, 205, 185), style = "plain", source = "playtime", need = 50, how = "Play 50 hours" },
	{ id = "time_100", name = "TOUCH GRASS", color = c(195, 245, 70), color2 = c(50, 130, 40), style = "glow", source = "playtime", need = 100, how = "Play 100 hours" },
	{ id = "time_250", name = "LIVES HERE", color = c(255, 228, 95), color2 = c(255, 140, 30), style = "glow", source = "playtime", need = 250, how = "Play 250 hours" },
	{ id = "time_500", name = "LEGEND", color = c(212, 224, 240), color2 = c(255, 255, 255), style = "shine", source = "playtime", need = 500, how = "Play 500 hours" },
	{ id = "time_1000", name = "ETERNAL", color = c(120, 230, 255), style = "aurora", source = "playtime", need = 1000, how = "Play 1,000 hours" },
} :: { Title }

Titles.ById = {} :: { [string]: Title }
for i, t in Titles.List do
	t.order = i
	Titles.ById[t.id] = t
end

Titles.KillSteps = {} :: { Title }
Titles.HourSteps = {} :: { Title }
for _, t in Titles.List do
	if t.source == "kills" then
		table.insert(Titles.KillSteps, t)
	elseif t.source == "playtime" then
		table.insert(Titles.HourSteps, t)
	end
end

-- "og,kills_10" <-> { og = true, kills_10 = true } (the owned titles travel as one player attribute)
function Titles.Decode(s: any): { [string]: boolean }
	local out = {}
	if typeof(s) == "string" then
		for id in string.gmatch(s, "[%w_]+") do
			if Titles.ById[id] then
				out[id] = true
			end
		end
	end
	return out
end

function Titles.Encode(set: { [string]: boolean }): string
	local list = {}
	for _, t in Titles.List do
		if set[t.id] then
			table.insert(list, t.id)
		end
	end
	return table.concat(list, ",")
end

-- the titles a number of kills / hours has earned
function Titles.Earned(source: string, amount: number): { string }
	local out = {}
	for _, t in (source == "kills" and Titles.KillSteps or Titles.HourSteps) do
		if amount >= (t.need :: number) then
			table.insert(out, t.id)
		end
	end
	return out
end

return Titles
