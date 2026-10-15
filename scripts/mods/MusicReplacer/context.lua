-- Tracks the game state that decides which music should play, and resolves it into one `resolved_context` string.
-- Knows nothing about audio files or playback.
-- See library.lua for file lookup and MusicReplacer.lua for the wiring.
--
-- Resolution rules that are not obvious from the code:
--	* The hub is told apart from a mission by `music_zone`, since `music_game_state` is "mission" for both.
--	* A boss is active while Wwise reports `music_combat == "boss"`, which is when the game plays its own boss music.
--	  Bosses that only open an encounter window get no boss music in the game, so they get none here either.
--	  Those are captains, daemonhosts, and Spillway's psyker, which the game's boss music check leaves out by their breed tags.
--	* A captain's or a daemonhost's encounter window counts as a boss only with its setting on.
--	  Scripted captains appear during events, and event music wins over bosses, so the setting only matters for random ones.
--	* Encounter windows are tracked per boss unit, since several bosses can be open at once and a start can repeat.
--	  A window stays open until its own end event, which the game sends when the boss dies or despawns.
--	  A boss that the game leaves stuck somewhere keeps its window open, just as it keeps the game's own boss music.
--	* A boss only counts in the hub or a mission, never on a loading screen.
--	  Meat Grinder's boss dummies leave `music_combat` at "boss" after leaving, until the next mission's intro ends.
--	* `music_combat` flips on and off every few seconds in real combat.
--	  So `mission_combat` holds for `combat_hold_seconds` after combat quiets, and a lull does not drop to `mission_explore`.
--	  Entering combat is never delayed.
--	* "horde_low" and "horde_high" resolve "mission_horde", below bosses. The game plays its own horde music for both.
--	  The game reports a horde only while at least 5 enemies are aggroed, so it drops out for a second or two mid-horde.
--	  So `mission_horde` holds for `horde_hold_seconds`, which is shorter than the combat hold, since a horde ends for good.
--	  Once that hold runs out, the plain combat state decides, with no combat hold added on top.
--	* No context resolves while `music_game_state == "cinematic"`, so custom music stays off during cutscenes.
--	* The hub and mission contexts only resolve while the game state is in the world: "mission", "mission_board" or "mission_ready".
--	  Loading screens, the loadout, the briefing, the intro and menus resolve no context, even once the zone has arrived.
--	  The game sends the hub zone about 10 seconds before the loading screen ends, and a mission zone partway through the briefing.
--	* Meat Grinder has no `wwise_state`, so it is recognized by its mission name instead.
--	  It resolves to "silence" unless the `meat_grinder_music` setting is on.
--	  "silence" plays no custom track and keeps the combat and exploration event suppression on.
--	* Wwise reports "no zone" as the string "None". Meat Grinder and the loading screens both report it.
--	  It is treated like nil, so neither plays mission music.
--	* Some missions never report a zone.
--	  No zone plus `music_game_state == "mission"` counts as a mission until a victory or defeat state ends it.
--	  It does not count while the hub is still loaded, since leaving the hub clears the zone a moment before the game state changes.
--	* `music_objective == "last_man_standing"` resolves "mission_last_stand", over bosses, combat and explore.
--	  The game sets it when one player of the team is alive. Once it ends, the context follows the other states again.
--	* Any other `music_objective` value is mission event music, for example "kill_event" or "fortification_event".
--	  It resolves "mission_event", over bosses, as the game's own event music does. Spillway's scripted bosses are events.
--	  Last stand and event music share the group, so the game itself decides between them, and last stand wins there.
--	* Mortis Trials is recognized by its own music zone, "horde_mode".
--	  Its waves, objective rounds and final win set `music_objective` and resolve "mortis_trials_wave".
--	  The breaks between them resolve "mortis_trials_break".
--	  Bosses, hordes and combat change neither, since nearly every wave brings bosses. A last stand still wins over both.
--	* Victory and defeat resolve to their own contexts, from their state until the next level starts.
--	  The game state returns to "mission" in between, so the outcome is tracked in `mission_outcome`.
--	  A loading screen or a real zone clears it, since a story mission's cutscene can skip the loading screen.

local Context = {}

local WwiseGameSyncManager = require("scripts/managers/wwise_game_sync/wwise_game_sync_manager")

-- ###########################################################################
-- State
-- ###########################################################################

