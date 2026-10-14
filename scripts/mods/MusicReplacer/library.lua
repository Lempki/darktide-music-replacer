-- Wraps the Audio Plugin's AudioFilesHandler (Audio.new_files_handler), with one handler per music context.
-- Each context is a single-level subfolder of this mod's "audio/" directory, for example ".../mods/MusicReplacer/audio/hub/".
--
-- Everything below is pcall-guarded.
-- AudioFilesHandler's async scan leaves a field nil until it resolves, and :count() and :lookup() index that field directly.
-- That is a hard error rather than a nil result, and a missing subfolder behaves the same way.
-- A missing, empty or not yet scanned folder resolves to nil here, which is the fallback-to-native-music signal the caller needs.
--
-- Each folder is scanned after the game's backend is ready, and again only when a rescan is requested.
-- So a file deleted during a session is still listed until then, and pick_file() checks that a file exists before returning it.

local Library = {}

-- Keep in sync with $AudioContexts in tools/build.ps1.
local CONTEXTS = { "hub", "mission_explore", "mission_combat", "mission_horde", "mission_boss", "mission_event", "mission_last_stand", "mission_victory", "mission_defeat" }

-- Relative to the game's own working directory.
-- Same "./../mods/<name>/..." convention DMF uses to find this mod's info.json.
local AUDIO_ROOT = "./../mods/MusicReplacer/audio"

local _io = Mods and Mods.lua and Mods.lua.io
local _os = Mods and Mods.lua and Mods.lua.os

-- The game rejects every backend request until its backend has initialized, and DLS lists folders through one.
-- With a short mod list, all mods finish loading before that, so the scan waits for it.
-- BackendManager has no public accessor for this, so the scan reads its private _initialized field.
-- If a game update removes that field, the scan starts after SCAN_FALLBACK_SECONDS instead of never.
local SCAN_FALLBACK_SECONDS = 30

-- A rescan builds new handlers next to the current ones and swaps each in once its listing has resolved.
-- Until then the old list keeps serving picks, so a rescan never interrupts playback.
-- A listing that never resolves, for example after a failed request, is dropped after this long and the old list stays.
local RESCAN_TIMEOUT_SECONDS = 10

local diagnostic_log = function() end -- No-op unless a real logger is passed to Library.init.
local audio_mod = nil
local waiting_to_scan = false
local scan_wait_elapsed = 0
local handlers = {}
local rescan_requested = false
local pending_handlers = nil -- context_name -> new handler while a rescan waits for its listing.
local rescan_elapsed = 0
local last_picked = {} -- context_name -> the file path most recently returned.
local reported_missing = {} -- file_path -> true once a missing file has been logged.

-- The handler's file paths start with the context folder name, so they sit directly under AUDIO_ROOT.
-- If io is unavailable the file is assumed to exist, so this check can never block playback.
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

-- Best effort, so a fresh install has every folder ready without creating them by hand.
-- Windows mkdir creates missing parents and does nothing if the folder exists.
-- pick_file()'s own fallback matters more than this succeeding.
local function ensure_audio_folder(context_name)
	if not _os or not _os.execute then
		return
	end

	local path = (AUDIO_ROOT .. "/" .. context_name):gsub("/", "\\")
	pcall(_os.execute, 'mkdir "' .. path .. '" >nul 2>nul')
end

local function is_backend_ready()
	local backend = Managers and Managers.backend
	return backend ~= nil and backend._initialized == true
end

local function new_handlers()
	local result = {}

	for _, context_name in ipairs(CONTEXTS) do
		-- This call is not pcall-wrapped.
		-- new_files_handler finds its path by walking the call stack for the calling mod's name.
		-- A pcall frame in that walk silently breaks the resolved path.
		-- The call itself has no crash risk, unlike the calls in pick_file().
		result[context_name] = audio_mod.new_files_handler(nil, context_name)
	end

	return result
end

local function scan_folders(reason)
	waiting_to_scan = false
	rescan_requested = false
	diagnostic_log(string.format("[library] scanning audio folders after %.1fs, %s", scan_wait_elapsed, reason))
	handlers = new_handlers()
end

-- The handler's file count, or nil while its listing has not resolved.
local function listing_count(handler)
	local ok, count = pcall(function()
		return handler:count()
	end)

	return ok and count or nil
end

local function describe_counts()
	local parts = {}

	for _, context_name in ipairs(CONTEXTS) do
		parts[#parts + 1] = string.format("%s=%s", context_name, tostring(listing_count(handlers[context_name])))
	end

	return table.concat(parts, " ")
end

-- Swaps in each pending handler whose listing has resolved.
-- Returns true once the rescan is over.
local function advance_rescan(dt)
	rescan_elapsed = rescan_elapsed + dt
	local waiting = false

	for context_name, handler in pairs(pending_handlers) do
		if listing_count(handler) then
			handlers[context_name] = handler
			pending_handlers[context_name] = nil
		else
			waiting = true
		end
	end

	if waiting and rescan_elapsed < RESCAN_TIMEOUT_SECONDS then
		return false
	end

	pending_handlers = nil
	reported_missing = {}
	diagnostic_log(string.format("[library] rescan finished%s: %s", waiting and ", keeping the old list for folders that did not answer" or "", describe_counts()))

	return true
end

-- Call once, after all mods have loaded.
-- The folders are scanned later, by Library.update().
-- `log`, if given, receives a line when the scan starts and the first time a listed file turns out to be missing.
function Library.init(log)
	diagnostic_log = log or diagnostic_log

	audio_mod = get_mod("Audio")
	if not audio_mod then
		return -- Audio Plugin missing. pick_file() below correctly returns nil.
	end

	for _, context_name in ipairs(CONTEXTS) do
		ensure_audio_folder(context_name)
	end

	waiting_to_scan = true
end

-- Asks for a rescan of every folder on the next update.
-- DMF calls a settings button through a pcall, which would break new_files_handler's call stack walk, so the scan waits for update.
function Library.request_rescan()
	if audio_mod then
		rescan_requested = true
	end
end

-- Call from the main mod file's mod.update, so the scan's call stack stays inside this mod.
-- Returns true on the update where a rescan finishes, so the caller can start a track for a context that had no files.
function Library.update(dt)
	if waiting_to_scan then
		scan_wait_elapsed = scan_wait_elapsed + dt

		if is_backend_ready() then
			scan_folders("the game backend is ready")
		elseif scan_wait_elapsed >= SCAN_FALLBACK_SECONDS then
			scan_folders("with no ready signal from the game backend")
		end

		return false
	end

	if rescan_requested and not pending_handlers then
		rescan_requested = false
		rescan_elapsed = 0
		diagnostic_log("[library] rescanning audio folders")
		pending_handlers = new_handlers()
	end

	if not pending_handlers then
		return false
	end

	return advance_rescan(dt)
end

-- The context's listed entries that still exist on disk, or nil when there are none.
local function usable_entries(context_name)
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

	return usable
end

-- Returns file_path, duration_seconds and is_only_file, or nil if no file is available.
-- Nil means the folder is missing, empty or not yet scanned, or no listed file exists any more.
-- It also means the scan has not started yet, or the Audio Plugin is missing.
-- The caller should fall back to native music on nil.
-- duration may be nil even with a file_path.
-- is_only_file flags a folder with exactly one usable file for native looping (see audio_client.lua).
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
