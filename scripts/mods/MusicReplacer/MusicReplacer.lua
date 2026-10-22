local mod = get_mod("MusicReplacer")

-- mod:io_dofile paths are relative to "mods/" and include this mod's own folder name.
-- MusicReplacer.mod's own paths follow the same rule.
local Contexts = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/contexts")
local Context = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/context")
local Suppression = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/suppression")
local Library = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/library")
local ResumePoints = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/resume_points")
local EventProbe = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/event_probe")
local MissionProbe = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/mission_probe")
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

DiagnosticLog.init(mod, NativeFfi)
local log = DiagnosticLog.write
local log_detail = DiagnosticLog.detail

-- tools/build.ps1 stamps the packaged info.json with the commit and build time, which tells two builds of one version apart.
-- The console log gets the line too, so a report without diagnostic.log still names the build.
local version_line = string.format("version %s, build %s",
	tostring(mod:get_metadata("version")), tostring(mod:get_metadata("build") or "unknown"))
mod:info("%s", version_line)
log("[startup] " .. version_line)

-- ###########################################################################
-- Playback Orchestration
-- ###########################################################################
-- Combines "what context" (context.lua) with "is there a file for it" (library.lua) to decide what audio_client.lua does.
-- Native music is only silenced once a replacement is available.
-- So a context with no file falls back to native music by construction.

local current_context = nil

-- False while the mod is turned off in the mod options.
-- DMF then disables the mod's hooks but keeps calling update, so nothing may start playing while this is false.
local enabled = true

-- True while playback is unavailable: before it has started, while Windows has no audio output, and once it gives up for the session.
local playback_lost = true

-- A track that ends within QUICK_END_SECONDS of starting did not really play, for example because Windows could not decode the file.
-- After MAX_QUICK_ENDS in a row from one folder, that folder stops retrying until the folders are listed again.
-- An override folder then gives way to the next folder, and a context's own folder to native music.
local QUICK_END_SECONDS = 3
local MAX_QUICK_ENDS = 3

local quick_ends = {} -- folder -> consecutive tracks from it that ended right after starting.
local gave_up = {} -- folder -> true once that folder stopped retrying.

-- folder -> true for an override folder the library listed songs for, but that had none left to pick, as after files were deleted.
-- It is skipped until the folders are listed again, so the override check does not keep switching back to it.
local emptied = {}

-- The custom track AudioClient was last asked to play, so a context change can remember where it stopped.
local playing_track = nil -- Fields: context_name, file_path, duration, is_only_file, and position, its last known position.

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
local context_status = "game's music"

local SOURCE_NAMES = { custom = "Custom", game = "Game's Own", silence = "Silence" }

-- What a context plays, from its setting: "custom", "game", or "silence".
-- Earlier versions also offered "custom_play_to_end", which plays as "custom" now.
local function source_of(context_name)
	local source = mod:get("source_" .. context_name)
	return SOURCE_NAMES[source] and source or "custom"
end

-- The volume settings are percentages of the music's normal level.
local function custom_volume()
	return (mod:get("custom_music_volume") or 100) / 100
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

	return menu_closed_elapsed < MENU_CLOSED_SECONDS and (mod:get("menu_volume") or 50) / 100 or 1
end

local function remember_playing_track(next_context_name)
	if not playing_track or playing_track.context_name == next_context_name or not AudioClient.is_playing() then
		return
	end

	local position = ResumePoints.remember(playing_track.context_name, playing_track.file_path,
		AudioClient.position(), playing_track.duration, playing_track.is_only_file, next_context_name)

	if position then
		log(string.format("[resume] %s: remembering %s at %.1fs", playing_track.context_name, playing_track.file_path, position))
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

-- The folder `context_name` plays from: the first of its override folders that has songs, else its own.
local function folder_for(context_name)
	return folders_for(context_name)[1]
end

-- The remembered song if `folder` still has that file, else a new pick from Library.pick_file().
-- Returns file_path, duration, is_only_file, and the start position of a resumed song.
-- A song is resumed only from the folder it played from, so a resume point from another folder gives way to a new pick.
local function choose_file(folder, resume_path, resume_position)
	if resume_path then
		local file_path, duration, is_only_file = Library.find_file(folder, resume_path)
		if file_path then
			return file_path, duration, is_only_file, resume_position
		end
	end

	return Library.pick_file(folder)
