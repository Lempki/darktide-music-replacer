-- Every context the mod can resolve, in the order the mod options list their dropdowns and the audio folders are listed.
-- Each entry says what the other modules need to know about its context, so a new context is one entry here.
-- It also needs its strings in MusicReplacer_localization.lua, and the rule that resolves it in context.lua.
--
-- Fields:
--	* id: the context's name, which is also its audio folder's name and its setting's "source_" suffix.
--	* folder: true when it plays songs from an audio folder of its own.
--	* own_settings: true when its choice lives in a settings group of its own, not in Music per Situation.
--	* silences: the game's state group that plays this context's own music, forced to "None" while a custom song plays.
--	  Combat music and the exploration music events are silenced for every context, so they are not listed.
--	* priority: its rank among the mission contexts, lowest first, matching the order context.lua resolves them in.
--	* resume: "always" when its song continues whenever it returns, "sequence" when only within one horde, fight, or event.
--	* loading_screen: true for a loading screen's context, which waits longer before it takes over.

local Contexts = {}

Contexts.list = {
	{ id = "title_screen", folder = true, silences = "music_game_state" },
	{ id = "character_select", folder = true, silences = "music_game_state" },
	{ id = "hub", folder = true, silences = "music_zone" },
	{ id = "loading", folder = true, silences = "music_game_state", loading_screen = true },
	{ id = "mission_preparation", folder = true, silences = "music_game_state" },
	{ id = "mission_briefing", folder = true, silences = "music_game_state", loading_screen = true },
	{ id = "explore", folder = true, priority = 1, resume = "always" },
	{ id = "combat", folder = true, priority = 2, resume = "always" },
	{ id = "horde", folder = true, priority = 3, resume = "sequence" },
	{ id = "boss", folder = true, priority = 4, resume = "sequence" },
	{ id = "event", folder = true, silences = "music_objective", priority = 5, resume = "sequence" },
	{ id = "last_stand", folder = true, silences = "music_objective", priority = 6 },
	{ id = "victory", folder = true, silences = "music_game_state" },
	{ id = "defeat", folder = true, silences = "music_game_state" },
	-- Mortis Trials' wave and break rank like event and explore, which they replace there.
	{ id = "mortis_trials_wave", folder = true, silences = "music_objective", priority = 5, resume = "always" },
	{ id = "mortis_trials_break", folder = true, priority = 1, resume = "always" },
	-- An Expedition rates its fights, safe rooms, and extraction instead of hordes and bosses.
	-- Its fights and safe rooms take turns with explore like combat and explore, and its extraction is a finale like an event.
	{ id = "expedition_combat", folder = true, priority = 2, resume = "always" },
	{ id = "expedition_safe_room", folder = true, priority = 1, resume = "always" },
	{ id = "expedition_extraction", folder = true, priority = 5 },
	-- Meat Grinder is where players try out loadouts and songs, so it has a settings group of its own.
	{ id = "meat_grinder", folder = true, own_settings = true },
}

local by_id = {}
for _, context in ipairs(Contexts.list) do
	by_id[context.id] = context
end

-- The entry for `id`, or nil for a context the catalog does not know.
function Contexts.get(id)
	return id and by_id[id]
end

return Contexts
