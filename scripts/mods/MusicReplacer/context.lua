-- Tracks the game state that decides which music should play, and resolves it into one `resolved_context` string.
-- Knows nothing about audio files or playback.
-- See library.lua for file lookup and MusicReplacer.lua for the wiring.
--
-- Resolution rules that are not obvious from the code:
--	* The hub is told apart from a mission by `music_zone`, since `music_game_state` is "mission" for both.
--	  The hub zone wins over every mission state, since quitting mid-event or mid-last-stand can leave `music_objective` set.
--	* A boss is active while Wwise reports `music_combat == "boss"`, which is when the game plays its own boss music.
--	  Bosses that only open an encounter window get no boss music in the game, so they get none here either.
--	  Those are captains, daemonhosts, and Spillway's psyker, which the game's boss music check leaves out by their breed tags.
--	* A captain's or a daemonhost's encounter window counts as a boss only with its setting on.
--	  Scripted captains appear during events, and event music wins over bosses, so the setting only matters for random ones.
--	* Encounter windows are tracked per boss unit, since several bosses can be open at once and a start can repeat.
--	  A window stays open until its own end event, which the game sends when the boss dies or despawns.
--	  A boss that the game leaves stuck somewhere keeps its window open, just as it keeps the game's own boss music.
--	* A boss only counts in a mission, never in the hub or on a loading screen.
--	  Boss windows are also cleared by every loading screen, so a window whose end event never came cannot reach the next level.
--	  Meat Grinder's boss dummies leave `music_combat` at "boss" after leaving, until the next mission's intro ends.
--	* `music_combat` flips on and off every few seconds in real combat.
--	  So `combat` holds for `combat_hold_seconds` after combat quiets, and a lull does not drop to `explore`.
--	  Entering combat is never delayed.
--	* "horde_low" and "horde_high" resolve "horde", below bosses. The game plays its own horde music for both.
--	  The game reports a horde only while at least 5 enemies are aggroed, so it drops out for a second or two mid-horde.
--	  So `horde` holds for `horde_hold_seconds`, which is shorter than the combat hold, since a horde ends for good.
--	  Once that hold runs out, the plain combat state decides, with no combat hold added on top.
--	* No context resolves while `music_game_state == "cinematic"`, so custom music stays off during cutscenes.
--	* The hub and mission contexts only resolve while the game state is in the world: "mission", "mission_board" or "mission_ready".
--	  Loading screens and the briefing resolve "loading" or "mission_briefing" instead, even once the zone has arrived.
--	  The briefing, and every loading screen after the mission board's "mission_ready", lead into a mission and resolve "mission_briefing".
--	  A plain loading screen does not say where it leads, so "mission_ready" tells joining a mission apart from leaving one.
--	  The mission preparation screen, where the party stands together before a mission, resolves "mission_preparation".
--	  The game reports it as "loadout" in every game mode.
--	  The mission's intro resolves no context and keeps the game's stinger.
--	  Menus such as character select resolve no context either.
--	  The game sends the hub zone about 10 seconds before the loading screen ends, and a mission zone partway through the briefing.
--	* Meat Grinder has no `wwise_state`, so it is recognized by its mission name instead.
--	  It resolves to "meat_grinder", whose own setting picks silence or the game's music there.
--	  With that setting on "custom", it resolves like a mission instead, so the explore and combat music plays.
--	* Wwise reports "no zone" as the string "None". Meat Grinder and the loading screens both report it.
--	  It is treated like nil, so neither plays mission music.
--	* Some missions never report a zone.
--	  No zone plus `music_game_state == "mission"` counts as a mission until a victory or defeat state ends it.
--	  It does not count while the hub is still loaded, since leaving the hub clears the zone a moment before the game state changes.
--	  Nor does it count with no mission loaded at all.
--	  Leaving the hub for character select unloads the hub a few seconds before the game state changes.
--	* `music_objective == "last_man_standing"` resolves "last_stand", over bosses, combat and explore.
--	  The game sets it when one player of the team is alive. Once it ends, the context follows the other states again.
--	* Any other `music_objective` value is mission event music, for example "kill_event" or "fortification_event".
--	  It resolves "event", over bosses, as the game's own event music does. Spillway's scripted bosses are events.
--	  Last stand and event music share the group, so the game itself decides between them, and last stand wins there.
--	  Some events clear `music_objective` for a few seconds between their stages, such as Cargo's end event.
--	  So `event` holds for `event_hold_seconds` after it clears, and the event's song does not start over at every stage.
--	* Mortis Trials is recognized by its own music zone, "horde_mode".
--	  Its waves, objective rounds and final win set `music_objective` and resolve "mortis_trials_wave".
--	  The breaks between them resolve "mortis_trials_break".
--	  Bosses, hordes and combat change neither, since nearly every wave brings bosses. A last stand still wins over both.
--	* Victory and defeat resolve to their own contexts, from their state until the next level starts.
--	  The game state returns to "mission" in between, so the outcome is tracked in `mission_outcome`.
--	  A loading screen or a real zone clears it, since a story mission's cutscene can skip the loading screen.
--	* Context.override_keys() names the override folders a context may use, most specific first.
--	  An event's kind is its `music_objective` value, kept through its hold, and a boss's kind is its breed.
--	  The mission is its code, and the game mode is "havoc" or "expeditions".
--	  Havoc is told apart by its Havoc data in the difficulty manager, since it changes no music state.
--	* Every menu screen sets the `options` group, for example to "ingame_menu" in the Esc menu or "vendor_menu" at a vendor.
--	  It decides no context. It only tells MusicReplacer.lua that a menu is open, so the music can be lowered.

