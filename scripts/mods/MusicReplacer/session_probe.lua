-- Logging-only probe for the Windows audio session of the playing ffplay, the first step toward changing a running track's volume.
-- It only reads the session volume and never changes anything.
-- It runs only while Diagnostic Logging is on, so normal play makes no COM calls until they are proven in the game.

local SessionProbe = {}

-- A session appears shortly after ffplay starts, so a new pid is looked up a few times before giving up.
local RETRY_SECONDS = 0.25
local GIVE_UP_SECONDS = 5

local _os = Mods and Mods.lua and Mods.lua.os

local mod = nil
local SessionVolume = nil
local diagnostic_log = function() end

local availability_reported = false
local probing_pid = nil
local probe_done = true
local probe_elapsed = 0
local retry_elapsed = 0

local function clock()
	return _os and _os.clock and _os.clock() or 0
end

function SessionProbe.init(dmf_mod, session_volume, log)
	mod = dmf_mod
	SessionVolume = session_volume
	diagnostic_log = log or diagnostic_log
end

local function report_availability()
	availability_reported = true

	local ok, available = pcall(SessionVolume.available)
	if ok and available then
		diagnostic_log("[session] Core Audio is available")
	else
		diagnostic_log("[session] Core Audio is unavailable: " .. tostring(ok and SessionVolume.error() or available))
	end
end

-- Call every tick with the playing track's pid, or nil.
-- Logs each new pid's session volume once, or that no session turned up.
function SessionProbe.update(dt, pid)
	if not mod or not mod:get("diagnostic_mode") then
		return
	end

	if not availability_reported then
		report_availability()
	end

	if pid ~= probing_pid then
		probing_pid = pid
		probe_done = pid == nil
		probe_elapsed = 0
		retry_elapsed = RETRY_SECONDS
	end

	if probe_done or SessionVolume.error() then
		return
	end

	probe_elapsed = probe_elapsed + dt
	retry_elapsed = retry_elapsed + dt

	if retry_elapsed < RETRY_SECONDS then
		return
	end
	retry_elapsed = 0

	local started = clock()
	local ok, volume = pcall(SessionVolume.get, pid)
	local lookup_ms = (clock() - started) * 1000

	if not ok then
		probe_done = true
		diagnostic_log(string.format("[session] pid %s: lookup failed: %s", tostring(pid), tostring(volume)))
	elseif volume then
		probe_done = true
		diagnostic_log(string.format("[session] pid %s: session volume %.2f, found %.2fs after the pid arrived, lookup took %.1f ms",
			tostring(pid), volume, probe_elapsed, lookup_ms))
	elseif probe_elapsed >= GIVE_UP_SECONDS then
		probe_done = true
		diagnostic_log(string.format("[session] pid %s: no audio session found within %ds, last lookup took %.1f ms",
			tostring(pid), GIVE_UP_SECONDS, lookup_ms))
	end
end

return SessionProbe
