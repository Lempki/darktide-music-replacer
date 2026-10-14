-- Holds the Windows audio session of each ffplay the audio client launches, so a running track's volume can change without a relaunch.
-- A track launches at the slider level the Audio Plugin bakes in, and its session scales it down from there.
-- A session cannot raise a track above its launch level, so that still needs a relaunch.
--
-- Windows saves a program's session volume when a held session is released or its process exits, and every new ffplay_dt.exe starts there.
-- Other mods play their sounds through the same ffplay_dt.exe.
-- So a session is held until its process has exited, then set back to 1 and released, which leaves the saved volume at 1.
-- The session of a new process takes a moment to appear, and the baked launch level covers that moment.

local VolumeSessions = {}

local LOOKUP_RETRY_SECONDS = 0.25
local LOOKUP_GIVE_UP_SECONDS = 5
local EXIT_CHECK_SECONDS = 0.5

local SessionVolume = nil
local pid_of = function() return nil end
local is_enabled = function() return false end
local diagnostic_log = function() end

local tracked = {} -- play_file_id -> { launch_percent, scale, session, waited, retry_elapsed, failed }
local retired = {} -- Sessions whose process is being stopped, held until it has exited.
local exit_check_elapsed = 0

-- `pid_of(play_file_id)` returns a launched process's pid once it is known.
-- `enabled()` is read at each launch, so turning the feature off reaches the next track.
function VolumeSessions.init(session_volume, get_pid, enabled, log)
	SessionVolume = session_volume
	pid_of = get_pid or pid_of
	is_enabled = enabled or is_enabled
	diagnostic_log = log or diagnostic_log
end

-- Starts looking for the session of a process launched at `launch_percent`, the integer volume the Audio Plugin baked in.
function VolumeSessions.track(play_file_id, launch_percent)
	if not play_file_id or not SessionVolume or not is_enabled() or not SessionVolume.available() then
		return
	end

	tracked[play_file_id] = {
		launch_percent = launch_percent,
		scale = 1,
		waited = 0,
		retry_elapsed = LOOKUP_RETRY_SECONDS,
	}
end

-- Sets a tracked process to `percent`, the music volume the sliders now ask for, from 0 to 100.
-- Returns false when only a relaunch can reach it: above its launch level, never tracked, or its session never appeared.
-- A session that has not appeared yet gets the level once it does.
function VolumeSessions.set_level(play_file_id, percent)
	local entry = play_file_id and tracked[play_file_id]
	if not entry or entry.failed then
		return false
	end

	-- Compared in the Audio Plugin's whole percents, so a fraction above the launch level does not force a relaunch.
	if math.floor(percent + 0.5) > entry.launch_percent then
		return false
	end

	entry.scale = entry.launch_percent > 0 and math.min(1, percent / entry.launch_percent) or 0

	if entry.session then
		entry.session:set(entry.scale)
	end

	return true
end

-- Call when a process is being stopped.
function VolumeSessions.retire(play_file_id)
	local entry = play_file_id and tracked[play_file_id]
	if not entry then
		return
	end

	tracked[play_file_id] = nil

	if entry.session then
		retired[#retired + 1] = entry.session
	end
end

local function look_up(play_file_id, entry, dt)
	entry.waited = entry.waited + dt
	entry.retry_elapsed = entry.retry_elapsed + dt

	if entry.retry_elapsed < LOOKUP_RETRY_SECONDS then
		return
	end
	entry.retry_elapsed = 0

	local pid = pid_of(play_file_id)
	local session = pid and SessionVolume.open(pid)

	if session then
		entry.session = session
		session:set(entry.scale)
		diagnostic_log(string.format("[session] pid %s: found after %.2fs, volume %.2f", tostring(pid), entry.waited, entry.scale))
	elseif entry.waited >= LOOKUP_GIVE_UP_SECONDS then
		entry.failed = true
		diagnostic_log(string.format("[session] pid %s: no audio session within %ds, so a slider change relaunches this track",
			tostring(pid), LOOKUP_GIVE_UP_SECONDS))
	end
end

-- Sets an exited process's session back to 1 and releases it, so Windows saves 1 for the next ffplay_dt.exe.
local function release_exited(force)
	for index = #retired, 1, -1 do
		local session = retired[index]
		local ended = session:process_ended()

		if ended or force then
			if ended then
				session:set(1)
			end
			session:close()
			table.remove(retired, index)
		end
	end
end

-- Call every tick.
function VolumeSessions.update(dt)
	for play_file_id, entry in pairs(tracked) do
		if not entry.session and not entry.failed then
			look_up(play_file_id, entry, dt)
		end
	end

	exit_check_elapsed = exit_check_elapsed + dt
	if exit_check_elapsed < EXIT_CHECK_SECONDS then
		return
	end
	exit_check_elapsed = 0

	-- A track can also end on its own without ever being stopped.
	for play_file_id, entry in pairs(tracked) do
		if entry.session and entry.session:process_ended() then
			VolumeSessions.retire(play_file_id)
		end
	end

	release_exited(false)
end

-- Call at unload, after the processes were killed.
-- A process still running keeps its current volume, since setting it back to 1 would be heard.
function VolumeSessions.shutdown()
	for play_file_id, entry in pairs(tracked) do
		if entry.session then
			retired[#retired + 1] = entry.session
		end
		tracked[play_file_id] = nil
	end

	release_exited(true)
end

return VolumeSessions