local Context = {}

local WwiseGameSyncManager = require("scripts/managers/wwise_game_sync/wwise_game_sync_manager")
local WwiseStateGroupCombat = require("scripts/managers/wwise_game_sync/wwise_state_groups/wwise_state_group_combat")

-- ###########################################################################
-- State
-- ###########################################################################

local music_combat = nil -- Current value of the "music_combat" state group.
local music_zone = nil -- Current value of the "music_zone" state group.
local music_game_state = nil -- Current value of the "music_game_state" state group.
local music_objective = nil -- Current value of the "music_objective" state group.
local menu_state = nil -- Current value of the "options" state group, which names the kind of menu open.
local mission_name = nil -- Name of the current mission, or nil while none is loaded.
local mission_is_hub = false -- True while the loaded mission's template is the hub.
local mission_is_operation = false -- True while the loaded mission is an Operation.
local mission_mode = nil -- "havoc" or "expeditions" while one runs, else nil.
local heading_to_mission = false -- True from the mission board's "mission_ready" until the trip into a mission ends.
local event_kind = nil -- The music_objective value of the event playing now, kept through its hold, or nil.
local mission_outcome = nil -- "victory" or "defeat" from that game state until the next level starts, else nil.
local open_bosses = {} -- Boss unit -> { breed = name, order = n } for every open encounter window.
local boss_open_order = 0 -- Counts up with every newly opened window, so the latest one can be found.

local resolved_context = nil -- Last computed context string, for example "hub".

-- State group name -> true once the hook has seen that group since this module loaded or Context.relearn() ran.
-- The game sets every group again on every tick, so a group not yet seen is caught up on the next tick even when its value has not changed.
local learned_groups = {}
local change_listeners = {}
local state_listeners = {}
local mission_listeners = {}
local listeners_registered = false
local log_detail = function() end -- No-op unless a real logger is passed to Context.init.

-- The holds that keep a context playing for a while after the game's state for it went quiet, in the order they drain.
-- Each is named after the context it keeps, and `remaining` is its seconds left.
-- Its setting always has a value, since DMF writes every setting's default before the mod's script runs.
local HOLDS = {
	{ name = "event", setting_id = "event_hold_seconds", remaining = 0 },
	{ name = "horde", setting_id = "horde_hold_seconds", remaining = 0 },
	{ name = "combat", setting_id = "combat_hold_seconds", remaining = 0 },
}

local hold_named = {}
for _, hold in ipairs(HOLDS) do
	hold_named[hold.name] = hold
end

local active_hold = nil -- "combat", "horde", or "event" while the resolved context comes from that hold, else nil.

local MISSION_OUTCOME_CONTEXTS = { victory = "victory", defeat = "defeat" }

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

