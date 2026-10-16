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
local combat_forced = false -- True while music_combat is forced to "None" and not yet restored.
local events_suppressed = false

-- State group name -> true while that group is suppressed and forced again after every real transition.
-- For groups the game sets repeatedly while a context lasts.
local reforced_groups = {}

-- ###########################################################################
-- State Forcing
-- ###########################################################################
-- The forced sets go straight to Wwise and never reach the _set_state hook, so context.lua keeps the game's real values.

-- Forces a state group to "None" once, remembering that it did so restore_group can undo it.
local function force_group_to_none(group_name)
	local real_value = real_states[group_name]

	if forced_groups[group_name] or not real_value or real_value == "None" then
		return
	end

	forced_groups[group_name] = true
	diagnostic_log(string.format("[suppress] forcing %s %s -> None", group_name, real_value))
	Wwise.set_state(group_name, "None")
end

local function restore_group(group_name)
	if not forced_groups[group_name] then
		return
	end

	forced_groups[group_name] = false
	diagnostic_log(string.format("[suppress] restoring %s to %s", group_name, tostring(real_states[group_name])))
	Wwise.set_state(group_name, real_states[group_name] or "None")
end

-- Forces a group to "None" and keeps forcing it after every real transition while on.
local function set_reforced_group(group_name, should_suppress)
	reforced_groups[group_name] = should_suppress or nil

	if should_suppress then
		force_group_to_none(group_name)
	else
		restore_group(group_name)
	end
end

-- ###########################################################################
-- Levers
-- ###########################################################################

-- Forces music_combat back to "None" for as long as it is on.
-- It is forced again after every real transition, since music_combat flaps between states repeatedly without ever settling.
-- Turning it on also forces the current value, otherwise a value set before suppression started plays until the next flap.
-- Turning it off restores the real value.
-- The game only re-sends a state when it changes, so a boss that started while this was on would otherwise stay silent for the whole fight.
function Suppression.set_combat(should_suppress)
	if should_suppress then
		if not combat_suppressed then
			diagnostic_log("[suppress] forcing music_combat to None while a custom track plays")
		end

		combat_suppressed = true

		local real_value = real_states.music_combat

		if real_value and real_value ~= "None" then
			combat_forced = true
			Wwise.set_state("music_combat", "None")
		end

		return
	end

	combat_suppressed = false

	if combat_forced then
		combat_forced = false

		local real_value = real_states.music_combat or "None"

		diagnostic_log(string.format("[suppress] restoring music_combat to %s", real_value))
		Wwise.set_state("music_combat", real_value)
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
-- The game sets this state repeatedly through a mission's end, so it is forced again after every real transition while on.
function Suppression.set_game_state(should_suppress)
	set_reforced_group("music_game_state", should_suppress)
end

-- Forces music_objective to "None" so the game's own last stand or event music stops.
-- It is engaged only for the last stand, event and Mortis Trials wave contexts, which are the ones this group decides.
-- The game sets this group repeatedly, so it is forced again after every real transition while on.
function Suppression.set_objective(should_suppress)
	set_reforced_group("music_objective", should_suppress)
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
			combat_forced = true
			Wwise.set_state("music_combat", "None")
		elseif new_state == "None" then
			combat_forced = false -- Wwise already matches the real value.
		end
	elseif group_name == "music_zone" then
		forced_groups.music_zone = false -- The game just set a real zone, which replaces any forced value.
	elseif reforced_groups[group_name] and new_state ~= "None" then
		forced_groups[group_name] = true
		Wwise.set_state(group_name, "None")
	else
		forced_groups[group_name] = false -- The game just set a real state, which replaces any forced value.
	end
end

-- Turns on the levers for a context that has a custom track available, or that is set to silence.
-- Combat and event suppression apply to every context.
-- The hub, the victory and defeat contexts, and the last stand, event and Mortis Trials wave contexts each need one more.
function Suppression.engage(context_name)
	Suppression.set_combat(true)
	Suppression.set_events(true)
	Suppression.set_zone(context_name == "hub")
	Suppression.set_game_state(context_name == "mission_victory" or context_name == "mission_defeat")
	Suppression.set_objective(context_name == "mission_last_stand" or context_name == "mission_event" or context_name == "mortis_trials_wave")
end

-- Turns every lever off, for no context or a context with no custom track.
function Suppression.release()
	Suppression.set_combat(false)
	Suppression.set_zone(false)
	Suppression.set_game_state(false)
	Suppression.set_objective(false)
	Suppression.set_events(false)
end

return Suppression
