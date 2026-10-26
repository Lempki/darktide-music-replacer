-- Tracks the game state that decides which music should play, and resolves it into one `resolved_context` string.
-- Knows nothing about audio files or playback.
-- See library.lua for file lookup and MusicReplacer.lua for the wiring.
--
-- Resolution rules that are not obvious from the code:
--	* The hub is told apart from a mission by `music_zone`, since `music_game_state` is "mission" for both.
--	  The hub zone wins over every mission state, since quitting mid-event or mid-last-stand can leave `music_objective` set.
--	* A boss is active while Wwise reports `music_combat == "boss"`, which is when the game plays its own boss music.
--	  Bosses that only open an encounter window get no boss music in the game, so they get none here either.
--	  Those are captains, daemonhosts, and Rodin Karnak in Spillway, which the game's boss music check leaves out by their breed tags.
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
--	* The game drops "boss" for a second or two now and then while the boss is still alive.
--	  So `boss` holds for `boss_hold_seconds` after it quiets, but only until the last boss window that counts has closed.
--	  A boss's death sends its end event, so boss music never outlasts the boss.
--	* "horde_low" and "horde_high" resolve "horde", below bosses. The game plays its own horde music for both.
--	  The game reports a horde only while at least 5 enemies are aggroed, so it drops out for a second or two mid-horde.
--	  So `horde` holds for `horde_hold_seconds`, whose default is shorter than the combat hold's, since a horde ends for good.
--	  Once that hold runs out, the plain combat state decides, with no combat hold added on top.
--	* A `music_combat` value outside KNOWN_COMBAT_STATES is one the mod does not know, so its meaning is unknown.
--	  Below the last stand, Mortis Trials, the Expedition extraction, and events, it resolves no context.
--	  So the game's music plays instead of an explore song silencing it.
--	  Each such value is logged once, so a bug report names it.
--	* No context resolves during a cutscene, so custom music stays off there.
--	  Story cutscenes set `music_game_state` to "cinematic", and the hub's own, such as Path of Trust, to "cinematic_pot".
--	* The hub and mission contexts only resolve while the game state is in the world: "mission", "mission_board" or "mission_ready".
--	  Loading screens and the briefing resolve "loading" or "mission_briefing" instead, even once the zone has arrived.
--	  The game sends the hub zone about 10 seconds before the loading screen ends, and a mission zone partway through the briefing.
--	  The briefing, and every loading screen after the mission board's "mission_ready", lead into a mission and resolve "mission_briefing".
--	  A plain loading screen does not say where it leads, so "mission_ready" tells joining a mission apart from leaving one.
--	  The mission preparation screen, where the party stands together before a mission, resolves "mission_preparation".
--	  The game reports it as "loadout" in every game mode.
--	  The mission's intro resolves no context and keeps the game's stinger.
--	* The title screen, "title", resolves "title_screen", and character select, "main_menu", resolves "character_select".
--	  Character creation, "character_creation", is a step inside character select and resolves "character_select" too.
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
--	  The mission is its code, and the game mode is "havoc", "expeditions", or "mortis_trials".
--	  The level names its mission only seconds before the briefing ends.
--	  So on the way into a mission, both come from the game's mechanism data.
--	  Havoc is told apart by its Havoc data in the difficulty manager, since it changes no music state.
--	  So Havoc is only known once the mission has loaded.
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
local mission_mode = nil -- "havoc", "expeditions", or "mortis_trials" while one runs, else nil.
local upcoming_mission = nil -- The mission a trip into a mission leads to, before its level names it, else nil.
local upcoming_mode = nil -- That mission's game mode, else nil.
local heading_to_mission = false -- True from the mission board's "mission_ready" until the trip into a mission ends.
local event_kind = nil -- The music_objective value of the event playing now, kept through its hold, or nil.
local mission_outcome = nil -- "victory" or "defeat" from that game state until the next level starts, else nil.
local open_bosses = {} -- Boss unit -> { breed = name, order = n } for every open encounter window.
local boss_open_order = 0 -- Counts up with every newly opened window, so the latest one can be found.

