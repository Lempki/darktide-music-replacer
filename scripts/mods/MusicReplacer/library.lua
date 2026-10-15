-- Keeps one file list per music context, listed through audio_folders.lua.
-- Each context is a single-level subfolder of this mod's "audio/" directory, for example ".../mods/MusicReplacer/audio/hub/".
--
-- The folders are listed on the first update and again when a rescan is requested.
-- Every file's duration is measured in the background, one file per update, so a large library never stalls a frame for long.
-- A file Windows cannot open while it is measured is left out of the picks from then on, so it cannot use up the caller's retries.
-- A file deleted after a listing is still listed until the next one, so pick_file() checks that a file exists before returning it.
-- A missing or empty folder resolves to nil here, which is the fallback-to-native-music signal the caller needs.

local Library = {}

-- Keep in sync with $AudioContexts in tools/build.ps1.
local CONTEXTS = {
	"hub",
	"mission_explore",
	"mission_combat",
	"mission_horde",
	"mission_boss",
	"mission_event",
	"mission_last_stand",
	"mission_victory",
	"mission_defeat",
	"mortis_trials_wave",
	"mortis_trials_break",
}

-- Relative to the game's own working directory.
-- Same "./../mods/<name>/..." convention DMF uses to find this mod's info.json.
local AUDIO_ROOT = "./../mods/MusicReplacer/audio"

local _os = Mods and Mods.lua and Mods.lua.os -- Only for timing the duration measurements.

local diagnostic_log = function() end -- No-op unless a real logger is passed to Library.init.
local AudioFolders = nil
local waiting_to_scan = false
local rescan_requested = false
local lists = {} -- context_name -> file paths, each starting with the context folder name.
local last_picked = {} -- context_name -> the file path most recently returned.
local reported_missing = {} -- file_path -> true once a missing file has been logged.
local unplayable = {} -- file_path -> true once Windows could not open the file.

-- file_path -> seconds, or false when the file could not be measured.
local durations = {}
local measure_queue = {}
local measure_index = 1
local measure_seconds = 0

local function clock()
	return _os and _os.clock and _os.clock() or 0
end

local function list_folder(context_name)
	local file_paths = {}

	for _, name in ipairs(AudioFolders.list(AUDIO_ROOT .. "/" .. context_name) or {}) do
		local file_path = context_name .. "/" .. name
		file_paths[#file_paths + 1] = file_path

		if durations[file_path] == nil then
			measure_queue[#measure_queue + 1] = file_path
		end
	end

	return file_paths
end

local function describe_counts()
	local parts = {}

	for _, context_name in ipairs(CONTEXTS) do
		parts[#parts + 1] = string.format("%s=%d", context_name, #lists[context_name])
	end

	return table.concat(parts, " ")
end

local function scan_folders(what)
	for _, context_name in ipairs(CONTEXTS) do
		lists[context_name] = list_folder(context_name)
	end

	reported_missing = {}
	diagnostic_log(string.format("[library] %s: %s", what, describe_counts()))
end

local function measure_next_duration()
	local file_path = measure_queue[measure_index]
	if not file_path then
		return
	end

	measure_queue[measure_index] = nil
	measure_index = measure_index + 1

	if durations[file_path] == nil then
		local started = clock()
		local duration, err = AudioFolders.duration(AUDIO_ROOT .. "/" .. file_path)
		measure_seconds = measure_seconds + (clock() - started)
		durations[file_path] = duration or false

		if err then
			unplayable[file_path] = true
			diagnostic_log(string.format("[library] %s cannot be played, skipping it: %s", file_path, err))
		end
	end

	if not measure_queue[measure_index] then
		diagnostic_log(string.format("[library] measured every file's duration, %.0f ms in total", measure_seconds * 1000))
		measure_queue = {}
		measure_index = 1
		measure_seconds = 0
	end
end

-- Call once, after all mods have loaded, with an initialized audio_folders.lua.
-- Creates any missing folder at once, and lists them on the first update.
-- `log`, if given, receives a line for each listing and the first time a listed file turns out to be missing.
function Library.init(log, audio_folders)
	diagnostic_log = log or diagnostic_log

	if not (audio_folders and audio_folders.available()) then
		return -- No way to list the folders. pick_file() below correctly returns nil.
	end
	AudioFolders = audio_folders

	AudioFolders.create(AUDIO_ROOT)
	for _, context_name in ipairs(CONTEXTS) do
		AudioFolders.create(AUDIO_ROOT .. "/" .. context_name)
	end

	waiting_to_scan = true
end

-- Asks for every folder to be listed again on the next update.
function Library.request_rescan()
	if AudioFolders then
		rescan_requested = true
	end
end

-- Call from the main mod file's mod.update.
-- Returns true on the update where a rescan finishes, so the caller can start a track for a context that had no files.
function Library.update()
	if not AudioFolders then
		return false
	end

	measure_next_duration()

	if waiting_to_scan then
		waiting_to_scan = false
		rescan_requested = false
		scan_folders("listed the audio folders")
		return false
	end

	if not rescan_requested then
		return false
	end

	rescan_requested = false

	-- A file replaced under the same name gets measured again.
	durations = {}
	unplayable = {}
	measure_queue = {}
	measure_index = 1
	measure_seconds = 0

	scan_folders("listed the audio folders again")
	return true
end

-- The context's listed entries that still exist on disk, or nil when there are none.
local function usable_entries(context_name)
	local file_paths = lists[context_name]
	if not file_paths or #file_paths == 0 then
		return nil
	end

	local usable = {}

	for _, file_path in ipairs(file_paths) do
		-- An unplayable file was already logged when it was measured.
		if not unplayable[file_path] then
			if AudioFolders.exists(AUDIO_ROOT .. "/" .. file_path) then
				usable[#usable + 1] = { file_path = file_path, duration = durations[file_path] or nil }
			elseif not reported_missing[file_path] then
				reported_missing[file_path] = true
				diagnostic_log(string.format("[library] %s is listed but missing on disk, skipping it. Press Rescan Audio Folders in the mod settings after changing files.", file_path))
			end
		end
	end

	if #usable == 0 then
		return nil
	end

	return usable
end

-- Returns file_path, duration_seconds and is_only_file, or nil if no file is available.
-- Nil means the folder is missing, empty or not yet listed, or no listed file exists any more.
-- The caller should fall back to native music on nil.
-- duration is nil until the file has been measured, or when it could not be.
-- is_only_file flags a folder with exactly one usable file, which loops.
-- With two or more usable files, the pick is random and never the file returned last time.
function Library.pick_file(context_name)
	local usable = usable_entries(context_name)
	if not usable then
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

-- The path of a picked file on disk, relative to the game's working directory.
function Library.disk_path(file_path)
	return AUDIO_ROOT .. "/" .. file_path
end

-- Returns the same values as pick_file() for one specific file, or nil if the context no longer has it.
-- A song resumed after a rescan may have been removed, or its folder may have gained or lost files.
function Library.find_file(context_name, file_path)
	local usable = usable_entries(context_name)
	if not usable then
		return nil
	end

	for _, entry in ipairs(usable) do
		if entry.file_path == file_path then
			return entry.file_path, entry.duration, #usable == 1
		end
	end

	return nil
end

return Library
