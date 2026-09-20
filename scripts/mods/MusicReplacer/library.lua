-- Wraps the Audio Plugin's AudioFilesHandler (Audio.new_files_handler), with one handler per music context.
-- Each context is a single-level subfolder of this mod's "audio/" directory, for example ".../mods/MusicReplacer/audio/hub/".
--
-- Everything below is pcall-guarded.
-- AudioFilesHandler's async scan leaves a field nil until it resolves, and :count() and :random() index that field directly.
-- That is a hard error rather than a nil result, and a missing subfolder behaves the same way.
-- A missing, empty or not yet scanned folder resolves to nil here, which is the fallback-to-native-music signal the caller needs.

local Library = {}

-- Keep in sync with $AudioContexts in tools/build.ps1.
local CONTEXTS = { "hub", "mission_explore", "mission_combat", "mission_boss", "mission_victory", "mission_defeat" }
local MAX_REPICK_ATTEMPTS = 5 -- Bounded retries to avoid an immediate repeat, see pick_file().

-- Relative to the game's own working directory.
-- Same "./../mods/<name>/..." convention DMF uses to find this mod's info.json.
local AUDIO_ROOT = "./../mods/MusicReplacer/audio"

local _os = Mods and Mods.lua and Mods.lua.os

local handlers = {}
local last_picked = {} -- context_name -> the file path most recently returned.

-- Best effort, so a fresh install has every folder ready without the user creating them.
-- Windows mkdir creates missing parents and does nothing if the folder exists.
-- pick_file()'s own fallback matters more than this succeeding.
local function ensure_audio_folder(context_name)
	if not _os or not _os.execute then
		return
	end

	local path = (AUDIO_ROOT .. "/" .. context_name):gsub("/", "\\")
	pcall(_os.execute, 'mkdir "' .. path .. '" >nul 2>nul')
end

-- Call once, after all mods have loaded.
function Library.init()
	local audio_mod = get_mod("Audio")
	if not audio_mod then
		return -- Audio Plugin missing. pick_file() below correctly returns nil.
	end

	for _, context_name in ipairs(CONTEXTS) do
		ensure_audio_folder(context_name)

		-- This call is not pcall-wrapped.
		-- new_files_handler finds its path by walking the call stack for the calling mod's name.
		-- A pcall frame in that walk silently breaks the resolved path.
		-- The call itself has no crash risk, unlike the calls in pick_file().
		handlers[context_name] = audio_mod.new_files_handler(nil, context_name)
	end
end

-- Returns file_path, duration_seconds and is_only_file, or nil if no file is available.
-- Nil means the folder is missing, empty or not yet scanned, Library.init() was not called, or the Audio Plugin is missing.
-- The caller should fall back to native music on nil.
-- duration may be nil even with a file_path.
-- is_only_file flags a single-file folder for native looping (see audio_client.lua).
-- :random() has no memory of its last pick, so with two or more files this retries for a non-repeat.
function Library.pick_file(context_name)
	local handler = handlers[context_name]
	if not handler then
		return nil
	end

	local count_ok, count = pcall(function()
		return handler:count()
	end)
	if not count_ok or not count or count == 0 then
		return nil
	end

	local previous = last_picked[context_name]
	local file_path, duration

	for _ = 1, MAX_REPICK_ATTEMPTS do
		local pick_ok, candidate = pcall(function()
			return handler:random(nil, true) -- with_metadata is true so the result carries the duration.
		end)
		if not pick_ok then
			return nil
		end

		file_path = candidate.file_path
		duration = candidate.duration

		if count == 1 or file_path ~= previous then
			break
		end
	end

	last_picked[context_name] = file_path

	return file_path, duration, count == 1
end

return Library
