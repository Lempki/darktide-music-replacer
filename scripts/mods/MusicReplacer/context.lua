-- Tracks the game state that decides which music should play, and resolves it into one `resolved_context` string.
-- Knows nothing about audio files or playback.
-- See library.lua for file lookup and MusicReplacer.lua for the wiring.
--
-- Resolution rules that are not obvious from the code:
--	* The hub is told apart from a mission by `music_zone`, since `music_game_state` is "mission" for both.
--	* A boss is active when Wwise reports `music_combat == "boss"` or a boss encounter window is open.
--	  Neither signal alone is reliable for every boss type, and either can get stuck.
--	  A real zone change clears both.
--	* Encounter windows are tracked per boss unit, since several bosses can be open at once and a start can repeat.
--	  A window stays open until its own end event, which the game sends when the boss dies or despawns.
--	  A boss that the game leaves stuck somewhere keeps its window open, just as it keeps the game's own boss music.
--	* A boss only counts in the hub or a mission, never on a loading screen.
--	  Meat Grinder's boss dummies leave `music_combat` at "boss" after leaving, until the next mission's intro ends.
--	* `music_combat` flips on and off every few seconds in real combat.
--	  So `mission_combat` holds for `combat_hold_seconds` after combat quiets, and a lull does not drop to `mission_explore`.
--	  Entering combat is never delayed.
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
local mission_name = nil -- Name of the current mission, or nil while none is loaded.
local mission_outcome = nil -- "victory" or "defeat" from that game state until the next level starts, else nil.
local open_bosses = {} -- Boss unit -> { breed = name, order = n } for every open encounter window.
local boss_open_count = 0 -- Increases with every newly opened window, so the latest one can be found.

local resolved_context = nil -- Last computed context string, for example "hub".
local change_listeners = {}
local state_listeners = {}
local listeners_registered = false
local diagnostic_log = function() end -- No-op unless a real logger is passed to Context.init.

-- Used only if mod:get() returns nil.
-- The real value is the combat_hold_seconds mod setting.
local COMBAT_HOLD_SECONDS_DEFAULT = 8

local combat_hold_remaining = 0 -- Seconds left before mission_combat may fall back to mission_explore.

local MISSION_OUTCOME_CONTEXTS = { victory = "mission_victory", defeat = "mission_defeat" }

-- Music-related state groups that do not decide a context yet, logged only so their transitions show up in diagnostic.log.
-- music_objective carries mission event music and "last_man_standing".
local LOGGED_ONLY_STATE_GROUPS = {
	music_objective = true,
	music_objective_progression = true,
	event_intensity = true,
	event_category = true,
	circumstance = true,
	expeditions_intensity = true,
}

-- Game states in which the player is in the hub or a mission, rather than on a loading screen, a briefing or a menu.
local IN_WORLD_GAME_STATES = { mission = true, mission_board = true, mission_ready = true }

-- Mission name of the training area where Meat Grinder runs.
-- Its template has no wwise_state, so music_zone reads "None" there.
local MEAT_GRINDER_MISSION = "tg_shooting_range"

-- ###########################################################################
-- Resolution
-- ###########################################################################

local function is_boss_active()
	return wwise_combat_state == "boss" or next(open_bosses) ~= nil
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

local function is_combat_active()
	return wwise_combat_state == "normal" or wwise_combat_state == "horde_low" or wwise_combat_state == "horde_high"
end

-- Returns the current mission's name, or nil before a level has loaded.
local function read_mission_name()
	local game_state = Managers and Managers.state
	local mission_manager = game_state and game_state.mission

	if not mission_manager then
		return nil
	end

	local ok, name = pcall(mission_manager.mission_name, mission_manager)

	return ok and name or nil
end

-- Wwise reports "None" as a string, not as nil.
local function has_no_zone()
	return music_zone == nil or music_zone == "None"
end

-- Some missions never report a zone, so a "mission" game state with no zone still counts as a mission.
local function is_zoneless_mission()
	return has_no_zone() and music_game_state == "mission" and not mission_outcome
end

local function resolve(mod)
	-- Cutscenes get no custom music, whatever zone or outcome is still set.
	if music_game_state == "cinematic" then
		return nil
	end

	-- Victory and defeat have their own contexts.
	-- They are checked before the boss signals, since a wipe can leave a boss encounter open.
	if mission_outcome then
		return MISSION_OUTCOME_CONTEXTS[mission_outcome]
	end

	if not IN_WORLD_GAME_STATES[music_game_state] then
		return nil
	end

	-- Meat Grinder is silent unless the player opts in.
	if mission_name == MEAT_GRINDER_MISSION and not mod:get("meat_grinder_music") then
		return "silence"
	end

	-- Not in the hub or a mission, for example the main menu, a loading screen or a mission end.
	-- This comes before the boss signals, since `music_combat` can stay at "boss" after a level ends.
	if has_no_zone() and not is_zoneless_mission() then
		return nil
	end

	if is_boss_active() then
		return "mission_boss"
	end

	if music_zone == "hub" then
		return "hub"
	end

	if has_no_zone() and resolved_context == nil then
		diagnostic_log(string.format("[zoneless] music_zone=%s with music_game_state=%s, treating as a mission", tostring(music_zone), tostring(music_game_state)))
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
		local ok, err = pcall(listener, resolved_context, old_context, current_boss_breed())
		if not ok then
			mod:error("[MusicReplacer] context change listener failed: " .. tostring(err))
		end
	end
end

-- ###########################################################################
-- Public API
-- ###########################################################################

-- Register a function to call whenever resolved_context changes.
-- The listener receives (new_context, old_context, boss_breed_or_nil).
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

-- Register a function to call on every real transition of a music state group, after context.lua has tracked it.
-- The listener receives (group_name, new_state) for music_combat, music_zone and music_game_state only.
function Context.on_state_change(listener)
	state_listeners[#state_listeners + 1] = listener
end

-- Installs the Wwise state hook and the boss encounter callbacks.
-- Call once from the main mod file's top level.
-- `log`, if given, receives a line for every raw state transition and boss event.
-- That is much more output than Context.on_change, so it is meant for diagnosing state issues.
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
		elseif group_name == "music_zone" then
			diagnostic_log(string.format("[raw] music_zone: %s -> %s", tostring(music_zone), tostring(new_state)))
			music_zone = new_state

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
		elseif group_name == "music_game_state" then
			diagnostic_log(string.format("[raw] music_game_state: %s -> %s", tostring(current), tostring(new_state)))
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
		else
			if LOGGED_ONLY_STATE_GROUPS[group_name] then
				diagnostic_log(string.format("[raw] %s: %s -> %s", group_name, tostring(current), tostring(new_state)))
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
	-- A repeated start for an open unit keeps its window as it is.
	function mod.on_boss_start(self, unit, boss_extension)
		local breed = boss_extension and boss_extension._breed
		local breed_name = breed and breed.name or "<unknown>"
		diagnostic_log(string.format("[raw] boss_encounter_start breed=%s", breed_name))

		if unit and not open_bosses[unit] then
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
-- Also tracks the current mission name.
function Context.update(mod, dt)
	local current_mission_name = read_mission_name()

	if current_mission_name ~= mission_name then
		mission_name = current_mission_name
		recompute(mod)
	end

	-- The hold only counts down once combat is inactive.
	-- resolve() refreshes it to its full value on every active tick, so it must not also drain while combat is active.
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
