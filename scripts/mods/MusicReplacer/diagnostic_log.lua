-- Writes the mod's diagnostic log to a plain file.
-- mod:echo() pops an on-screen notification per call, which is unusable at this volume, so this writes to a file instead.
-- The file holds mostly playback decisions and raw state transitions, for troubleshooting why a track is playing after the fact.
-- It is opt-in through the "diagnostic_mode" mod option, which defaults to off.
-- The option is checked on every call, so toggling it applies immediately.
-- With the option off, the file is never created.

local DiagnosticLog = {}

local _io = Mods and Mods.lua and Mods.lua.io
local _os = Mods and Mods.lua and Mods.lua.os

local LOG_DIR_NAME = "Fatshark/Darktide/MusicReplacer"
local LOG_FILE_NAME = "diagnostic.log"
local LOG_MAX_LINES = 2000 -- Oldest lines are dropped beyond this. Checked once per session.

local mod = nil -- Set by DiagnosticLog.init, needed for the mod options and error reporting.
local log_file = nil
local log_file_attempted = false

-- DMF keeps a persistent table through a mod reload, so a reload does not count as a new launch and wipe the log.
local launch_state = {}

local function appdata_root()
	if not _os then
		return nil
	end
	return _os.getenv("APPDATA") or _os.getenv("XDG_DATA_HOME")
end

local function ensure_directory(path)
	-- Best effort, since io.open below is the real success check.
	if _os and _os.execute then
		pcall(_os.execute, 'mkdir "' .. path:gsub("/", "\\") .. '" >nul 2>nul')
	end
end

-- Rewrites the whole file, so this is only safe to call once per session, not per write() call.
local function trim_log_file(path)
	local file = _io.open(path, "r")
	if not file then
		return
	end

	local lines = {}
	for line in file:lines() do
		lines[#lines + 1] = line
	end
	file:close()

	if #lines <= LOG_MAX_LINES then
		return
	end

	local trimmed = _io.open(path, "w")
	if not trimmed then
		return
	end

	for i = #lines - LOG_MAX_LINES + 1, #lines do
		trimmed:write(lines[i], "\n")
	end
	trimmed:close()
end

local function get_log_file()
	if log_file then
		return log_file
	end

	if log_file_attempted then
		return nil
	end
	log_file_attempted = true

	if not _io then
		return nil
	end

	local base = appdata_root()
	if not base then
		return nil
	end

	local dir = base .. "/" .. LOG_DIR_NAME
	ensure_directory(dir)

	local path = dir .. "/" .. LOG_FILE_NAME

	-- This only runs once per session (see log_file_attempted above).
	-- So the setting resets the file once, at the first write, and not on every write() call.
	local file_mode = "a"
	if mod:get("reset_log_on_launch") and not launch_state.log_reset then
		file_mode = "w"
	else
		trim_log_file(path)
	end
	launch_state.log_reset = true

	local file, err = _io.open(path, file_mode)
	if not file then
		mod:error("[MusicReplacer] could not open log file: " .. tostring(err))
		return nil
	end

	log_file = file
	return log_file
end

-- Call once from the main mod file's top level.
function DiagnosticLog.init(mod_instance)
	mod = mod_instance
	launch_state = mod:persistent_table("diagnostic_log")
end

function DiagnosticLog.write(line)
	if not mod:get("diagnostic_mode") then
		return
	end

	local file = get_log_file()
	if not file then
		return
	end

	local timestamp = _os and _os.date and _os.date("%Y-%m-%d %H:%M:%S") or "????-??-?? ??:??:??"
	file:write("[", timestamp, "] ", line, "\n")
	file:flush()
end

-- Call from the main mod file's mod.on_unload.
function DiagnosticLog.close()
	if log_file then
		log_file:close()
		log_file = nil
		log_file_attempted = false
	end
end

return DiagnosticLog