end

-- Stops any custom song and lets the game's own music play, as wherever no custom song plays.
-- `status`, when given, is the reason the debug overlay shows.
local function hand_back(status)
	if status then
		context_status = status
	end
	AudioClient.stop()
	Suppression.release()
end

-- is_new_context separates a real context change from advancing within the same context.
-- Advancing means a playlist continuation, and only a real change should fade in again.
local function play_context(context_name, is_new_context)
	if is_new_context then
		remember_playing_track(context_name)
		ResumePoints.enter(context_name)
	end

	current_folder = nil

	if not context_name then
		hand_back("game's music")
		return
	end

	-- Meat Grinder only resolves to its own context for these two, since "custom" plays the mission contexts there.
	local source = source_of(context_name)
	context_status = SOURCE_NAMES[source]

	if source == "game" then
		hand_back()
		log(string.format("[playback] %s: set to the game's own music", context_name))
		return
	end

	if source == "silence" then
		AudioClient.stop()
		Suppression.engage(context_name)
		log(string.format("[playback] %s: set to silence", context_name))
		return
	end

	-- Playback that could not start, or gave up after repeated audio device failures, leaves the native music alone.
	if not AudioClient.available() then
		hand_back("game's music, no audio output")
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

		file_path, duration, is_only_file, start_position = choose_file(folder, resume_path, resume_position)
		if file_path or folder == context_name then
			break
		end

		emptied[folder] = true
		log(string.format("[playback] %s: the %s folder has no songs left, trying the next folder", context_name, folder))
	end
	current_folder = folder

	-- Only the context's own folder gets here, since an override folder that gave up is left out.
	if gave_up[folder] then
		hand_back("game's music, its songs would not play")
		log(string.format("[playback] %s: its tracks would not play earlier, using native music", context_name))
		return
	end

	if not file_path then
		-- No replacement is available: no folder, an empty folder, or a scan that has not finished.
		-- Native music is left alone.
		hand_back("game's music, no songs")
		log(string.format("[playback] %s: no file available, using native music", context_name))
		return
	end

	Suppression.engage(context_name)

	local loudness = Loudness.describe(file_path)
	log(string.format("[playback] %s: %s %s%s (duration=%s%s%s)",
		context_name, start_position and "resuming" or "playing", file_path,
		start_position and string.format(" at %.1fs", start_position) or "",
		tostring(duration), is_only_file and ", looping" or "", loudness and (", " .. loudness) or ""))

	playing_track = { context_name = context_name, file_path = file_path, duration = duration, is_only_file = is_only_file }

	-- A single file loops from its first play, with no seam, so it needs no end fade.
	AudioClient.play(file_path, {
		duration_seconds = not is_only_file and duration or nil,
		fade_in = is_new_context,
		loop = is_only_file,
		start_position = start_position,
		on_finished = function(failed)
			-- A loop only gets here if its file could not be played.
			-- After a context change, whatever triggered it already called play_context for the new context.
			if current_context ~= context_name then
				return
			end

			-- A file that could not be played always counts.
			-- Otherwise a track counts when it ended within QUICK_END_SECONDS and before half its length.
			-- So a short file that plays through does not count.
			-- A file the library has not measured yet has its decoder's length instead.
			-- Without either, ending within QUICK_END_SECONDS is enough, so files that end at once cannot reopen every frame.
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
						log(string.format("[playback] %s: %d tracks in a row ended within %ds, using native music until the game restarts or the folders are rescanned",
							context_name, MAX_QUICK_ENDS, QUICK_END_SECONDS))
						hand_back("game's music, its songs would not play")
						return
					end
				end
			else
				quick_ends[folder] = 0
			end

			play_context(context_name, false)
		end,
	})
end

-- Context changes are debounced, so a state that flickers and returns does not restart the track.
local DEBOUNCE_SECONDS = 0.6

-- Each change restarts the debounce, so states that keep flickering would never settle, as with both holds set to 0.
-- A pending change commits after this long anyway.
local MAX_DEBOUNCE_SECONDS = 3