local wwise_combat_state = nil -- Current value of the "music_combat" state group.
local music_zone = nil -- Current value of the "music_zone" state group.
local music_game_state = nil -- Current value of the "music_game_state" state group.
local music_objective = nil -- Current value of the "music_objective" state group.
local mission_name = nil -- Name of the current mission, or nil while none is loaded.
local mission_is_hub = false -- True while the loaded mission's template is the hub.
local mission_is_operation = false -- True while the loaded mission is an Operation.
local mission_outcome = nil -- "victory" or "defeat" from that game state until the next level starts, else nil.
local open_bosses = {} -- Boss unit -> { breed = name, order = n } for every open encounter window.
local boss_open_count = 0 -- Increases with every newly opened window, so the latest one can be found.

local resolved_context = nil -- Last computed context string, for example "hub".

-- State group name -> true once the hook has seen that group since this module loaded or Context.relearn() ran.
-- The game sets every group again on every tick, so a group not yet seen is caught up on the next tick even when its value has not changed.
local learned_groups = {}
local change_listeners = {}
local state_listeners = {}
local listeners_registered = false
local diagnostic_log = function() end -- No-op unless a real logger is passed to Context.init.

-- Fallbacks for when the hold settings read nil.
local COMBAT_HOLD_SECONDS_DEFAULT = 8
local HORDE_HOLD_SECONDS_DEFAULT = 3

local combat_hold_remaining = 0 -- Seconds left before mission_combat may fall back to mission_explore.
local horde_hold_remaining = 0 -- Seconds left before mission_horde may fall back to the plain combat state.

local MISSION_OUTCOME_CONTEXTS = { victory = "mission_victory", defeat = "mission_defeat" }

-- Breeds the game plays no boss music for, mapped to the setting that makes them count as bosses.
-- The game has several daemonhost breeds, for mutators and other modes, and all of them behave alike.
local OPT_IN_BOSS_SETTINGS = {
	chaos_daemonhost = "daemonhost_boss_music",
	chaos_daemonhost_torment = "daemonhost_boss_music",
	chaos_mutator_daemonhost = "daemonhost_boss_music",
	renegade_captain = "captain_boss_music",
	renegade_twin_captain = "captain_boss_music",
	renegade_twin_captain_two = "captain_boss_music",
	cultist_captain = "captain_boss_music",
}

-- The music_objective value the game sets while one player of the team is alive.
local LAST_MAN_STANDING = "last_man_standing"

-- Music-related state groups that do not decide a context yet, logged only so their transitions show up in diagnostic.log.
local LOGGED_ONLY_STATE_GROUPS = {
	music_objective_progression = true,
	event_intensity = true,
	event_category = true,
	circumstance = true,
}

-- Game states in which the player is in the hub or a mission, rather than on a loading screen, a briefing or a menu.
local IN_WORLD_GAME_STATES = { mission = true, mission_board = true, mission_ready = true }

-- Mission name of the training area where Meat Grinder runs.
-- Its template has no wwise_state, so music_zone reads "None" there.
local MEAT_GRINDER_MISSION = "tg_shooting_range"

-- The music_zone value the game sets for Mortis Trials.
local MORTIS_TRIALS_ZONE = "horde_mode"

-- ###########################################################################
-- Resolution
-- ###########################################################################

local function is_boss_active(mod)
	if wwise_combat_state == "boss" then
		return true
	end

	for _, boss in pairs(open_bosses) do
		local setting_id = OPT_IN_BOSS_SETTINGS[boss.breed]

		if setting_id and mod:get(setting_id) then
			return true
		end
	end

	return false
end

-- Breed name of the most recently opened encounter window, or nil when none is open.
local function current_boss_breed()
	local latest = nil

	for _, boss in pairs(open_bosses) do
		if not latest or boss.order > latest.order then
			latest = boss
		end
	end

	return latest and latest.breed
end

local function is_horde_active()
	return wwise_combat_state == "horde_low" or wwise_combat_state == "horde_high"
end

local function combat_hold_seconds(mod)
	return mod:get("combat_hold_seconds") or COMBAT_HOLD_SECONDS_DEFAULT
end

local function horde_hold_seconds(mod)
	return mod:get("horde_hold_seconds") or HORDE_HOLD_SECONDS_DEFAULT
end

local function is_combat_active()
	return wwise_combat_state == "normal" or wwise_combat_state == "horde_low" or wwise_combat_state == "horde_high"
end

-- Returns the current mission's name, whether its template is the hub, and whether it is an Operation.
-- Returns nil, false, false before a level has loaded.
local function read_mission()
	local game_state = Managers and Managers.state
	local mission_manager = game_state and game_state.mission

	if not mission_manager then
		return nil, false, false
	end

	local ok, name = pcall(mission_manager.mission_name, mission_manager)

	if not ok or not name then
		return nil, false, false
	end

	local template_ok, template = pcall(mission_manager.mission, mission_manager)
	local has_template = template_ok and type(template) == "table"

	return name, has_template and template.is_hub == true, has_template and template.mission_type == "operations"
