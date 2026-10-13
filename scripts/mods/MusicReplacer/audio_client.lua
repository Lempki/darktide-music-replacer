-- Thin wrapper over the Audio Plugin's play_file API.
-- Plays one music track at a time, crossfading between switches, either playlisting through a folder or native-looping a single file.
-- Knows nothing about context or file choice. See context.lua, library.lua and MusicReplacer.lua.
-- Plugin API: https://github.com/ronvoluted/darktide-mods/tree/main/Audio
--
-- Constraints the rest of this file is built around:
--	* play_file() learns its OS pid asynchronously.
--	  Stopping before the pid arrives cannot kill anything, and the Audio Plugin never retries, which orphans the process.
--	  retry_pending_stops() below mitigates this.
--	* ffplay is headless with no live control channel, so an already-playing track's volume and filters cannot change.
--	  So a crossfade is a one-sided fade-in overlap, not a symmetric fade.
--	  A relaunch-based symmetric fade glitches audibly, which sounds worse than not fading at all.
--	* The Audio Plugin bakes -volume in once at launch (confirmed from play_file.lua).
--	  AudioClient.update() reacts to a slider change on the next tick, then ignores further changes for VOLUME_RELAUNCH_COOLDOWN_SECONDS.
--	  Each relaunch stops the track and starts it again at its current position.
--	  That is accepted since a slider change is rare and deliberate.
--	* -ss after -i combined with -loop restarts every loop iteration from the seeked position, not the file's true start (confirmed in-game).
--	  So a native_loop relaunch plays a finite tail to the file's true end first, then resumes native looping from position 0.
--	  That is the same seam the loop already uses, so it sounds like an ordinary loop and not a restart.
--	* After -ss, ffplay's filters see timestamps from the file's own timeline (verified by printing frame timestamps).
--	  So afade's st is measured against the full file duration, not against the seek point.

local AudioClient = {}

local FADE_IN_SECONDS = 2
local FADE_OUT_SECONDS = 2 -- Also used for a track's own natural-end fade-out.

-- How long an outgoing track keeps playing unmodified alongside an incoming one before it is stopped.
-- Longer than FADE_IN_SECONDS so the incoming track masks the cutoff.
local CROSSFADE_OVERLAP_SECONDS = 3

-- After reacting to a change, ignore further changes for this long.
-- This caps a continued drag without delaying the first reaction.
local VOLUME_RELAUNCH_COOLDOWN_SECONDS = 1

local _os = Mods and Mods.lua and Mods.lua.os -- Only for AudioClient.shutdown()'s direct kill.

local audio_mod = nil
local dls_mod = nil
local log_fn = function() end -- Replaced with the real logger by AudioClient.init(log), see MusicReplacer.lua.
local current_play_file_id = nil
local pending_stop_ids = {} -- play_file_id -> true for kills that are not yet confirmed.
local scheduled_stops = {} -- List of {remaining, play_file_id} entries for the crossfade overlap.

-- Tracks the current track well enough to relaunch it at a new volume. See AudioClient.update().
local current_file_path = nil

-- The file's full duration, fixed across a volume relaunch so the fade-out lands at the file's real end.
local current_total_duration = nil

-- Seconds into the file's timeline.
-- Keeps counting across a relaunch and resets only on a new AudioClient.play call.
local current_elapsed = 0

local current_native_loop = false
local current_on_finished = nil
local current_master_slider = nil
local current_music_slider = nil
local volume_cooldown_elapsed = VOLUME_RELAUNCH_COOLDOWN_SECONDS -- Starts elapsed, so the first real change is never held back.

function AudioClient.init(log)
	audio_mod = get_mod("Audio")
	dls_mod = get_mod("DarktideLocalServer")
	log_fn = log or log_fn
end

function AudioClient.available()
	return audio_mod ~= nil
end

-- Seconds the current track has been playing since it was started, or 0 if nothing is playing.
-- It keeps counting across a volume relaunch.
function AudioClient.elapsed()
	return current_elapsed
end

-- Retries stops that had no known pid yet.
-- Cheap and normally a no-op, so it can run every tick.
local function retry_pending_stops()
	if not audio_mod or not dls_mod then
		return
	end

	for play_file_id in pairs(pending_stop_ids) do
		local pid = audio_mod.file_pid(play_file_id)
		if pid then
			dls_mod.stop_process(pid)
			pending_stop_ids[play_file_id] = nil
		end
	end
end