local resolved_context = nil -- Last computed context string, for example "hub".

-- State group name -> true once the hook has seen that group since this module loaded or Context.relearn() ran.
-- The game calls _set_state for every group on every tick, even when its value is unchanged.
-- So a group not yet seen is caught up on the next tick.
local learned_groups = {}
local change_listeners = {}
local state_listeners = {}
local mission_listeners = {}
local listeners_registered = false
local log_detail = function() end -- It does nothing unless Context.init is given a real logger.
local log = function() end -- The same for the important lines, which are always logged.

-- The holds that keep a context playing for a while after the game's state for it went quiet, in the order resolve() checks them.
-- Each is named after the context it keeps, and `remaining` is its seconds left.
-- Its setting always has a value, since DMF writes every setting's default before the mod's script runs.
local HOLDS = {
	{ name = "event", setting_id = "event_hold_seconds", remaining = 0 },
	{ name = "boss", setting_id = "boss_hold_seconds", remaining = 0 },
	{ name = "horde", setting_id = "horde_hold_seconds", remaining = 0 },
	{ name = "combat", setting_id = "combat_hold_seconds", remaining = 0 },
	-- An Expedition's fights flip on and off as often as ordinary ones, so they share the combat hold's setting.
	{ name = "expedition_combat", setting_id = "combat_hold_seconds", remaining = 0 },
}

local hold_named = {}
for _, hold in ipairs(HOLDS) do
	hold_named[hold.name] = hold
end

local active_hold = nil -- The name of the hold the resolved context comes from, else nil.

-- True once the last open boss window that counts has closed, so the boss hold ends with the boss.
-- A new window that counts, or a boss fight that starts over, clears it.
local boss_fight_over = false

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

-- Music-related state groups that decide no context, logged only so their transitions show up with Detailed Logging on.
local LOGGED_ONLY_STATE_GROUPS = {
	music_objective_progression = true,
	event_intensity = true,
	event_category = true,
	circumstance = true,
}

-- expeditions_intensity copies music_combat everywhere, so it is only logged on the values it has of its own.
-- Every Expedition sets them, in music_combat too, in place of the standard combat states.
local EXPEDITION_ONLY_COMBAT_STATES = {
	no_combat = true,
	low_combat = true,
	med_combat = true,
	high_combat = true,
	safe_room = true,
	extraction = true,
}

-- An Expedition's fight levels, which resolve "expedition_combat".
-- The level follows how alert the enemy is, not how hard the fight is.
local EXPEDITION_FIGHT_STATES = { low_combat = true, med_combat = true, high_combat = true }

-- Every music_combat value the game's wwise_game_sync_settings.lua lists, the standard ones and an Expedition's.
local KNOWN_COMBAT_STATES = { None = true, normal = true, horde_low = true, horde_high = true, boss = true }
for state in pairs(EXPEDITION_ONLY_COMBAT_STATES) do
	KNOWN_COMBAT_STATES[state] = true
end

-- Unknown music_combat values already logged, so each is logged once.
local reported_unknown_states = {}

-- Game states in which the player is in the hub or a mission, rather than on a loading screen, a briefing or a menu.
local IN_WORLD_GAME_STATES = { mission = true, mission_board = true, mission_ready = true }

-- Game states of a loading screen, and of the briefing before a mission.
local LOADING_GAME_STATES = { loading = true, mission_loading = true, mission_briefing = true }

-- Game states of a cutscene, which each cutscene names in its template.
-- Story cutscenes use "cinematic", and the hub's own, such as Path of Trust and the hub location intros, use "cinematic_pot".
local CUTSCENE_GAME_STATES = { cinematic = true, cinematic_pot = true }

