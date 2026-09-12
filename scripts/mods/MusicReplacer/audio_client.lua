-- Thin wrapper over the Audio Plugin's play_file API: plays one music track at a time, crossfading between switches, either playlisting through a folder or native-looping a single file.
-- Knows nothing about context or file choice -- see context.lua/library.lua/MusicReplacer.lua.
-- Plugin API: https://github.com/ronvoluted/darktide-mods/tree/main/Audio
--
-- Two load-bearing constraints:
-- 	* play_file() learns its OS pid asynchronously; stopping before it arrives can't kill anything, and Audio Plugin never retries -- an orphaned process. retry_pending_stops() below mitigates this.
-- 	* ffplay is headless with no live control channel -- an already-playing track's volume/filters can't change, so crossfade is a one-sided fade-in overlap, not a true symmetric fade (a relaunch-based true fade glitched audibly worse than not fading at all).
--
-- That second constraint also means the game's own volume sliders do nothing to an already-playing track, since Audio Plugin bakes -volume in once, at launch, from whatever the sliders read at that moment (confirmed directly from its play_file.lua source).
-- AudioClient.update() polls them every VOLUME_CHECK_INTERVAL_SECONDS and, on a change, relaunches the current track re-seeked to its own elapsed position -- the same kill-and-reseek mechanism the crossfade-echo attempt above used and found to glitch audibly, accepted here since a slider change is a rare, deliberate user action rather than something happening on every track.
-- Rests on two ffplay behaviours neither confirmed nor documented anywhere: that -ss placed after -i still resets the relaunched process's own presentation clock to 0 (needed for the natural-end fade-out to land at the right point), and that native_loop's loop=0 keeps looping from the seeked position rather than drifting back to the file's true start. Test both explicitly in-game rather than assuming either holds.

local AudioClient = {}

local FADE_IN_SECONDS = 2
local FADE_OUT_SECONDS = 2 -- also used for a track's own natural-end fade-out

-- How long an outgoing track keeps playing unmodified alongside an incoming one before being stopped -- longer than FADE_IN_SECONDS so the incoming track masks the cutoff.
local CROSSFADE_OVERLAP_SECONDS = 3

local VOLUME_CHECK_INTERVAL_SECONDS = 3 -- How often to check the master/music sliders for a change worth relaunching over.

local _os = Mods and Mods.lua and Mods.lua.os -- Only for AudioClient.shutdown()'s direct kill.

local audio_mod = nil
local dls_mod = nil
local log_fn = function() end -- Replaced with the real logger by AudioClient.init(log), see MusicReplacer.lua.
local current_play_file_id = nil
local pending_stop_ids = {} -- play_file_id -> true, unconfirmed kills.
local scheduled_stops = {} -- {remaining, play_file_id} list, for crossfade overlap.

-- Tracks the currently playing (foreground) track well enough to relaunch it re-seeked at a new volume -- see the slider check in AudioClient.update() below.
local current_file_path = nil
local current_total_duration = nil -- The file's own full duration as first given to AudioClient.play, fixed across a volume relaunch so the natural-end fade-out keeps landing at the right point.
local current_elapsed = 0 -- Seconds into the current file's own timeline, keeps counting across a volume relaunch, resets only on a genuinely new AudioClient.play call.
local current_native_loop = false
local current_on_finished = nil
local current_master_slider = nil
local current_music_slider = nil
local volume_check_elapsed = 0

function AudioClient.init(log)
	audio_mod = get_mod("Audio")
	dls_mod = get_mod("DarktideLocalServer")
	log_fn = log or log_fn
end

function AudioClient.available()
	return audio_mod ~= nil
end

-- Retries stops that had no known pid yet.
-- Cheap -- normally a no-op.
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