end

-- Wwise reports "None" as a string, not as nil.
local function has_no_zone()
	return music_zone == nil or music_zone == "None"
end

-- Some missions never report a zone, so a "mission" game state with no zone still counts as a mission.
local function is_zoneless_mission()
	return has_no_zone() and music_game_state == "mission" and not mission_outcome and not mission_is_hub
end

local function resolve(mod)
	-- Cutscenes get no custom music, whatever zone or outcome is still set.
	if music_game_state == "cinematic" then
		return nil
	end

	-- Victory and defeat are checked before the boss signals, since a wipe can leave a boss encounter open.
	if mission_outcome then
		return MISSION_OUTCOME_CONTEXTS[mission_outcome]
	end

	if not IN_WORLD_GAME_STATES[music_game_state] then
		return nil
	end

	if mission_name == MEAT_GRINDER_MISSION and not mod:get("meat_grinder_music") then
		return "silence"
	end

	-- Not in the hub or a mission, for example the main menu, a loading screen or a mission end.
	-- This comes before the boss signals, since `music_combat` can stay at "boss" after a level ends.
	if has_no_zone() and not is_zoneless_mission() then
		return nil
	end

	if music_objective == LAST_MAN_STANDING then
		return "mission_last_stand"
	end

	if music_zone == MORTIS_TRIALS_ZONE then
		local in_wave = music_objective ~= nil and music_objective ~= "None"
		return in_wave and "mortis_trials_wave" or "mortis_trials_break"
	end

	-- Operations script their music across the whole mission, in stages with short gaps between them, so each is one long event.
	if (music_objective and music_objective ~= "None") or mission_is_operation then
		return "mission_event"
	end

	if is_boss_active(mod) then
		return "mission_boss"
	end

	if music_zone == "hub" then
		return "hub"
	end

	if has_no_zone() and resolved_context == nil then
		diagnostic_log(string.format("[zoneless] music_zone=%s with music_game_state=%s, treating as a mission", tostring(music_zone), tostring(music_game_state)))
	end

	if is_horde_active() then
		horde_hold_remaining = horde_hold_seconds(mod)
		combat_hold_remaining = 0
		return "mission_horde"
	end

	if horde_hold_remaining > 0 then
		diagnostic_log(string.format("[hold] horde quiet, holding mission_horde for %.1fs more", horde_hold_remaining))
		return "mission_horde"
	end

	if is_combat_active() then
		combat_hold_remaining = combat_hold_seconds(mod)
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
		local ok, err = pcall(listener, resolved_context, old_context, current_boss_breed())
		if not ok then
			mod:error("[MusicReplacer] context change listener failed: " .. tostring(err))
		end
	end
end

-- A group caught up with its value unchanged, after a load or Context.relearn(), has no real previous value to show.
local function describe_transition(group_name, from, to)
	if from == to then
		return string.format("[raw] %s: %s, read again", group_name, tostring(to))
	end

	return string.format("[raw] %s: %s -> %s", group_name, tostring(from), tostring(to))
end

-- ###########################################################################
-- Public API
-- ###########################################################################

