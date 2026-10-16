local InputUtils = require("scripts/managers/input/input_utils")

-- Key values in the tooltips, in the color the game itself uses for highlighted terms.
local function highlight(text)
	return InputUtils.apply_color_to_input_text(text, Color.terminal_text_warning_light(255, true))
end

-- Each tooltip says what its setting does, then gives the notes that matter in a second paragraph.
-- The README keeps the full explanations.
return {
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
		en = "Finds the audio files you added or removed since the game started.\n\n" ..
			"A song that is playing keeps playing.",
	},
	resume_songs = {
		en = "Resume Songs",
	},
	resume_songs_tooltip = {
		en = "Explore, combat, and Mortis Trials songs continue where they stopped when their music comes back.\n\n" ..
			"Horde, boss, and event songs continue too after an interruption, while that horde, fight, or event lasts. " ..
			"Every mission and hub visit starts with fresh songs.",
	},

	where_music_plays = {
		en = "Where Music Plays",
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
	meat_grinder_music = {
		en = "Music in Meat Grinder",
	},
	meat_grinder_music_tooltip = {
		en = "Plays your explore and combat music in the Meat Grinder training area, which is a quick way to test your files.\n\n" ..
			highlight("Off") .. " keeps the area quiet, including the game's own combat music.",
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
		en = "Diagnostic Logging",
	},
	diagnostic_mode_tooltip = {
		en = "Writes what the mod sees and decides to " .. highlight("diagnostic.log") .. ", to attach to a bug report.\n\n" ..
			"The file is in %%APPDATA%%\\Fatshark\\Darktide\\MusicReplacer. It writes a lot, so turn it on only while troubleshooting.",
	},
	reset_log_on_launch = {
		en = "Reset Log on Launch",
	},
	reset_log_on_launch_tooltip = {
		en = "Starts " .. highlight("diagnostic.log") .. " afresh every time the game launches.\n\n" ..
			highlight("Off") .. " keeps adding to it, trimmed to its last 2,000 lines.",
	},
}