-- Leaving the hub for a mission reports a loading screen for about 2 seconds before the mission preparation screen.
-- So a change to a loading context waits this long, and the hub song carries straight on into the preparation screen's song.
local LOADING_DEBOUNCE_SECONDS = 3
local LOADING_CONTEXTS = {}
for _, context in ipairs(Contexts.list) do
	LOADING_CONTEXTS[context.id] = context.loading_screen
end

local pending_context = nil

-- How long the pending change waits for quiet, which is longer for a change into a loading screen.
local function debounce_seconds()
	return LOADING_CONTEXTS[pending_context] and LOADING_DEBOUNCE_SECONDS or DEBOUNCE_SECONDS
end

local debounce_elapsed = 0
local pending_elapsed = 0
local has_pending_change = false
local replay_requested = false -- True when the current context should play again once the pending change commits.

local function commit_pending_context()
	has_pending_change = false
	local replay = replay_requested
	replay_requested = false

	if pending_context == current_context and not replay then
		-- A flicker round-tripped back to what is already playing, so there is nothing to do.
		return
	end

	current_context = pending_context
	play_context(pending_context, true) -- true marks a real context change.
end

-- Plays the current context again, as after a rescan or a changed setting.
-- While a change is still settling, that waits for its commit, which plays anyway, so the music does not crossfade twice.
local function replay_current_context()
	if has_pending_change then
		replay_requested = true
		return
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
-- Wiring
-- ###########################################################################

-- The state the debug overlay shows. Kept to plain values, so building it never changes what plays.
local function overlay_snapshot()
	if not enabled then
		return { turned_off = true }
	end

	local hold, hold_seconds = Context.hold()
	local volume, menu_level, song_level = AudioClient.levels()
	local song = AudioClient.is_playing() and playing_track and playing_track.file_path or nil

	local pending_seconds = nil
	if has_pending_change then
		pending_seconds = math.max(0, math.min(debounce_seconds() - debounce_elapsed, MAX_DEBOUNCE_SECONDS - pending_elapsed))
	end

	return {
		context = current_context,
		status = context_status,
		hold = hold,
		hold_seconds = hold_seconds,
		pending = has_pending_change and (pending_context or "none") or nil,
		folder = current_folder,
		overrides = current_context and table.concat(Context.override_keys(mod, current_context), ", ") or nil,
		pending_seconds = pending_seconds,
		song = song and song:match("[^/]+$"),
		position = AudioClient.position(),
		duration = AudioClient.duration(),
		volume = volume,
		menu_level = menu_level,
		menu_volume = (mod:get("menu_volume") or 50) / 100,
		song_level = song_level,
		evening_out = mod:get("normalize_loudness") == true,
	}
end

-- The overlay's element uses the game's UI classes, so it is only loaded once the overlay is first shown.
local OverlayElement = nil

local function create_overlay_element(constant_elements, draw_layer)
	OverlayElement = OverlayElement or mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/debug_overlay_element")(DebugOverlay)
	return OverlayElement:new(constant_elements, draw_layer)
end

local function apply_overlay_settings()
	DebugOverlay.set_enabled(mod:get("debug_overlay") == true, mod:get("debug_overlay_corner"), (mod:get("debug_overlay_scale") or 100) / 100)
end

-- Raw state transitions, suppression, and sound events are detailed lines. The rest of the log is the important events.
Suppression.init(log_detail)
EventProbe.init(log_detail)
MissionProbe.init(log)
ResumePoints.init(mod)
Context.on_state_change(Suppression.on_state_change)
Context.on_state_change(ResumePoints.on_state_change)
Context.init(mod, log_detail)

-- Level flow hands an event's IDs on to later nodes, which pass them to the engine unchecked, so a nil ID can raise an error.
-- So a native music event Suppression silences still starts, and is stopped at once, which leaves the game valid IDs.
local function stop_if_suppressed(wwise_world, event_name, playing_id, ...)
	if playing_id and Suppression.should_stop_event(event_name) then
		WwiseWorld.stop_event(wwise_world, playing_id)
	end

	return playing_id, ...
end

