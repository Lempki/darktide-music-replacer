-- Direct counterpart of audio_client.lua with the same interface, playing through direct_player.lua inside the game.
-- A switch is a true crossfade: the outgoing song fades out while the incoming one fades in.
-- The volume sliders set every stream's gain directly, up or down, so no slider change restarts a song.
-- A file that cannot be opened behaves like a track that ended at once, so MusicReplacer.lua's quick-end guard handles it.
-- When the audio device is lost and XAudio2 cannot follow, the engine is rebuilt and the song resumes where it was.
--
-- A song that fades out is paused and parked rather than freed. If the mod resumes that song while it is parked,
-- the same stream fades back in from exactly where it stopped, with no reopening, no seek, and no repeated seconds.

local DirectAudioClient = {}

local CROSSFADE_SECONDS = 2
local NATURAL_END_FADE_SECONDS = 2 -- Also how long before the end a song that is not looping starts fading out.
local STOP_FADE_SECONDS = 0.5

-- How long a faded-out song stays parked. Each holds about 0.7 MB, and most returns, like combat after a lull, come sooner.
local PARK_SECONDS = 60

-- Recoveries in a row before giving up for the session. Playing well for HEALTHY_SECONDS resets the count.
local MAX_RECOVERIES = 3
local HEALTHY_SECONDS = 30

local STATS_LOG_SECONDS = 300

local DirectPlayer = nil
local disk_path = function(file_path) return file_path end
local log_fn = function() end

local current = nil -- { stream, file_path, loop, duration, on_finished, elapsed, end_fading }
local outgoing = {} -- { stream, file_path, parked_elapsed } for songs fading out or parked, after a switch or a stop.
local finished_elapsed = 0 -- The last finished track's elapsed time, which on_finished reads through elapsed() like with audio_client.lua.
local gain = 1
local current_master_slider = nil
local current_music_slider = nil
local recoveries = 0
local healthy_elapsed = 0
local broken = nil -- Why direct playback gave up for the session, or nil.
local stats_elapsed = 0
local longest_gap = 0
local used = false -- Set by the first play, so the stats only show once direct playback is in use.

-- `options.direct_player` is an initialized direct_player.lua.
-- `options.disk_path(file_path)` turns a library path into a path on disk.
function DirectAudioClient.init(log, options)
	log_fn = log or log_fn
	DirectPlayer = options.direct_player
	disk_path = options.disk_path or disk_path
end

function DirectAudioClient.available()
	return DirectPlayer ~= nil and broken == nil and DirectPlayer.available()
end

-- Why direct playback is unavailable, or nil.
function DirectAudioClient.error()
	return broken or (DirectPlayer and DirectPlayer.error())
end

-- Seconds since the current track started. After a track ends, its time until the next play or stop.
function DirectAudioClient.elapsed()
	return current and current.elapsed or finished_elapsed
end

-- Seconds into the current file.
function DirectAudioClient.position()
	return current and current.stream and current.stream:position() or 0
end

function DirectAudioClient.is_playing()
	return current ~= nil
end

local function read_sliders()
	local master = Application.user_setting("sound_settings", "option_master_slider") or 100
	local music = Application.user_setting("sound_settings", "options_music_slider") or 100
	return master, music
end

-- The same level the Audio Plugin bakes into ffplay, as a linear amplitude scale.
local function slider_gain(master, music)
	return master * music / 10000
end