-- expeditions_intensity copies music_combat everywhere, so it is only logged on the values it has of its own.
-- The game sets them, in music_combat too, while an Expedition's heat system is active.
local EXPEDITION_ONLY_COMBAT_STATES = {
	no_combat = true,
	low_combat = true,
	med_combat = true,
	high_combat = true,
	safe_room = true,
	extraction = true,
}

-- Game states in which the player is in the hub or a mission, rather than on a loading screen, a briefing or a menu.
local IN_WORLD_GAME_STATES = { mission = true, mission_board = true, mission_ready = true }

-- Game states of a loading screen, and of the briefing before a mission.
local LOADING_GAME_STATES = { loading = true, mission_loading = true, mission_briefing = true }

-- Game states that end a trip into a mission: the mission's intro, its end, a cutscene, and the main menu.
local ARRIVAL_GAME_STATES = {
	mission_intro = true,
	victory = true,
	defeat = true,
	game_score_win = true,
	game_score_lose = true,
	cinematic = true,
	main_menu = true,
	title = true,
}

-- Game states of the mission preparation screen.
local PREPARATION_GAME_STATES = { loadout = true, loadout_ready = true }

-- Mission name of the training area where Meat Grinder runs.
-- Its template has no wwise_state, so music_zone reads "None" there.
local MEAT_GRINDER_MISSION = "tg_shooting_range"

-- The music_zone value the game sets for Mortis Trials.
local MORTIS_TRIALS_ZONE = "horde_mode"

-- ###########################################################################
-- Resolution
-- ###########################################################################

-- True when an open encounter window plays boss music by its breed's setting.
local function opted_in(mod, boss)
	local setting_id = OPT_IN_BOSS_SETTINGS[boss.breed]
	return setting_id ~= nil and mod:get(setting_id) == true
end

local function is_boss_active(mod)
	if music_combat == "boss" then
		return true
	end

	for _, boss in pairs(open_bosses) do
		if opted_in(mod, boss) then
			return true
		end
	end

	return false
end

-- Breed name of the most recently opened encounter window that counts as a boss, or nil when none does.
-- A captain or daemonhost with its setting off plays no boss music, so it does not name the folder during another boss's fight.
local function current_boss_breed(mod)
	local latest = nil

	for _, boss in pairs(open_bosses) do
		local counts = not OPT_IN_BOSS_SETTINGS[boss.breed] or opted_in(mod, boss)
		if counts and (not latest or boss.order > latest.order) then
			latest = boss
		end
	end

	return latest and latest.breed
end

local function is_horde_active()
	return music_combat == "horde_low" or music_combat == "horde_high"
end

-- Starts the named hold at its full length, while its state is still active.
local function start_hold(mod, name)
	local hold = hold_named[name]
	hold.remaining = mod:get(hold.setting_id)
end

-- True while the named hold keeps its context, which is then the hold the overlay shows.
local function holding(name)
	local hold = hold_named[name]
	if hold.remaining <= 0 then
		return false
	end

	log_detail(string.format("[hold] %s quiet, holding %s for %.1fs more", name, name, hold.remaining))
	active_hold = name
	return true
end

-- Operations count as one event from start to end. Last stand shares the group, but is not an event.
local function is_event_active()
	return (music_objective ~= nil and music_objective ~= "None" and music_objective ~= LAST_MAN_STANDING) or mission_is_operation
end

local function is_combat_active()
	return music_combat == "normal" or music_combat == "horde_low" or music_combat == "horde_high"
end

hold_named.event.is_active = is_event_active
hold_named.horde.is_active = is_horde_active
hold_named.combat.is_active = is_combat_active

-- "havoc" during a Havoc run, "expeditions" during an Expedition, else nil.
local function read_mode(template)
	if template and template.game_mode_name == "expedition" then
		return "expeditions"
	end

	local difficulty = Managers.state.difficulty
	if difficulty and difficulty.get_parsed_havoc_data then
		local ok, havoc_data = pcall(difficulty.get_parsed_havoc_data, difficulty)
		if ok and havoc_data then
			return "havoc"
		end
	end

	return nil
end

