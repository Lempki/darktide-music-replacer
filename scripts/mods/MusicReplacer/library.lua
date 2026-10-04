-- Wraps the Audio Plugin's AudioFilesHandler (Audio.new_files_handler), with one handler per music context.
-- Each context is a single-level subfolder of this mod's "audio/" directory, for example ".../mods/MusicReplacer/audio/hub/".
--
-- Everything below is pcall-guarded.
-- AudioFilesHandler's async scan leaves a field nil until it resolves, and :count() and :lookup() index that field directly.
-- That is a hard error rather than a nil result, and a missing subfolder behaves the same way.
-- A missing, empty or not yet scanned folder resolves to nil here, which is the fallback-to-native-music signal the caller needs.
--
-- Each folder is scanned once, when the game launches, and the list is never refreshed.
-- So a file deleted during a session is still listed, and pick_file() checks that a file exists before returning it.
-- A file added during a session is not listed until the next launch.

local Library = {}

-- Keep in sync with $AudioContexts in tools/build.ps1.
local CONTEXTS = { "hub", "mission_explore", "mission_combat", "mission_boss", "mission_victory", "mission_defeat" }

-- Relative to the game's own working directory.
-- Same "./../mods/<name>/..." convention DMF uses to find this mod's info.json.
local AUDIO_ROOT = "./../mods/MusicReplacer/audio"

local _io = Mods and Mods.lua and Mods.lua.io
local _os = Mods and Mods.lua and Mods.lua.os

local diagnostic_log = function() end -- No-op unless a real logger is passed to Library.init.
local handlers = {}
local last_picked = {} -- context_name -> the file path most recently returned.
local reported_missing = {} -- file_path -> true once a missing file has been logged.

-- The handler's file paths start with the context folder name, so they sit directly under AUDIO_ROOT.
-- If io is unavailable the file is assumed to exist, which is the behavior before this check.
-- The same goes for a name with non-ASCII characters.
-- The handler's paths are UTF-8, and io.open on Windows reads them in the system code page, so an existing file could look missing.
local function file_exists(file_path)
	if not _io or file_path:find("[\128-\255]") then
		return true
	end

	local file = _io.open(AUDIO_ROOT .. "/" .. file_path, "rb")
	if not file then
		return false
	end

	file:close()
	return true
end

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
-- `log`, if given, receives a line the first time a listed file turns out to be missing.
function Library.init(log)
	diagnostic_log = log or diagnostic_log

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
-- Nil means the folder is missing, empty or not yet scanned, or no listed file exists any more.
-- It also means Library.init() was not called, or the Audio Plugin is missing.
-- The caller should fall back to native music on nil.
-- duration may be nil even with a file_path.
-- is_only_file flags a folder with exactly one usable file for native looping (see audio_client.lua).
-- With two or more usable files, the pick is random and never the file returned last time.
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

	local usable = {}

	for index = 1, count do
		local lookup_ok, entry = pcall(function()
			return handler:lookup(index, true) -- with_metadata is true so the entry carries the duration.
		end)
		if not lookup_ok then
			return nil
		end

		if entry and entry.file_path then
			if file_exists(entry.file_path) then
				usable[#usable + 1] = entry
			elseif not reported_missing[entry.file_path] then
				reported_missing[entry.file_path] = true
				diagnostic_log(string.format("[library] %s is listed but missing on disk, skipping it. Folders are scanned once at launch, so restart the game after changing files.", entry.file_path))
			end
		end
	end

	if #usable == 0 then
		return nil
	end

	local previous = last_picked[context_name]
	local pool = usable

	if #usable > 1 then
		pool = {}
		for _, entry in ipairs(usable) do
			if entry.file_path ~= previous then
				pool[#pool + 1] = entry
			end
		end
	end

	local picked = pool[math.random(1, #pool)]

	last_picked[context_name] = picked.file_path

	return picked.file_path, picked.duration, #usable == 1
end

return Library
