-- Remembers where a context's song stopped, so the song continues when that context returns.
-- A new song is picked only once one ends on its own.
-- Every loading screen forgets everything, so each mission and hub visit starts with fresh picks.

local ResumePoints = {}

-- Explore and combat take turns all through a mission, as do Mortis Trials' waves and breaks.
-- So their songs continue whenever they come back.
-- Hordes, boss fights, and events continue only under the sequence rule below.
-- Last stands, the hub, and the mission's end start a fresh song every time.
local RESUMABLE_CONTEXTS = {
	mission_explore = true,
	mission_combat = true,
	mission_horde = true,
	mission_boss = true,
	mission_event = true,
	mortis_trials_wave = true,
	mortis_trials_break = true,
}

-- Mission contexts by the priority context.lua resolves them in, lowest first.
local PRIORITY = { mission_explore = 1, mission_combat = 2, mission_horde = 3, mission_boss = 4, mission_event = 5, mission_last_stand = 6 }

-- A horde, a boss fight, or an event is one stretch that higher-priority music can interrupt, such as a last stand during an event.
-- Its song continues only if the music did not drop to a lower-priority context in between, which shows that it ended.
-- A new horde, fight, or event then gets a new pick, so a folder with several songs still varies.
local SEQUENCES = { mission_horde = true, mission_boss = true, mission_event = true }

local function ends_sequence(context_name, next_context_name)
	return SEQUENCES[context_name] == true and PRIORITY[next_context_name] ~= nil and PRIORITY[next_context_name] < PRIORITY[context_name]
end

-- Resuming this close to the end would play a few seconds and then switch songs anyway.
local MIN_REMAINING_SECONDS = 10

local mod = nil
local points = {} -- context_name -> { file_path, position }
local is_loading = false

function ResumePoints.init(dmf_mod)
	mod = dmf_mod
end

-- Pass to Context.on_state_change.
-- A loading screen forgets everything. Nothing is remembered from then on until ResumePoints.enter() gets the next level's first context.
-- So a song still playing when the debounced change away from the old level arrives is not kept for the next one.
function ResumePoints.on_state_change(group_name, new_state)
	if group_name ~= "music_game_state" or new_state ~= "loading" then
		return
	end

	is_loading = true
	points = {}
end

function ResumePoints.forget_all()
	points = {}
end

-- Call on every context change, before take(), to forget the sequences that the new context ends.
function ResumePoints.enter(context_name)
	if context_name ~= nil then
		is_loading = false
	end

	for sequence_name in pairs(SEQUENCES) do
		if ends_sequence(sequence_name, context_name) then
			points[sequence_name] = nil
		end
	end
end

-- Remembers `position` seconds into `file_path` for `context_name`, which is giving way to `next_context_name`.
-- Returns the position it kept, or nil.
-- `duration` may be nil. With it, a single file's loop is wrapped back into the file, and a song near its end is not kept.
-- The context change into a loading screen can come after the loading state itself.
-- So nothing is kept from a loading screen until the next level's first context.
function ResumePoints.remember(context_name, file_path, position, duration, is_only_file, next_context_name)
	if is_loading or not RESUMABLE_CONTEXTS[context_name] or not (mod and mod:get("resume_songs")) then
		return nil
	end

	if ends_sequence(context_name, next_context_name) then
		points[context_name] = nil
		return nil
	end

	points[context_name] = nil

	if duration and duration > 0 then
		if is_only_file then
			position = position % duration
		end

		if position > duration - MIN_REMAINING_SECONDS then
			return nil
		end
	end

	points[context_name] = { file_path = file_path, position = position }

	return position
end

-- Returns and forgets the context's point as file_path and position, or nil if it has none.
function ResumePoints.take(context_name)
	local point = points[context_name]
	points[context_name] = nil

	if not point then
		return nil
	end

	return point.file_path, point.position
end

return ResumePoints
