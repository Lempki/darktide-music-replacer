-- Logging-only probe for Wwise events.
-- It never changes or silences anything.
-- Useful for finding the events behind a sound.
-- Also useful for spotting new, missing or renamed events after a game update.

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

-- Every event name seen once, noise included, so a repeated event is never matched against the patterns again.
local seen_events = {}
local log_detail = function() end -- No-op unless a real logger is passed to EventProbe.init.

local function is_noise(event_name)
	for _, pattern in ipairs(NOISE_PATTERNS) do
		if event_name:find(pattern, 1, true) then
			return true
		end
	end

	return false
end

-- Call once from the main mod file's top level.
function EventProbe.init(detail_logger)
	log_detail = detail_logger or log_detail
end

-- Called for every Wwise event, from the single trigger_resource_event hook in MusicReplacer.lua.
-- A mod can only install one hook per method on itself, so this does not hook anything on its own.
function EventProbe.observe(event_name, extra_arg_count)
	if type(event_name) ~= "string" then
		return
	end

	if event_name:find("music", 1, true) then
		log_detail(string.format("[probe] music event: %s (extra args: %d)", event_name, extra_arg_count))
	elseif not seen_events[event_name] then
		seen_events[event_name] = true
		if not is_noise(event_name) then
			log_detail(string.format("[probe] new event: %s", event_name))
		end
	end
end

return EventProbe
