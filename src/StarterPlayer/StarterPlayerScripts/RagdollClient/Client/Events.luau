--!nonstrict
-- Events (v2.0): server messages (FX remote) that the blood / effects code does not know itself go here.
-- Any client module registers a handler: Events.On("tased", function(payload) ... end).

local Events = {}

local handlers: { [string]: { (any) -> () } } = {}

function Events.On(t: string, fn: (any) -> ())
	handlers[t] = handlers[t] or {}
	table.insert(handlers[t], fn)
end

function Events.Dispatch(t: string, payload: any)
	local list = handlers[t]
	if not list then
		return
	end
	for _, fn in list do
		task.spawn(fn, payload)
	end
end

return Events
