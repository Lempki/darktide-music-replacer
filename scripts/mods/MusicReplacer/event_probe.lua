-- Logging-only probe for Wwise events.
-- It never changes or silences anything.
-- Useful for finding the events behind a sound, or for spotting new, missing or renamed events after a game or Audio Plugin update.

local EventProbe = {}

-- Event name fragments to leave out of the log.
-- Music events are still logged if they ever appear under any of these.
-- See docs/wwise-events.md for what each folder held and why it is left out.
local NOISE_PATTERNS = {
	"events/minions/",
	"events/weapon/",
	"events/player/",
	"events/world/",
	"events/ui/play_hud_",
	"events/ui/play_smart_tag",
	"events/ui/play_ui_mouseover",
	"events/ui/play_ui_click",
	"events/ui/play_ui_enter",
	"events/ui/play_ui_back",
	"events/ui/play_ui_popup_",
	"events/ui/play_ui_mission_",
	"events/ui/play_ui_npc_interacts",
	"events/ui/play_ui_character_loadout",
}

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
-- Music events are logged every time they fire. Any other event is logged only the first time its name is seen, unless it matches NOISE_PATTERNS.
-- Call from on_all_mods_loaded, since the Audio Plugin also waits until then to hook it.
function EventProbe.init(mod, log)
	mod:hook(CLASS.WwiseWorld, "trigger_resource_event", function(func, wwise_world, event_name, ...)
		if type(event_name) == "string" then
			if event_name:find("music", 1, true) then
				log(string.format("[probe] music event: %s (extra args: %d)", event_name, select("#", ...)))
			elseif not seen_events[event_name] and not is_noise(event_name) then
				seen_events[event_name] = true
				log(string.format("[probe] new event: %s", event_name))
			end
		end

		return func(wwise_world, event_name, ...)
	end)
end

return EventProbe