mod.on_all_mods_loaded = function()
	MediaDecoder.init(NativeFfi)
	AudioFolders.init(NativeFfi, MediaDecoder)
	Library.init(log, AudioFolders)
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
	})
	Loudness.set_enabled(mod:get("normalize_loudness"))
	Library.on_listed(Loudness.set_files)
	AudioClient.init(log, { player = Player, disk_path = Library.disk_path, level_of = Loudness.level })
	AudioClient.set_volume(custom_volume())
	DebugOverlay.init(log, { snapshot = overlay_snapshot, create_element = create_overlay_element })
	apply_overlay_settings()

	-- A mod can only install one hook per method on itself.
	-- So Suppression and EventProbe cannot each hook WwiseWorld.trigger_resource_event on their own.
	-- This one hook serves both instead.
	-- EventProbe always sees the event first, including one Suppression is about to stop.
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

	-- The context may have resolved before Library and AudioClient were ready.
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
	current_context = nil
	playing_track = nil
	hand_back()
	log("[mod] turned off, the game's own music plays")
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

mod.on_setting_changed = function(setting_id)
	if setting_id == "source_meat_grinder" or setting_id == "daemonhost_boss_music" or setting_id == "captain_boss_music" then
		Context.refresh(mod)

		-- Game's Own and Silence both resolve meat_grinder, so switching between them changes no context and needs a replay here.
		if enabled and setting_id == "source_meat_grinder" and current_context == "meat_grinder" and Context.current() == "meat_grinder" then
			play_context(current_context, true)
		end
	elseif setting_id == "debug_overlay" or setting_id == "debug_overlay_corner" or setting_id == "debug_overlay_scale" then
		apply_overlay_settings()
	elseif setting_id == "custom_music_volume" then
		AudioClient.set_volume(custom_volume())
	elseif setting_id == "normalize_loudness" then
		Loudness.set_enabled(mod:get("normalize_loudness"))
		AudioClient.refresh_levels()
		log(string.format("[loudness] evening out turned %s", mod:get("normalize_loudness") and "on" or "off"))
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

-- Called by the Rescan Audio Folders button in the mod settings.
mod.rescan_audio = function()
	-- Pressing it is also the player's way to ask for another try after playback gave up.
	AudioClient.try_again()
	Library.request_rescan()
end

-- An update gap at least this long is logged, which shows how long the game's thread stalls, as during loading screens.
local STALL_LOG_SECONDS = 1

mod.update = function(dt)
	if dt >= STALL_LOG_SECONDS then
		log(string.format("[timing] the game's thread stalled for %.1fs", dt))
	end

	Context.update(mod, dt)

	if Library.update(dt) then
		-- A replaced file deserves another try, so contexts that gave up retry after a rescan.
		quick_ends = {}
		gave_up = {}
		emptied = {}

		-- A context that played native music for lack of files starts its new track now, not at its next change.
		-- A custom track that is playing keeps playing, and the next pick uses the new list.
		if enabled and not AudioClient.is_playing() then
			replay_current_context()
		end
	end

	if enabled then
		Loudness.update(current_context)
	end

	AudioClient.set_menu_volume(menu_volume(dt))
	AudioClient.update(dt)

	-- Kept on every tick, since the song is already gone by the time playback is found to have stopped.
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
		if enabled then
			replay_current_context()
		end
	end
	was_playing = AudioClient.is_playing()

	-- An override folder can start to apply while the context stays the same, as when the game names a boss after its music started.
	override_check_elapsed = override_check_elapsed + dt
	if override_check_elapsed >= OVERRIDE_CHECK_SECONDS then
		override_check_elapsed = 0
		if enabled and current_folder and not has_pending_change then
			local folder = folder_for(current_context)
			if folder ~= current_folder then
				log(string.format("[playback] %s: switching from the %s folder to the %s folder", current_context, current_folder, folder))
				play_context(current_context, true)
			end
		end
	end

	MissionProbe.update()
	DebugOverlay.update()

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
	shut_down("the audio", AudioClient.shutdown)
	shut_down("the decoder", MediaDecoder.shutdown)

	-- A reload hands the music back to the game, or a silenced zone or game state stays silent until the game changes it.
	-- The reloaded mod reads the game's states again on its first tick.
	if not exit_game then
		shut_down("the silencing", Suppression.release)
	end

	DiagnosticLog.close()
end
