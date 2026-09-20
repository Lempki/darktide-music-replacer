-- Tracks the pieces of game state relevant to music selection and resolves them into a single `resolved_context` string. Knows nothing about audio files or playback -- see library.lua for file lookup and MusicReplacer.lua for wiring it all together.
--
-- Non-obvious resolution rules:
--	* `music_zone`, not `music_game_state`, distinguishes the hub from a mission -- `music_game_state` settles to "mission" for both.
--	* "boss active" is the OR of two independent, loosely-correlated signals: Wwise's `music_combat == "boss"`, and an open boss_encounter_start...end window. Neither alone is reliable for every boss type, and either can get stuck independently -- a real zone change force-clears both as a recovery mechanism. BOSS_BREED_TIMEOUT_SECONDS is a time-based backstop for whatever that doesn't catch.
--	* `music_combat` flips on/off every few seconds during real combat, not just Psykhanium-style flicker. `mission_combat` holds for `combat_hold_seconds` (a mod setting) after combat quiets, so a lull doesn't drop to `mission_explore` -- entering combat stays instant.
--	* Wwise reports "no zone" as the string "None", not real nil -- confirmed via testing (Meat Grinder, and the loading screen between missions, both report this). Treated the same as nil so neither plays mission music.
--	* A mission can also run start to finish without ever reporting a zone (an Operation did). So no zone plus `music_game_state == "mission"` counts as a mission, until a victory or defeat state ends it.
--	* Victory and defeat each resolve to their own context, from their state until the next loading screen. The game state briefly returns to "mission" in between, so the outcome is tracked in `mission_outcome`.

local Context = {}

local WwiseGameSyncManager = require("scripts/managers/wwise_game_sync/wwise_game_sync_manager")

-- ###########################################################################
-- State
-- ###########################################################################

local wwise_combat_state = nil -- Current value of the "music_combat" state group.
local music_zone = nil -- Current value of the "music_zone" state group.
local music_game_state = nil -- Current value of the "music_game_state" state group.
local mission_outcome = nil -- "victory" or "defeat" from that game state until the next loading screen, else nil.
local active_boss_breed = nil -- Breed name while a boss encounter is open, else nil.
local active_boss_breed_age = 0 -- Seconds since active_boss_breed was last set.

local suppress_music_combat = false -- See Context.set_suppress_music_combat.
local forced_groups = {} -- State group name -> true while that group is forced to "None" and not yet restored.
local suppress_music_game_state = false -- See Context.set_suppress_music_game_state.
local suppress_music_events = false -- See Context.set_suppress_music_events.

local resolved_context = nil -- Last computed context string, e.g. "hub".
local change_listeners = {}
local listeners_registered = false
local diagnostic_log = function() end -- No-op unless a real logger is passed to Context.init.

-- Generous upper bound on any real boss encounter -- a safety net against active_boss_breed getting stuck, not a design target.
local BOSS_BREED_TIMEOUT_SECONDS = 180

-- Fallback if mod:get() ever returns nil -- the real value is the combat_hold_seconds mod setting.
local COMBAT_HOLD_SECONDS_DEFAULT = 8

local combat_hold_remaining = 0 -- Seconds left before mission_combat may fall back to mission_explore.

-- Native music that starts from a Wwise event instead of a state.
-- Plain substrings, matched against the full event name.
local SUPPRESSED_MUSIC_EVENT_PATTERNS = { "events/music/play_exploration" }

local MISSION_OUTCOME_CONTEXTS = { victory = "mission_victory", defeat = "mission_defeat" }

-- ###########################################################################
-- Resolution
-- ###########################################################################

local function is_boss_active()
	return wwise_combat_state == "boss" or active_boss_breed ~= nil
end

local function is_combat_active()
	return wwise_combat_state == "normal" or wwise_combat_state == "horde_low" or wwise_combat_state == "horde_high"
end

-- Wwise reports "None" as a string, not real nil.
local function has_no_zone()
	return music_zone == nil or music_zone == "None"
end

-- Some missions never report a zone, so a "mission" game state with no zone still counts as being in one.
local function is_zoneless_mission()
	return has_no_zone() and music_game_state == "mission" and not mission_outcome
end

local function resolve(mod)
	-- Victory and defeat are mission end states with their own contexts.
	-- Checked before the boss signals, since a wipe can leave a boss encounter open.
	if mission_outcome then
		return MISSION_OUTCOME_CONTEXTS[mission_outcome]
	end

	if is_boss_active() then
		return "mission_boss"
	end

	if music_zone == "hub" then
		return "hub"
	end

	if has_no_zone() then
		if not is_zoneless_mission() then
			-- Not in the hub or a mission (main menu, loading, mission end, etc.).
			return nil
		end

		if resolved_context == nil then
			diagnostic_log(string.format("[zoneless] music_zone=%s with music_game_state=%s, treating as a mission", tostring(music_zone), tostring(music_game_state)))
		end
	end

	if is_combat_active() then
		combat_hold_remaining = mod:get("combat_hold_seconds") or COMBAT_HOLD_SECONDS_DEFAULT
		return "mission_combat"
	end

	if combat_hold_remaining > 0 then
		diagnostic_log(string.format("[hold] combat quiet, holding mission_combat for %.1fs more", combat_hold_remaining))
		return "mission_combat"
	end

	return "mission_explore"