local function stop_id(play_file_id)
	if not audio_mod or not play_file_id then
		return
	end

	audio_mod.stop_file(play_file_id)
	pending_stop_ids[play_file_id] = true -- May not have actually killed anything yet.
	retry_pending_stops()
end

-- Reads the same two sliders the Audio Plugin multiplies together for music volume, defaulting to 100 like it does.
local function read_volume_sliders()
	local master = Application.user_setting("sound_settings", "option_master_slider") or 100
	local music = Application.user_setting("sound_settings", "options_music_slider") or 100
	return master, music
end

-- Builds the afade filter string, or nil for none.
-- It has a fade-in if opts.fade_in, plus a natural-end fade-out if duration_seconds is known.
-- Neither applies to opts.native_loop.
-- ffplay's -loop re-triggers baked-in filters every iteration, so a fade would recur forever.
-- ffmpeg allows several comma-separated afade instances in one chain, each with its own time window.
--
-- The Audio Plugin's play_file() prepends one "afade=" to whatever this returns.
-- So only a chained second instance may restate the filter name itself.
-- A fade-out alone, as in every relaunch and every playlist continuation, would otherwise become "afade=afade=...".
-- ffplay rejects that and kills the process almost immediately.
local function build_afade(opts)
	if opts.native_loop then
		return nil
	end

	local afade = nil

	if opts.fade_in then
		afade = string.format("t=in:d=%s", FADE_IN_SECONDS)
	end

	if opts.duration_seconds and opts.duration_seconds > (FADE_IN_SECONDS + FADE_OUT_SECONDS) then
		local fade_out_args = string.format("t=out:st=%s:d=%s", opts.duration_seconds - FADE_OUT_SECONDS, FADE_OUT_SECONDS)
		afade = afade and (afade .. ",afade=" .. fade_out_args) or fade_out_args
	end

	return afade
end

-- Relaunches the current track so a slider change reaches a track that is already playing.
-- Only called from the slider check in AudioClient.update().
local function relaunch_at_current_volume()
	if not current_play_file_id or not current_file_path then
		return
	end

	log_fn(string.format("[volume] relaunching %s at %.1fs (master=%s, music=%s)",
		current_file_path, current_elapsed, tostring(current_master_slider), tostring(current_music_slider)))

	stop_id(current_play_file_id) -- Stopped at once, not crossfade-scheduled, since this continues the same track and is not a switch.

	local file_path = current_file_path
	local on_finished = current_on_finished

	if current_native_loop then
		-- A plain reseek would permanently shorten the loop (see the header).
		-- So this finishes the cycle as a finite play to the file's true end.
		-- It then resumes native looping from position 0, the same seam the loop already uses.
		local seek_position = current_elapsed

		local tail_play_file_id
		tail_play_file_id = audio_mod.play_file(file_path, {
			audio_type = "music",
			loop = 1,
			pos = seek_position > 0 and seek_position or nil,
			track_status = function()
				if current_play_file_id ~= tail_play_file_id then
					return -- Superseded by a real context change before the tail finished.
				end

				log_fn(string.format("[volume] %s: tail finished, resuming native loop from start", file_path))

				local resumed_play_file_id
				resumed_play_file_id = audio_mod.play_file(file_path, {
					audio_type = "music",
					loop = 0,
					track_status = function()
						if on_finished and current_play_file_id == resumed_play_file_id then
							on_finished()
						end
					end,
				})
				current_play_file_id = resumed_play_file_id
				current_elapsed = 0 -- The file restarted from its true beginning.
			end,
		})

		current_play_file_id = tail_play_file_id
		return
	end

	local seek_position = current_elapsed

	local play_file_id
	play_file_id = audio_mod.play_file(file_path, {
		audio_type = "music",
		loop = 1,
		-- After a seek, ffplay's filters still see timestamps from the file's own timeline.
		-- So the fade-out point is measured against the full duration, not what is left.
		afade = build_afade({ native_loop = false, duration_seconds = current_total_duration, fade_in = false }),
		pos = seek_position > 0 and seek_position or nil,
		track_status = function()
			if on_finished and current_play_file_id == play_file_id then
				on_finished()
			end
		end,
	})

	current_play_file_id = play_file_id
end