-- The listener receives (new_context, old_context, boss_breed_or_nil) whenever the resolved context changes.
function Context.on_change(listener)
	change_listeners[#change_listeners + 1] = listener
end

function Context.current()
	return resolved_context, current_boss_breed()
end

-- Resolves again after a setting change.
function Context.refresh(mod)
	recompute(mod)
end

-- Makes the next value the game sets for every state group count as a change, so this module and its listeners catch up.
-- For when the hook may have missed changes, as while the mod is turned off, since DMF disables a mod's hooks then.
-- The next change it resolves is reported even if it matches the context from before.
function Context.relearn()
	learned_groups = {}
	resolved_context = nil
end

-- Register a function to call on every real transition of a music state group, after context.lua has tracked it.
-- The listener receives (group_name, new_state) for music_combat, music_zone, music_game_state and music_objective only.
function Context.on_state_change(listener)
	state_listeners[#state_listeners + 1] = listener
end

-- Call once from the main mod file's top level.
-- `log`, if given, receives a line for every raw state transition and boss event.
-- That is much more output than Context.on_change, so it is meant for diagnosing state issues.
function Context.init(mod, log)
	diagnostic_log = log or diagnostic_log

	mod:hook(WwiseGameSyncManager, "_set_state", function(func, self, group_name, new_state)
		local current = self._wwise_state_group_states and self._wwise_state_group_states[group_name]
		local is_transition = current ~= new_state or not learned_groups[group_name]

		func(self, group_name, new_state)

		if not is_transition then
			return
		end

		learned_groups[group_name] = true

		if group_name == "music_combat" then
			wwise_combat_state = new_state
			diagnostic_log(describe_transition(group_name, current, new_state))
		elseif group_name == "music_zone" then
			diagnostic_log(describe_transition(group_name, music_zone, new_state))

			-- Catching up after a load or Context.relearn() is not a zone change, so it keeps the outcome and the boss windows.
			local zone_changed = music_zone ~= nil and new_state ~= music_zone
			music_zone = new_state

			if zone_changed then
				-- A real zone means a new level has started, which ends the previous mission's outcome.
				-- The score screen sets the zone to "None", so that case keeps the outcome.
				if not has_no_zone() then
					mission_outcome = nil
				end

				-- A real zone change clears both boss signals, since either can get stuck on its own.
				-- The tracked combat state is only this module's copy, so it corrects itself on the next real transition.
				-- A boss encounter that is still open keeps is_boss_active() true anyway.
				wwise_combat_state = nil
				open_bosses = {}
				combat_hold_remaining = 0 -- A new zone starts fresh, not partway through the last hold.
				horde_hold_remaining = 0
			end
		elseif group_name == "music_game_state" then
			diagnostic_log(describe_transition(group_name, current, new_state))
			music_game_state = new_state

			-- The state returns to "mission" between victory or defeat and the next loading screen.
			-- So the outcome is only cleared by a loading screen or a mission intro.
			if new_state == "victory" or new_state == "game_score_win" then
				mission_outcome = "victory"
			elseif new_state == "defeat" or new_state == "game_score_lose" then
				mission_outcome = "defeat"
			elseif new_state == "loading" or new_state == "mission_intro" then
				mission_outcome = nil
			end
		elseif group_name == "music_objective" then
			diagnostic_log(describe_transition(group_name, current, new_state))
			music_objective = new_state
		else
			if LOGGED_ONLY_STATE_GROUPS[group_name] then
				diagnostic_log(describe_transition(group_name, current, new_state))
			end

			return
		end

		for _, listener in ipairs(state_listeners) do
			local ok, err = pcall(listener, group_name, new_state)
			if not ok then
				mod:error("[MusicReplacer] state change listener failed: " .. tostring(err))
			end
		end

		recompute(mod)
	end)

	-- Managers.event:register needs the callback as a string method name, looked up on the registered object.
	-- Passing a function registers without error, then crashes the game when the event fires.
	-- A repeated start for an open unit keeps its window as it is, and is not logged.
	-- Meat Grinder's boss dummies repeat their start over and over.
	function mod.on_boss_start(self, unit, boss_extension)
		if unit and open_bosses[unit] then
			return
		end

		local breed = boss_extension and boss_extension._breed
		local breed_name = breed and breed.name or "<unknown>"
		diagnostic_log(string.format("[raw] boss_encounter_start breed=%s", breed_name))

		if unit then
			boss_open_count = boss_open_count + 1
			open_bosses[unit] = { breed = breed_name, order = boss_open_count }
		end

		recompute(mod)
	end

	function mod.on_boss_end(self, unit, boss_extension)
		diagnostic_log("[raw] boss_encounter_end")

		if unit then
			open_bosses[unit] = nil
		end

		recompute(mod)
	end
end

-- Call from the main mod file's mod.update.
-- Managers.event does not exist at mod-load time, so the boss callbacks are registered on the first tick where it does.
function Context.update(mod, dt)
	local current_mission_name, current_mission_is_hub, current_mission_is_operation = read_mission()

	if current_mission_name ~= mission_name or current_mission_is_hub ~= mission_is_hub
		or current_mission_is_operation ~= mission_is_operation then
		mission_name = current_mission_name
		mission_is_hub = current_mission_is_hub
		mission_is_operation = current_mission_is_operation
		recompute(mod)
	end

	-- The hold only counts down once combat is inactive.
	-- resolve() refreshes it to its full value on every active tick, so it must not also drain while combat is active.
	if horde_hold_remaining > 0 and not is_horde_active() then
		horde_hold_remaining = math.max(horde_hold_remaining - dt, 0)

		if horde_hold_remaining == 0 then
			recompute(mod)
		end
	end

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
