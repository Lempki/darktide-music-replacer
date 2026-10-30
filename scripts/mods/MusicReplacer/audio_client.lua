-- Plays the music inside the game through player.lua, one song at a time with crossfades between them.
-- A switch is a true crossfade: the outgoing song fades out while the incoming one fades in.
-- The volume sliders set every stream's gain directly, up or down, so no slider change restarts a song.
-- The Custom Music Volume setting and an open menu scale that gain too, the menu with a short fade.
-- Each song also has its own level, from evening out its loudness, which it keeps from its start.
-- A file that cannot be opened behaves like a track that ended at once, so MusicReplacer.lua's quick-end guard handles it.
-- When the audio device is lost and XAudio2 cannot follow, the engine is rebuilt and the song resumes where it was.
--
-- A song that fades out is paused and parked rather than freed.
-- If the mod resumes a parked song, the same stream fades back in from exactly where it stopped.
-- Nothing is reopened or sought, so no second of the song plays twice.

local AudioClient = {}

-- The Fade Length setting: how long a switch crossfades, and how long a song that is not looping fades out at its end.
-- That end fade starts this long before the song's end, or halfway through a shorter song, so the song is silent as it ends.
local fade_seconds = 2
local STOP_FADE_SECONDS = 0.5

-- How long the music takes to go down to its menu volume, or back up.
local MENU_FADE_SECONDS = 0.5

-- How long a faded-out song stays parked, since most returns, like combat after a lull, come sooner.
-- Each parked song holds its 4-second buffer pool, about 0.7 MB for 44.1 kHz stereo, which grows with the rate and channels.
local PARK_SECONDS = 60

-- Parked songs beyond this are freed, oldest first. Each also keeps its file open.
local MAX_PARKED = 4

-- Opening a file slower than this is logged, since it stalls the game's thread for that long.
local SLOW_OPEN_MS = 100

-- Recoveries in a row before giving up, until the mod is turned on again or the folders are rescanned.
-- Playing well for HEALTHY_SECONDS resets the count.
local MAX_RECOVERIES = 3
local HEALTHY_SECONDS = 30

-- How often to try again while Windows has no audio output, such as after the only headset was unplugged.
local RETRY_SECONDS = 5

local STATS_LOG_SECONDS = 300

local Player = nil
local disk_path = function(file_path) return file_path end
local level_of = function() return 1 end
local log = function() end

local current = nil -- Fields: stream, file_path, loop, level, duration, on_finished, elapsed, end_fading.
local outgoing = {} -- { stream, file_path, loop, level, parked_elapsed } for songs fading out or parked, after a switch or a stop.
local finished_elapsed = 0 -- The last finished track's elapsed time, which on_finished reads through elapsed().
local finished_duration = nil -- The last finished track's length, which on_finished reads through duration().
local gain = 1
local current_master_slider = nil
local current_music_slider = nil
local volume = 1 -- The Custom Music Volume setting, as a linear amplitude scale.
local menu_target = 1 -- The menu volume while a menu is open, else 1.
local menu_level = 1 -- Where the fade toward menu_target is now.
local menu_rate = 0 -- How far menu_level moves per second.
local recoveries = 0
local healthy_elapsed = 0
local retry_elapsed = 0
local broken = nil -- Why playback gave up for the session, or nil.
local engine_suspect = nil -- Why a fading song failed while no song played, which the engine may not have reported itself.
local stats_elapsed = 0
local longest_gap = 0
local used = false -- Set by the first play, so the stats only show once music has played.

-- `options.player` is an initialized player.lua.
-- `options.disk_path(file_path)` turns a library path into a path on disk.
-- `options.level_of(file_path)` gives a song's own volume scale, 1 by default.
function AudioClient.init(logger, options)
	log = logger or log
	Player = options.player
	disk_path = options.disk_path or disk_path
	level_of = options.level_of or level_of
end

function AudioClient.available()
	return Player ~= nil and broken == nil and Player.available()
end

-- True when playback is unavailable only for a reason that can pass, such as having no audio output.
-- AudioClient.update() tries again every few seconds, and AudioClient.available() turns true once it works.
function AudioClient.can_retry()
	return Player ~= nil and broken == nil and Player.can_retry()
end

-- Lets playback try again after it gave up for the session, as when the player turns the mod on again or rescans the folders.
function AudioClient.try_again()
	if broken then
		log("[player] trying playback again after giving up")
	end
	broken = nil
	recoveries = 0
end

