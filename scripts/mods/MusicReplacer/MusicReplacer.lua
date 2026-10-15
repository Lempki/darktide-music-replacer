local mod = get_mod("MusicReplacer")

-- mod:io_dofile paths are relative to "mods/" and include this mod's own folder name.
-- MusicReplacer.mod's own paths follow the same rule.
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
local DiagnosticLog = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/diagnostic_log")

DiagnosticLog.init(mod)
local log = DiagnosticLog.write

-- tools/build.ps1 stamps the packaged info.json with the commit and build time, which tells two builds of one version apart.
-- The console log gets the line too, since diagnostic.log is only written while Diagnostic Logging is on.
local version_line = string.format("version %s, build %s",
	tostring(mod:get_metadata("version")), tostring(mod:get_metadata("build") or "unknown"))
mod:info("%s", version_line)
log("[startup] " .. version_line)

-- ###########################################################################
-- Playback Orchestration
-- ###########################################################################
-- Combines "what context" (context.lua) with "is there a file for it" (library.lua) to decide what audio_client.lua does.
-- Native music is only silenced once a replacement is confirmed playing.
-- So a context with no file falls back to native music by construction.

local current_context = nil

-- True until playback has started, and again once it gives up for the session.
local playback_lost = true

-- A track that ends within QUICK_END_SECONDS of starting did not really play, for example because Windows could not decode the file.
-- After MAX_QUICK_ENDS in a row for one context, that context stops retrying and uses native music for the rest of the session.
local QUICK_END_SECONDS = 3
local MAX_QUICK_ENDS = 3

local quick_ends = {} -- context_name -> consecutive tracks that ended right after starting.
local gave_up = {} -- context_name -> true once that context stopped retrying.

-- The custom track AudioClient was last asked to play, so a context change can remember where it stopped.
local playing_track = nil -- { context_name, file_path, duration, is_only_file }

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

-- The context's remembered song if it still has that file, else a new pick from Library.pick_file().
-- Returns file_path, duration, is_only_file, and the start position of a resumed song.
local function choose_file(context_name, is_new_context)
	if is_new_context then
		local resume_path, position = ResumePoints.take(context_name)

		if resume_path then
			local file_path, duration, is_only_file = Library.find_file(context_name, resume_path)
			if file_path then
				return file_path, duration, is_only_file, position
			end
		end
	end

	return Library.pick_file(context_name)
end

-- is_new_context separates a real context change from advancing within the same context.
-- Advancing means a playlist continuation, and only a real change should fade in again.
local function play_context(context_name, is_new_context)
	if is_new_context then
		remember_playing_track(context_name)
		ResumePoints.enter(context_name)
	end

	if not context_name then
		AudioClient.stop()
		Suppression.release()
		return
	end

	if context_name == "silence" then
		AudioClient.stop()
		Suppression.engage(context_name)
		log("[playback] silence: no custom music, combat and exploration event suppression on")
		return
	end

	if gave_up[context_name] then
		AudioClient.stop()
		Suppression.release()
		log(string.format("[playback] %s: its tracks would not play earlier, using native music", context_name))
		return
	end

	-- Playback that could not start, or gave up after repeated audio device failures, leaves the native music alone.
	if not AudioClient.available() then
		AudioClient.stop()
		Suppression.release()
		return
	end

	local file_path, duration, is_only_file, start_position = choose_file(context_name, is_new_context)

	if not file_path then
		-- No replacement is available: no folder, an empty folder, or a scan that has not finished.
		-- Native music is left alone.
		AudioClient.stop()
		Suppression.release()
		log(string.format("[playback] %s: no file available, using native music", context_name))
		return
	end

	Suppression.engage(context_name)

	log(string.format("[playback] %s: %s %s%s (duration=%s%s)",
		context_name, start_position and "resuming" or "playing", file_path,
		start_position and string.format(" at %.1fs", start_position) or "",
		tostring(duration), is_only_file and ", looping" or ""))

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

			-- A file that could not be played always counts, since it has no measured duration to compare with.
			-- Otherwise, without a known duration or for a very short file, ending quickly is normal, so the check is skipped.
			local quick = failed or (duration and duration > QUICK_END_SECONDS * 2 and AudioClient.elapsed() < QUICK_END_SECONDS)
			if quick then
				quick_ends[context_name] = (quick_ends[context_name] or 0) + 1

				if quick_ends[context_name] >= MAX_QUICK_ENDS then
					gave_up[context_name] = true
					log(string.format("[playback] %s: %d tracks in a row ended within %ds, giving up and using native music until the game restarts",
						context_name, MAX_QUICK_ENDS, QUICK_END_SECONDS))
					AudioClient.stop()
					Suppression.release()
					return
				end
			else
				quick_ends[context_name] = 0
			end

			play_context(context_name, false)
		end,
	})
