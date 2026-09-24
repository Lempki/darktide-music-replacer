local mod = get_mod("MusicReplacer")

-- mod:io_dofile paths are relative to "mods/" and include this mod's own folder name.
-- MusicReplacer.mod's own paths follow the same rule.
local Context = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/context")
local Suppression = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/suppression")
local Library = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/library")
local AudioClient = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/audio_client")
local EventProbe = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/event_probe")
local MissionProbe = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/mission_probe")
local DiagnosticLog = mod:io_dofile("MusicReplacer/scripts/mods/MusicReplacer/diagnostic_log")

DiagnosticLog.init(mod)
local log = DiagnosticLog.write

-- ###########################################################################
-- Playback Orchestration
-- ###########################################################################
-- Combines "what context" (context.lua) with "is there a file for it" (library.lua) to decide what audio_client.lua does.
-- Native music is only silenced once a replacement is confirmed playing.
-- So a context with no file falls back to native music by construction.

local current_context = nil

-- context_name -> true once a single-file context has finished its first filtered play-through and switched to native looping.
local native_loop_active = {}

-- is_new_context separates a real context change from advancing within the same context.
-- Advancing means a playlist continuation or a native loop's own repeat, and only a real change should fade in again.
local function play_context(context_name, is_new_context)
	if not context_name then
		AudioClient.stop()
		Suppression.release()
		return
	end

	if is_new_context then
		-- A real (re-)entry restarts a single-file context from a fresh, filtered first play. See use_native_loop below.
		native_loop_active[context_name] = nil
	end

	local file_path, duration, is_only_file = Library.pick_file(context_name)

	if not file_path then
		-- No replacement is available: no folder, an empty folder, no Audio Plugin, or a scan that has not finished.
		-- Native music is left alone.
		AudioClient.stop()
		Suppression.release()
		log(string.format("[playback] %s: no file available, using native music", context_name))
		return
	end

	-- A file is confirmed playing for context_name here, since the no-file branch above already returned.
	-- So the native music is silenced for it.
	Suppression.engage(context_name)

	-- A single-file context plays once normally first, with loop=1 and the fades.
	-- After that it switches to native looping, with loop=0 and no filters.
	-- ffplay's -loop re-triggers filters every iteration, so a fade-in from the start would otherwise repeat forever.
	local use_native_loop = is_only_file and native_loop_active[context_name] == true

	log(string.format("[playback] %s: playing %s (duration=%s%s)",
		context_name, file_path, tostring(duration), use_native_loop and ", looping natively" or ""))

	-- A single file loops forever, so a natural-end fade-out would only fade to silence before a hard restart of the same track.
	-- Leaving the duration out is what disables that fade-out, including after a volume relaunch.
	AudioClient.play(file_path, {
		duration_seconds = not is_only_file and duration or nil,
		fade_in = is_new_context,
		native_loop = use_native_loop,
		on_finished = function()
			-- Never fires once use_native_loop is true.
			-- Only continues if still in this context.
			-- If it changed, whatever triggered the change already called play_context for the new one.
			if current_context == context_name then
				if is_only_file then
					native_loop_active[context_name] = true
				end
				play_context(context_name, false)
			end
		end,
	})
end

-- Context changes are debounced before they are acted on.
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
Context.on_state_change(Suppression.on_state_change)
Context.init(mod, log)

mod.on_all_mods_loaded = function()
	Library.init()
	AudioClient.init(log)

	-- A mod can only install one hook per method on itself, so Suppression and EventProbe cannot each hook WwiseWorld.trigger_resource_event on their own.
	-- This one hook serves both instead.
	-- EventProbe always sees the event first, including one Suppression is about to drop.
	mod:hook(CLASS.WwiseWorld, "trigger_resource_event", function(func, wwise_world, event_name, ...)
		EventProbe.observe(event_name, select("#", ...))

		if Suppression.should_drop_event(event_name) then
			return
		end

		return func(wwise_world, event_name, ...)
	end)

	if not AudioClient.available() then
		mod:error(
			"[MusicReplacer] Audio Plugin not found -- music replacement disabled, native music will play "
				.. "normally. Install 'Audio' (and its dependency 'DarktideLocalServer') from Nexus Mods and "
				.. "place both above MusicReplacer in mod_load_order.txt."
		)
	end

	-- The context may have resolved before Library and AudioClient were ready.
	-- Re-evaluate now, bypassing the debounce, since this is a one-off catch-up.
	has_pending_change = false
	current_context = Context.current()
	play_context(current_context, true)
end

mod.update = function(dt)
	Context.update(mod, dt)
	AudioClient.update(dt)
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
	AudioClient.shutdown() -- Direct OS-level kill, since the normal stop cannot be relied on here.
	DiagnosticLog.close()
end