-- Returns the current mission's name, whether its template is the hub, whether it is an Operation, its game mode, and its template.
-- Returns nil, false, false, nil, nil before a level has loaded.
local function read_mission()
	local game_state = Managers and Managers.state
	local mission_manager = game_state and game_state.mission

	if not mission_manager then
		return nil, false, false, nil
	end

	local ok, name = pcall(mission_manager.mission_name, mission_manager)

	if not ok or not name then
		return nil, false, false, nil
	end

	local template_ok, template = pcall(mission_manager.mission, mission_manager)
	template = template_ok and type(template) == "table" and template or nil

	return name, template ~= nil and template.is_hub == true, template ~= nil and template.mission_type == "operations", read_mode(template), template
end

-- Wwise reports "None" as a string, not as nil.
local function has_no_zone()
	return music_zone == nil or music_zone == "None"
end

-- Some missions never report a zone, so a "mission" game state with no zone still counts as a mission.
local function is_zoneless_mission()
	return has_no_zone() and music_game_state == "mission" and not mission_outcome and mission_name ~= nil and not mission_is_hub
end

local function resolve(mod)
	active_hold = nil

	-- Cutscenes get no custom music, whatever zone or outcome is still set.
	if music_game_state == "cinematic" then
		return nil
	end

	-- Victory and defeat are checked before the boss signals, since a wipe can leave a boss encounter open.
	if mission_outcome then
		return MISSION_OUTCOME_CONTEXTS[mission_outcome]
	end

	-- A loading screen clears the outcome, so the loading screen after a mission's end gets here too.
	if LOADING_GAME_STATES[music_game_state] then
		return (heading_to_mission or music_game_state == "mission_briefing") and "mission_briefing" or "loading"
	end

	if PREPARATION_GAME_STATES[music_game_state] then
		return "mission_preparation"
	end

	if not IN_WORLD_GAME_STATES[music_game_state] then
		return nil
	end

	-- An unknown stored value plays as "custom", the same as in MusicReplacer.lua's source_of.
	local meat_grinder_source = mission_name == MEAT_GRINDER_MISSION and mod:get("source_meat_grinder")
	if meat_grinder_source == "game" or meat_grinder_source == "silence" then
		return "meat_grinder"
	end

	-- Not in the hub or a mission, for example the main menu, a loading screen or a mission end.
	-- This comes before the boss signals, since `music_combat` can stay at "boss" after a level ends.
	if has_no_zone() and not is_zoneless_mission() then
		return nil
	end

	if music_zone == "hub" then
		return "hub"
	end

	if music_objective == LAST_MAN_STANDING then
		return "last_stand"
	end

	if music_zone == MORTIS_TRIALS_ZONE then
		local in_wave = music_objective ~= nil and music_objective ~= "None"
		return in_wave and "mortis_trials_wave" or "mortis_trials_break"
	end

	-- Operations script their music across the whole mission, in stages with short gaps between them, so each is one long event.
	if is_event_active() then
		start_hold(mod, "event")
		return "event"
	end

	if holding("event") then
		return "event"
	end

	if is_boss_active(mod) then
		return "boss"
	end

	if has_no_zone() and resolved_context == nil then
		log_detail(string.format("[zoneless] music_zone=%s with music_game_state=%s, treating as a mission", tostring(music_zone), tostring(music_game_state)))
	end

	if is_horde_active() then
		start_hold(mod, "horde")
		hold_named.combat.remaining = 0
		return "horde"
	end

	if holding("horde") then
		return "horde"
	end

	if is_combat_active() then
		start_hold(mod, "combat")
		return "combat"
	end

	if holding("combat") then
		return "combat"
	end

	return "explore"
end

local function recompute(mod)
	local new_context = resolve(mod)

	-- An event's kind lasts until the event and its hold are over, so a cutscene in the middle of it keeps it for its return.
	-- The game does not set music_objective again after such an interruption, so the kind would not come back on its own.
	if not is_event_active() and hold_named.event.remaining == 0 then
		event_kind = nil
	end

	if new_context == resolved_context then
		return
	end

	local old_context = resolved_context
	resolved_context = new_context

	for _, listener in ipairs(change_listeners) do
		local ok, err = pcall(listener, resolved_context, old_context, current_boss_breed(mod))
		if not ok then
			mod:error("Music Replacer could not switch the music for a change in the game: %s", tostring(err))
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
	return resolved_context
