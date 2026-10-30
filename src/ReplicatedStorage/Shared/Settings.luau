--!nonstrict
-- Settings: what every player can switch for himself in the menu (M). The client keeps the values
-- and every effect asks Settings.Get(...) before it draws; the server only stores them
-- (SettingsService) so they come back next time.

local Settings = {}

export type Def = { key: string, label: string, kind: string, default: any, min: number?, max: number?, step: number?, hidden: boolean?, requires: string? }

-- (order = order in the menu)
Settings.List = {
	{ key = "blood", label = "Blood (drops, splats, pools)", kind = "bool", default = true },
	{ key = "gore", label = "Gore (wounds, bones, gibs)", kind = "bool", default = true },
	{ key = "vfx", label = "Big effects (smoke, fire, shards)", kind = "bool", default = true },
	{ key = "shake", label = "Camera shake", kind = "bool", default = true },
	{ key = "hurtflash", label = "Red flash when hurt", kind = "bool", default = true },
	{ key = "post", label = "Bloom / sun rays / colour", kind = "bool", default = true },
	{ key = "shadows", label = "Shadows", kind = "bool", default = true },
	{ key = "hallucinations", label = "Hallucinations (virus)", kind = "bool", default = true },
	{ key = "tracers", label = "Bullet tracers", kind = "bool", default = true },
	{ key = "volume", label = "Volume", kind = "number", default = 1, min = 0, max = 1, step = 0.1 },
	{ key = "fov", label = "Field of view", kind = "number", default = 72, min = 50, max = 110, step = 5 },
	{ key = "uiScale", label = "UI size", kind = "number", default = 1, min = 0.6, max = 1.6, step = 0.1 }, -- (v2.0)
	{ key = "boombox", label = "Boombox music (other people's)", kind = "bool", default = true },
	{ key = "experimental", label = "Experimental lighting", kind = "bool", default = false },
	{ key = "hideCrosshair", label = "Hide crosshair", kind = "bool", default = false },
	{ key = "hideStatus", label = "Hide body status panel", kind = "bool", default = false },
	{ key = "hideAmmo", label = "Hide ammo / hand panel", kind = "bool", default = false },
	{ key = "hideHints", label = "Hide key hints", kind = "bool", default = false },
	{ key = "hideAll", label = "Hide the whole HUD", kind = "bool", default = false },
	-- (only shows for a player who has the Wonder spec: the owner, or somebody the owner gave it to)
	{ key = "wonder", label = "Calamity spec (Wonder)", kind = "bool", default = false, requires = "wonder" },
	{ key = "grabOutline", label = "White outline on things you can grab", kind = "bool", default = true }, -- (v2.8)
	{ key = "cyberHud", label = "Cyberware bar (implant keys)", kind = "bool", default = true }, -- (v2.8)
	-- (v2.8.1) dying: the screen is black at once (no death screen, no camera on your body); back alive it fades in
	{ key = "realisticDeath", label = "Realistic death (black screen)", kind = "bool", default = false },
	-- (v2.8.2) WARDEN OPTICS: in first person you look through the red lenses (a red shade); off = a clear view
	{ key = "opticsShade", label = "Red optics shade (first person)", kind = "bool", default = true },
	{ key = "tutorialDone", label = "Tutorial done", kind = "bool", default = false, hidden = true },
	-- (v2.8) the keys of the cyber bar, slot 1-9 (M > CYBER: click a slot, press a key): KeyCode names
	{ key = "cyberKeys", label = "Cyber keys", kind = "string", default = "One,Two,Three,Four,Five,Six,Seven,Eight,Nine", max = 200, hidden = true },
	{ key = "keyBinds", label = "Keys", kind = "string", default = "", max = 400, hidden = true }, -- (v2.8) M > SETTINGS > KEYS (Input.ApplyBinds)
	-- the layout of the touch buttons the player dragged around (no row in the menu): "Name=x,y;Name=x,y"
	{ key = "mobileLayout", label = "Touch button layout", kind = "string", default = "", max = 900, hidden = true },
} :: { Def }

Settings.ByKey = {} :: { [string]: Def }
for _, d in Settings.List do
	Settings.ByKey[d.key] = d
end

local values: { [string]: any } = {}
for _, d in Settings.List do
	values[d.key] = d.default
end

-- Settings.Changed:Connect(function(key, value) ... end)
local listeners: { (string, any) -> () } = {}
Settings.Changed = {
	Connect = function(_self, fn: (string, any) -> ())
		table.insert(listeners, fn)
	end,
}

-- only known keys with the right type (numbers clamped): what the server stores
function Settings.Clean(data: { [any]: any }): { [string]: any }
	local out = {}
	for _, d in Settings.List do
		local v = data[d.key]
		if d.kind == "bool" and typeof(v) == "boolean" then
			out[d.key] = v
		elseif d.kind == "string" and typeof(v) == "string" and #v <= (d.max or 400) then
			out[d.key] = v
		elseif d.kind == "number" and typeof(v) == "number" and v == v then
			out[d.key] = math.clamp(v, d.min or -math.huge, d.max or math.huge)
		end
	end
	return out
end

function Settings.Get(key: string): any
	return values[key]
end

function Settings.Set(key: string, value: any)
	local d = Settings.ByKey[key]
	if not d then
		return
	end
	local clean = Settings.Clean({ [key] = value })[key]
	if clean == nil or values[key] == clean then
		return
	end
	values[key] = clean
	for _, fn in listeners do
		task.spawn(fn, key, clean)
	end
end

function Settings.SetAll(data: { [string]: any })
	for k, v in Settings.Clean(data) do
		Settings.Set(k, v)
	end
end

function Settings.All(): { [string]: any }
	return table.clone(values)
end

return Settings
