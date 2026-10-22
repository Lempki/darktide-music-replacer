-- Keeps one file list per music context, listed through audio_folders.lua.
-- Each context is a single-level subfolder of this mod's "audio/" directory, for example ".../mods/MusicReplacer/audio/hub/".
-- A context folder can hold override folders one level further down, such as "boss/chaos_spawn/".
-- Their lists are kept under that key, in lowercase, since the names match what the game reports and Windows ignores case.
--
-- The folders are listed on the first update, again when a rescan is requested, and again once files change on disk.
-- Windows reports a change for every step of a copy, so a change only lists the folders once the changes have stopped for a moment.
-- Every file's duration is measured in the background, one file per update, so a large library never stalls a frame for long.
-- A file Windows cannot open while it is measured is left out of the picks from then on, so it cannot use up the caller's retries.
-- A file deleted after a listing is still listed until the next one, so pick_file() checks that a file exists before returning it.
-- Where Windows cannot watch the folders, as on some network drives, only the Rescan Audio Folders button lists them again.
-- A missing or empty folder resolves to nil here, which is the fallback-to-native-music signal the caller needs.
-- Every listing is passed on to the Library.on_listed listeners, which is how the loudness measurements learn of changed files.

local Library = {}

local Contexts = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/contexts")

-- The contexts with an audio folder of their own, in the catalog's order.
local CONTEXTS = {}
for _, context in ipairs(Contexts.list) do
	if context.folder then
		CONTEXTS[#CONTEXTS + 1] = context.id
	end
end

-- Relative to the game's own working directory.
-- Same "./../mods/<name>/..." convention DMF uses to find this mod's info.json.
local AUDIO_ROOT = "./../mods/MusicReplacer/audio"

local _os = Mods and Mods.lua and Mods.lua.os -- Only for timing the duration measurements.

local log = function() end -- No-op unless a real logger is passed to Library.init.
local AudioFolders = nil
local waiting_to_scan = false
local rescan_requested = false
local full_rescan_requested = false -- Set by the Rescan Audio Folders button, which measures every file again.

-- A file still being copied would be measured half-written and skipped as unplayable, so a change waits for this much quiet.
local QUIET_SECONDS = 3

local watcher = nil
local quiet_seconds = nil -- Seconds since the last change Windows reported, or nil while none waits for a listing.
local lists = {} -- folder key, a context name or "context/override", -> file paths, each starting with that key.
local override_folders = {} -- context_name -> its override folder keys, sorted.
local last_picked = {} -- context_name -> the file path most recently returned.
local reported_missing = {} -- file_path -> true once a missing file has been logged.
local unplayable = {} -- file_path -> true once Windows could not open the file.
local stamps = {} -- file_path -> its size and write time at the last listing.
local previous_stamps = {} -- The stamps of the listing before, so an unchanged file keeps what was measured of it.
local listed_listeners = {}

-- file_path -> seconds, or false when the file could not be measured.
local durations = {}
local measure_queue = {}
local measure_index = 1
local measure_seconds = 0

local function clock()
	return _os and _os.clock and _os.clock() or 0
end

local function list_folder(folder_key)
	local file_paths = {}

	local names, name_stamps = AudioFolders.list(AUDIO_ROOT .. "/" .. folder_key)

	for _, name in ipairs(names or {}) do
		local file_path = folder_key .. "/" .. name
		file_paths[#file_paths + 1] = file_path
		stamps[file_path] = name_stamps and name_stamps[name] or ""

		-- A new or changed file is measured again. An empty stamp says nothing about a change, so it counts as changed.
		if stamps[file_path] == "" or stamps[file_path] ~= previous_stamps[file_path] then
			durations[file_path] = nil
			unplayable[file_path] = nil
		end

		if durations[file_path] == nil then
			measure_queue[#measure_queue + 1] = file_path
		end
	end

	return file_paths
end

-- Every folder key in listing order: each context, then its override folders.
local function each_folder_key()
	local keys = {}
	for _, context_name in ipairs(CONTEXTS) do
		keys[#keys + 1] = context_name
		for _, key in ipairs(override_folders[context_name] or {}) do
			keys[#keys + 1] = key
		end
	end
	return keys
end

local function describe_counts()
	local parts = {}

	for _, key in ipairs(each_folder_key()) do
		parts[#parts + 1] = string.format("%s=%d", key, #lists[key])
	end

	return table.concat(parts, " ")
end

local function scan_folders(what)
	previous_stamps = stamps
	stamps = {}
	lists = {}
	override_folders = {}

	for _, context_name in ipairs(CONTEXTS) do
		lists[context_name] = list_folder(context_name)

		local keys = {}
		for _, name in ipairs(AudioFolders.subfolders(AUDIO_ROOT .. "/" .. context_name) or {}) do
			local key = context_name .. "/" .. name:lower()
			if not lists[key] then
				keys[#keys + 1] = key
				lists[key] = list_folder(key)
			end
		end
		override_folders[context_name] = keys
	end

	-- A file that is no longer listed has nothing left to keep.
	for file_path in pairs(durations) do
		if not stamps[file_path] then
			durations[file_path] = nil
			unplayable[file_path] = nil
		end
	end

	reported_missing = {}
	log(string.format("[library] %s: %s", what, describe_counts()))

	local entries = {}
	for _, key in ipairs(each_folder_key()) do
		for _, file_path in ipairs(lists[key]) do
			entries[#entries + 1] = { file_path = file_path, stamp = stamps[file_path] }
		end
	end

	for _, listener in ipairs(listed_listeners) do
		listener(entries)
	end
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
			log(string.format("[library] %s cannot be played, skipping it: %s", file_path, err))
		end
	end

	if not measure_queue[measure_index] then
		log(string.format("[library] measured every file's duration, %.0f ms in total", measure_seconds * 1000))
		measure_queue = {}
		measure_index = 1
		measure_seconds = 0
	end
end

-- Call once, after all mods have loaded, with an initialized audio_folders.lua.
-- Creates any missing folder at once, and lists them on the first update.
-- `log`, if given, receives a line for each listing and the total measuring time.
-- It also receives one for each file Windows cannot open, and the first time a listed file turns out to be missing.
function Library.init(logger, audio_folders)
	log = logger or log

	if not (audio_folders and audio_folders.available()) then
		return -- No way to list the folders. pick_file() below correctly returns nil.
	end
	AudioFolders = audio_folders

	AudioFolders.create(AUDIO_ROOT)
	for _, context_name in ipairs(CONTEXTS) do
		AudioFolders.create(AUDIO_ROOT .. "/" .. context_name)
	end

	-- Watching starts after the folders exist, so creating them is not reported as a change.
	local err
	watcher, err = AudioFolders.watch(AUDIO_ROOT)
	if not watcher then
		log(string.format("[library] %s, so changed files need Rescan Audio Folders", tostring(err)))
	end

	waiting_to_scan = true
end

-- Call from the main mod file's mod.on_unload. Stops watching the folders.
function Library.shutdown()
	if watcher then
		watcher:close()
		watcher = nil
	end
end

-- Notes a change Windows reported, and asks for a listing once changes have stopped for QUIET_SECONDS.
local function follow_changes(dt)
	if watcher:changed() then
		quiet_seconds = 0
	elseif quiet_seconds then
		quiet_seconds = quiet_seconds + dt
		if quiet_seconds >= QUIET_SECONDS then
			quiet_seconds = nil
			rescan_requested = true
		end
	end
end

-- Registers a function to call after every listing, with every listed file as { file_path, stamp } in context order.
-- The stamp changes whenever the file's size or write time does.
function Library.on_listed(listener)
	listed_listeners[#listed_listeners + 1] = listener
end

-- Asks for every folder to be listed again on the next update, and every file to be measured again.
-- The button is how a player asks to retry a file that would not play, so it does not keep what was measured before.
function Library.request_rescan()
	if AudioFolders then
		rescan_requested = true
		full_rescan_requested = true
	end
end

-- Call from the main mod file's mod.update with the seconds since the last update.
-- Returns true on the update where a rescan finishes, so the caller can start a track for a context that had no files.
function Library.update(dt)
	if not AudioFolders then
		return false
	end

	if watcher then
		follow_changes(dt or 0)
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

	-- A rescan the watcher started only measures the new and changed files, which their stamps show.
	if full_rescan_requested then
		full_rescan_requested = false
		durations = {}
		unplayable = {}
	end
	measure_queue = {}
	measure_index = 1
	measure_seconds = 0

	scan_folders("listed the audio folders again")
	return true
end

-- True when the folder of `folder_key`, a context or "context/override", has a listed file that Windows can play.
-- It only reads the listing, so it is cheap enough to ask often.
function Library.has_files(folder_key)
	for _, file_path in ipairs(lists[folder_key] or {}) do
		if not unplayable[file_path] then
			return true
		end
	end
	return false
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
				log(string.format("[library] %s is listed but missing on disk, skipping it until the folders are listed again", file_path))
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