-- Why playback is unavailable, or nil.
function AudioClient.error()
	return broken or (Player and Player.error())
end

-- Seconds since the current track started. After a track ends, its time until the next play or stop.
function AudioClient.elapsed()
	return current and current.elapsed or finished_elapsed
end

-- Seconds into the current file.
function AudioClient.position()
	return current and current.stream and current.stream:position() or 0
end

function AudioClient.is_playing()
	return current ~= nil
end

local function duration_of(entry)
	return (entry.stream and entry.stream.duration) or entry.duration
end

-- The current song's length in seconds, from its decoder or the library, or nil.
-- After a track ends, its length until the next play or stop.
function AudioClient.duration()
	if current then
		return duration_of(current)
	end
	return finished_duration
end

-- The Custom Music Volume, the menu lowering where its fade is now, and the current song's own level, as linear scales.
function AudioClient.levels()
	return volume, menu_level, current and current.level or 1
end

-- How loud the music sounds now, as a share of full scale, for the debug overlay's meter.
-- During a crossfade it is the louder of the two songs.
function AudioClient.meter()
	local loudest = current and current.stream and current.stream:audible_level() or 0
	for _, entry in ipairs(outgoing) do
		if entry.stream then
			loudest = math.max(loudest, entry.stream:audible_level())
		end
	end
	return loudest
end

-- The keys are spelled as the game's sound_settings.lua spells them, "option_" for the master slider and "options_" for music.
local function read_sliders()
	local master = Application.user_setting("sound_settings", "option_master_slider") or 100
	local music = Application.user_setting("sound_settings", "options_music_slider") or 100
	return master, music
end

-- The game's master and music sliders, the Custom Music Volume setting, and the menu fade, as a linear amplitude scale.
local function current_gain()
	return current_master_slider * current_music_slider / 10000 * volume * menu_level
end

-- Reads the sliders and sets every stream's gain at once.
local function apply_gain()
	current_master_slider, current_music_slider = read_sliders()
	gain = current_gain()

	if current and current.stream then
		current.stream:set_gain(gain * current.level)
	end
	for _, entry in ipairs(outgoing) do
		entry.stream:set_gain(gain * entry.level)
	end
end

-- Moves menu_level toward menu_target. Returns true while it moves.
local function move_menu_level(dt)
	if menu_level == menu_target then
		return false
	end

	local step = menu_rate * dt
	if math.abs(menu_target - menu_level) <= step then
		menu_level = menu_target
	elseif menu_target > menu_level then
		menu_level = menu_level + step
	else
		menu_level = menu_level - step
	end
	return true
end

-- Sets the Fade Length, in seconds. 0 switches at once.
function AudioClient.set_fade_seconds(seconds)
	fade_seconds = math.max(0, seconds)
end

-- Sets the Custom Music Volume, as a linear amplitude scale, at once.
function AudioClient.set_volume(scale)
	if scale ~= volume then
		volume = scale
		apply_gain()
	end
end

-- Asks every song for its own level again, as when evening out is turned on or off, and applies it at once.
function AudioClient.refresh_levels()
	if current then
		current.level = level_of(current.file_path)
	end
	for _, entry in ipairs(outgoing) do
		entry.level = level_of(entry.file_path)
	end
	apply_gain()
end

-- Sets the level to fade to while a menu is open, or 1 while none is. Call every tick.
function AudioClient.set_menu_volume(target)
	if target ~= menu_target then
		menu_target = target
		menu_rate = math.abs(menu_target - menu_level) / MENU_FADE_SECONDS
	end
end

