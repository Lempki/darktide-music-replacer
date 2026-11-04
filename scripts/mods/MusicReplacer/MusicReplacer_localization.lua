local InputUtils = require("scripts/managers/input/input_utils")

-- Key values in the tooltips, in the color the game itself uses for highlighted terms.
local function highlight(text)
	return InputUtils.apply_color_to_input_text(text, Color.terminal_text_warning_light(255, true))
end

-- Each tooltip says what its setting does, then gives the notes that matter in a second paragraph.
-- docs/settings.md keeps the full explanations.

-- Builds the English tooltip of a situation dropdown, since every one offers the same choices.
-- `note`, if given, is one more sentence about that situation.
-- A translation writes its own full text instead, since the sentence order differs between languages.
local function source_tooltip(when, note)
	return "What plays " .. when .. ".\n\n" ..
		highlight("Custom") .. " plays your songs from its folder. " ..
		highlight("Vanilla") .. " always plays the game's music, and " .. highlight("Silence") .. " plays nothing." ..
		(note and " " .. note or "") ..
		"\n\nWith " .. highlight("Custom") .. ", an empty folder plays the game's music."
end

local strings = {
	your_songs = {
		en = "Your Songs",
	},
	rescan_audio = {
		en = "Rescan Audio Folders",
	},
	rescan_audio_button = {
		en = "Rescan",
	},
	rescan_audio_tooltip = {
		en = "Lists the audio folders again at once, and checks every song again.\n\n" ..
			"The mod notices added, removed, and replaced files by itself a few seconds after they change. " ..
			"This button is for drives where Windows cannot report changes, such as some network drives, " ..
			"for retrying a song that would not play, and for bringing back a situation's folder that went missing.",
	},
	playback = {
		en = "Playback",
	},
	fade_seconds = {
		en = "Fade Length",
	},
	fade_seconds_tooltip = {
		en = "How long the music crossfades when the situation changes, and how long a song fades out at its end. " ..
			"A switch to the game's music or to silence always takes half a second.\n\n" ..
			"Set to " .. highlight("0") .. " to switch at once.",
	},
	resume_songs = {
		en = "Resume Songs",
	},
	resume_songs_tooltip = {
		en = "Explore, combat, Mortis Trials, and Expedition fight and safe room songs continue where they stopped when their music comes back.\n\n" ..
			"Horde, boss, and event songs also continue after an interruption, as long as that horde, fight, or event lasts. " ..
			"Every mission and hub visit starts with fresh songs.",
	},

	playback_controls = {
		en = "Playback Controls",
	},
	next_song_keybind = {
		en = "Next Song",
	},
	next_song_keybind_tooltip = {
		en = "Crossfades to another song from the folder playing now. " ..
			"With one song in the folder, that song keeps playing, and a paused one resumes where it stopped.\n\n" ..
			"The next situation still starts its own pick, and the skipped song does not continue later. " ..
			"DMF runs keybinds even while you type in chat, so a key that is not a letter, such as one on the numpad or an F-key, works best.",
	},
	previous_song_keybind = {
		en = "Previous Song",
	},
	previous_song_keybind_tooltip = {
		en = "Within the first 3 seconds of a song, crossfades back to the song that played before it in this situation. " ..
			"Pressing it again keeps going back.\n\n" ..
			"Later into a song, or with no earlier song, it starts the song playing now over. " ..
			"A new situation starts with no earlier songs.",
	},
	restart_song_keybind = {
		en = "Restart Song",
	},
	restart_song_keybind_tooltip = {
		en = "Jumps back to the start of the song playing now.",
	},
	pause_song_keybind = {
		en = "Pause / Resume",
	},
	pause_song_keybind_tooltip = {
		en = "Pauses the song playing now, and the next press resumes it where it stopped. " ..
			"The game's music stays silent while it is paused.\n\n" ..
			"Next Song, Previous Song, Restart Song, and removing the song with Remove from Rotation also end the pause. " ..
			"A new situation ends it too, and the paused song continues later like any song that was playing.",
	},
	remove_song_keybind = {
		en = "Remove from Rotation",
	},
	remove_song_keybind_tooltip = {
		en = "Press twice to stop the song playing now from ever being picked in its folder again, and move on to another song. " ..
			"The first press asks, and a second press removes the song while the question shows, as Message Duration and Message Fade Out set. " ..
			"The file stays where it is, and a copy in another folder still plays there.\n\n" ..
			"Removed songs are listed in removed.txt, beside the mod's log. " ..
			"Restore Removed Songs puts them all back, and deleting a line from the file, then pressing Rescan, puts one back.",
	},
	restore_removed_songs = {
		en = "Restore Removed Songs",
	},
	restore_removed_songs_button = {
		en = "Restore",
	},
	restore_removed_songs_tooltip = {
		en = "Puts every song that Remove from Rotation took out back into its folder's rotation.",
	},
	key_fade_seconds = {
		en = "Key Fade Length",
	},
	key_fade_seconds_tooltip = {
		en = "How long the music crossfades when one of these keys changes the song, pauses it, or resumes it. " ..
			"Fade Length still sets the fades when the situation changes and when a song ends by itself.\n\n" ..
			"A key that starts the song playing now over always jumps to its start in a tenth of a second, " ..
			"so two copies of the song never play over each other.\n\n" ..
			"Set to " .. highlight("0") .. " to switch at once.",
	},
	on_screen_messages = {
		en = "On-Screen Messages",
	},
	key_press_messages = {
		en = "For Key Presses",
	},
	key_press_messages_tooltip = {
		en = "Shows a short message in a corner of the screen when you press one of the Playback Controls keys, such as the song that plays next. " ..
			"It fades out after a few seconds, and shows on every screen, loading screens included.\n\n" ..
			highlight("Off") .. " shows no message for them. The keys still work.",
	},
	song_change_messages = {
		en = "For Song Changes",
	},
	song_change_messages_tooltip = {
		en = "Shows the song's name in a corner of the screen when one of your songs starts by itself: " ..
			"when a situation starts its music, and when a song ends and the next one plays.\n\n" ..
			"While For Key Presses is off, it also names the song a Playback Controls key starts.",
	},
	message_seconds = {
		en = "Message Duration",
	},
	message_seconds_tooltip = {
		en = "How long a message stays at full opacity before it fades out.\n\n" ..
			"With Message Fade Out, it also sets how long a second press of Remove from Rotation counts, even with For Key Presses off.",
	},
	message_fade_out_seconds = {
		en = "Message Fade Out",
	},
	message_fade_out_seconds_tooltip = {
		en = "How long a message takes to fade out.\n\n" ..
			"Set to " .. highlight("0") .. " to hide it at once.",
	},
	-- %s is the name of the song file.
	song_now_playing = {
		en = "Now playing: %s",
	},
	message_scale = {
		en = "Message Size",
	},
	message_scale_tooltip = {
		en = "How big the on-screen messages are, on top of the game's HUD Scale setting.\n\n" ..
			highlight("100%%") .. " is their normal size at that HUD Scale.",
	},
	message_color = {
		en = "Message Color",
	},
	message_color_tooltip = {
		en = "The color of the on-screen messages. Its alpha sets how opaque they are.",
	},
	pixels_unit = {
		en = "px",
	},
	message_backdrop_opacity = {
		en = "Message Backdrop Opacity",
	},
	message_backdrop_opacity_tooltip = {
		en = "How dark the backdrop behind the on-screen messages is. It fades out toward the middle of the screen, and with the message.\n\n" ..
			highlight("0%%") .. " leaves out the backdrop.",
	},
	message_corner = {
		en = "Message Corner",
	},
	message_corner_tooltip = {
		en = "The corner of the screen the on-screen messages show in. " ..
			"They align to its side, so in a right corner they are right-aligned.",
	},
	corner_bottom_left = {
		en = "Bottom Left",
	},
	corner_bottom_right = {
		en = "Bottom Right",
	},
	corner_top_left = {
		en = "Top Left",
	},
	corner_top_right = {
		en = "Top Right",
	},
	message_offset_x = {
		en = "Message Offset X",
	},
	message_offset_x_tooltip = {
		en = "Moves the on-screen messages sideways, away from their corner toward the middle of the screen, in the game's UI pixels.\n\n" ..
			"At " .. highlight("0") .. ", their backdrop touches the corner's side.",
	},
	message_offset_y = {
		en = "Message Offset Y",
	},
	message_offset_y_tooltip = {
		en = "Moves the on-screen messages up or down, away from their corner toward the middle of the screen, in the game's UI pixels.\n\n" ..
			"At " .. highlight("0") .. ", their backdrop touches the corner's top or bottom edge.",
	},
	-- The messages a key press shows. %s is the name of the song file unless a comment below says otherwise.
	control_next_song = {
		en = "Next song: %s",
	},
	control_previous_song = {
		en = "Previous song: %s",
	},
	control_restart_song = {
		en = "Restarted: %s",
	},
	control_paused = {
		en = "Paused: %s",
	},
	control_resumed = {
		en = "Resumed: %s",
	},
	control_no_song = {
		en = "No song of yours is playing",
	},
	-- The first %s is where the song plays, such as "Hub" or "Boss (chaos_spawn)", and the second is the song.
	control_only_song = {
		en = "Only song in %s: %s",
	},
	control_remove_confirm = {
		en = "Press again to remove from %s: %s",
	},
	control_removed_song = {
		en = "Removed from %s: %s",
	},
	control_restored_song = {
		en = "Restored 1 song in every situation",
	},
	-- %s is the number of songs, always more than one.
	control_restored_songs = {
		en = "Restored %s songs in every situation",
	},
	control_nothing_removed = {
		en = "No songs are removed",
	},

	music_per_situation = {
		en = "Music per Situation",
	},
	source_custom = {
		en = "Custom",
	},
	source_game = {
		en = "Vanilla",
	},
	source_silence = {
		en = "Silence",
	},
	source_title_screen = {
		en = "Title Screen",
	},
	source_title_screen_tooltip = {
		en = source_tooltip("on the title screen, before character select"),
	},
	source_character_select = {
		en = "Character Select",
	},
	source_character_select_tooltip = {
		en = source_tooltip("on the character select screen, also while creating a character"),
	},
	source_hub = {
		en = "Hub",
	},
	source_hub_tooltip = {
		en = source_tooltip("in the Mourningstar"),
	},
	source_loading = {
		en = "Loading",
	},
	source_loading_tooltip = {
		en = source_tooltip("on loading screens that lead anywhere but into a mission: after starting the game, after a mission, and on the way to Meat Grinder"),
	},
	source_mission_preparation = {
		en = "Mission Preparation",
	},
	source_mission_preparation_tooltip = {
		en = source_tooltip("on the mission preparation screen, where the party gathers before a mission and can still change loadouts"),
	},
	source_mission_briefing = {
		en = "Mission Briefing",
	},
	source_mission_briefing_tooltip = {
		en = source_tooltip(
			"on the loading screen before the preparation screen and in the briefing on the way into a mission, " ..
				"and on the loading screen when joining a mission in progress",
			"The intro itself keeps the game's music. " ..
				"With Resume Songs on, a song that starts on the loading screen before the preparation screen continues in the briefing after it."
		),
	},
	source_explore = {
		en = "Explore",
	},
	source_explore_tooltip = {
		en = source_tooltip("in a mission while nothing threatens you"),
	},
	source_combat = {
		en = "Combat",
	},
	source_combat_tooltip = {
		en = source_tooltip("in a mission while enemies attack you, outside a horde or a boss fight"),
	},
	source_horde = {
		en = "Horde",
	},
	source_horde_tooltip = {
		en = source_tooltip("during a horde"),
	},
	source_boss = {
		en = "Boss",
	},
	source_boss_tooltip = {
		en = source_tooltip("while a monstrosity is near you"),
	},
	source_event = {
		en = "Event",
	},
	source_event_tooltip = {
		en = source_tooltip("while a mission event plays its music, and through a whole Operation"),
	},
	source_last_stand = {
		en = "Last Stand",
	},
	source_last_stand_tooltip = {
		en = source_tooltip("while only one player of the team is left alive"),
	},
	source_victory = {
		en = "Victory",
	},
	source_victory_tooltip = {
		en = source_tooltip("after a mission is won, until the loading screen"),
	},
	source_defeat = {
		en = "Defeat",
	},
	source_defeat_tooltip = {
		en = source_tooltip("after a mission is lost, until the loading screen"),
	},
	source_mortis_trials_wave = {
		en = "Mortis Trials Wave",
	},
	source_mortis_trials_wave_tooltip = {
		en = source_tooltip("during a Mortis Trials wave"),
	},
	source_mortis_trials_break = {
		en = "Mortis Trials Break",
	},
	source_mortis_trials_break_tooltip = {
		en = source_tooltip("between Mortis Trials waves"),
	},
	source_expedition_combat = {
		en = "Expedition Combat",
	},
	source_expedition_combat_tooltip = {
		en = source_tooltip("during a fight in an Expedition"),
	},
	source_expedition_safe_room = {
		en = "Expedition Safe Room",
	},
	source_expedition_safe_room_tooltip = {
		en = source_tooltip("in an Expedition's safe room"),
	},
	source_expedition_extraction = {
		en = "Expedition Extraction",
	},
	source_expedition_extraction_tooltip = {
		en = source_tooltip("while an Expedition's extraction runs"),
	},

	meat_grinder = {
		en = "Meat Grinder",
	},
	-- The situation's name, which the debug overlay shows.
	source_meat_grinder = {
		en = "Meat Grinder",
	},
	meat_grinder_music = {
		en = "Music",
	},
	source_meat_grinder_tooltip = {
		en = "What plays in the Meat Grinder training area.\n\n" ..
			highlight("Silence") .. " plays nothing, as in the game. " ..
			highlight("Meat Grinder Folder") .. " plays your songs from its folder all through the visit, whatever the dummies do. " ..
			highlight("One Situation") .. " plays the situation you choose, to try out its songs. " ..
			highlight("Like a Mission") .. " follows the game as a mission does, with explore, combat, and boss music.\n\n" ..
			"Every situation keeps its own choice in Music per Situation. " ..
			"With " .. highlight("Meat Grinder Folder") .. ", an empty folder plays the game's music, which is none there. " ..
			"Since Darktide 1.13.0, the boss dummies stand there from the start, so " .. highlight("Like a Mission") ..
			" plays boss music for as long as one of them is still alive. It is recommended to use it with a mod that gives you control over the dummies.",
	},
	meat_grinder_folder = {
		en = "Meat Grinder Folder",
	},
	meat_grinder_one_situation = {
		en = "One Situation",
	},
	meat_grinder_like_a_mission = {
		en = "Like a Mission",
	},
	meat_grinder_situation = {
		en = "Situation",
	},
	meat_grinder_situation_tooltip = {
		en = "The situation that " .. highlight("One Situation") .. " plays in Meat Grinder, as if it were happening.\n\n" ..
			"It plays by its choice in Music per Situation. With " .. highlight("Boss") .. ", a boss dummy plays the override folder named after its breed.",
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
			"At " .. highlight("100%%") .. " they play as loud as the files themselves. The game's music is not affected.",
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

	boss_music = {
		en = "Boss Music",
	},
	captain_boss_music = {
		en = "Boss Music for Captains",
	},
	captain_boss_music_tooltip = {
		en = "Plays your boss music while a captain is in the fight.\n\n" ..
			highlight("Off") .. " leaves captains to the game's music. During an event, event music still plays.",
	},
	daemonhost_boss_music = {
		en = "Boss Music for Daemonhosts",
	},
	daemonhost_boss_music_tooltip = {
		en = "Plays your boss music while an angered daemonhost is alive.\n\n" ..
			highlight("Off") .. " follows the game, which plays no music for daemonhosts.",
	},

	music_holds = {
		en = "Music Holds",
	},
	seconds_unit = {
		en = "s",
	},
	combat_hold_seconds = {
		en = "Combat Music Hold",
	},
	combat_hold_seconds_tooltip = {
		en = "How long combat music keeps playing after a fight quiets down, so a short lull does not switch to explore music.\n\n" ..
			"Set to " .. highlight("0") .. " to follow the game exactly.",
	},
	horde_hold_seconds = {
		en = "Horde Music Hold",
	},
	horde_hold_seconds_tooltip = {
		en = "How long horde music keeps playing after the game stops reporting a horde. " ..
			"The game drops that signal for a moment whenever few enemies are on you.\n\n" ..
			"Set to " .. highlight("0") .. " to follow the game exactly.",
	},
	boss_hold_seconds = {
		en = "Boss Music Hold",
	},
	boss_hold_seconds_tooltip = {
		en = "How long boss music keeps playing after the game stops reporting a boss that is still alive. " ..
			"The game drops that signal for a moment now and then during a boss fight. " ..
			"Boss music still ends as soon as the boss dies.\n\n" ..
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
		en = "Writes much more to " .. highlight("diagnostic.log") .. ": every change in the game's music, " ..
			"each time the mod silences it, and the game's sound events.\n\n" ..
			"The important events are always logged, which is enough for most bug reports. " ..
			"The extra lines add up quickly, so turn this on only while tracking down a problem.",
	},
	debug_overlay = {
		en = "Debug Overlay",
	},
	debug_overlay_tooltip = {
		en = "Shows, in the top left corner of the screen, which situation the mod sees, the song playing, and how loud it plays. " ..
			"It shows on every screen, loading screens included.\n\n" ..
			"Useful for checking which music a moment counts as.",
	},
	debug_overlay_scale = {
		en = "Overlay Size",
	},
	debug_overlay_scale_tooltip = {
		en = "How big the debug overlay is, on top of the game's HUD Scale setting. It grows and shrinks away from the corner.\n\n" ..
			highlight("100%%") .. " is its normal size at that HUD Scale.",
	},
	debug_overlay_opacity = {
		en = "Backdrop Opacity",
	},
	debug_overlay_opacity_tooltip = {
		en = "How dark the backdrop behind the debug overlay is. The text always stays fully visible.\n\n" ..
			highlight("0%%") .. " leaves out the backdrop.",
	},
}

return strings