-- Reads the same two sliders Audio Plugin itself multiplies together for music volume (see play_file.lua's volume_adjustment) -- both default to 100 (unset), matching what it does.
local function read_volume_sliders()
	local master = Application.user_setting("sound_settings", "option_master_slider") or 100
	local music = Application.user_setting("sound_settings", "options_music_slider") or 100
	return master, music
end

-- fade-in if opts.fade_in, plus a natural-end fade-out if duration_seconds is known -- neither for opts.native_loop (ffplay's -loop re-triggers baked-in filters every iteration, so a fade would recur forever).
-- ffmpeg allows multiple comma-separated afade instances in one chain, each scoped to its own time window.
local function build_afade(opts)
	if opts.native_loop then
		return nil
	end

	local afade = nil

	if opts.fade_in then
		afade = string.format("t=in:d=%s", FADE_IN_SECONDS)
	end

	if opts.duration_seconds and opts.duration_seconds > (FADE_IN_SECONDS + FADE_OUT_SECONDS) then
		local fade_out_clause = string.format(
			"afade=t=out:st=%s:d=%s", opts.duration_seconds - FADE_OUT_SECONDS, FADE_OUT_SECONDS)
		afade = afade and (afade .. "," .. fade_out_clause) or fade_out_clause
	end

	return afade
end

-- Relaunches the current track re-seeked to its own elapsed position, so a slider change actually reaches a track that's already playing.
-- Only ever called from AudioClient.update()'s slider check below.
local function relaunch_at_current_volume()
	if not current_play_file_id or not current_file_path then
		return
	end

	log_fn(string.format("[volume] relaunching %s at %.1fs (master=%s, music=%s)",
		current_file_path, current_elapsed, tostring(current_master_slider), tostring(current_music_slider)))

	stop_id(current_play_file_id) -- Immediate, not crossfade-scheduled: a continuation of the same track, not a switch to a different one.

	local remaining_duration = current_total_duration and math.max(current_total_duration - current_elapsed, 0) or nil
	local on_finished = current_on_finished
	local native_loop = current_native_loop
	local seek_position = current_elapsed

	local play_file_id
	play_file_id = audio_mod.play_file(current_file_path, {
		audio_type = "music",
		loop = native_loop and 0 or 1,
		afade = build_afade({ native_loop = native_loop, duration_seconds = remaining_duration, fade_in = false }),
		pos = seek_position > 0 and seek_position or nil,
		track_status = function()
			if on_finished and current_play_file_id == play_file_id then
				on_finished()
			end
		end,
	})

	current_play_file_id = play_file_id
end

-- Call periodically to catch late pids, advance crossfade timers, and check the volume sliders.
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

	volume_check_elapsed = volume_check_elapsed + dt
	if volume_check_elapsed < VOLUME_CHECK_INTERVAL_SECONDS then
		return
	end
	volume_check_elapsed = 0

	local master_slider, music_slider = read_volume_sliders()
	if master_slider ~= current_master_slider or music_slider ~= current_music_slider then
		current_master_slider, current_music_slider = master_slider, music_slider
		relaunch_at_current_volume()
	end
end

-- Immediate silence (native-music fallback, mod unload) -- not a handoff, unlike AudioClient.play's crossfade switch.
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

-- mod.on_unload only.
-- The normal stop path needs the game's own network manager to relay a kill to DarktideLocalServer, which can be torn down by then on a normal quit, leaving the track running.
-- This kills directly via a synchronous pid lookup + os.execute(), needing nothing the game might already be tearing down -- still can't help a hard crash.
-- Blocks the calling thread, so never call this outside shutdown.
function AudioClient.shutdown()
	if not audio_mod or not _os or not _os.execute then
		AudioClient.stop()
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

	AudioClient.stop() -- Cheap extra insurance in case the normal path does land.
end

-- Plays file_path as 2D music, crossfading with whatever was playing (see the header note).
-- Returns false if Audio Plugin isn't available (caller should fall back to native music).
--
-- opts.duration_seconds	-- Schedules the natural-end fade-out.
-- opts.fade_in				-- Only for an actual context change, not for advancing within an unchanged one (playlist continuation, or a loop's own repeats).
-- opts.native_loop			-- ffplay `loop = 0` for a single-file context instead of relaunch-per-repeat.
-- opts.on_finished			-- Fires once on natural end. Never with native_loop. Not for an interrupted play.
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

	local on_finished = opts.on_finished

	-- Declared before assignment: the closure needs the upvalue filled in after this call, not the stale value `local x = f(x)` would capture.
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