-- Game states that end a trip into a mission: the mission's intro, its end, a cutscene, the title screen, and character select.
local ARRIVAL_GAME_STATES = {
	mission_intro = true,
	victory = true,
	defeat = true,
	game_score_win = true,
	game_score_lose = true,
	main_menu = true,
	title = true,
}
for state in pairs(CUTSCENE_GAME_STATES) do
	ARRIVAL_GAME_STATES[state] = true
end

-- Game states of the mission preparation screen.
local PREPARATION_GAME_STATES = { loadout = true, loadout_ready = true }

-- Game states of the menus before the hub, by the context each resolves.
-- Character creation is a step inside character select, so it keeps character select's music.
local MENU_CONTEXTS = { title = "title_screen", main_menu = "character_select", character_creation = "character_select" }

-- The mission name of the training area where Meat Grinder runs.
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

-- A captain or daemonhost with its setting off plays no boss music, so its window does not count.
local function counts_as_boss(mod, boss)
	return not OPT_IN_BOSS_SETTINGS[boss.breed] or opted_in(mod, boss)
end

local function is_boss_active(mod)
	if music_combat == "boss" then
		return true
	end

	-- Other bosses count through music_combat alone, as the game's boss music does, so only an opted-in window adds one.
	for _, boss in pairs(open_bosses) do
		if opted_in(mod, boss) then
			return true
		end
	end

	return false
end

-- Breed name of the most recently opened encounter window that counts as a boss, or nil when none does.
-- So a captain or daemonhost with its setting off does not name the folder during another boss's fight.
local function current_boss_breed(mod)
	local latest = nil

	for _, boss in pairs(open_bosses) do
		if counts_as_boss(mod, boss) and (not latest or boss.order > latest.order) then
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
	hold.length = hold.remaining
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

local function is_expedition_fight_active()
	return EXPEDITION_FIGHT_STATES[music_combat] == true
end

hold_named.event.is_active = is_event_active
hold_named.boss.is_active = is_boss_active
hold_named.horde.is_active = is_horde_active
hold_named.combat.is_active = is_combat_active
hold_named.expedition_combat.is_active = is_expedition_fight_active

-- The game mode a mission template names: "expeditions" or "mortis_trials", else nil.
local function template_mode(template)
	if not template then
		return nil
	elseif template.game_mode_name == "expedition" then
		return "expeditions"
	elseif template.game_mode_name == "survival" then
		return "mortis_trials"
	end

	return nil
end

-- The template's game mode, or "havoc" during a Havoc run, else nil.
local function read_mode(template)
	local mode = template_mode(template)
	if mode then
		return mode
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

