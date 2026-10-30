--!strict
-- SaveGate (v2.8): private servers save NOTHING. Whatever is earned or given there (kills, play time, titles, dollars,
-- skins, cyberware, quests, admin gifts) lasts for that session only and never reaches a public server. Players
-- still bring their public progress INTO a private server (it is loaded, just never written back). Settings (keys,
-- sizes) are preferences, not progress: they are saved everywhere.

local SaveGate = {}

function SaveGate.Private(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0
end

-- may progress be written to a DataStore on this server?
function SaveGate.CanSave(): boolean
	return not SaveGate.Private()
end

return SaveGate
