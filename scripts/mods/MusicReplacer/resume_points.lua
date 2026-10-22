-- Remembers where a context's song stopped, so the song continues when that context returns.
-- A new song is picked only once one ends on its own.
-- Every loading screen forgets everything, so each mission and hub visit starts with fresh picks.
-- The one exception is a mission loading song that the mission preparation screen interrupts, which continues in the briefing after it.

local ResumePoints = {}

local Contexts = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/contexts")

-- Explore and combat take turns all through a mission, as do Mortis Trials' waves and breaks.
-- So their songs continue whenever they come back, which the catalog marks as resuming "always".
-- Hordes, boss fights, and events continue only under the sequence rule below, which it marks as "sequence".
-- Last stands, the hub, and the mission's end start a fresh song every time.
local RESUMABLE_CONTEXTS = {}

-- Mission contexts by the priority context.lua resolves them in, lowest first.
local PRIORITY = {}

-- A horde, a boss fight, or an event is one stretch that higher-priority music can interrupt, such as a last stand during an event.
-- Its song continues only if the music did not drop to a lower-priority context in between, which shows that it ended.
-- A new horde, fight, or event then gets a new pick, so a folder with several songs still varies.
local SEQUENCES = {}

for _, context in ipairs(Contexts.list) do
	RESUMABLE_CONTEXTS[context.id] = context.resume ~= nil or nil
	PRIORITY[context.id] = context.priority
	SEQUENCES[context.id] = context.resume == "sequence" or nil
end

local function ends_sequence(context_name, next_context_name)
	return SEQUENCES[context_name] == true and PRIORITY[next_context_name] ~= nil and PRIORITY[next_context_name] < PRIORITY[context_name]
end

-- Resuming this close to the end would play a few seconds and then switch songs anyway.
local MIN_REMAINING_SECONDS = 10

local mod = nil
local points = {} -- context_name -> a table with file_path and position.

-- The mission loading song the preparation screen interrupted, kept apart from `points`, since loading screens clear those.
local loading_point = nil
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
	loading_point = nil
end

-- Call on every context change, before take(), to forget the sequences that the new context ends.
function ResumePoints.enter(context_name)
	-- The loading and preparation contexts are part of the loading screen, not the next level.
	if context_name ~= nil and context_name ~= "loading" and context_name ~= "mission_loading" and context_name ~= "mission_preparation" then
		is_loading = false
	end

	-- Only the briefing after the preparation screen continues the mission loading song.
	if context_name ~= "mission_loading" and context_name ~= "mission_preparation" then
		loading_point = nil
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
-- The position to keep: a single file's loop wraps back into the file, and nil when the song is too close to its end.
local function kept_position(position, duration, is_only_file)
	if duration and duration > 0 then
		if is_only_file then
			position = position % duration
		end

		if position > duration - MIN_REMAINING_SECONDS then
			return nil
		end
	end

	return position
end

function ResumePoints.remember(context_name, file_path, position, duration, is_only_file, next_context_name)
	if not (mod and mod:get("resume_songs")) then
		return nil
	end

	if context_name == "mission_loading" then
		loading_point = nil
		if next_context_name ~= "mission_preparation" then
			return nil
		end

		position = kept_position(position, duration, is_only_file)
		loading_point = position and { file_path = file_path, position = position }
		return position
	end

	if is_loading or not RESUMABLE_CONTEXTS[context_name] then
		return nil
	end

	if ends_sequence(context_name, next_context_name) then
		points[context_name] = nil
		return nil
	end

	points[context_name] = nil

	position = kept_position(position, duration, is_only_file)
	if not position then
		return nil
	end

	points[context_name] = { file_path = file_path, position = position }

	return position
end

-- Returns and forgets the context's point as file_path and position, or nil if it has none.
function ResumePoints.take(context_name)
	local point = points[context_name]
	points[context_name] = nil

	if context_name == "mission_loading" then
		point = loading_point
		loading_point = nil
	end

	if not point then
		return nil
	end

	return point.file_path, point.position
end

return ResumePoints
