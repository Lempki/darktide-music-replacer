local InputUtils = require("scripts/managers/input/input_utils")

-- Key values in the tooltips, in the color the game itself uses for highlighted terms.
local function highlight(text)
	return InputUtils.apply_color_to_input_text(text, Color.terminal_text_warning_light(255, true))
end

-- Each tooltip says what its setting does, then gives the notes that matter in a second paragraph.
-- The README keeps the full explanations.

-- Every context's dropdown offers the same choices, so their tooltips share the explanation.
local function source_tooltip(when)
	return "What plays " .. when .. ".\n\n" ..
		highlight("Custom") .. " plays your songs from its folder, or the game's music while the folder is empty. " ..
		highlight("Custom (Play to End)") .. " also lets a song finish after the music moves to something less important, " ..
		"such as from a boss back to exploring. " ..
		highlight("Game's Own") .. " always plays the game's music, and " .. highlight("Silence") .. " plays nothing."
end

local strings = {
	songs = {
		en = "Songs",
	},
	rescan_audio = {
		en = "Rescan Audio Folders",
	},
	rescan_audio_button = {
		en = "Rescan",
	},
	rescan_audio_tooltip = {
		en = "Lists the audio folders again at once.\n\n" ..
			"The mod notices added, removed, and replaced files by itself a few seconds after they change. " ..
			"This button is for drives where Windows cannot report changes, such as some network drives.",
	},
	resume_songs = {
		en = "Resume Songs",
	},
	resume_songs_tooltip = {
		en = "Explore, combat, and Mortis Trials songs continue where they stopped when their music comes back.\n\n" ..
			"Horde, boss, and event songs continue too after an interruption, while that horde, fight, or event lasts. " ..
			"Every mission and hub visit starts with fresh songs.",
	},

	music_per_context = {
		en = "Music per Context",
	},
	source_custom = {
		en = "Custom",
	},
	source_custom_play_to_end = {
		en = "Custom (Play to End)",
	},
	source_game = {
		en = "Game's Own",
	},
	source_silence = {
		en = "Silence",
	},
	source_meat_grinder = {
		en = "Meat Grinder",
	},
	source_meat_grinder_tooltip = {
		en = "What plays in the Meat Grinder training area.\n\n" ..
			highlight("Custom") .. " plays your explore and combat songs, which is a quick way to test them. " ..
			highlight("Game's Own") .. " plays the game's combat music, and " .. highlight("Silence") .. " keeps the area quiet.",
	},

	volume = {
		en = "Volume",
	},
	-- DMF formats every string, so this shows as a single percent sign.
	percent_unit = {
		en = "%%",
	},
	custom_music_volume = {
		en = "Custom Music Volume",
	},
	custom_music_volume_tooltip = {
		en = "How loud your songs play, on top of the game's master and music volume.\n\n" ..
			"At " .. highlight("100%%") .. " they play as loud as the files themselves. The game's own music is not affected.",
	},
	menu_volume = {
		en = "Menu Volume",
	},
	menu_volume_tooltip = {
		en = "How loud your songs play while a menu is open, such as the Esc menu, the inventory, the mission board, or a vendor.\n\n" ..
			"It is a share of the Custom Music Volume. " .. highlight("100%%") .. " keeps the music at full volume in menus.",
	},

	where_music_plays = {
		en = "Boss Music",
	},
	captain_boss_music = {
		en = "Boss Music for Captains",
	},
	captain_boss_music_tooltip = {
		en = "Plays your boss music while a captain, including the Karnak Twins, is in the fight.\n\n" ..
			highlight("Off") .. " leaves captains to the game's own music.",
	},
	daemonhost_boss_music = {
		en = "Boss Music for Daemonhosts",
	},
	daemonhost_boss_music_tooltip = {
		en = "Plays your boss music while an angered daemonhost is alive.\n\n" ..
			highlight("Off") .. " follows the game, which plays no music for daemonhosts.",
	},

	timing = {
		en = "Timing",
	},
	seconds_unit = {
		en = "s",
	},
	combat_hold_seconds = {
		en = "Combat Music Hold",
	},
	combat_hold_seconds_tooltip = {
		en = "How long combat music keeps playing after a fight quiets down, so a short lull does not switch to explore music.\n\n" ..
			"Set to " .. highlight("0") .. " to switch at once.",
	},
	horde_hold_seconds = {
		en = "Horde Music Hold",
	},
	horde_hold_seconds_tooltip = {
		en = "How long horde music keeps playing after the game stops reporting a horde. " ..
			"The game drops that signal for a moment whenever few enemies are on you.\n\n" ..
			"Set to " .. highlight("0") .. " to follow the game exactly.",
	},
	event_hold_seconds = {
		en = "Event Music Hold",
	},
	event_hold_seconds_tooltip = {
		en = "How long event music keeps playing after the game ends an event's music. " ..
			"Some events pause their music for a few seconds between stages.\n\n" ..
			"Set to " .. highlight("0") .. " to follow the game exactly.",
	},

	debug = {
		en = "Debug",
	},
	diagnostic_mode = {
		en = "Detailed Logging",
	},
	diagnostic_mode_tooltip = {
		en = "Adds the game's raw music states, the silencing of its music, and its sound events to " .. highlight("diagnostic.log") .. ".\n\n" ..
			"The important events are always logged, which is enough for most bug reports. " ..
			"The detailed lines add up quickly, so turn this on only while tracking down a problem.",
	},
}

-- Each context's dropdown: its title, and when it plays.
local CONTEXTS = {
	{ "hub", "Hub", "in the Mourningstar" },
	{ "mission_explore", "Explore", "in a mission while nothing threatens you" },
	{ "mission_combat", "Combat", "while enemies attack you outside a horde or a boss fight" },
	{ "mission_horde", "Horde", "during a horde" },
	{ "mission_boss", "Boss", "while a monstrosity is near you" },
	{ "mission_event", "Event", "while a mission event plays its music, and through a whole Operation" },
	{ "mission_last_stand", "Last Stand", "while only one player of the team is alive" },
	{ "mission_victory", "Victory", "after a mission is won" },
	{ "mission_defeat", "Defeat", "after a mission is lost" },
	{ "mortis_trials_wave", "Mortis Trials Wave", "during a Mortis Trials wave" },
	{ "mortis_trials_break", "Mortis Trials Break", "between Mortis Trials waves" },
}

for _, context in ipairs(CONTEXTS) do
	strings["source_" .. context[1]] = { en = context[2] }
	strings["source_" .. context[1] .. "_tooltip"] = { en = source_tooltip(context[3]) }
end

return strings
