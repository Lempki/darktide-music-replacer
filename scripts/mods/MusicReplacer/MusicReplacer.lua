local mod = get_mod("MusicReplacer")

-- mod:io_dofile paths are relative to "mods/", including this mod's own folder name -- same requirement as MusicReplacer.mod's own paths.
local Context = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/context")
local Library = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/library")
local AudioClient = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/audio_client")
local EventProbe = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/event_probe")

-- ###########################################################################
-- File Logging
-- ###########################################################################
-- mod:echo() pops an on-screen notification per call, unusable at this volume, so this writes to a plain file instead -- mostly playback decisions, for troubleshooting "why is it playing this" after the fact.
-- Opt-in via the "diagnostic_mode" mod option, default off -- checked live on every call, so toggling it applies immediately and a user who leaves it off never gets a file created.

local _io = Mods and Mods.lua and Mods.lua.io
local _os = Mods and Mods.lua and Mods.lua.os

local LOG_DIR_NAME = "Fatshark/Darktide/MusicReplacer"
local LOG_FILE_NAME = "diagnostic.log"
local LOG_MAX_LINES = 2000 -- Oldest lines are dropped beyond this, checked once per session.

local log_file = nil
local log_file_attempted = false

local function appdata_root()
	if not _os then
		return nil
	end
	return _os.getenv("APPDATA") or _os.getenv("XDG_DATA_HOME")
end

local function ensure_directory(path)
	-- Best-effort mkdir. io.open below is the real success check.
	if _os and _os.execute then
		pcall(_os.execute, 'mkdir "' .. path:gsub("/", "\\") .. '" >nul 2>nul')
	end
end

-- Drops the oldest lines once the file exceeds LOG_MAX_LINES, keeping only the most recent.
-- Rewrites the whole file, so this is only safe to call once per session, not per log() call.
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

	-- "w" truncates, "a" appends.
	-- This only runs once per session (log_file_attempted above), so the setting only ever resets the file once, at the first write, not on every log() call.
	local mode = "a"
	if mod:get("reset_log_on_launch") then
		mode = "w"
	else
		trim_log_file(path)
	end

	local file, err = _io.open(path, mode)
	if not file then
		mod:error("[MusicReplacer] could not open log file: " .. tostring(err))
		return nil
	end

	log_file = file
	return log_file
end

local function log(line)
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

-- ###########################################################################
-- Playback Orchestration
-- ###########################################################################
-- Combines "what context" (context.lua) with "is there a file for it" (library.lua) to decide what audio_client.lua does.
-- Suppression of native boss music is only ever turned on once we know we have a replacement ready, so "no file provided" falls back to native music by construction rather than as a bolted-on check.

local current_context = nil

-- context_name -> true once a single-file context has completed one normal (filtered) play-through and switched to pure native looping.
local native_loop_active = {}

-- is_new_context distinguishes an actual context change from advancing within the same one (playlist continuation, a native loop's own repeats) -- only the former should re-fade in.
local function play_context(context_name, is_new_context)
	if not context_name then
		AudioClient.stop()
		Context.set_suppress_music_combat(false)
		return
	end

	if is_new_context then
		-- A genuine (re-)entry restarts a single-file context's cycle from a fresh, filtered first play -- see use_native_loop below.
		native_loop_active[context_name] = nil
	end

	local file_path, duration, is_only_file = Library.pick_file(context_name)

	if not file_path then
		-- No replacement available (no folder, empty, Audio Plugin missing, or scan not finished) -- leave native music alone.
		AudioClient.stop()
		Context.set_suppress_music_combat(false)
		log(string.format("[playback] %s: no file available, using native music", context_name))
		return
	end

	-- A file is confirmed playing for context_name by this point (the no-file branch above already returned), so suppress native combat-intensity music unconditionally.
	-- Confirmed safe against corrupting wwise_combat_state: no boss fight across every session logged so far ever showed the phantom instant follow-up transition a recursive Wwise.set_state call would cause.
	-- Does not help hub, which almost certainly does not run on music_combat at all -- see context.lua's own note.
	Context.set_suppress_music_combat(true)

	-- Single-file contexts play once normally (loop=1, filtered) first, then switch to pure native looping (loop=0, no filters) -- ffplay's -loop re-triggers filters every iteration, so a fade-in from the start would otherwise repeat forever.
	local use_native_loop = is_only_file and native_loop_active[context_name] == true

	log(string.format("[playback] %s: playing %s (duration=%s%s)",
		context_name, file_path, tostring(duration), use_native_loop and ", looping natively" or ""))

	AudioClient.play(file_path, {
		duration_seconds = duration,
		fade_in = is_new_context,
		native_loop = use_native_loop,
		on_finished = function()
			-- Never fires once use_native_loop is true.
			-- Only continue if still in this context -- if it changed, whatever triggered that already called play_context for the new one.
			if current_context == context_name then
				if is_only_file then
					native_loop_active[context_name] = true
				end
				play_context(context_name, false)
			end
		end,
	})
end

-- Debounce context changes before acting on them.
local DEBOUNCE_SECONDS = 0.6

local pending_context = nil
local debounce_elapsed = 0
local has_pending_change = false

local function commit_pending_context()
	has_pending_change = false

	if pending_context == current_context then
		-- A flicker round-tripped back to what's already playing -- nothing to do.
		return
	end

	current_context = pending_context
	play_context(pending_context, true) -- true marks a genuine context change.
end

Context.on_change(function(new_context, old_context, boss_breed)
	log(string.format("[context] %s -> %s%s",
		tostring(old_context), tostring(new_context),
		boss_breed and (" (breed=" .. boss_breed .. ")") or ""))

	pending_context = new_context
	debounce_elapsed = 0
	has_pending_change = true
end)

-- ###########################################################################
-- Wiring
-- ###########################################################################

Context.init(mod, log)

mod.on_all_mods_loaded = function()
	Library.init()
	AudioClient.init(log)
	EventProbe.init(mod, log) -- Investigating native hub music. Remove this call once the events are known.

	if not AudioClient.available() then
		mod:error(
			"[MusicReplacer] Audio Plugin not found -- music replacement disabled, native music will play "
				.. "normally. Install 'Audio' (and its dependency 'DarktideLocalServer') from Nexus Mods and "
				.. "place both above MusicReplacer in mod_load_order.txt."
		)
	end

	-- Context may have resolved before Library/AudioClient were ready -- re-evaluate now, bypassing the debounce since this is a one-off catch-up.
	has_pending_change = false
	current_context = Context.current()
	play_context(current_context, true)
end

mod.update = function(dt)
	Context.update(mod, dt)
	AudioClient.update(dt)

	if has_pending_change then
		debounce_elapsed = debounce_elapsed + dt

		if debounce_elapsed >= DEBOUNCE_SECONDS then
			commit_pending_context()
		end
	end
end

mod.on_unload = function()
	Context.shutdown(mod)
	AudioClient.shutdown() -- Direct OS-level kill, not just the (here unreliable) normal stop.

	if log_file then
		log_file:close()
		log_file = nil
		log_file_attempted = false
	end
end