end

-- The hold that keeps the current context, "combat", "horde", or "event", and its seconds left, or nil.
function Context.hold()
	if not active_hold then
		return nil
	end
	return active_hold, hold_named[active_hold].remaining
end

-- The override folder names `context_name` may use right now, most specific first.
-- They are the event's or the boss's kind, then the mission's code, then the game mode.
-- MusicReplacer.lua plays the first one that has songs.
function Context.override_keys(mod, context_name)
	local keys = {}

	if context_name == "event" and event_kind then
		keys[#keys + 1] = event_kind
	elseif context_name == "boss" then
		keys[#keys + 1] = current_boss_breed(mod)
	end

	if mission_name and not mission_is_hub then
		keys[#keys + 1] = mission_name
	end

	keys[#keys + 1] = mission_mode

	return keys
end

-- True while the game shows a menu, such as the Esc menu, the inventory, the mission board, or a vendor.
function Context.menu_open()
	return menu_state ~= nil and menu_state ~= "None"
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

-- Register a function to call with the mission's name and template whenever the mission changes, before the context follows it.
-- Both are nil while no level is loaded.
function Context.on_mission_change(listener)
	mission_listeners[#mission_listeners + 1] = listener
end

-- Register a function to call on every real transition of a music state group, after context.lua has tracked it.
-- The listener receives (group_name, new_state) for music_combat, music_zone, music_game_state and music_objective only.
function Context.on_state_change(listener)
	state_listeners[#state_listeners + 1] = listener
end

-- Tracks a real transition of a state group, after the game has set it.
local function track_transition(mod, group_name, current, new_state)
	learned_groups[group_name] = true

	if group_name == "music_combat" then
		music_combat = new_state
		log_detail(describe_transition(group_name, current, new_state))
	elseif group_name == "music_zone" then
		log_detail(describe_transition(group_name, music_zone, new_state))

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
			music_combat = nil
			open_bosses = {}
			-- A new zone starts fresh, not partway through the last hold.
			for _, hold in ipairs(HOLDS) do
				hold.remaining = 0
			end
		end
	elseif group_name == "music_game_state" then
		log_detail(describe_transition(group_name, current, new_state))
		music_game_state = new_state

		-- A loading screen that ends in "mission" has reached its level, such as when joining a mission in progress.
		-- Catching up inside a level ends the trip too, since its arrival may have passed while the mod was off.
		-- The mission board comes before every "mission_ready", so a ready that was taken back does not linger.
		local arrived = new_state == "mission" and (current == "loading" or current == "mission")
		if new_state == "mission_ready" or new_state == "loadout" or new_state == "mission_briefing" then
			heading_to_mission = true
		elseif new_state == "mission_board" or ARRIVAL_GAME_STATES[new_state] or arrived then
			heading_to_mission = false
		end

		-- The state returns to "mission" between victory or defeat and the next loading screen.
		-- So within this group, only a loading screen or a mission intro clears the outcome.
		if new_state == "victory" or new_state == "game_score_win" then
			mission_outcome = "victory"
		elseif new_state == "defeat" or new_state == "game_score_lose" then
			mission_outcome = "defeat"
		elseif new_state == "loading" or new_state == "mission_intro" then
			mission_outcome = nil
		end

		-- A zoneless mission can follow another level with no zone change, which would otherwise keep a stale window open.
		if new_state == "loading" then
			open_bosses = {}
		end
	elseif group_name == "music_objective" then
		log_detail(describe_transition(group_name, current, new_state))
		music_objective = new_state
		if new_state ~= "None" and new_state ~= LAST_MAN_STANDING then
			event_kind = new_state
		end
	elseif group_name == "options" then
		log_detail(describe_transition(group_name, current, new_state))
		menu_state = new_state
		return
	else
		local expedition_only = group_name == "expeditions_intensity"
			and (EXPEDITION_ONLY_COMBAT_STATES[new_state] or EXPEDITION_ONLY_COMBAT_STATES[current])
		if LOGGED_ONLY_STATE_GROUPS[group_name] or expedition_only then
			log_detail(describe_transition(group_name, current, new_state))
		end

		return
	end

	for _, listener in ipairs(state_listeners) do
		local ok, err = pcall(listener, group_name, new_state)
		if not ok then
			mod:error("Music Replacer could not follow a change of the game's music state: %s", tostring(err))
		end
	end

	recompute(mod)
end

-- Hands the game's own return values back through the hook, so the hook stays invisible to the game.
local function after_set_state(mod, group_name, current, new_state, is_transition, ...)
	if is_transition then
		track_transition(mod, group_name, current, new_state)
	end

	return ...
end

-- Call once from the main mod file's top level.
-- `log`, if given, receives a line for every raw state transition and boss event.
-- That is much more output than Context.on_change, so it is meant for diagnosing state issues.
function Context.init(mod, detail_logger)
	log_detail = detail_logger or log_detail

	-- The game's combat group decides only once per launch whether it runs an Expedition, on the first mission it sees.
	-- Without this, every mission after an Expedition reports Expedition states to the mod, with no horde or boss, until the game restarts.
	-- Clearing that decision as each mission ends makes the next mission decide again.
	mod:hook_safe(WwiseStateGroupCombat, "on_gameplay_shutdown", function(self)
		self._is_expedition_init = nil
	end)

	mod:hook(WwiseGameSyncManager, "_set_state", function(func, self, group_name, new_state)
		local current = self._wwise_state_group_states and self._wwise_state_group_states[group_name]
		local is_transition = current ~= new_state or not learned_groups[group_name]

		return after_set_state(mod, group_name, current, new_state, is_transition, func(self, group_name, new_state))
	end)

	-- Managers.event:register needs the callback as a string method name, looked up on the registered object.
	-- Passing a function registers without error, then crashes the game when the event fires.
	-- A repeated start for an open unit keeps its window as it is, and is not logged.
	-- Meat Grinder's boss dummies repeat their start over and over.
	function mod:on_boss_start(unit, boss_extension)
		if unit and open_bosses[unit] then
			return
		end

		local breed = boss_extension and boss_extension._breed
		local breed_name = breed and breed.name or "<unknown>"
		log_detail(string.format("[raw] boss_encounter_start breed=%s", breed_name))

		if unit then
			boss_open_order = boss_open_order + 1
			open_bosses[unit] = { breed = breed_name, order = boss_open_order }
		end

		recompute(mod)
	end

	function mod:on_boss_end(unit)
		log_detail("[raw] boss_encounter_end")

		if unit then
			open_bosses[unit] = nil
		end

		recompute(mod)
	end
end

-- Call from the main mod file's mod.update.
-- Managers.event does not exist at mod-load time, so the boss callbacks are registered on the first tick where it does.
function Context.update(mod, dt)
	local current_mission_name, current_mission_is_hub, current_mission_is_operation, current_mode, template = read_mission()

	if current_mode ~= mission_mode then
		log_detail(string.format("[mission] game mode: %s", tostring(current_mode or "ordinary")))
		mission_mode = current_mode
	end

	if current_mission_name ~= mission_name then
		for _, listener in ipairs(mission_listeners) do
			local ok, err = pcall(listener, current_mission_name, template)
			if not ok then
				mod:error("Music Replacer could not follow a change of mission: %s", tostring(err))
			end
		end
	end

	if current_mission_name ~= mission_name or current_mission_is_hub ~= mission_is_hub
		or current_mission_is_operation ~= mission_is_operation then
		mission_name = current_mission_name
		mission_is_hub = current_mission_is_hub
		mission_is_operation = current_mission_is_operation
		recompute(mod)
	end

	-- A hold only counts down once its state is inactive.
	-- resolve() sets it to its full length whenever it runs while the state is active, so it must not also drain then.
	-- Each hold is capped by its setting on every tick, so a lowered setting also shortens a hold that is already running.
	for _, hold in ipairs(HOLDS) do
		if hold.remaining > 0 and not hold.is_active() then
			hold.remaining = math.max(math.min(hold.remaining, mod:get(hold.setting_id)) - dt, 0)

			if hold.remaining == 0 then
				recompute(mod)
			end
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
