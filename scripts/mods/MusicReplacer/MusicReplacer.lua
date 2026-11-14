local mod = get_mod("MusicReplacer")

-- mod:io_dofile paths are relative to "mods/" and include this mod's own folder name.
local Contexts = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/contexts")
local Context = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/context")
local Suppression = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/suppression")
local Library = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/library")
local Playlist = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/playlist")
local RemovedSongs = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/removed_songs")
local ResumePoints = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/resume_points")
local EventProbe = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/event_probe")
local MissionProbe = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/mission_probe")
local BossProbe = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/boss_probe")
local NativeFfi = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/native_ffi")
local MediaDecoder = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/media_decoder")
local AudioFolders = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/audio_folders")
local XAudio = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/xaudio")
local Player = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/player")
local AudioClient = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/audio_client")
local LoudnessMeter = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/loudness_meter")
local Loudness = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/loudness")
local DiagnosticLog = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/diagnostic_log")
local DebugOverlay = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/debug_overlay")
local OnScreenMessage = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/on_screen_message")

local WwiseGameSyncManager = require("scripts/managers/wwise_game_sync/wwise_game_sync_manager")

DiagnosticLog.init(mod, NativeFfi)
local log = DiagnosticLog.write
local log_detail = DiagnosticLog.detail

-- tools/build.ps1 stamps the packaged info.json with the commit and build time, which tells two builds of one version apart.
-- The console log gets the line too, so a report without the mod's own log file still names the build.
local version_line = string.format("version %s, build %s",
	tostring(mod:get_metadata("version")), tostring(mod:get_metadata("build") or "unknown"))
mod:info("%s", version_line)
log("[startup] " .. version_line)

-- ###########################################################################
-- Playback Orchestration
-- ###########################################################################
-- Combines "what context" (context.lua) with "is there a file for it" (library.lua) to decide what audio_client.lua does.
-- Apart from Silence and a pause, the game's music is only silenced once a replacement is available.
-- So a context with no file falls back to the game's music by construction.

local current_context = nil

-- False while the mod is turned off in the mod options.
-- DMF then disables the mod's hooks but keeps calling update, so nothing must start playing while this is false.
local enabled = true

-- True while playback is unavailable: before it has started, while Windows has no audio output, and once it gives up for the session.
local playback_lost = true

-- A track that ends within QUICK_END_SECONDS of starting did not really play, for example because Windows could not decode the file.
-- After MAX_QUICK_ENDS in a row from one folder, that folder stops retrying until the folders are listed again.
-- An override folder then gives way to the next folder, and a context's own folder to the game's music.
local QUICK_END_SECONDS = 3
local MAX_QUICK_ENDS = 3

local quick_ends = {} -- folder -> consecutive tracks from it that ended right after starting.
local gave_up = {} -- folder -> true once that folder stopped retrying.

-- folder -> true for an override folder the library listed songs for, but that had none left to pick, as after files were deleted.
-- It is skipped until the folders are listed again, so the override check does not keep switching back to it.
local emptied = {}

-- The custom track AudioClient was last asked to play, so a context change can remember where it stopped.
local playing_track = nil -- Its fields are context_name, file_path, duration, is_only_file, and position, its last known position.

-- True while the Pause / Resume key holds the song in playing_track, at its `position`.
-- AudioClient has stopped it, but the game's music stays silenced, so the situation is quiet until the song resumes.
local paused = false

-- The situation that takes over once the song playing now ends, while Let Songs Finish holds the change back, else nil.
-- The current context stays the one whose song plays, so the keys and the overlay still speak about that song.
local context_after_song = nil

-- The song that was playing when playback stopped working, as when the only headset is unplugged: context_name, file_path, position.
-- It continues where it was once playback works again, if its context is still the one playing.
local lost_track = nil
local was_playing = false -- Whether a custom song played on the last tick, so a song that had already stopped is never taken as lost.

-- The folder the current context's songs come from: its own, or an override folder inside it, such as "boss/chaos_spawn".
-- Nil while the context plays no custom music by its setting, so no override is looked for.
local current_folder = nil

-- How often to check whether another override folder applies, such as once the game names the boss.
local OVERRIDE_CHECK_SECONDS = 0.5
local override_check_elapsed = 0

-- What the current context plays, for the debug overlay: a choice's name, or why the game's music plays.
local context_status = "Vanilla"

local SOURCE_NAMES = { custom = "Custom", game = "Vanilla", silence = "Silence" }

-- What a context plays, from its setting: "custom", "game", or "silence".
-- Any other stored value plays as "custom", so a value from an option the dropdown does not offer still plays custom songs.
local function source_of(context_name)
	local source = mod:get("source_" .. context_name)
	return SOURCE_NAMES[source] and source or "custom"
end

-- The volume settings are percentages of the music's normal level.
-- DMF writes every setting's default from MusicReplacer_data.lua before this script runs, so a setting never reads as nil.
local function custom_volume()
	return mod:get("custom_music_volume") / 100
end

-- Moving from one menu to another, such as from a vendor back to the Esc menu, reports no menu for a moment.
-- So the music stays lowered until no menu has been open for this long.
local MENU_CLOSED_SECONDS = 0.5

local menu_closed_elapsed = MENU_CLOSED_SECONDS

local function menu_volume(dt)
	if Context.menu_open() then
		menu_closed_elapsed = 0
	else
		menu_closed_elapsed = menu_closed_elapsed + dt
	end

	return menu_closed_elapsed < MENU_CLOSED_SECONDS and mod:get("menu_volume") / 100 or 1
end

-- True when a song loops: a folder's only song always does, and with Repeat Song on, every song does.
local function loops(is_only_file)
	return is_only_file == true or mod:get("repeat_song") == true
end

-- True when a song that starts or changes now loops.
-- A song that Let Songs Finish waits for has to end, so the waiting situation can take over, and so does a key's song in its place.
local function plays_looping(is_only_file)
	return loops(is_only_file) and not context_after_song
end

