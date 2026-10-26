-- Silences the game's own music while a custom track plays.
-- The game's music comes from Wwise state groups and from Wwise events, and each source has its own lever below.
-- See docs/wwise-events.md for what each lever silences.
-- It knows nothing about audio files or playback, only which of the game's sources to silence for a context.

local Suppression = {}

local Contexts = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/contexts")

-- The game's music that starts from a Wwise event instead of a state.
-- Each is a plain substring, matched against the full event name.
local SUPPRESSED_MUSIC_EVENT_PATTERNS = { "events/music/play_exploration" }

-- A cutscene starts its own music through an event whose name has both of these, such as play_cs03_music_116bpm.
-- That music can run on after the cutscene ends, under the custom song that takes over then.
local CUTSCENE_EVENT_PREFIX = "events/cinematics/"
local CUTSCENE_MUSIC_WORD = "music"

-- At most this many cutscene music events are remembered, the newest ones, since a level only has a few cutscenes.
local MAX_CUTSCENE_EVENTS = 8

local log_detail = function() end -- It does nothing unless Suppression.init is given a real logger.

local real_states = {} -- State group name -> the last value the game set, fed by Suppression.on_state_change.
local forced_groups = {} -- State group name -> true while that group is forced to "None" and not yet restored.

local events_suppressed = false

-- Cutscene music events that started since the last loading screen, each { world, playing_id, name }, to stop once a custom song plays.
local cutscene_events = {}

-- State group name -> true while that group is suppressed and forced again after every real transition.
-- It is for groups the game changes repeatedly while a context lasts.
local reforced_groups = {}

-- ###########################################################################
-- State Forcing
-- ###########################################################################
-- The forced sets go straight to Wwise and never reach the _set_state hook, so context.lua keeps the game's real values.
-- The game calls _set_state for every group on every tick, but passes a state on to Wwise only when it changes.
-- So a state forced here stays forced until the game's next real change of that group.

-- Forces a state group to "None" once, and remembers that it did, so restore_group can undo it.
local function force_group_to_none(group_name)
	local real_value = real_states[group_name]

	if forced_groups[group_name] or not real_value or real_value == "None" then
		return
	end

	forced_groups[group_name] = true
	log_detail(string.format("[suppress] forcing %s %s -> None", group_name, real_value))
	Wwise.set_state(group_name, "None")
end

local function restore_group(group_name)
	if not forced_groups[group_name] then
		return
	end

	forced_groups[group_name] = false
	log_detail(string.format("[suppress] restoring %s to %s", group_name, tostring(real_states[group_name])))
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
-- Without that, a boss that started while this was on would stay silent, since the game sends "boss" to Wwise only when it changes.
-- expeditions_intensity always holds the same value as music_combat, and the game's Expedition music may follow either.
local function set_combat(should_suppress)
	set_reforced_group("music_combat", should_suppress)
	set_reforced_group("expeditions_intensity", should_suppress)
end

-- Forces music_zone to "None" so the game's hub music stops.
-- The hub does not run on music_combat, so the combat lever has no effect there.
-- Unlike the reforced groups, it is forced only once, and the forced value stays until the game's next real zone change.
-- Turning it off restores the real zone, otherwise the game's hub music would stay silent after the custom track stops.
local function set_zone(should_suppress)
	if should_suppress then
		force_group_to_none("music_zone")
	else
		restore_group("music_zone")
	end
end

-- Forces music_game_state to "None" so the game's own victory, defeat, and loading music stops.
-- The game changes this state repeatedly around a mission's start and end, so it is forced again after every real transition while on.
local function set_game_state(should_suppress)
	set_reforced_group("music_game_state", should_suppress)
end

-- Forces music_objective to "None" so the game's own last stand or event music stops.
-- It is engaged only for the last stand, event and Mortis Trials wave contexts, which are the ones this group decides.
-- The game changes this group repeatedly, so it is forced again after every real transition while on.
local function set_objective(should_suppress)
	set_reforced_group("music_objective", should_suppress)