local function fade_out(entry, seconds)
	entry.stream:fade_to(0, seconds)
	outgoing[#outgoing + 1] = { stream = entry.stream, file_path = entry.file_path, loop = entry.loop, level = entry.level, parked_elapsed = nil }
end

-- Frees the oldest parked songs beyond MAX_PARKED. The list is in the order the songs faded out.
local function free_extra_parked()
	local parked = 0
	for index = #outgoing, 1, -1 do
		local entry = outgoing[index]
		if entry.parked_elapsed then
			parked = parked + 1
			if parked > MAX_PARKED then
				entry.stream:destroy()
				table.remove(outgoing, index)
			end
		end
	end
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

-- Destroys every stream and recreates the engine on next use.
-- Returns false once that has happened more than MAX_RECOVERIES times in a row, and playback gives up until AudioClient.try_again().
local function rebuild_engine(reason)
	destroy_all()
	Player.reset()
	engine_suspect = nil

	recoveries = recoveries + 1
	if recoveries > MAX_RECOVERIES then
		broken = string.format("gave up after %d recoveries in a row, the last after: %s", MAX_RECOVERIES, reason)
		log("[player] " .. broken)
		return false
	end

	return true
end

-- True while a song is fading out, which shows the engine still plays.
local function has_live_stream()
	for _, entry in ipairs(outgoing) do
		if not entry.parked_elapsed and not entry.stream:failure() and not entry.stream:file_failure() then
			return true
		end
	end
	return false
end

-- Takes the fading or parked stream of `file_path` out of the outgoing list, or returns nil.
-- A stream that loops is only taken back to loop again, since one that does not loop must end for the next pick to follow.
local function take_outgoing(file_path, loop)
	for index, entry in ipairs(outgoing) do
		local stream = entry.stream
		if entry.file_path == file_path and entry.loop == loop and not stream:ended() and not stream:failure() and not stream:file_failure() then
			table.remove(outgoing, index)
			return entry.stream
		end
	end
	return nil
end

-- The length a song's fades go by, or nil for a looping song, which never fades out, or one whose length is not known.
-- The decoder's duration matches its positions, while the library's can be off by a second or more.
-- It is also there before the library has measured the file.
local function song_duration(stream, loop, library_duration)
	if loop then
		return nil
	end
	return stream.duration or library_duration
end

-- How long a song fades in, and out at its end: the Fade Length, or half the song when it is shorter than two fades.
-- Longer fades would overlap, so the song would never reach full level, or play silent throughout.
local function song_fade_seconds(duration)
	if duration then
		return math.min(fade_seconds, duration / 2)
	end
	return fade_seconds
end

-- Plays file_path, crossfading with whatever was playing.
-- opts: fade_in, loop, start_position, duration_seconds, and on_finished(failed).
-- Returns false when playback is unavailable.
function AudioClient.play(file_path, opts)
	if not AudioClient.available() then
		return false
	end

	-- A failure that outlived its stream means the engine stopped working while no song needed it, so it is rebuilt first.
	local engine_failure = Player.engine_failure() or engine_suspect
	if engine_failure then
		log(string.format("[player] the engine stopped working (%s), rebuilding it", engine_failure))
		if not rebuild_engine(engine_failure) or not AudioClient.available() then
			return false
		end
	end

	opts = opts or {}

	-- Only a resume continues a parked song. A fresh pick of the same file starts it over, as the resume rules want.
	local revived = opts.start_position and take_outgoing(file_path, opts.loop == true)

	if current and current.stream then
		if opts.fade_in then
			fade_out(current, fade_seconds)
		else
			current.stream:destroy() -- A continuation follows a track that has already ended.
		end
	end

	used = true
	finished_elapsed = 0
	finished_duration = nil
	current_master_slider, current_music_slider = read_sliders()
	gain = current_gain()
	local level = level_of(file_path)

	local loop = opts.loop == true
	local stream, err

	if revived then
		stream = revived
		stream:resume()
		stream:set_gain(gain * level)
		stream:fade_to(1, opts.fade_in and song_fade_seconds(song_duration(stream, loop, opts.duration_seconds)) or 0)
		log(string.format("[player] continuing %s from %.1fs, where it faded out", file_path, stream:position()))
	else
		local open_opts = {
			start_position = opts.start_position,
			loop = loop,
			gain = gain * level,
			fade = opts.fade_in and 0 or 1,
		}
		local refused_voice
		stream, err, refused_voice = Player.open(disk_path(file_path), open_opts)

		if Player.last_open_ms() >= SLOW_OPEN_MS then
			log(string.format("[timing] opening %s took %d ms", file_path, Player.last_open_ms()))
		end

		-- A dead engine refuses every voice, and so can one file's format.
		-- With no song fading out to show the engine still plays, it is rebuilt and the file gets one more try.
		-- That is not counted as a recovery, since a file the engine refuses again was the cause.
		if not stream and refused_voice and not has_live_stream() then
			log(string.format("[player] %s was refused a voice (%s), rebuilding the engine and trying once more", file_path, tostring(err)))
			destroy_all()
			Player.reset()
			if AudioClient.available() then
				stream, err = Player.open(disk_path(file_path), open_opts)
			end
		end

		if stream then
			if opts.fade_in then
				stream:fade_to(1, song_fade_seconds(song_duration(stream, loop, opts.duration_seconds)))
			end
		else
			log(string.format("[player] %s could not be played: %s", file_path, tostring(err)))
		end
	end

	current = {
		stream = stream,
		file_path = file_path,
		loop = loop,
		level = level,
		duration = opts.duration_seconds,
		on_finished = opts.on_finished,
		elapsed = 0,
		end_fading = false,
	}

	return true
end

-- Lets the current song play on as `file_path` for a new context, with that context's own ending in `opts.on_finished`.
-- For a copy of the song that is playing, so it continues instead of starting over. Returns false when nothing plays.
function AudioClient.retarget(file_path, opts)
	if not current then
		return false
	end

	current.file_path = file_path
	current.on_finished = opts.on_finished
	current.duration = opts.duration_seconds
	return true
end

-- Fades the current track out quickly, for falling back to the game's music and for contexts without music.
function AudioClient.stop()
	if current and current.stream then
		fade_out(current, STOP_FADE_SECONDS)
	end
	current = nil
	finished_elapsed = 0
	finished_duration = nil
end

-- Calls on_finished with true when the file could not be played at all, or `file_failed` says it stopped for its own reasons.
local function finish(file_failed)
	local on_finished = current.on_finished
	local failed = file_failed == true or current.stream == nil
	finished_elapsed = current.elapsed
	finished_duration = duration_of(current)
	if current.stream then
		current.stream:destroy()
	end
	current = nil

	if on_finished then
		on_finished(failed)
	end
end

-- Rebuilds the engine after a failure and resumes the current song where it was.
local function recover(reason)
	local resume = current
	local position = resume and resume.stream and resume.stream:position() or 0

	if not rebuild_engine(reason) then
		return
	end

	log(string.format("[player] playback failed (%s), rebuilding the engine and resuming at %.1fs", reason, position))

	if resume then
		local resumed = AudioClient.play(resume.file_path, {
			start_position = position,
			loop = resume.loop,
			duration_seconds = resume.duration,
			on_finished = resume.on_finished,
			fade_in = true,
		})

		if not resumed and AudioClient.can_retry() then
			log(string.format("[player] no audio output (%s), trying again every %ds", tostring(Player.error()), RETRY_SECONDS))
		end
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

	if stream:file_failure() then
		log(string.format("[player] %s could not be played: %s", current.file_path, stream:file_failure()))
		finish(true)
		return
	end

	if stream:ended() then
		finish()
		return
	end

	local duration = song_duration(stream, current.loop, current.duration)
	if duration and not current.end_fading and stream:position() >= duration - song_fade_seconds(duration) then
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
		log(string.format("[player] pools %d KB, Lua heap %d KB, slowest refill %.1f ms, longest update gap %.2fs",
			Player.pool_bytes() / 1024, collectgarbage("count"), Player.slowest_fill_ms(), longest_gap))
		longest_gap = 0
	end
end

-- Call every tick: follows the sliders and the menu volume, moves fades, refills queues, and finishes ended tracks.
function AudioClient.update(dt)
	if not Player then
		return
	end

	-- A lost audio output leaves no engine to rebuild until Windows has an output again.
	-- Retrying does not count as a recovery, so a headset that stays unplugged for long never gives up playback.
	if AudioClient.can_retry() then
		retry_elapsed = retry_elapsed + dt
		if retry_elapsed >= RETRY_SECONDS then
			retry_elapsed = 0
			Player.reset()
			if Player.available() then
				log("[player] the audio output is back")
			end
		end
	else
		retry_elapsed = 0
	end

	log_stats(dt)

	local master, music = read_sliders()
	if move_menu_level(dt) or master ~= current_master_slider or music ~= current_music_slider then
		apply_gain()
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

		-- A song that plays on shows the engine works, so a fading song's failure only counts against the engine without one.
		-- A stall, the usual sign of a lost device, is never reported by the engine itself.
		local current_plays = current and current.stream and not current.stream:failure()
		if stream:failure() and not current_plays then
			engine_suspect = engine_suspect or stream:failure()
		end

		if stream:ended() or stream:failure() or stream:file_failure() or (entry.parked_elapsed and entry.parked_elapsed >= PARK_SECONDS) then
			stream:destroy()
			table.remove(outgoing, index)
		elseif not entry.parked_elapsed and not stream:fading() then
			stream:pause()
			entry.parked_elapsed = 0
		end
	end

	free_extra_parked()
end

-- Call from mod.on_unload. Stops everything at once and releases XAudio2.
function AudioClient.shutdown()
	destroy_all()

	if Player then
		Player.reset()
	end
end

return AudioClient