local function fade_out(entry, seconds)
	entry.stream:fade_to(0, seconds)
	outgoing[#outgoing + 1] = { stream = entry.stream, file_path = entry.file_path, parked_elapsed = nil }
end

local function destroy_all()
	if current and current.stream then
		current.stream:destroy()
	end
	current = nil

	for _, entry in ipairs(outgoing) do
		entry.stream:destroy()
	end
	outgoing = {}
end

-- Takes the fading or parked stream of `file_path` out of the outgoing list, or returns nil.
local function take_outgoing(file_path)
	for index, entry in ipairs(outgoing) do
		if entry.file_path == file_path and not entry.stream:ended() and not entry.stream:failure() then
			table.remove(outgoing, index)
			return entry.stream
		end
	end
	return nil
end

-- Plays file_path, crossfading with whatever was playing. Takes the same opts as audio_client.lua's play.
-- Returns false when direct playback is unavailable.
function DirectAudioClient.play(file_path, opts)
	if not DirectAudioClient.available() then
		return false
	end

	opts = opts or {}

	-- Only a resume continues a parked song. A fresh pick of the same file starts it over, as the resume rules want.
	local revived = opts.start_position and take_outgoing(file_path)

	if current and current.stream then
		if opts.fade_in then
			fade_out(current, CROSSFADE_SECONDS)
		else
			current.stream:destroy() -- A continuation follows a track that has already ended.
		end
	end

	used = true
	finished_elapsed = 0
	current_master_slider, current_music_slider = read_sliders()
	gain = slider_gain(current_master_slider, current_music_slider)

	local loop = opts.native_loop == true
	local stream, err

	if revived then
		stream = revived
		stream:resume()
		stream:set_gain(gain)
		stream:fade_to(1, opts.fade_in and CROSSFADE_SECONDS or 0)
		log_fn(string.format("[direct] continuing %s from %.1fs, where it faded out", file_path, stream:position()))
	else
		stream, err = DirectPlayer.open(disk_path(file_path), {
			start_position = opts.start_position,
			loop = loop,
			gain = gain,
			fade = opts.fade_in and 0 or 1,
		})

		if stream then
			if opts.fade_in then
				stream:fade_to(1, CROSSFADE_SECONDS)
			end
		else
			log_fn(string.format("[direct] %s could not be played: %s", file_path, tostring(err)))
		end
	end

	current = {
		stream = stream,
		file_path = file_path,
		loop = loop,
		duration = opts.duration_seconds,
		on_finished = opts.on_finished,
		elapsed = 0,
		end_fading = false,
	}

	return true
end

-- Fades the current track out quickly, for the native-music fallback and contexts without music.
function DirectAudioClient.stop()
	if current and current.stream then
		fade_out(current, STOP_FADE_SECONDS)
	end
	current = nil
	finished_elapsed = 0
end

local function finish()
	local on_finished = current.on_finished
	finished_elapsed = current.elapsed
	if current.stream then
		current.stream:destroy()
	end
	current = nil

	if on_finished then
		on_finished()
	end
end

-- Rebuilds the engine after a failure and resumes the current song where it was.
local function recover(reason)
	local resume = current
	local position = resume and resume.stream and resume.stream:position() or 0

	destroy_all()
	DirectPlayer.reset()

	recoveries = recoveries + 1
	if recoveries > MAX_RECOVERIES then
		broken = string.format("gave up after %d recoveries in a row, the last after: %s", MAX_RECOVERIES, reason)
		log_fn("[direct] " .. broken)
		return
	end

	log_fn(string.format("[direct] playback failed (%s), rebuilding the engine and resuming at %.1fs", reason, position))

	if resume then
		DirectAudioClient.play(resume.file_path, {
			start_position = position,
			native_loop = resume.loop,
			duration_seconds = resume.duration,
			on_finished = resume.on_finished,
			fade_in = true,
		})
	end
end

local function update_current(dt)
	current.elapsed = current.elapsed + dt
	local stream = current.stream

	if not stream then
		finish()
		return
	end

	stream:update(dt)

	if stream:failure() then
		recover(stream:failure())
		return
	end

	if stream:ended() then
		finish()
		return
	end

	-- The decoder's own duration matches its positions, while the library's can differ by a second or more for the same file.
	-- A caller without a duration asked for no fade-out, as for a single file that is about to loop.
	local duration = current.duration and (stream.duration or current.duration)
	if duration and not current.loop and not current.end_fading and stream:position() >= duration - NATURAL_END_FADE_SECONDS then
		current.end_fading = true
		stream:fade_to(0, math.max(0.1, duration - stream:position()))
	end
end

local function log_stats(dt)
	if not used then
		return
	end

	longest_gap = math.max(longest_gap, dt)
	stats_elapsed = stats_elapsed + dt
	if stats_elapsed >= STATS_LOG_SECONDS then
		stats_elapsed = 0
		log_fn(string.format("[direct] pools %d KB, Lua heap %d KB, slowest refill %.1f ms, longest update gap %.2fs",
			DirectPlayer.pool_bytes() / 1024, collectgarbage("count"), DirectPlayer.slowest_fill_ms(), longest_gap))
		longest_gap = 0
	end
end

-- Call every tick: follows the sliders, moves fades, refills queues, and finishes ended tracks.
function DirectAudioClient.update(dt)
	if not DirectPlayer then
		return
	end

	log_stats(dt)

	local master, music = read_sliders()
	if master ~= current_master_slider or music ~= current_music_slider then
		current_master_slider, current_music_slider = master, music
		gain = slider_gain(master, music)

		if current and current.stream then
			current.stream:set_gain(gain)
		end
		for _, entry in ipairs(outgoing) do
			entry.stream:set_gain(gain)
		end
	end

	if current then
		update_current(dt)
	end

	if current and current.stream and not current.stream:failure() then
		healthy_elapsed = healthy_elapsed + dt
		if healthy_elapsed >= HEALTHY_SECONDS then
			recoveries = 0
		end
	else
		healthy_elapsed = 0
	end

	for index = #outgoing, 1, -1 do
		local entry = outgoing[index]
		local stream = entry.stream
		stream:update(dt)

		if entry.parked_elapsed then
			entry.parked_elapsed = entry.parked_elapsed + dt
		end

		if stream:ended() or stream:failure() or (entry.parked_elapsed and entry.parked_elapsed >= PARK_SECONDS) then
			stream:destroy()
			table.remove(outgoing, index)
		elseif not entry.parked_elapsed and not stream:fading() then
			stream:pause()
			entry.parked_elapsed = 0
		end
	end
end

-- Call from mod.on_unload. Stops everything at once and releases XAudio2.
function DirectAudioClient.shutdown()
	destroy_all()

	if DirectPlayer then
		DirectPlayer.reset()
	end
end

return DirectAudioClient