-- Call every tick to catch late pids, advance crossfade timers, and check the volume sliders.
function AudioClient.update(dt)
	retry_pending_stops()

	for i = #scheduled_stops, 1, -1 do
		local entry = scheduled_stops[i]
		entry.remaining = entry.remaining - dt

		if entry.remaining <= 0 then
			table.remove(scheduled_stops, i)
			stop_id(entry.play_file_id)
		end
	end

	if not current_play_file_id then
		return
	end

	current_elapsed = current_elapsed + dt

	if volume_cooldown_elapsed < VOLUME_RELAUNCH_COOLDOWN_SECONDS then
		volume_cooldown_elapsed = volume_cooldown_elapsed + dt
		return
	end

	local master_slider, music_slider = read_volume_sliders()
	if master_slider ~= current_master_slider or music_slider ~= current_music_slider then
		current_master_slider, current_music_slider = master_slider, music_slider
		volume_cooldown_elapsed = 0
		relaunch_at_current_volume()
	end
end

-- Immediate silence, for the native-music fallback and mod unload.
-- Not a handoff, unlike the crossfade switch in AudioClient.play.
function AudioClient.stop()
	if current_play_file_id then
		local play_file_id = current_play_file_id
		current_play_file_id = nil
		stop_id(play_file_id)
	end

	for _, entry in ipairs(scheduled_stops) do
		stop_id(entry.play_file_id)
	end
	scheduled_stops = {}

	current_file_path = nil
	current_total_duration = nil
	current_elapsed = 0
end

-- Call from mod.on_unload only.
-- The normal stop path needs the game's network manager to relay a kill to DarktideLocalServer.
-- That manager can already be torn down on a normal quit, which leaves the track running.
-- This kills directly through a synchronous pid lookup and os.execute(), which needs nothing the game may be tearing down.
-- It cannot help a hard crash.
-- It blocks the calling thread, so never call it outside shutdown.
function AudioClient.shutdown()
	-- The plugin's stop request indexes Managers.backend, which is already gone at game exit and would raise an error there.
	-- On a mod reload the backend still exists, so the request still goes out.
	local function stop_if_backend_exists()
		if Managers and Managers.backend then
			AudioClient.stop()
		end
	end

	if not audio_mod or not _os or not _os.execute then
		stop_if_backend_exists()
		return
	end

	local function force_kill(play_file_id)
		local pid = audio_mod.file_pid(play_file_id)
		if pid then
			pcall(_os.execute, string.format('taskkill /PID %s /F /T >nul 2>nul', pid))
		end
	end

	if current_play_file_id then
		force_kill(current_play_file_id)
	end

	for _, entry in ipairs(scheduled_stops) do
		force_kill(entry.play_file_id)
	end

	stop_if_backend_exists() -- Extra insurance in case the normal path does land.
end

-- Plays file_path as 2D music, crossfading with whatever was playing (see the header).
-- Returns false if the Audio Plugin is not available, and the caller should fall back to native music.
--
-- opts.duration_seconds schedules the natural-end fade-out. Leaving it out means no fade-out.
-- opts.fade_in is only for a real context change, not for advancing within an unchanged one.
-- Advancing means a playlist continuation or a loop's own repeat.
-- opts.native_loop plays with ffplay loop=0 for a single-file context, instead of relaunching per repeat.
-- opts.on_finished fires once on natural end. It never fires with native_loop or for an interrupted play.
function AudioClient.play(file_path, opts)
	if not audio_mod then
		return false
	end

	opts = opts or {}

	if current_play_file_id then
		scheduled_stops[#scheduled_stops + 1] = {
			remaining = CROSSFADE_OVERLAP_SECONDS,
			play_file_id = current_play_file_id,
		}
	end

	current_file_path = file_path
	current_total_duration = opts.duration_seconds
	current_elapsed = 0
	current_native_loop = opts.native_loop or false
	current_on_finished = opts.on_finished
	current_master_slider, current_music_slider = read_volume_sliders()
	volume_cooldown_elapsed = VOLUME_RELAUNCH_COOLDOWN_SECONDS

	local on_finished = opts.on_finished

	-- play_file_id is declared before the assignment so the closure captures the upvalue this call fills in.
	-- `local x = f(x)` would capture a stale value instead.
	local play_file_id
	play_file_id = audio_mod.play_file(file_path, {
		audio_type = "music",
		loop = opts.native_loop and 0 or 1,
		afade = build_afade(opts),
		track_status = function()
			if on_finished and current_play_file_id == play_file_id then
				on_finished()
			end
		end,
	})

	current_play_file_id = play_file_id

	return true
end

return AudioClient
