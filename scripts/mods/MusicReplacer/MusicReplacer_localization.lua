local InputUtils = require("scripts/managers/input/input_utils")
local Contexts = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/contexts")

-- Key values in the tooltips, in the color the game itself uses for highlighted terms.
local function highlight(text)
	return InputUtils.apply_color_to_input_text(text, Color.terminal_text_warning_light(255, true))
end

-- Each tooltip says what its setting does, then gives the notes that matter in a second paragraph.
-- The README keeps the full explanations.

-- Every context's dropdown ends with what an empty folder plays, since that is the question players ask most.
local EMPTY_FOLDER_NOTE = "\n\nAn empty folder plays the game's own music, except with " .. highlight("Silence") .. "."

-- Every context's dropdown offers the same choices, so their tooltips share the explanation.
local function source_tooltip(when)
	return "What plays " .. when .. ".\n\n" ..
		highlight("Custom") .. " plays your songs from its folder. " ..
		highlight("Game's Own") .. " always plays the game's music, and " .. highlight("Silence") .. " plays nothing." ..
		EMPTY_FOLDER_NOTE
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
	source_game = {
		en = "Game's Own",
	},
	source_silence = {
		en = "Silence",
	},
	source_loading = {
		en = "Loading",
	},
	source_loading_tooltip = {
		en = "What plays on loading screens that lead anywhere but into a mission: after starting the game, after a mission, and on the way to Meat Grinder.\n\n" ..
			highlight("Custom") .. " plays your songs from its folder. " ..
			highlight("Game's Own") .. " always plays the game's music, and " .. highlight("Silence") .. " plays nothing." ..
			EMPTY_FOLDER_NOTE,
	},
	source_mission_briefing = {
		en = "Mission Loading",
	},
	source_mission_briefing_tooltip = {
		en = "What plays on the loading screens and the briefing on the way into a mission, also when joining a mission in progress.\n\n" ..
			highlight("Custom") .. " plays your songs from its folder. " ..
			highlight("Game's Own") .. " always plays the game's music, and " .. highlight("Silence") .. " plays nothing. " ..
			"The intro itself keeps the game's music, and a song interrupted by the preparation screen continues in the briefing." ..
			EMPTY_FOLDER_NOTE,
	},
	source_mission_preparation = {
		en = "Preparation",
	},
	source_mission_preparation_tooltip = {
		en = "What plays on the mission preparation screen, where the party stands together before a mission and can still change loadouts.\n\n" ..
			highlight("Custom") .. " plays your songs from its folder. " ..
			highlight("Game's Own") .. " always plays the game's music, and " .. highlight("Silence") .. " plays nothing." ..
			EMPTY_FOLDER_NOTE,
	},
	source_meat_grinder = {
		en = "Meat Grinder",
	},
	source_meat_grinder_tooltip = {
		en = "What plays in the Meat Grinder training area.\n\n" ..
			highlight("Custom") .. " plays your explore and combat songs, which is a quick way to test them. " ..
			highlight("Game's Own") .. " plays the game's combat music, and " .. highlight("Silence") .. " keeps the area quiet.\n\n" ..
			"With " .. highlight("Custom") .. ", empty explore and combat folders play the game's own music.",
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
	normalize_loudness = {
		en = "Even Out Loudness",
	},
	normalize_loudness_tooltip = {
		en = "Plays every song at about the same loudness, without changing your files.\n\n" ..
			"Each song is measured once in the background and remembered. " ..
			"A song not measured yet plays at its own level, and a quiet song is only raised as far as it can go without distorting.",
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
	debug_overlay = {
		en = "Debug Overlay",
	},
	debug_overlay_tooltip = {
		en = "Shows the current context, the song playing, and its volume in a corner of the screen, on every screen, loading screens included.\n\n" ..
			"Meant for checking what the mod does, such as which context a moment counts as.",
	},
	debug_overlay_corner = {
		en = "Overlay Corner",
	},
	debug_overlay_corner_tooltip = {
		en = "Where the debug overlay sits.\n\n" ..
			highlight("Top Left") .. " stays clear of the mission objectives, which sit at the top right.",
	},
	debug_overlay_scale = {
		en = "Overlay Size",
	},
	debug_overlay_scale_tooltip = {
		en = "How big the debug overlay is. It grows and shrinks away from its corner.\n\n" ..
			highlight("100%%") .. " is its normal size.",
	},
	debug_overlay_top_left = {
		en = "Top Left",
	},
	debug_overlay_top_right = {
		en = "Top Right",
	},
	diagnostic_mode_tooltip = {
		en = "Adds the game's raw music states, the silencing of its music, and its sound events to " .. highlight("diagnostic.log") .. ".\n\n" ..
			"The important events are always logged, which is enough for most bug reports. " ..
			"The detailed lines add up quickly, so turn this on only while tracking down a problem.",
	},
}

-- Each context's dropdown title, and when it plays, for the contexts that share the common tooltip.
-- The loading screens and Meat Grinder have tooltips of their own above.
local CONTEXT_TEXT = {
	title_screen = { "Title Screen", "on the title screen, before character select" },
	character_select = { "Character Select", "on the character select screen, also while creating a character" },
	hub = { "Hub", "in the Mourningstar" },
	explore = { "Explore", "in a mission while nothing threatens you" },
	combat = { "Combat", "while enemies attack you outside a horde or a boss fight" },
	horde = { "Horde", "during a horde" },
	boss = { "Boss", "while a monstrosity is near you" },
	event = { "Event", "while a mission event plays its music, and through a whole Operation" },
	last_stand = { "Last Stand", "while only one player of the team is alive" },
	victory = { "Victory", "after a mission is won" },
	defeat = { "Defeat", "after a mission is lost" },
	mortis_trials_wave = { "Mortis Trials Wave", "during a Mortis Trials wave" },
	mortis_trials_break = { "Mortis Trials Break", "between Mortis Trials waves" },
}

for _, context in ipairs(Contexts.list) do
	local text = CONTEXT_TEXT[context.id]
	if text then
		strings["source_" .. context.id] = { en = text[1] }
		strings["source_" .. context.id .. "_tooltip"] = { en = source_tooltip(text[2]) }
	end
end

return strings
