-- Logs the game's Wwise events, and never changes or silences anything.
-- It finds the events behind a sound, and spots new, missing or renamed events after a game update.

local EventProbe = {}

-- Events whose names contain any of these are left out of the log, since they fire too often.
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
local log_detail = function() end -- It does nothing unless EventProbe.init is given a real logger.

local function is_noise(event_name)
	for _, pattern in ipairs(NOISE_PATTERNS) do
		if event_name:find(pattern, 1, true) then
			return true
		end
	end

	return false
end

-- Minion sounds are noise, except right after a boss appears or picks a target, when they can name what the player hears then.
local MINION_EVENTS = "events/minions/"
local minion_reveal_seconds = 0
local revealed_minion_events = {} -- Event name -> true for each one logged in the current reveal.

-- Call once from the main mod file's top level.
function EventProbe.init(detail_logger)
	log_detail = detail_logger or log_detail
end

-- Logs each minion event once for the next `seconds`, which BossProbe asks for around a boss's arrival.
function EventProbe.reveal_minion_events(seconds)
	if minion_reveal_seconds <= 0 then
		revealed_minion_events = {}
	end
	minion_reveal_seconds = math.max(minion_reveal_seconds, seconds)
end

-- Call every update, so a reveal ends.
function EventProbe.update(dt)
	if minion_reveal_seconds > 0 then
		minion_reveal_seconds = minion_reveal_seconds - dt
	end
end

-- The single trigger_resource_event hook in MusicReplacer.lua calls this for every Wwise event.
function EventProbe.observe(event_name, extra_arg_count)
	if type(event_name) ~= "string" then
		return
	end

	if event_name:find("music", 1, true) then
		log_detail(string.format("[probe] music event: %s (extra args: %d)", event_name, extra_arg_count))
	elseif minion_reveal_seconds > 0 and event_name:find(MINION_EVENTS, 1, true) and not revealed_minion_events[event_name] then
		revealed_minion_events[event_name] = true
		seen_events[event_name] = true
		log_detail(string.format("[probe] minion event near a boss: %s", event_name))
	elseif not seen_events[event_name] then
		seen_events[event_name] = true
		if not is_noise(event_name) then
			log_detail(string.format("[probe] new event: %s", event_name))
		end
	end
end

return EventProbe