local function remember_playing_track(next_context_name)
	if not playing_track or playing_track.context_name == next_context_name then
		return
	end

	-- AudioClient no longer holds a paused song, so it is remembered where it was paused.
	local stopped_at
	if paused then
		stopped_at = playing_track.position
	elseif AudioClient.is_playing() then
		stopped_at = AudioClient.position()
	else
		return
	end

	local position = ResumePoints.remember(playing_track.context_name, playing_track.file_path,
		stopped_at, playing_track.duration, loops(playing_track.is_only_file), next_context_name)

	if position then
		log(string.format("[resume] %s: remembering %s at %.1fs", playing_track.context_name, playing_track.file_path, position))
	end
end

-- Keeps where the song playing now stopped, for its folder, as the situation switches to another of its folders.
-- So a situation that moves back and forth between folders, as Rolling Steel's stages do, continues each folder's song.
local function remember_folder_song()
	if not playing_track or not AudioClient.is_playing() then
		return
	end

	local position = ResumePoints.remember_folder(current_folder, playing_track.file_path,
		AudioClient.position(), playing_track.duration, loops(playing_track.is_only_file))

	if position then
		log(string.format("[resume] %s: remembering %s at %.1fs for the %s folder", current_context, playing_track.file_path, position, current_folder))
	end
end