end

-- Context changes are debounced, so a state that flickers and returns does not restart the track.
local DEBOUNCE_SECONDS = 0.6

local pending_context = nil
local debounce_elapsed = 0
local has_pending_change = false

local function commit_pending_context()
	has_pending_change = false

	if pending_context == current_context then
		-- A flicker round-tripped back to what is already playing, so there is nothing to do.
		return
	end

	current_context = pending_context
	play_context(pending_context, true) -- true marks a real context change.
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

Suppression.init(log)
EventProbe.init(log)
MissionProbe.init(log)
ResumePoints.init(mod)
Context.on_state_change(Suppression.on_state_change)
Context.on_state_change(ResumePoints.on_state_change)
Context.init(mod, log)

mod.on_all_mods_loaded = function()
	MediaDecoder.init(NativeFfi)
	AudioFolders.init(NativeFfi, MediaDecoder)
	Library.init(log, AudioFolders)
	XAudio.init(NativeFfi)
	Player.init(NativeFfi, MediaDecoder, XAudio)
	AudioClient.init(log, { player = Player, disk_path = Library.disk_path })

	-- A mod can only install one hook per method on itself.
	-- So Suppression and EventProbe cannot each hook WwiseWorld.trigger_resource_event on their own.
	-- This one hook serves both instead.
	-- EventProbe always sees the event first, including one Suppression is about to drop.
	mod:hook(CLASS.WwiseWorld, "trigger_resource_event", function(func, wwise_world, event_name, ...)
		EventProbe.observe(event_name, select("#", ...))

		if Suppression.should_drop_event(event_name) then
			return
		end

		return func(wwise_world, event_name, ...)
	end)

	playback_lost = not AudioClient.available()
	if playback_lost then
		local reason = tostring(AudioClient.error())
		log("[player] unavailable: " .. reason)
		mod:error("[MusicReplacer] Windows audio playback could not start, so the game's own music plays as usual: %s", reason)
	end

	-- The context may have resolved before Library and AudioClient were ready.
	-- Re-evaluate now, bypassing the debounce, since this is a one-off catch-up.
	has_pending_change = false
	current_context = Context.current()
	play_context(current_context, true)
end

mod.on_setting_changed = function(setting_id)
	if setting_id == "meat_grinder_music" or setting_id == "daemonhost_boss_music" or setting_id == "captain_boss_music" then
		Context.refresh(mod)
	elseif setting_id == "resume_songs" and not mod:get("resume_songs") then
		ResumePoints.forget_all()
	end
end

-- Called by the Rescan Audio Folders button in the mod settings.
mod.rescan_audio = function()
	Library.request_rescan()
end

-- An update gap at least this long is logged, which shows how long the game's thread stalls, as during loading screens.
local STALL_LOG_SECONDS = 1

mod.update = function(dt)
	if dt >= STALL_LOG_SECONDS then
		log(string.format("[timing] the game's thread stalled for %.1fs", dt))
	end

	Context.update(mod, dt)

	if Library.update() then
		-- A replaced file deserves another try, so contexts that gave up retry after a rescan.
		quick_ends = {}
		gave_up = {}

		-- A context that played native music for lack of files starts its new track now, not at its next change.
		-- A custom track that is playing keeps playing, and the next pick uses the new list.
		if not AudioClient.is_playing() then
			play_context(current_context, true)
		end
	end

	AudioClient.update(dt)

	-- Playback that gives up mid-session hands the music back to the game at once, not at the next context change.
	if not playback_lost and not AudioClient.available() then
		playback_lost = true
		Suppression.release()
	end

	MissionProbe.update()

	if has_pending_change then
		debounce_elapsed = debounce_elapsed + dt

		if debounce_elapsed >= DEBOUNCE_SECONDS then
			commit_pending_context()
		end
	end
end

mod.on_unload = function()
	Context.shutdown(mod)
	AudioClient.shutdown()
	DiagnosticLog.close()
end
