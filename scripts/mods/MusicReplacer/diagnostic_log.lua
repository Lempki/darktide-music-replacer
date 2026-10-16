-- Writes the mod's log, diagnostic.log, to a plain file in %APPDATA%\Fatshark\Darktide\MusicReplacer.
-- mod:echo() pops an on-screen notification per call, which is unusable at this volume, so this writes to a file instead.
-- The important events, such as context changes, playback decisions, and failures, are always written, so a bug report can include the log.
-- The detailed lines, such as raw state transitions and sound events, are only written while the "diagnostic_mode" option is on.
-- The option is checked on every call, so toggling it applies immediately.
-- Every launch starts a fresh file and keeps the previous session's beside it as diagnostic-prev.log.

local DiagnosticLog = {}

local _io = Mods and Mods.lua and Mods.lua.io
local _os = Mods and Mods.lua and Mods.lua.os

local LOG_DIR_NAME = "Fatshark/Darktide/MusicReplacer"
local LOG_FILE_NAME = "diagnostic.log"
local PREVIOUS_FILE_NAME = "diagnostic-prev.log"

-- A runaway log stops here rather than filling the disk. A long session with detailed lines stays well under a megabyte.
local MAX_BYTES = 10 * 1024 * 1024

local mod = nil -- Set by DiagnosticLog.init, needed for the mod options and error reporting.
local log_file = nil
local log_file_attempted = false

-- DMF keeps a persistent table through a mod reload, so a reload continues the session's file instead of starting a new one.
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
	local file_mode = "a"

	if not launch_state.started then
		launch_state.started = true
		launch_state.bytes = 0
		pcall(_os.remove, dir .. "/" .. PREVIOUS_FILE_NAME)
		pcall(_os.rename, path, dir .. "/" .. PREVIOUS_FILE_NAME)
		file_mode = "w"
	end

	local file, err = _io.open(path, file_mode)
	if not file then
		mod:error("[MusicReplacer] could not open log file: " .. tostring(err))
		return nil
	end

	log_file = file
	return log_file
end

local function write_line(line)
	local file = get_log_file()
	if not file then
		return
	end

	if launch_state.bytes >= MAX_BYTES then
		return
	end

	local timestamp = _os and _os.date and _os.date("%Y-%m-%d %H:%M:%S") or "????-??-?? ??:??:??"
	local text = string.format("[%s] %s\n", timestamp, line)
	launch_state.bytes = launch_state.bytes + #text

	if launch_state.bytes >= MAX_BYTES then
		text = string.format("[%s] [log] stopped writing, the file reached %d MB\n", timestamp, MAX_BYTES / 1024 / 1024)
	end

	file:write(text)
	file:flush()
end

-- Call once from the main mod file's top level.
function DiagnosticLog.init(mod_instance)
	mod = mod_instance
	launch_state = mod:persistent_table("diagnostic_log")
end

-- Writes an important event, which every log keeps.
function DiagnosticLog.write(line)
	write_line(line)
end

-- Writes a detailed line, which only the "diagnostic_mode" option keeps.
function DiagnosticLog.detail(line)
	if mod:get("diagnostic_mode") then
		write_line(line)
	end
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