-- The mission a trip into a mission leads to, and its template, from the game's mechanism data, else nil.
-- The client gets it from the mission server before the level loads, since the game loads the level by it.
-- In the hub, the data names the hub, which leads nowhere.
local function read_upcoming_mission()
	local mechanism = Managers and Managers.mechanism
	if not mechanism or not mechanism.mechanism_data then
		return nil, nil
	end

	local ok, data = pcall(mechanism.mechanism_data, mechanism)
	local name = ok and type(data) == "table" and data.mission_name or nil
	if not name then
		return nil, nil
	end

	-- Loaded here, under pcall, so a change in the game's files costs only the early names, never the mod's start.
	local templates_ok, templates = pcall(require, "scripts/settings/mission/mission_templates")
	local template = templates_ok and type(templates) == "table" and templates[name] or nil

	if type(template) ~= "table" or template.is_hub then
		return nil, nil
	end

	return name, template
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
	if CUTSCENE_GAME_STATES[music_game_state] then
		return nil
	end

	-- The menus come before the outcome, since a mission's end always passes a loading screen before them.
	if MENU_CONTEXTS[music_game_state] then
		return MENU_CONTEXTS[music_game_state]
	end

	-- Victory and defeat are checked before the boss signals, since a wipe can leave a boss encounter open.
	if mission_outcome then
		return MISSION_OUTCOME_CONTEXTS[mission_outcome]
	end

	-- A loading screen clears the outcome, so the loading screen after a mission's end gets here too.
	if LOADING_GAME_STATES[music_game_state] then
		-- The first "mission_briefing" is the game's state. The second is the mod's context, which also covers loading screens into a mission.
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

	-- No zone outside a zoneless mission means the player is between levels, as when leaving the hub clears its zone first.
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

	-- An Expedition's extraction is its finale, so it ranks like an event, below a last stand.
	if music_combat == "extraction" then
		return "expedition_extraction"
	end

	-- Operations script their music across the whole mission, in stages with short gaps between them, so each is one long event.
	if is_event_active() then
		start_hold(mod, "event")
		return "event"
	end

	if holding("event") then
		return "event"
	end

	if music_combat ~= nil and not KNOWN_COMBAT_STATES[music_combat] then
		if not reported_unknown_states[music_combat] then
			reported_unknown_states[music_combat] = true
			log(string.format("[context] music_combat has a value the mod does not know, %s, so the game's music plays", music_combat))
		end
		return nil
	end

	if is_boss_active(mod) then
		-- A boss after other music is a new fight, even when no window announced it.
		if resolved_context ~= "boss" then
			boss_fight_over = false
		end

		if not boss_fight_over then
			start_hold(mod, "boss")
		end

		return "boss"
	end

	if holding("boss") then
		-- Combat that goes on under the held boss starts its own hold, which takes over once the boss hold ends.
		if is_combat_active() then
			start_hold(mod, "combat")
		end

		return "boss"
	end

	if has_no_zone() and resolved_context == nil then
		log_detail(string.format("[zoneless] music_zone=%s with music_game_state=%s, treating as a mission", tostring(music_zone), tostring(music_game_state)))
	end

	if is_horde_active() then
		start_hold(mod, "horde")
		-- Once the horde hold runs out, the plain combat state decides, with no combat hold left over from before the horde.
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

	if is_expedition_fight_active() then
		start_hold(mod, "expedition_combat")
		return "expedition_combat"
	end

	if holding("expedition_combat") then
		return "expedition_combat"
	end

	if music_combat == "safe_room" then
		return "expedition_safe_room"
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

-- Why no context resolves now, for the debug overlay: "cutscene", "intro", or "unknown_state", else nil.
function Context.idle_reason()
	if resolved_context then
		return nil
	elseif CUTSCENE_GAME_STATES[music_game_state] then
		return "cutscene"
	elseif music_game_state == "mission_intro" then
		return "intro"
	elseif music_combat ~= nil and not KNOWN_COMBAT_STATES[music_combat] then
		return "unknown_state"
	end
	return nil
end

