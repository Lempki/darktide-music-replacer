-- Remembers where a context's song stopped, so the song continues when that context returns.
-- A new song is picked only once one ends on its own.
-- Every loading screen forgets everything, so each mission and hub visit starts with fresh picks.

local ResumePoints = {}

-- Explore and combat take turns all through a mission, so their songs continue whenever they come back.
-- Hordes and boss fights continue only under the rule below.
-- Events, last stands, and the mission's end start a fresh song every time.
local RESUMABLE_CONTEXTS = { mission_explore = true, mission_combat = true, mission_horde = true, mission_boss = true }

-- A horde or a boss fight is one stretch that higher-priority music, such as an event, can interrupt.
-- Its song continues only if the music did not drop to a lower-priority context in between, which shows that it ended.
-- A new horde or fight then gets a new pick, so a folder with several songs still varies.
local SEQUENCE_ENDED_BY = {
	mission_horde = { mission_combat = true, mission_explore = true },
	mission_boss = { mission_horde = true, mission_combat = true, mission_explore = true },
}

local function ends_sequence(context_name, next_context_name)
	local ended_by = SEQUENCE_ENDED_BY[context_name]
	return ended_by ~= nil and ended_by[next_context_name] == true
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
function ResumePoints.on_state_change(group_name, new_state)
	if group_name ~= "music_game_state" then
		return
	end

	is_loading = new_state == "loading"

	if is_loading then
		points = {}
	end
end

function ResumePoints.forget_all()
	points = {}
end

-- Call on every context change, before take(), to forget the hordes and boss fights that the new context ends.
function ResumePoints.enter(context_name)
	for sequence_name in pairs(SEQUENCE_ENDED_BY) do
		if ends_sequence(sequence_name, context_name) then
			points[sequence_name] = nil
		end
	end
end

-- Remembers `position` seconds into `file_path` for `context_name`, which is giving way to `next_context_name`.
-- Returns the position it kept, or nil.
-- `duration` may be nil. With it, a single file's native loop is wrapped back into the file, and a song near its end is not kept.
-- The context change into a loading screen can come after the loading state itself, so nothing is kept while loading.
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