end

local function recompute(mod)
	local new_context = resolve(mod)

	if new_context == resolved_context then
		return
	end

	local old_context = resolved_context
	resolved_context = new_context

	for _, listener in ipairs(change_listeners) do
		local ok, err = pcall(listener, resolved_context, old_context, active_boss_breed)
		if not ok then
			mod:error("[MusicReplacer] context change listener failed: " .. tostring(err))
		end
	end
end

-- ###########################################################################
-- Public API
-- ###########################################################################

-- Register a function to be called whenever resolved_context changes: listener(new_context, old_context, boss_breed_or_nil)
function Context.on_change(listener)
	change_listeners[#change_listeners + 1] = listener
end

function Context.current()
	return resolved_context, active_boss_breed
end

-- Whether to force native music_combat back to "None" for as long as a custom track is playing.
-- External toggle, not automatic -- the caller should only enable this once a replacement track is confirmed playing.
-- Applied continuously, not just on the first transition, since music_combat can flap between states repeatedly without ever settling.
-- Also forces the current value immediately when turning on, not just the next transition -- otherwise a value already set before suppression started keeps playing natively until music_combat happens to flap again.
function Context.set_suppress_music_combat(should_suppress)
	suppress_music_combat = should_suppress

	if should_suppress and wwise_combat_state and wwise_combat_state ~= "None" then
		Wwise.set_state("music_combat", "None")
	end
end

-- Forces a state group to "None" once, remembering that it did so restore_group can undo it.
-- Does nothing if the group is already forced or has no real value to replace.
local function force_group_to_none(group_name, real_value)
	if forced_groups[group_name] or not real_value or real_value == "None" then
		return
	end

	forced_groups[group_name] = true
	diagnostic_log(string.format("[suppress] forcing %s %s -> None", group_name, real_value))
	Wwise.set_state(group_name, "None")
end

-- Puts a group forced by force_group_to_none back to its real value.
local function restore_group(group_name, real_value)
	if not forced_groups[group_name] then
		return
	end

	forced_groups[group_name] = false
	diagnostic_log(string.format("[suppress] restoring %s to %s", group_name, tostring(real_value)))
	Wwise.set_state(group_name, real_value or "None")
end

-- Whether to force Wwise's music_zone to "None" so the native hub music stops.
-- The hub does not run on music_combat, so set_suppress_music_combat has no effect there.
-- The game only re-sends music_zone when it changes, so the forced value stays until the next real zone change.
-- Turning this off restores the real zone, otherwise native hub music would stay silent after the custom track stops.
-- The forced set goes straight to Wwise and never reaches the _set_state hook, so `music_zone` here keeps the real value.
function Context.set_suppress_music_zone(should_suppress)
	if should_suppress then
		force_group_to_none("music_zone", music_zone)
	else
		restore_group("music_zone", music_zone)
	end
end

-- Whether to force Wwise's music_game_state to "None" so the game's own victory and defeat music stops.
-- Whether this silences it is not yet confirmed, and the lever is a guess based on how the hub's music_zone worked.
-- Unlike music_zone, the game sets this state repeatedly through a mission's end, so it is forced again after each real transition while enabled.
-- Turning this off restores the real state.
-- The forced set goes straight to Wwise and never reaches the _set_state hook, so `music_game_state` here keeps the real value.
function Context.set_suppress_music_game_state(should_suppress)
	suppress_music_game_state = should_suppress

	if should_suppress then
		force_group_to_none("music_game_state", music_game_state)
	else
		restore_group("music_game_state", music_game_state)
	end
end

-- Whether to drop native music events that match SUPPRESSED_MUSIC_EVENT_PATTERNS instead of letting them play.
-- Mission event sequences start their own music through events, which the state forcing above never reaches.
-- Only the start of an event is dropped, so nothing native is left playing to stop later.
-- Events that fire while this is off play normally, and a track they started keeps playing.
function Context.set_suppress_music_events(should_suppress)
	suppress_music_events = should_suppress
end

-- Hooks WwiseWorld.trigger_resource_event to drop the events described above.
-- Call from on_all_mods_loaded, since the Audio Plugin also waits until then to hook it.
function Context.init_event_hook(mod)
	mod:hook(CLASS.WwiseWorld, "trigger_resource_event", function(func, wwise_world, event_name, ...)
		if suppress_music_events and type(event_name) == "string" then
			for _, pattern in ipairs(SUPPRESSED_MUSIC_EVENT_PATTERNS) do
				if event_name:find(pattern, 1, true) then
					diagnostic_log(string.format("[suppress] skipped native music event: %s", event_name))
					return
				end
			end
		end

		return func(wwise_world, event_name, ...)
	end)
end

-- Wire up the Wwise state hook.
-- Call once from the main mod file's top level.
-- `log`, if given, receives a line for every raw music_zone/music_combat transition and boss event -- much higher volume than Context.on_change, meant for diagnosing state issues, not everyday use.
function Context.init(mod, log)
	diagnostic_log = log or diagnostic_log

	mod:hook(WwiseGameSyncManager, "_set_state", function(func, self, group_name, new_state)
		local current = self._wwise_state_group_states and self._wwise_state_group_states[group_name]
		local is_transition = current ~= new_state

		func(self, group_name, new_state)

		if not is_transition then
			return
		end

		if group_name == "music_combat" then
			wwise_combat_state = new_state
			diagnostic_log(string.format("[raw] music_combat: %s -> %s", tostring(current), tostring(new_state)))

			if suppress_music_combat and new_state ~= "None" then
				Wwise.set_state("music_combat", "None")
			end
		elseif group_name == "music_zone" then
			diagnostic_log(string.format("[raw] music_zone: %s -> %s", tostring(music_zone), tostring(new_state)))
			music_zone = new_state
			forced_groups.music_zone = false -- The game just set a real zone, which replaces any forced value.

			-- A real zone change force-clears both is_boss_active() signals (either can get stuck alone -- see top-of-file note).
			-- Safe for a real cross-zone encounter: this is our own tracked copy of wwise_combat_state, and self-corrects on the next real transition.
			-- A still-open active_boss_breed independently keeps is_boss_active() true regardless.
			wwise_combat_state = nil
			active_boss_breed = nil
			combat_hold_remaining = 0 -- A new zone starts fresh, not mid-hold from the last one.
		elseif group_name == "music_game_state" then
			diagnostic_log(string.format("[raw] music_game_state: %s -> %s", tostring(current), tostring(new_state)))
			music_game_state = new_state

			-- The state briefly returns to "mission" between victory/defeat and the next loading screen, so the outcome is only cleared on a real loading screen or mission intro.
			if new_state == "victory" or new_state == "game_score_win" then
				mission_outcome = "victory"
			elseif new_state == "defeat" or new_state == "game_score_lose" then
				mission_outcome = "defeat"
			elseif new_state == "loading" or new_state == "mission_intro" then
				mission_outcome = nil
			end

			if suppress_music_game_state and new_state ~= "None" then
				forced_groups.music_game_state = true
				Wwise.set_state("music_game_state", "None")
			else
				forced_groups.music_game_state = false -- The game just set a real state, which replaces any forced value.
			end
		else
			return
		end

		recompute(mod)
	end)

	-- Managers.event:register wants a STRING method name looked up on `context`, not a function reference -- passing a function registers fine but crashes the game the moment the event fires.
	function mod.on_boss_start(self, unit, boss_extension)
		local breed = boss_extension and boss_extension._breed
		active_boss_breed = breed and breed.name or "<unknown>"
		active_boss_breed_age = 0
		diagnostic_log(string.format("[raw] boss_encounter_start breed=%s", active_boss_breed))
		recompute(mod)
	end

	function mod.on_boss_end(self, unit, boss_extension)
		diagnostic_log("[raw] boss_encounter_end")
		active_boss_breed = nil
		recompute(mod)
	end
end

-- Call from the main mod file's mod.update.
-- Managers.event doesn't exist at mod-load time, so listeners are registered lazily once it is.
-- Also advances the BOSS_BREED_TIMEOUT_SECONDS watchdog every tick.
function Context.update(mod, dt)
	if active_boss_breed then
		active_boss_breed_age = active_boss_breed_age + dt

		if active_boss_breed_age > BOSS_BREED_TIMEOUT_SECONDS then
			diagnostic_log(string.format("[raw] active_boss_breed watchdog: forcing clear after %ss stuck (breed was %s)", BOSS_BREED_TIMEOUT_SECONDS, tostring(active_boss_breed)))
			active_boss_breed = nil
			active_boss_breed_age = 0
			recompute(mod)
		end
	end

	-- Only ticks down once combat is genuinely inactive.
	-- resolve() already refreshes combat_hold_remaining to the full setting on every active tick, so counting down unconditionally here made it drain during active combat too, leaving an effectively random amount whenever combat actually stopped.
	if combat_hold_remaining > 0 and not is_combat_active() then
		combat_hold_remaining = math.max(combat_hold_remaining - dt, 0)

		if combat_hold_remaining == 0 then
			recompute(mod)
		end
	end

	if listeners_registered then
		return
	end

	if Managers and Managers.event then
		Managers.event:register(mod, "boss_encounter_start", "on_boss_start")
		Managers.event:register(mod, "boss_encounter_end", "on_boss_end")
		listeners_registered = true
	end
end

-- Call from the main mod file's mod.on_unload.
function Context.shutdown(mod)
	if listeners_registered and Managers and Managers.event then
		Managers.event:unregister(mod, "boss_encounter_start")
		Managers.event:unregister(mod, "boss_encounter_end")
	end

	listeners_registered = false
end

return Context
