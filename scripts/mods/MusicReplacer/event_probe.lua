-- Logging-only probe for Wwise events.
-- It never changes or silences anything.
-- Useful for finding the events behind a sound, or for spotting new, missing or renamed events after a game or Audio Plugin update.

local EventProbe = {}

-- Event name fragments to log under a separate tag instead of the plain one.
-- Empty until logged evidence shows what is worth filtering.
local NOISE_PATTERNS = {}

local seen_events = {}

local function is_noise(event_name)
	for _, pattern in ipairs(NOISE_PATTERNS) do
		if event_name:find(pattern, 1, true) then
			return true
		end
	end

	return false
end

-- Hooks WwiseWorld.trigger_resource_event, the same call the Audio Plugin hooks for its own event logging.
-- Music events are logged every time they fire. Any other event is logged only the first time its name is seen.
-- Call from on_all_mods_loaded, since the Audio Plugin also waits until then to hook it.
function EventProbe.init(mod, log)
	mod:hook(CLASS.WwiseWorld, "trigger_resource_event", function(func, wwise_world, event_name, ...)
		if type(event_name) == "string" then
			if event_name:find("music", 1, true) then
				log(string.format("[probe] music event: %s (extra args: %d)", event_name, select("#", ...)))
			elseif not seen_events[event_name] then
				seen_events[event_name] = true
				log(string.format("[probe] %s: %s", is_noise(event_name) and "new noise event" or "new event", event_name))
			end
		end

		return func(wwise_world, event_name, ...)
	end)
end

return EventProbe