end

-- Stops the game's music events that match SUPPRESSED_MUSIC_EVENT_PATTERNS as soon as they start.
-- Mission event sequences start their own music through events, which the state forcing never reaches.
-- Only an event that starts while this is on is stopped, so the game's music is untouched once it is off.
local function set_events(should_suppress)
	events_suppressed = should_suppress
end

-- ###########################################################################
-- Public API
-- ###########################################################################

-- Call once from the main mod file's top level.
-- `detail_logger`, if given, receives a line each time a lever forces, restores or stops something.
function Suppression.init(detail_logger)
	log_detail = detail_logger or log_detail
end

-- The single trigger_resource_event hook in MusicReplacer.lua calls this for every Wwise event.
-- Returns true if the caller should stop the event it just started.
-- A mod can only install one hook per method on itself, so this does not hook anything on its own.
function Suppression.should_stop_event(event_name)
	if not events_suppressed or type(event_name) ~= "string" then
		return false
	end

	for _, pattern in ipairs(SUPPRESSED_MUSIC_EVENT_PATTERNS) do
		if event_name:find(pattern, 1, true) then
			log_detail(string.format("[suppress] stopped the game's music event: %s", event_name))
			return true
		end
	end

	return false
end

-- The trigger_resource_event hook calls this for every event that keeps playing, with its world and playing ID.
-- Cutscene music is remembered, so it can be stopped once a custom song takes over.
function Suppression.watch_event(wwise_world, event_name, playing_id)
	if type(event_name) ~= "string" or not event_name:find(CUTSCENE_EVENT_PREFIX, 1, true)
		or not event_name:find(CUTSCENE_MUSIC_WORD, 1, true) then
		return
	end

	if #cutscene_events >= MAX_CUTSCENE_EVENTS then
		table.remove(cutscene_events, 1)
	end
	cutscene_events[#cutscene_events + 1] = { world = wwise_world, playing_id = playing_id, name = event_name }
end

-- Register with Context.on_state_change so the levers see every real transition.
-- A loading screen ends the level its cutscene music belonged to, along with that level's Wwise world, so the events are forgotten.
-- Keeps the last real value of each group, and forces or releases a group again when the game replaces it.
function Suppression.on_state_change(group_name, new_state)
	real_states[group_name] = new_state

	if group_name == "music_game_state" and new_state == "loading" then
		cutscene_events = {}
	end

	if group_name == "music_zone" then
		forced_groups.music_zone = false -- The game just set a real zone, which replaces any forced value.
	elseif reforced_groups[group_name] and new_state ~= "None" then
		forced_groups[group_name] = true
		Wwise.set_state(group_name, "None")
	else
		forced_groups[group_name] = false -- The game just set a real state, which replaces any forced value.
	end
end

-- Stops the cutscene music that may still be playing, since a custom song takes over now.
-- A cutscene's music already over has nothing left to stop, which Wwise ignores.
local function stop_cutscene_music()
	for _, event in ipairs(cutscene_events) do
		local ok = pcall(WwiseWorld.stop_event, event.world, event.playing_id)
		if ok then
			log_detail(string.format("[suppress] stopped the cutscene's music event: %s", event.name))
		end
	end
	cutscene_events = {}
end

-- Turns on the levers for a context that has a custom track available, or that is set to silence.
-- Combat and event suppression apply to every context.
-- A context whose own music comes from one more state group, as the catalog's `silences` names, has that group forced too.
function Suppression.engage(context_name)
	local context = Contexts.get(context_name)
	local silences = context and context.silences

	set_combat(true)
	set_events(true)
	stop_cutscene_music()
	set_zone(silences == "music_zone")
	set_game_state(silences == "music_game_state")
	set_objective(silences == "music_objective")
end

-- Turns every lever off, for no context or a context with no custom track.
function Suppression.release()
	set_combat(false)
	set_zone(false)
	set_game_state(false)
	set_objective(false)
	set_events(false)
end

return Suppression