-- The name of the hold that keeps the current context, such as "combat", its seconds left, and its full length, or nil.
function Context.hold()
	if not active_hold then
		return nil
	end
	local hold = hold_named[active_hold]
	return active_hold, hold.remaining, hold.length or hold.remaining
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
	else
		keys[#keys + 1] = upcoming_mission
	end

	keys[#keys + 1] = mission_mode or upcoming_mode

	return keys
end

-- True while the game shows a menu, such as the Esc menu, the inventory, the mission board, or a vendor.
function Context.menu_open()
	return menu_state ~= nil and menu_state ~= "None"
end

-- Resolves again after a setting change.
-- A boss that a setting just turned off is no gap in its fight, so the boss hold ends at once.
function Context.refresh(mod)
	if not current_boss_breed(mod) then
		hold_named.boss.remaining = 0
	end

	recompute(mod)
end

-- Makes the next value the game sets for every state group count as a change, so this module and its listeners catch up.
-- It is for when the hook may have missed changes, as while the mod is turned off, since DMF disables a mod's hooks then.
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
-- The listener receives (group_name, new_state) for music_combat, music_zone, music_game_state, music_objective, and expeditions_intensity.
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

		-- expeditions_intensity decides no context, but its listeners still need it, since the silencing forces it with music_combat.
		if group_name ~= "expeditions_intensity" then
			return
		end
	end

	for _, listener in ipairs(state_listeners) do
		local ok, err = pcall(listener, group_name, new_state)
		if not ok then
			mod:error("Music Replacer could not follow a change of the game's music state: %s", tostring(err))
		end
	end

	if group_name ~= "expeditions_intensity" then
		recompute(mod)
	end
end

-- Hands the game's own return values back through the hook, so the hook stays invisible to the game.
local function after_set_state(mod, group_name, current, new_state, is_transition, ...)
	if is_transition then
		track_transition(mod, group_name, current, new_state)
	end

	return ...
end

-- Call once from the main mod file's top level.
-- `detail_logger`, if given, receives a line for every raw state transition and boss event.
-- That is much more output than Context.on_change, so it is meant for diagnosing state issues.
-- `logger`, if given, receives the important lines, such as a music_combat value the mod does not know.
function Context.init(mod, detail_logger, logger)
	log_detail = detail_logger or log_detail
	log = logger or log

	-- The game's combat group decides only once per launch whether it runs an Expedition, on the first mission it sees.
	-- Without this, every mission after an Expedition reports Expedition states to the mod, with no horde or boss, until the game restarts.
	-- The same holds the other way: an Expedition after any other mission reports the standard states, and resolves no Expedition context.
	-- Clearing that decision as each mission ends makes the next mission decide again.
	mod:hook_safe(WwiseStateGroupCombat, "on_gameplay_shutdown", function(self)
		self._is_expedition_init = nil
	end)

	mod:hook(WwiseGameSyncManager, "_set_state", function(func, self, group_name, new_state)
		local current = self._wwise_state_group_states and self._wwise_state_group_states[group_name]
		local is_transition = current ~= new_state or not learned_groups[group_name]

		return after_set_state(mod, group_name, current, new_state, is_transition, func(self, group_name, new_state))
	end)

	-- The game sends its boss extension with both events, so both lines can name the breed.
	local function breed_name_of(boss_extension)
		local breed = boss_extension and boss_extension._breed
		return breed and breed.name or "<unknown>"
	end

	-- Managers.event:register needs the callback as a string method name, looked up on the registered object.
	-- Passing a function registers without error, then crashes the game when the event fires.
	-- A repeated start for an open unit keeps its window as it is, and is not logged.
	-- Meat Grinder's boss dummies repeat their start over and over.
	function mod:on_boss_start(unit, boss_extension)
		if unit and open_bosses[unit] then
			return
		end

		local breed_name = breed_name_of(boss_extension)
		log_detail(string.format("[raw] boss_encounter_start breed=%s", breed_name))

		if unit then
			boss_open_order = boss_open_order + 1
			open_bosses[unit] = { breed = breed_name, order = boss_open_order }

			if counts_as_boss(mod, open_bosses[unit]) then
				boss_fight_over = false
			end
		end

		recompute(mod)
	end

	function mod:on_boss_end(unit, boss_extension)
		log_detail(string.format("[raw] boss_encounter_end breed=%s", breed_name_of(boss_extension)))

		local closed = unit and open_bosses[unit]
		if closed then
			open_bosses[unit] = nil

			-- The game sends the end event when the boss dies or despawns, so its music has nothing left to bridge.
			if counts_as_boss(mod, closed) and not current_boss_breed(mod) then
				boss_fight_over = true
				hold_named.boss.remaining = 0
			end
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

	-- The upcoming mission is only read on the way into a mission, before its level names it.
	local next_mission, next_template = nil, nil
	if heading_to_mission and (current_mission_name == nil or current_mission_is_hub) then
		next_mission, next_template = read_upcoming_mission()
	end

	if next_mission ~= upcoming_mission then
		upcoming_mission = next_mission
		upcoming_mode = template_mode(next_template)

		if next_mission then
			log_detail(string.format("[mission] heading to %s, game mode: %s", next_mission, tostring(upcoming_mode or "ordinary")))
		end
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
		if hold.remaining > 0 and not hold.is_active(mod) then
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