-- The folders `context_name` can play from, in order: its override folders that have songs, then its own.
local function folders_for(context_name)
	local folders = {}
	for _, key in ipairs(Context.override_keys(mod, context_name)) do
		local folder = context_name .. "/" .. key:lower()
		if not gave_up[folder] and not emptied[folder] and Library.has_files(folder) then
			folders[#folders + 1] = folder
		end
	end
	folders[#folders + 1] = context_name
	return folders
end

local function folder_for(context_name)
	return folders_for(context_name)[1]
end

-- The remembered song if `folder` still has that file, else the next song from Playlist.next().
-- Returns file_path, duration, is_only_file, and the start position of a resumed song.
-- A song is resumed only from the folder it played from, so a resume point from another folder gives way to a new pick.
local function choose_file(folder, resume_path, resume_position)
	if resume_path then
		local file_path, duration, is_only_file = Library.find_file(folder, resume_path)
		if file_path then
			return file_path, duration, is_only_file, resume_position
		end
	end

	return Playlist.next(folder, playing_track and playing_track.file_path)
end

-- Stops any custom song and hands the music back to the game.
-- `status`, when given, is the reason the debug overlay shows.
local function hand_back(status)
	if status then
		context_status = status
	end
	AudioClient.stop()
	Suppression.release()
end

local function song_name(file_path)
	return file_path:match("[^/]+$")
end

-- The localized `text_id`, formatted with `...`, for the on-screen message.
-- Song and folder names are the player's own text, and "{#" starts a tag in the game's markup, so it is broken up.
local function message_text(text_id, ...)
	local text = mod:localize(text_id, ...)
	return (text:gsub("{#", "{ #"))
end

local function show_message(text_id, ...)
	OnScreenMessage.show(message_text(text_id, ...))
end

local play_context
local play_track

-- The AudioClient.play options for `track` from `folder`, whose on_finished plays the context's next song.
-- `track` holds file_path, duration, is_only_file, start_position, fade_in, and fade_seconds, which only the keys set.
local function track_opts(context_name, folder, track)
	local duration = track.duration
	local is_looping = plays_looping(track.is_only_file)

	-- A looping song loops from its first play, with no seam, so it needs no end fade.
	return {
		duration_seconds = not is_looping and duration or nil,
		fade_in = track.fade_in,
		fade_seconds = track.fade_seconds,
		loop = is_looping,
		start_position = track.start_position,
		on_finished = function(failed)
			-- A loop only gets here if its file could not be played.
			-- After a context change, whatever triggered it already called play_context for the new context.
			if current_context ~= context_name then
				return
			end

			-- The song Let Songs Finish held the change back for has ended, so the situation that waited takes over.
			if context_after_song then
				local next_context = context_after_song
				log(string.format("[playback] %s: the song finished, so %s takes over", context_name, tostring(next_context)))
				current_context = next_context
				play_context(next_context, true)
				return
			end

			-- A file that could not be played always counts.
			-- Any other track counts when it ended within QUICK_END_SECONDS and before half its length, so a short song that plays through does not.
			-- An unmeasured file has its decoder's length instead, and without either, ending within QUICK_END_SECONDS is enough.
			-- So a file that ends at once cannot reopen every frame.
			local elapsed = AudioClient.elapsed()
			local length = duration or AudioClient.duration()
			local quick = failed or (elapsed < QUICK_END_SECONDS and (not length or elapsed < length / 2))
			if quick then
				quick_ends[folder] = (quick_ends[folder] or 0) + 1

				if quick_ends[folder] >= MAX_QUICK_ENDS then
					gave_up[folder] = true

					-- An override folder gives way to the next folder, which play_context picks below.
					if folder ~= context_name then
						log(string.format("[playback] %s: %d tracks in a row from the %s folder ended within %ds, trying the next folder until the folders are rescanned",
							context_name, MAX_QUICK_ENDS, folder, QUICK_END_SECONDS))
					else
						log(string.format("[playback] %s: %d tracks in a row ended within %ds, playing the game's music until the game restarts or the folders are rescanned",
							context_name, MAX_QUICK_ENDS, QUICK_END_SECONDS))
						hand_back("Vanilla, its songs would not play")
						return
					end
				end
			else
				quick_ends[folder] = 0
			end

			-- Repeat Song turned on too late for the stream to loop still repeats this song, from a new start.
			-- A song that ended at once is left to the checks above, so a broken file cannot repeat forever.
			if not quick and mod:get("repeat_song") then
				local file_path, file_duration, is_only_file = Library.find_file(folder, track.file_path)
				if file_path then
					log(string.format("[playback] %s: repeating %s", context_name, file_path))
					play_track(context_name, folder, { file_path = file_path, duration = file_duration, is_only_file = is_only_file })
					return
				end
			end

			-- A file that could not play is left out, so Previous Song never goes back to it.
			if not failed then
				Playlist.add_played(track.file_path)
			end

			play_context(context_name, false)
		end,
	}
end

-- Starts `track` from `folder` for `context_name`, as track_opts() describes it.
play_track = function(context_name, folder, track)
	local file_path, start_position = track.file_path, track.start_position

	local loudness = Loudness.describe(file_path)
	log(string.format("[playback] %s: %s %s%s (duration=%s%s%s)",
		context_name, start_position and "resuming" or "playing", file_path,
		start_position and string.format(" at %.1fs", start_position) or "",
		tostring(track.duration), plays_looping(track.is_only_file) and ", looping" or "", loudness and (", " .. loudness) or ""))

	playing_track = { context_name = context_name, file_path = file_path, duration = track.duration, is_only_file = track.is_only_file }

	AudioClient.play(file_path, track_opts(context_name, folder, track))
end

-- is_new_context separates a real context change from advancing within the same context.
-- Advancing means a playlist continuation, and only a real change should fade in again.
play_context = function(context_name, is_new_context)
	-- Whatever plays now is decided afresh, so no change waits for a song any more.
	context_after_song = nil

	if is_new_context then
		remember_playing_track(context_name)
		ResumePoints.enter(context_name)
		-- Previous Song stays within one situation, and a switch to an override folder or a replay starts the situation afresh too.
		Playlist.forget_history()
	end

	-- Whatever the context plays now replaces a paused song.
	paused = false
	current_folder = nil

	if not context_name then
		hand_back("Vanilla")
		return
	end

	local source = source_of(context_name)
	context_status = SOURCE_NAMES[source]

	if source == "game" then
		hand_back()
		log(string.format("[playback] %s: set to the game's music", context_name))
		return
	end

	if source == "silence" then
		AudioClient.stop()
		Suppression.engage(context_name)
		log(string.format("[playback] %s: set to silence", context_name))
		return
	end

	-- Playback that could not start, or gave up after repeated audio device failures, leaves the game's music alone.
	if not AudioClient.available() then
		hand_back("Vanilla, no audio output")
		return
	end

	local resume_path, resume_position = nil, nil
	if is_new_context then
		resume_path, resume_position = ResumePoints.take(context_name)
	end

	if lost_track then
		if lost_track.context_name == context_name then
			resume_path, resume_position = lost_track.file_path, lost_track.position
		end
		lost_track = nil
	end

	-- The first folder with a song to play wins, so an override folder whose files are gone gives way to the next.
	local folder, file_path, duration, is_only_file, start_position
	for _, candidate in ipairs(folders_for(context_name)) do
		folder = candidate
		if gave_up[folder] then
			break
		end

		-- A folder this situation switched away from earlier continues its own song first.
		local folder_path, folder_position = nil, nil
		if is_new_context then
			folder_path, folder_position = ResumePoints.take_folder(folder)
		end

		if folder_path then
			file_path, duration, is_only_file, start_position = choose_file(folder, folder_path, folder_position)
		else
			file_path, duration, is_only_file, start_position = choose_file(folder, resume_path, resume_position)
		end
		if file_path or folder == context_name then
			break
		end

		emptied[folder] = true
		log(string.format("[playback] %s: the %s folder has no songs left, trying the next folder", context_name, folder))
	end
	current_folder = folder

	-- Only the context's own folder gets here, since an override folder that gave up is left out.
	if gave_up[folder] then
		hand_back("Vanilla, its songs would not play")
		log(string.format("[playback] %s: its tracks would not play earlier, playing the game's music", context_name))
		return
	end

	if not file_path then
		-- No replacement is available, as with no folder, an empty folder, or a scan that has not finished.
		hand_back("Vanilla, no songs")
		log(string.format("[playback] %s: no file available, playing the game's music", context_name))
		return
	end

	Suppression.engage(context_name)

	local track = { file_path = file_path, duration = duration, is_only_file = is_only_file, start_position = start_position, fade_in = is_new_context }

	-- A lone song that the new context's folder holds alone too keeps playing instead of starting over.
	-- The player put the same song in both folders, so it is one piece of music across both contexts.
	local previous = playing_track
	if is_new_context and is_only_file and previous and previous.is_only_file and AudioClient.is_playing()
		and Library.same_song(previous.file_path, file_path) and AudioClient.retarget(file_path, track_opts(context_name, folder, track)) then
		log(string.format("[playback] %s: continuing %s, the same song as %s", context_name, file_path, previous.file_path))
		playing_track = { context_name = context_name, file_path = file_path, duration = duration, is_only_file = true, position = previous.position }
		return
	end

	-- The keys start their songs through play_manual_pick, which names them itself.
	if mod:get("song_change_messages") then
		show_message("song_now_playing", song_name(file_path))
	end

	play_track(context_name, folder, track)
end

-- Context changes are debounced, so a state that flickers and returns does not restart the track.
local DEBOUNCE_SECONDS = 0.6

-- Each change restarts the debounce, so states that keep flickering would never settle, as with the holds set to 0.
-- A pending change commits after this long anyway.
local MAX_DEBOUNCE_SECONDS = 3

-- Leaving the hub reports a loading screen for 1 to 2 seconds before the preparation screen.
-- So a change to a loading context waits LOADING_DEBOUNCE_SECONDS, and the hub song carries on into the preparation screen's.
-- The briefing after the preparation screen takes the normal wait, since nothing that brief comes between them.
-- A level reached from a loading screen can start an intro or a cutscene a moment later, as the prologue does.
-- So the first situation after a loading screen waits as long.
-- The hub and the preparation screen are left out, since nothing replaces them a moment after they arrive.
local SETTLED_ARRIVALS = { hub = true, mission_preparation = true }
local LOADING_DEBOUNCE_SECONDS = 3
local LOADING_CONTEXTS = {}
for _, context in ipairs(Contexts.list) do
	LOADING_CONTEXTS[context.id] = context.loading_screen
end

local pending_context = nil

-- How long the pending change waits for quiet, which is longer around a loading screen.
local function debounce_seconds()
	if LOADING_CONTEXTS[pending_context] and current_context ~= "mission_preparation" then
		return LOADING_DEBOUNCE_SECONDS
	end
	if LOADING_CONTEXTS[current_context] and pending_context ~= nil and not SETTLED_ARRIVALS[pending_context] then
		return LOADING_DEBOUNCE_SECONDS
	end
	return DEBOUNCE_SECONDS
end

local debounce_elapsed = 0
local pending_elapsed = 0
local has_pending_change = false
local replay_requested = false -- True when the current context should play again once the pending change commits.

-- True when Let Songs Finish holds the change to `next_context` back until the song playing now ends.
-- Only a situation that ranks no higher waits, since a fight or a boss should not wait for a calm song.
-- Only a change to the player's own songs waits, so Vanilla, Silence, and an empty folder still take over at once.
local function waits_for_song(next_context)
	if not mod:get("let_songs_finish") or paused or not current_folder or not AudioClient.is_playing() then
		return false
	end

	local playing_entry = Contexts.get(current_context)
	local next_entry = next_context and Contexts.get(next_context)
	if not (playing_entry and playing_entry.priority and next_entry and next_entry.priority) then
		return false
	end
	if next_entry.priority > playing_entry.priority then
		return false
	end

	return source_of(next_context) == "custom" and Library.has_files(folder_for(next_context))
end

local function commit_pending_context()
	has_pending_change = false
	local replay = replay_requested
	replay_requested = false

	if pending_context == current_context and not replay then
		-- A flicker round-tripped back to what is already playing, so there is nothing to do.
		-- The song's own situation is back, so it no longer has to end, and loops again if it should.
		if context_after_song then
			log(string.format("[playback] %s: back before the song ended, so %s no longer waits", current_context, tostring(context_after_song)))
			context_after_song = nil
			local is_looping = loops(playing_track.is_only_file)
			AudioClient.set_loop(is_looping, not is_looping and playing_track.duration or nil)
		end
		return
	end

	if not replay and waits_for_song(pending_context) then
		log(string.format("[playback] %s: letting %s finish before %s", current_context, playing_track.file_path, tostring(pending_context)))
		context_after_song = pending_context
		-- A looping song would never end, so it plays to the end of the pass it is in.
		AudioClient.set_loop(false, playing_track.duration)
		return
	end

	current_context = pending_context
	play_context(pending_context, true) -- true marks a real context change.
end

-- Plays the current context again, as after a rescan or a changed setting.
-- While a change is still settling, that waits for its commit, which plays anyway, so the music does not crossfade twice.
-- A situation waiting for a song to finish takes over instead, since the replay starts its music anew anyway.
local function replay_current_context()
	if has_pending_change then
		replay_requested = true
		return
	end

	if context_after_song then
		current_context = context_after_song
	end
	play_context(current_context, true)
end

Context.on_change(function(new_context, old_context, boss_breed)
	-- Boss events still arrive while the mod is off, since they are not hooks. Turning it back on catches up anyway.
	if not enabled then
		return
	end

	log(string.format("[context] %s -> %s%s",
		tostring(old_context), tostring(new_context),
		boss_breed and (" (breed=" .. boss_breed .. ")") or ""))

	if not has_pending_change then
		pending_elapsed = 0
	end

	pending_context = new_context
	debounce_elapsed = 0
	has_pending_change = true
end)

-- ###########################################################################
-- Playback Controls
-- ###########################################################################
-- The keys in the Playback Controls group, which DMF calls once per press.
-- Manual control only steers the situation playing now, so it does none of a context change's work.
-- The next context change still starts its own pick.
-- While a change is still settling, a key acts on what plays now.

-- Shows a key's message, unless For Key Presses is off.
local function notify_control(text_id, ...)
	if not mod:get("key_press_messages") then
		return
	end

	show_message(text_id, ...)
end

-- True while one of the player's songs plays for the current situation, or is paused, the only music the keys act on.
local function has_song_to_control()
	if not enabled or current_folder == nil or playing_track == nil or not AudioClient.available() then
		return false
	end
	return paused or AudioClient.is_playing()
end

-- Seconds into the song playing now, or into the paused song.
local function song_position()
	if paused then
		return playing_track.position
	end
	return AudioClient.position()
end

-- The folder playing now as the player knows it: the situation's name, and an override folder's name after it.
-- An example is "Boss (chaos_spawn)".
-- A removal lasts beyond this situation, so its messages say where the song was taken out.
-- The pattern that joins the two names is localized too, since languages set such a name apart in their own ways.
local function folder_label()
	local situation = mod:localize("source_" .. current_context)
	if current_folder == current_context then
		return situation
	end
	return mod:localize("override_folder_label", situation, current_folder:match("[^/]+$"))
end

-- `control` names the key in the log.
local function say_no_song(control)
	log(string.format("[control] %s: none of your songs plays", control))
	notify_control("control_no_song")
end

-- How long a key's switch from the song playing now to its own start takes.
-- Two copies of one song crossfading sound like an echo, so this is just long enough to avoid a click.
local SAME_SONG_FADE_SECONDS = 0.1

-- Crossfades to `file_path` from the folder playing now over the Key Fade Length, which ends a pause.
-- Without `start_position`, even the song playing now starts over in a fresh stream instead of reviving the copy that fades out.
local function play_manual_pick(file_path, duration, is_only_file, start_position)
	local is_same_song = file_path == playing_track.file_path
	local fade_seconds = mod:get("key_fade_seconds")
	if not start_position and AudioClient.is_playing() and is_same_song then
		fade_seconds = math.min(fade_seconds, SAME_SONG_FADE_SECONDS)
	end

	paused = false
	context_status = SOURCE_NAMES.custom
	play_track(current_context, current_folder, { file_path = file_path, duration = duration, is_only_file = is_only_file,
		start_position = start_position, fade_in = true, fade_seconds = fade_seconds })

	-- A key's own message names the song it starts, so For Song Changes only names that song while For Key Presses is off.
	-- A key that keeps the same song, as Restart Song and Resume do, changes no song.
	if not is_same_song and mod:get("song_change_messages") and not mod:get("key_press_messages") then
		show_message("song_now_playing", song_name(file_path))
	end
end

-- Starts the song playing or paused now over from its file.
-- A song whose file a rescan no longer finds in the folder keeps playing, since opening the file again would fail and lose it.
local function restart_playing_song()
	local file_path, duration, is_only_file = Library.find_file(current_folder, playing_track.file_path)
	if not file_path then
		log(string.format("[control] %s: %s is no longer in %s, so it keeps playing", current_context, playing_track.file_path,
			current_folder))
		notify_control("control_song_gone", folder_label(), song_name(playing_track.file_path))
		return
	end

	play_manual_pick(file_path, duration, is_only_file)
	notify_control("control_restart_song", song_name(file_path))
end

-- Plays the paused song on from where it stopped.
local function resume_paused_song()
	play_manual_pick(playing_track.file_path, playing_track.duration, playing_track.is_only_file, playing_track.position)
end

-- True when the song playing or paused now is the only one its folder still holds.
-- A song that a rescan took out of the folder is not, even when the folder holds one song.
local function is_lone_song()
	local file_path, _, is_only_file = Library.find_file(current_folder, playing_track.file_path)
	return file_path ~= nil and is_only_file
end

-- The Next Song key: crossfades to another song from the folder playing now.
-- The skipped song keeps no resume point, since the song that replaces it is the one a later context change remembers.
mod.next_song = function()
	if not has_song_to_control() then
		say_no_song("next song")
		return
	end

	-- While Let Songs Finish holds a change back, moving on means going to the situation that waits.
	if context_after_song then
		local next_context = context_after_song
		log(string.format("[control] %s: next song, so %s takes over now", current_context, next_context))
		current_context = next_context
		play_context(next_context, true)
		if AudioClient.is_playing() and playing_track then
			notify_control("control_next_song", song_name(playing_track.file_path))
		end
		return
	end

	-- Starting a folder's only song over is what Restart Song does, so Next keeps it playing, resumes it if paused, and says why.
	if is_lone_song() then
		log(string.format("[control] %s: next song, but %s has no other song", current_context, current_folder))
		if paused then
			resume_paused_song()
		end
		notify_control("control_only_song", folder_label(), song_name(playing_track.file_path))
		return
	end

	-- A rescan can empty the folder while its song still plays, and nothing replaces that song then.
	local file_path, duration, is_only_file = Playlist.next(current_folder, playing_track.file_path)
	if not file_path then
		log(string.format("[control] %s: next song, but %s has no songs left", current_context, current_folder))
		notify_control("control_no_songs_left", folder_label())
		return
	end

	log(string.format("[control] %s: next song", current_context))
	Playlist.add_played(playing_track.file_path)
	play_manual_pick(file_path, duration, is_only_file)
	notify_control("control_next_song", song_name(file_path))
end

mod.restart_song = function()
	if not has_song_to_control() then
		say_no_song("restart song")
		return
	end

	log(string.format("[control] %s: restart song", current_context))
	restart_playing_song()
end

-- Previous Song goes back only within this many seconds into a song, and later starts the song over, as most music players do.
local PREVIOUS_SONG_SECONDS = 3

-- The Previous Song key: goes back to the song that played before in this situation, or starts the song playing now over.
mod.previous_song = function()
	if not has_song_to_control() then
		say_no_song("previous song")
		return
	end

	local file_path, duration, is_only_file = nil, nil, nil
	if song_position() < PREVIOUS_SONG_SECONDS then
		file_path, duration, is_only_file = Playlist.previous(current_folder, playing_track.file_path)
	end

	if not file_path then
		log(string.format("[control] %s: previous song, starting this one over", current_context))
		restart_playing_song()
		return
	end

	log(string.format("[control] %s: previous song", current_context))
	play_manual_pick(file_path, duration, is_only_file)
	notify_control("control_previous_song", song_name(file_path))
end

-- What the overlay's status tag reads while a song is paused. It starts with "Custom", so the tag keeps Custom's color.
local PAUSED_STATUS = "Custom, paused"

-- The Pause / Resume key: stops the song playing now while the game's music stays silent, and the next press resumes it where it stopped.
-- A context change ends the pause, and the paused song keeps its resume point like any song that was playing.
mod.pause_song = function()
	if not has_song_to_control() then
		say_no_song("pause")
		return
	end

	if paused then
		log(string.format("[control] %s: resume", current_context))
		resume_paused_song()
		notify_control("control_resumed", song_name(playing_track.file_path))
		return
	end

	log(string.format("[control] %s: pause", current_context))
	playing_track.position = AudioClient.position()
	AudioClient.stop(mod:get("key_fade_seconds"))
	paused = true
	context_status = PAUSED_STATUS
	notify_control("control_paused", song_name(playing_track.file_path))
end

-- The song the first press of Remove from Rotation asked about: file_path, and the seconds left for a second press.
-- Removing takes two presses, so a stray key press cannot take a song out of rotation.
local removal_asked = nil

-- Forgets the first press once its time is over. Call on every update.
local function expire_removal(dt)
	if not removal_asked then
		return
	end

	removal_asked.seconds_left = removal_asked.seconds_left - dt
	if removal_asked.seconds_left <= 0 then
		removal_asked = nil
	end
end

-- Takes the song playing now out of its folder's rotation and moves on, as Next Song does.
-- After the folder's last song, the situation plays again, which falls back as for an empty folder.
local function remove_playing_song()
	local file_path = playing_track.file_path
	RemovedSongs.add(file_path)
	Library.remove_file(file_path)
	Loudness.forget(file_path)
	log(string.format("[control] %s: removed %s from rotation", current_context, file_path))
	local label = folder_label()

	-- The situation plays again at once, even while a change is still settling, so the removed song never plays on.
	local next_path, duration, is_only_file = Playlist.next(current_folder, file_path)
	if next_path then
		play_manual_pick(next_path, duration, is_only_file)
	else
		play_context(current_context, true)
	end

	-- Shown after the replay, so the removal is the message that stays, not the song the next folder starts.
	notify_control("control_removed_song", label, song_name(file_path))
end

-- The Remove from Rotation key: the first press asks, and a second press while the question shows removes the song.
-- The file stays on disk. Restore Removed Songs puts every removed song back.
mod.remove_song = function()
	if not has_song_to_control() then
		say_no_song("remove song")
		return
	end

	if removal_asked and removal_asked.file_path == playing_track.file_path then
		removal_asked = nil
		remove_playing_song()
		return
	end

	-- A second press counts for as long as the question shows, fade out included, so a press while it shows always removes the song.
	-- That holds with For Key Presses off too, when no question shows.
	removal_asked = { file_path = playing_track.file_path, seconds_left = OnScreenMessage.seconds_shown() }

	if mod:get("key_press_messages") then
		OnScreenMessage.show(message_text("control_remove_confirm", folder_label(), song_name(playing_track.file_path)))
	end
end

-- The Toggle Shuffle key. It changes the setting itself, so the mod options show the new choice and it lasts.
-- It works whatever plays, since it only decides what the next pick does.
mod.toggle_shuffle = function()
	local is_on = not mod:get("shuffle")
	mod:set("shuffle", is_on, true)
	log(string.format("[control] shuffle %s", is_on and "on" or "off"))
	notify_control(is_on and "control_shuffle_on" or "control_shuffle_off")
end

-- Makes the song playing now follow Repeat Song, so the setting takes effect without waiting for the next song.
-- A paused song follows it once it resumes, since resuming starts it again.
local function apply_repeat_song()
	if not has_song_to_control() or paused then
		return
	end

	local is_looping = plays_looping(playing_track.is_only_file)
	if AudioClient.set_loop(is_looping, not is_looping and playing_track.duration or nil) then
		log(string.format("[playback] %s: %s %s", current_context, playing_track.file_path, is_looping and "loops now" or "plays to its end now"))
	else
		log(string.format("[playback] %s: %s is too close to its end to loop, so it starts over once it ends", current_context, playing_track.file_path))
	end
end

-- The Toggle Repeat Song key. Like Toggle Shuffle, it changes the setting itself, and works whatever plays.
mod.toggle_repeat_song = function()
	local is_on = not mod:get("repeat_song")
	-- Logged first, since the setting change logs what it does to the song playing now.
	log(string.format("[control] repeat song %s", is_on and "on" or "off"))
	mod:set("repeat_song", is_on, true)
	notify_control(is_on and "control_repeat_song_on" or "control_repeat_song_off")
end

-- The Restore Removed Songs button. Listing the folders again brings the songs back into every rotation.
mod.restore_removed_songs = function()
	local count = RemovedSongs.clear()
	log(string.format("[control] restored %d removed song(s)", count))

	if count == 0 then
		notify_control("control_nothing_removed")
		return
	end

	Library.request_listing()
	if count == 1 then
		notify_control("control_restored_song")
	else
		notify_control("control_restored_songs", count)
	end
end

-- ###########################################################################
-- Wiring
-- ###########################################################################

-- The state the debug overlay shows. Kept to plain values, so building it never changes what plays.
local function overlay_snapshot()
	if not enabled then
		return { turned_off = true }
	end

	local hold, hold_seconds, hold_length = Context.hold()
	local volume, menu_level, song_level, song_measured = AudioClient.levels()
	local song = (AudioClient.is_playing() or paused) and playing_track and playing_track.file_path or nil

	-- AudioClient no longer holds a paused song, so its length comes from the library.
	-- Its level is the one it resumes at, since a resume sets the level again.
	local duration = AudioClient.duration()
	if paused then
		duration = playing_track.duration
		song_level = Loudness.level(playing_track.file_path)
		song_measured = Loudness.is_measured(playing_track.file_path)
	end

	-- A situation set to Vanilla or Silence plays no folder, so it looks for no override either.
	local overrides = current_folder and table.concat(Context.override_keys(mod, current_context), ", ") or nil

	local measuring_done, measuring_total = Loudness.progress()
	local fading_in, fading_out = AudioClient.fades()

	local pending_seconds = nil
	if has_pending_change then
		pending_seconds = math.max(0, math.min(debounce_seconds() - debounce_elapsed, MAX_DEBOUNCE_SECONDS - pending_elapsed))
	end

	return {
		context = current_context,
		situation = current_context and mod:localize("source_" .. current_context) or nil,
		idle = not current_context and Context.idle_reason() or nil,
		status = context_status,
		skipped = current_context and Context.skipped() or nil,
		hold = hold,
		hold_seconds = hold_seconds,
		hold_length = hold_length,
		pending = has_pending_change and (pending_context or "none") or nil,
		pending_length = has_pending_change and debounce_seconds() or nil,
		after_song = context_after_song,
		folder = current_folder,
		overrides = overrides,
		pending_seconds = pending_seconds,
		song = song and song:match("[^/]+$"),
		position = song_position(),
		duration = duration,
		volume = volume,
		menu_level = menu_level,
		menu_open = Context.menu_open(),
		menu_volume = mod:get("menu_volume") / 100,
		song_level = song_level,
		song_measured = song_measured,
		evening_out = mod:get("normalize_loudness") == true,
		measuring_done = measuring_done,
		measuring_total = measuring_total,
		fade_in = fading_in,
		fade_out = fading_out and {
			song = song_name(fading_out.file_path),
			level = fading_out.level,
			seconds_left = fading_out.seconds_left,
			more = fading_out.more,
		} or nil,
	}
end

-- The overlay's element uses the game's UI classes, so it is only loaded once the overlay is first shown.
local OverlayElement = nil

local function create_overlay_element(constant_elements, draw_layer)
	OverlayElement = OverlayElement or mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/debug_overlay_element")(DebugOverlay)
	return OverlayElement:new(constant_elements, draw_layer)
end

local function apply_overlay_settings()
	DebugOverlay.set_enabled(mod:get("debug_overlay") == true, mod:get("debug_overlay_scale") / 100, mod:get("debug_overlay_opacity") / 100)
end

-- The on-screen message's element uses the game's UI classes too, so it is only loaded once the message is first shown.
local OnScreenMessageElement = nil

local function create_on_screen_message_element(constant_elements, draw_layer)
	OnScreenMessageElement = OnScreenMessageElement or mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/on_screen_message_element")(OnScreenMessage)
	return OnScreenMessageElement:new(constant_elements, draw_layer)
end

local ON_SCREEN_MESSAGE_SETTINGS = {
	key_press_messages = true,
	song_change_messages = true,
	notice_messages = true,
	error_messages = true,
	message_scale = true,
	message_color = true,
	notice_color = true,
	error_color = true,
	message_corner = true,
	message_backdrop_opacity = true,
	message_offset_x = true,
	message_offset_y = true,
	message_seconds = true,
	message_fade_out_seconds = true,
}

-- The element stays on screen while any of the four kinds of message is on.
-- Key presses and song changes check their own settings before they show, and on_screen_message.lua checks notices and errors.
local function apply_on_screen_message_settings()
	local any_on = mod:get("key_press_messages") == true or mod:get("song_change_messages") == true
		or mod:get("notice_messages") == true or mod:get("error_messages") == true
	OnScreenMessage.set_shown_kinds({ notice = mod:get("notice_messages"), error = mod:get("error_messages") })
	OnScreenMessage.set_enabled(any_on, {
		scale = mod:get("message_scale") / 100,
		color = mod:get("message_color"),
		notice_color = mod:get("notice_color"),
		error_color = mod:get("error_color"),
		corner = mod:get("message_corner"),
		offset_x = mod:get("message_offset_x"),
		offset_y = mod:get("message_offset_y"),
		backdrop_opacity = mod:get("message_backdrop_opacity") / 100,
	})
	OnScreenMessage.set_timing(mod:get("message_seconds"), mod:get("message_fade_out_seconds"))
end

-- Raw state transitions, the silencing, and sound events go to the detailed log.
Suppression.init(log_detail)
EventProbe.init(log_detail)
MissionProbe.init(log)
BossProbe.init(log_detail)
Context.on_mission_change(MissionProbe.on_mission_change)
ResumePoints.init(mod)
Playlist.init({ usable_entries = Library.usable_entries, find_file = Library.find_file })
Playlist.set_shuffle(mod:get("shuffle"))
Context.on_state_change(Suppression.on_state_change)
Context.on_state_change(ResumePoints.on_state_change)
Context.init(mod, log_detail, log)

-- A level can end without a loading screen, as a story mission does when its debrief cutscene leads into the hub.
-- The game stops every mission sound there and destroys the level's Wwise world, so the cutscene music is forgotten too.
mod:hook_safe(WwiseGameSyncManager, "on_gameplay_shutdown", function()
	Suppression.forget_cutscene_music()
end)

-- Level flow hands an event's IDs on to later nodes, which pass them to the engine unchecked, so a nil ID can raise an error.
-- So a game music event that Suppression silences still starts, and is stopped at once, which leaves the game valid IDs.
local function stop_if_suppressed(wwise_world, event_name, playing_id, ...)
	if playing_id then
		if Suppression.should_stop_event(event_name) then
			WwiseWorld.stop_event(wwise_world, playing_id)
		else
			Suppression.watch_event(wwise_world, event_name, playing_id)
		end
	end

	return playing_id, ...
end

mod.on_all_mods_loaded = function()
	MediaDecoder.init(NativeFfi)
	AudioFolders.init(NativeFfi, MediaDecoder)
	RemovedSongs.init(log, DiagnosticLog.folder())
	Library.init(log, AudioFolders, { is_removed = RemovedSongs.contains })
	XAudio.init(NativeFfi)
	Player.init(NativeFfi, MediaDecoder, XAudio)
	Loudness.init({
		log = log,
		detail = log_detail,
		media_decoder = MediaDecoder,
		native_ffi = NativeFfi,
		loudness_meter = LoudnessMeter,
		disk_path = Library.disk_path,
		folder = DiagnosticLog.folder(),
		is_removed = RemovedSongs.contains,
	})
	Loudness.set_enabled(mod:get("normalize_loudness"))
	Library.on_listed(Loudness.set_files)
	AudioClient.init(log, { player = Player, disk_path = Library.disk_path, level_of = Loudness.level, is_measured = Loudness.is_measured })
	AudioClient.set_volume(custom_volume())
	AudioClient.set_fade_seconds(mod:get("fade_seconds"))
	DebugOverlay.init(log, { snapshot = overlay_snapshot, meter = AudioClient.meter, create_element = create_overlay_element })
	apply_overlay_settings()
	OnScreenMessage.init(log, { create_element = create_on_screen_message_element })
	apply_on_screen_message_settings()

	-- A mod can hook a method only once, so this one hook serves both Suppression and EventProbe.
	-- EventProbe sees every event first, even one Suppression stops.
	mod:hook(CLASS.WwiseWorld, "trigger_resource_event", function(func, wwise_world, event_name, ...)
		EventProbe.observe(event_name, select("#", ...))

		return stop_if_suppressed(wwise_world, event_name, func(wwise_world, event_name, ...))
	end)

	playback_lost = not AudioClient.available()
	if playback_lost then
		local reason = tostring(AudioClient.error())
		log("[player] unavailable: " .. reason)
		mod:error("Music Replacer could not start Windows audio playback, so the game's music plays as usual: %s", reason)
	end

	-- The context can resolve before Library and AudioClient are ready.
	-- Re-evaluate now, bypassing the debounce, since this is a one-off catch-up.
	has_pending_change = false
	if enabled then
		current_context = Context.current()
		play_context(current_context, true)
	end
end

-- DMF also calls these once at startup with initial_call set, to report the saved state. Nothing plays yet then.
mod.on_disabled = function(initial_call)
	enabled = false

	if initial_call then
		return
	end

	-- A song that is turned off mid-mission continues from there if the mod is turned on again before the next loading screen.
	remember_playing_track(nil)
	has_pending_change = false
	replay_requested = false
	context_after_song = nil
	current_context = nil
	playing_track = nil
	paused = false
	hand_back()
	-- DMF disables the hooks while the mod is off, so a level can end unseen, and its cutscene music with it.
	Suppression.forget_cutscene_music()
	log("[mod] turned off, the game's music plays")
end

mod.on_enabled = function(initial_call)
	enabled = true

	if initial_call then
		return
	end

	-- The hooks missed every state change while the mod was off.
	Context.relearn()
	AudioClient.try_again()
	log("[mod] turned on, catching up with the game's music states")
end

-- Settings that decide how the context resolves, so it resolves again when one changes.
local RESOLVING_SETTINGS = {
	captain_boss_music = true,
	daemonhost_boss_music = true,
	source_meat_grinder = true,
	meat_grinder_situation = true,
}

mod.on_setting_changed = function(setting_id)
	-- Meat Grinder's own choice reaches the last branch below when it moves between Silence and its folder, which both resolve meat_grinder.
	-- A situation that can be skipped changes what resolves when it moves to or from Skip.
	local skippable_source = setting_id:match("^source_(.+)$")
	if RESOLVING_SETTINGS[setting_id] or (skippable_source and Contexts.can_skip(skippable_source)) then
		local previous_context = Context.current()
		Context.refresh(mod)

		-- A change the setting made is the player's own, so it takes over at once, without the waits meant for the game's flickers.
		-- A change the game made before keeps its wait.
		-- The commit plays the new situation by its current choice, so the last branch below has nothing left to do.
		if enabled and has_pending_change and Context.current() ~= previous_context then
			commit_pending_context()
			return
		end
	end

	if setting_id == "debug_overlay" or setting_id == "debug_overlay_scale" or setting_id == "debug_overlay_opacity" then
		apply_overlay_settings()
	elseif ON_SCREEN_MESSAGE_SETTINGS[setting_id] then
		apply_on_screen_message_settings()
	elseif setting_id == "custom_music_volume" then
		AudioClient.set_volume(custom_volume())
	elseif setting_id == "fade_seconds" then
		AudioClient.set_fade_seconds(mod:get("fade_seconds"))
	elseif setting_id == "normalize_loudness" then
		Loudness.set_enabled(mod:get("normalize_loudness"))
		AudioClient.refresh_levels()
		log(string.format("[loudness] evening out turned %s", mod:get("normalize_loudness") and "on" or "off"))
	elseif setting_id == "shuffle" then
		Playlist.set_shuffle(mod:get("shuffle"))
	elseif setting_id == "repeat_song" then
		apply_repeat_song()
	elseif setting_id == "let_songs_finish" and not mod:get("let_songs_finish") and context_after_song then
		-- Nothing waits for a song with the setting off, so the situation that waited takes over at once.
		local next_context = context_after_song
		log(string.format("[playback] %s: let songs finish turned off, so %s takes over now", current_context, next_context))
		current_context = next_context
		play_context(next_context, true)
	elseif setting_id == "resume_songs" and not mod:get("resume_songs") then
		ResumePoints.forget_all()
	elseif enabled and current_context and setting_id == "source_" .. current_context then
		-- The context playing now follows its new setting at once. A custom song that is already playing keeps playing.
		local source = source_of(current_context)
		if source == "game" or source == "silence" or not AudioClient.is_playing() then
			replay_current_context()
		end
	end
end

-- The Rescan Audio Folders button in the mod settings calls this.
mod.rescan_audio = function()
	-- Pressing it is also the player's way to ask for another try after playback gave up.
	AudioClient.try_again()
	-- It also picks up lines a player deleted from removed.txt by hand.
	RemovedSongs.load()
	Loudness.forget_failures()
	Library.request_rescan()
end

-- An update gap at least this long is logged, which shows how long the game's thread stalls, as during loading screens.
local STALL_LOG_SECONDS = 1

mod.update = function(dt)
	if dt >= STALL_LOG_SECONDS then
		log(string.format("[timing] the game's thread stalled for %.1fs", dt))
	end

	Context.update(mod, dt)
	expire_removal(dt)

	-- The boss probe only feeds the detailed log, so it reads nothing while that is off.
	if mod:get("diagnostic_mode") then
		BossProbe.update(dt)
	end

	if Library.update(dt) then
		-- A replaced file deserves another try, so contexts that gave up retry after a rescan.
		quick_ends = {}
		gave_up = {}
		emptied = {}

		-- A context that played the game's music for lack of files starts its new track now, not at its next change.
		-- A custom track that is playing or paused keeps playing or paused, and the next pick uses the new list.
		if enabled and not AudioClient.is_playing() and not paused then
			replay_current_context()
		end
	end

	if enabled then
		Loudness.update(playing_track and playing_track.file_path, current_folder, current_context)
	end

	AudioClient.set_menu_volume(menu_volume(dt))
	AudioClient.update(dt)

	-- The position is kept on every tick, since the song is already gone by the time playback is found to have stopped.
	if playing_track and AudioClient.is_playing() then
		playing_track.position = AudioClient.position()
	end

	-- Playback that stops working hands the music back to the game at once, not at the next context change.
	-- Playback that works again, such as once a headset is plugged back in, takes over again at once too.
	local available = AudioClient.available()
	if not playback_lost and not available then
		playback_lost = true
		if was_playing and playing_track and playing_track.position then
			lost_track = { context_name = playing_track.context_name, file_path = playing_track.file_path, position = playing_track.position }
		end
		Suppression.release()
	elseif playback_lost and available then
		playback_lost = false
		if paused then
			-- A paused situation stays quiet until the song resumes, so the game's music is silenced again.
			Suppression.engage(current_context)
		elseif enabled then
			replay_current_context()
		end
	end
	was_playing = AudioClient.is_playing()

	-- An override folder can start to apply while the context stays the same, as when the game names a boss after its music started.
	-- A paused song resumes first, and the switch follows on the next check.
	override_check_elapsed = override_check_elapsed + dt
	if override_check_elapsed >= OVERRIDE_CHECK_SECONDS then
		override_check_elapsed = 0
		if enabled and current_folder and not has_pending_change and not paused and not context_after_song then
			local folder = folder_for(current_context)
			if folder ~= current_folder then
				log(string.format("[playback] %s: switching from the %s folder to the %s folder", current_context, current_folder, folder))
				remember_folder_song()
				play_context(current_context, true)
			end
		end
	end

	DebugOverlay.update()
	OnScreenMessage.update()

	if enabled and has_pending_change then
		debounce_elapsed = debounce_elapsed + dt
		pending_elapsed = pending_elapsed + dt

		if debounce_elapsed >= debounce_seconds() or pending_elapsed >= MAX_DEBOUNCE_SECONDS then
			commit_pending_context()
		end
	end
end

-- Each shutdown step runs on its own, so one that fails cannot leave the others undone.
-- Otherwise songs could play on through a reload, the overlay stay on screen, or the game's music stay silenced.
local function shut_down(name, step, ...)
	local ok, err = pcall(step, ...)
	if not ok then
		log(string.format("[mod] shutting down %s failed: %s", name, tostring(err)))
	end
end

mod.on_unload = function(exit_game)
	shut_down("the context", Context.shutdown, mod)
	shut_down("the library", Library.shutdown)
	shut_down("the loudness measuring", Loudness.shutdown)
	shut_down("the overlay", DebugOverlay.shutdown)
	shut_down("the on-screen message", OnScreenMessage.shutdown)
	shut_down("the audio", AudioClient.shutdown)
	shut_down("the decoder", MediaDecoder.shutdown)

	-- A reload hands the music back to the game, or a silenced zone or game state stays silent until the game changes it.
	-- The reloaded mod reads the game's states again on its first tick.
	if not exit_game then
		shut_down("the silencing", Suppression.release)
	end

	DiagnosticLog.close()
end
