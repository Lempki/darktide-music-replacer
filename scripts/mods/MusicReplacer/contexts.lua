-- Every context the mod can resolve, in the order the mod options list their dropdowns and the audio folders are listed.
-- Each entry says what the other modules need to know about its context, so a new context is one entry here.
-- It also needs its strings in MusicReplacer_localization.lua, and the rule that resolves it in context.lua.
--
-- Fields:
--	* id: the context's name, which is also its audio folder's name and its setting's "source_" suffix.
--	* own_settings: true when its choice lives in a settings group of its own, not in Music per Situation.
--	* silences: the game's state group that plays this context's own music, forced to "None" while a custom song plays.
--	  Combat music and the exploration music events are silenced for every context, so they are not listed.
--	* priority: its rank among the mission contexts, lowest first, matching the order context.lua resolves them in.
--	  A ranked context set to Skip leaves the ranking, so context.lua resolves the one below it instead.
--	* resume: "always" when its song continues whenever it returns, "sequence" when only within one horde, fight, or event.
--	* loading_screen: true for a loading screen's context, which waits longer before it takes over.
--	* mission_overrides: false for a context that belongs to no one mission, so no mission code or game mode names its override folders.
--	  Without it, such a folder would apply only when the game happens to name a mission early or late, which no player could rely on.

local Contexts = {}

Contexts.list = {
	{ id = "title_screen", silences = "music_game_state", mission_overrides = false },
	{ id = "character_select", silences = "music_game_state", mission_overrides = false },
	{ id = "hub", silences = "music_zone", mission_overrides = false },
	{ id = "loading", silences = "music_game_state", loading_screen = true, mission_overrides = false },
	{ id = "mission_preparation", silences = "music_game_state" },
	{ id = "mission_briefing", silences = "music_game_state", loading_screen = true },
	{ id = "explore", priority = 1, resume = "always" },
	{ id = "combat", priority = 2, resume = "always" },
	{ id = "horde", priority = 3, resume = "sequence" },
	{ id = "boss", priority = 4, resume = "sequence" },
	{ id = "event", silences = "music_objective", priority = 5, resume = "sequence" },
	{ id = "last_stand", silences = "music_objective", priority = 6 },
	{ id = "victory", silences = "music_game_state" },
	{ id = "defeat", silences = "music_game_state" },
	-- Mortis Trials' wave and break rank like event and explore, which they replace there.
	{ id = "mortis_trials_wave", silences = "music_objective", priority = 5, resume = "always" },
	{ id = "mortis_trials_break", priority = 1, resume = "always" },
	-- An Expedition rates its fights, safe rooms, and extraction instead of hordes and bosses.
	-- Its fights and safe rooms take turns with explore like combat and explore, and its extraction is a finale like an event.
	{ id = "expedition_combat", priority = 2, resume = "always" },
	{ id = "expedition_safe_room", priority = 1, resume = "always" },
	{ id = "expedition_extraction", priority = 5 },
	-- Meat Grinder is where players try out loadouts and songs, so it has a settings group of its own.
	{ id = "meat_grinder", own_settings = true },
}

local by_id = {}
for _, context in ipairs(Contexts.list) do
	by_id[context.id] = context
end

-- The entry for `id`, or nil for a context the catalog does not know.
function Contexts.get(id)
	return id and by_id[id]
end

-- True when the context can be set to Skip, which lets the context ranked below it play instead.
-- Only a context ranked above the lowest rank can, since nothing ranks below explore, Mortis Trials' break, or an Expedition's safe room.
function Contexts.can_skip(id)
	local context = by_id[id]
	return context ~= nil and context.priority ~= nil and context.priority > 1
end

return Contexts
