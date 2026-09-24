-- Silences the game's own music while a custom track plays.
-- Native music comes from Wwise state groups and from Wwise events, and each source has its own lever below.
-- See docs/wwise-events.md for how each lever was found and how well it is confirmed.
-- Knows nothing about audio files or playback, only which native sources to silence for a context.

local Suppression = {}

-- Native music that starts from a Wwise event instead of a state.
-- Plain substrings, matched against the full event name.
local SUPPRESSED_MUSIC_EVENT_PATTERNS = { "events/music/play_exploration" }

local diagnostic_log = function() end -- No-op unless a real logger is passed to Suppression.init.

local real_states = {} -- State group name -> the last value the game set, fed by Suppression.on_state_change.
local forced_groups = {} -- State group name -> true while that group is forced to "None" and not yet restored.

local combat_suppressed = false
local game_state_suppressed = false
local events_suppressed = false

-- ###########################################################################
-- State Forcing
-- ###########################################################################
-- The forced sets go straight to Wwise and never reach the _set_state hook, so context.lua keeps the game's real values.

-- Forces a state group to "None" once, remembering that it did so restore_group can undo it.
-- Does nothing if the group is already forced or has no real value to replace.
local function force_group_to_none(group_name)
	local real_value = real_states[group_name]

	if forced_groups[group_name] or not real_value or real_value == "None" then
		return
	end

	forced_groups[group_name] = true
	diagnostic_log(string.format("[suppress] forcing %s %s -> None", group_name, real_value))
	Wwise.set_state(group_name, "None")
end

-- Puts a group forced by force_group_to_none back to its real value.
local function restore_group(group_name)
	if not forced_groups[group_name] then
		return
	end

	forced_groups[group_name] = false
	diagnostic_log(string.format("[suppress] restoring %s to %s", group_name, tostring(real_states[group_name])))
	Wwise.set_state(group_name, real_states[group_name] or "None")
end

-- ###########################################################################
-- Levers
-- ###########################################################################

-- Forces music_combat back to "None" for as long as it is on.
-- It is forced again after every real transition, since music_combat flaps between states repeatedly without ever settling.
-- Turning it on also forces the current value, otherwise a value set before suppression started plays until the next flap.
function Suppression.set_combat(should_suppress)
	combat_suppressed = should_suppress

	local real_value = real_states.music_combat

	if should_suppress and real_value and real_value ~= "None" then
		Wwise.set_state("music_combat", "None")
	end
end

-- Forces music_zone to "None" so the native hub music stops.
-- The hub does not run on music_combat, so set_combat has no effect there.
-- The game only re-sends music_zone when it changes, so the forced value stays until the next real zone change.
-- Turning it off restores the real zone, otherwise native hub music would stay silent after the custom track stops.
function Suppression.set_zone(should_suppress)
	if should_suppress then
		force_group_to_none("music_zone")
	else
		restore_group("music_zone")
	end
end

-- Forces music_game_state to "None" so the game's own victory and defeat music stops.
-- Whether this silences it is not yet confirmed.
-- The game sets this state repeatedly through a mission's end, so it is forced again after every real transition while on.
-- Turning it off restores the real state.
function Suppression.set_game_state(should_suppress)
	game_state_suppressed = should_suppress

	if should_suppress then
		force_group_to_none("music_game_state")
	else
		restore_group("music_game_state")
	end
end

-- Drops native music events that match SUPPRESSED_MUSIC_EVENT_PATTERNS instead of letting them play.
-- Mission event sequences start their own music through events, which the state forcing never reaches.
-- Only the start of an event is dropped, so there is nothing native left to stop later.
function Suppression.set_events(should_suppress)
	events_suppressed = should_suppress
end

-- ###########################################################################
-- Public API
-- ###########################################################################

-- Call once from the main mod file's top level.
-- `log`, if given, receives a line each time a lever forces, restores or drops something.
function Suppression.init(log)
	diagnostic_log = log or diagnostic_log
end

-- Called for every Wwise event, from the single trigger_resource_event hook in MusicReplacer.lua.
-- Returns true if the caller should drop the event instead of letting it play.
-- A mod can only install one hook per method on itself, so this does not hook anything on its own.
-- See MusicReplacer.lua for why this and EventProbe share one hook.
function Suppression.should_drop_event(event_name)
	if not events_suppressed or type(event_name) ~= "string" then
		return false
	end

	for _, pattern in ipairs(SUPPRESSED_MUSIC_EVENT_PATTERNS) do
		if event_name:find(pattern, 1, true) then
			diagnostic_log(string.format("[suppress] skipped native music event: %s", event_name))
			return true
		end
	end

	return false
end

-- Register with Context.on_state_change so the levers see every real transition.
-- Keeps the last real value of each group, and forces or releases a group again when the game replaces it.
function Suppression.on_state_change(group_name, new_state)
	real_states[group_name] = new_state

	if group_name == "music_combat" then
		if combat_suppressed and new_state ~= "None" then
			Wwise.set_state("music_combat", "None")
		end
	elseif group_name == "music_zone" then
		forced_groups.music_zone = false -- The game just set a real zone, which replaces any forced value.
	elseif group_name == "music_game_state" then
		if game_state_suppressed and new_state ~= "None" then
			forced_groups.music_game_state = true
			Wwise.set_state("music_game_state", "None")
		else
			forced_groups.music_game_state = false -- The game just set a real state, which replaces any forced value.
		end
	end
end

-- Turns on the levers for a context that has a custom track confirmed playing.
-- Combat and event suppression apply to every context. The hub and the victory and defeat contexts each need one more.
function Suppression.engage(context_name)
	Suppression.set_combat(true)
	Suppression.set_events(true)
	Suppression.set_zone(context_name == "hub")
	Suppression.set_game_state(context_name == "mission_victory" or context_name == "mission_defeat")
end

-- Turns every lever off, for no context or a context with no custom track.
function Suppression.release()
	Suppression.set_combat(false)
	Suppression.set_zone(false)
	Suppression.set_game_state(false)
	Suppression.set_events(false)
end

return Suppression
