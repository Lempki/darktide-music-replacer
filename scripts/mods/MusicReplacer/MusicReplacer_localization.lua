local InputUtils = require("scripts/managers/input/input_utils")

-- Key values in the tooltips, in the color the game itself uses for highlighted terms.
local function highlight(text)
	return InputUtils.apply_color_to_input_text(text, Color.terminal_text_warning_light(255, true))
end

-- Each tooltip says what its setting does, then gives the notes that matter in a second paragraph.
-- docs/settings.md keeps the full explanations.

-- Builds the English tooltip of a situation dropdown, since every one offers the same choices.
-- `note`, if given, is one more sentence about that situation.
-- `skipped`, given for a situation that offers Skip, says what plays while it is skipped.
-- `empty`, if given, says what an empty folder plays instead of the game's music.
-- A translation writes its own full text instead, since the sentence order differs between languages.
local function source_tooltip(when, note, skipped, empty)
	return "What plays " .. when .. ".\n\n" ..
		highlight("Custom") .. " plays your songs from its folder. " ..
		highlight("Vanilla") .. " always plays the game's music, and " .. highlight("Silence") .. " plays nothing." ..
		(skipped and " " .. highlight("Skip") .. " passes it over, so " .. skipped .. "." or "") ..
		(note and " " .. note or "") ..
		"\n\nWith " .. highlight("Custom") .. ", an empty folder plays " .. (empty or "the game's music") .. "."
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
		en = "Lists the audio folders again at once, and checks again whether every song plays.\n\n" ..
			"The mod notices added, removed, and replaced files by itself, 3 seconds after files stop changing. " ..
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
	shuffle = {
		en = "Shuffle",
	},
	shuffle_tooltip = {
		en = "Plays each folder's songs in a random order, each once before any song repeats.\n\n" ..
			"Turned off, each folder plays in the order File Explorer sorts it by name, and continues after the song it played last.",
	},
	repeat_song = {
		en = "Repeat Song",
	},
	repeat_song_tooltip = {
		en = "Loops the song playing now with no gap, and every song after it. " ..
			"Next Song and a new situation still change the song, and the new one loops too.\n\n" ..
			"A folder's only song always loops.",
	},
	let_songs_finish = {
		en = "Let Songs Finish",
	},
	let_songs_finish_tooltip = {
		en = "When the music would switch to a situation that is no more urgent, such as from Combat back to Explore, " ..
			"the song playing now plays to its end first. A looping song plays to the end of the pass it is in.\n\n" ..
			"A switch to a more urgent situation, to the game's music, to silence, or to a situation with no songs still happens at once. " ..
			"Next Song moves on right away.",
	},
	resume_songs = {
		en = "Resume Songs",
	},
	resume_songs_tooltip = {
		en = "Continues a song where it stopped when its situation comes back, such as Explore after a fight.\n\n" ..
			"Explore, Combat, Mortis Trials Wave and Break, Expedition Combat, and Expedition Safe Room songs always do. " ..
			"Horde, Boss Near, Boss, and Event songs do as long as that horde, boss fight, or event lasts. " ..
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
			"Keys also work while you type in chat, so a key that is not a letter, such as one on the numpad or an F-key, works best.",
	},
	previous_song_keybind = {
		en = "Previous Song",
	},
	previous_song_keybind_tooltip = {
		en = "Within the first 3 seconds of a song, crossfades back to the song that played before it in this situation, " ..
			"and each further press goes back one more.\n\n" ..
			"Later into a song, or with no earlier song, it starts the song playing now over.",
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
			"The file stays where it is.\n\n" ..
			highlight("Restore All Removed Songs") .. " puts every removed song back, " ..
			"and a situation's own " .. highlight("Restore Removed Songs") .. " puts back the ones removed from it.",
	},
	restore_removed_songs = {
		en = "Restore All Removed Songs",
	},
	restore_removed_songs_button = {
		en = "Restore",
	},
	restore_removed_songs_tooltip = {
		en = "Puts every song that Remove from Rotation took out back into its folder's rotation, and a message says how many came back.",
	},
	shuffle_keybind = {
		en = "Toggle Shuffle",
	},
	shuffle_keybind_tooltip = {
		en = "Turns Shuffle on or off, and the message says which.\n\n" ..
			"While the situation playing now has its own " .. highlight("Shuffle") .. " set to On or Off, " ..
			"it changes that one instead, and the message names the situation.",
	},
	repeat_song_keybind = {
		en = "Toggle Repeat Song",
	},
	repeat_song_keybind_tooltip = {
		en = "Turns Repeat Song on or off, and the message says which.\n\n" ..
			"While the situation playing now has its own " .. highlight("Repeat Song") .. " set to On or Off, " ..
			"it changes that one instead, and the message names the situation.",
	},
	key_fade_seconds = {
		en = "Key Fade Length",
	},
	key_fade_seconds_tooltip = {
		en = "How long the music crossfades when one of these keys changes the song, pauses it, or resumes it. " ..
			"Fade Length still sets the fades when the situation changes and when a song ends by itself.\n\n" ..
			"Set to " .. highlight("0") .. " to switch at once.",
	},
	on_screen_messages = {
		en = "On-Screen Messages",
	},
	key_press_messages = {
		en = "For Key Presses",
	},
	key_press_messages_tooltip = {
		en = "Shows a message in Message Color when you press a Playback Controls key or a Restore button, such as the song that plays next.\n\n" ..
			highlight("Off") .. " shows none for them, and the keys still work.",
	},
	song_change_messages = {
		en = "For Song Changes",
	},
	song_change_messages_tooltip = {
		en = "Shows a message in Message Color when one of your songs starts by itself, such as when a situation starts its music. " ..
			"With For Key Presses off, it also names the song a key starts.\n\n" ..
			highlight("Off") .. " shows none for them, and the songs still play.",
	},
	notice_messages = {
		en = "For Notices",
	},
	notice_messages_tooltip = {
		en = "Shows a message in Notice Color when there is something you need to know, such as how many songs the mod found.\n\n" ..
			highlight("Off") .. " shows none for them, and each is still written to diagnostic.log.",
	},
	error_messages = {
		en = "For Errors",
	},
	error_messages_tooltip = {
		en = "Shows a message in Error Color when something goes wrong, such as Windows audio playback failing to start.\n\n" ..
			highlight("Off") .. " shows none for them, and each is still written to diagnostic.log.",
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
	-- The error messages stay short, since a message shows for a few seconds, and the details go to diagnostic.log.
	error_audio_unavailable = {
		en = "Windows audio playback could not start, so the game's music plays. Details in diagnostic.log.",
	},
	error_game_change = {
		en = "The music could not follow a change in the game. Details in diagnostic.log.",
	},
	error_log_unavailable = {
		en = "diagnostic.log could not be opened, so nothing is logged this launch.",
	},
	message_look = {
		en = "Look",
	},
	message_look_tooltip = {
		en = "How the on-screen messages look.\n\n" ..
			highlight("Default") .. " draws them in their default size, colors, and corner.\n" ..
			highlight("Custom") .. " shows the settings to change that. Your changes stay saved while Default is chosen.",
	},
	look_default = {
		en = "Default",
	},
	look_custom = {
		en = "Custom",
	},
	-- The notices say what the mod found once it has listed and checked the audio folders, at launch and whenever they change.
	-- Its songs and folders count every folder, so a song in two folders counts twice.
	notice_no_songs = {
		en = "No songs found. Put them in the folders in mods\\MusicReplacer\\audio.",
	},
	notice_found_song = {
		en = "Found 1 song.",
	},
	-- %s is the number of songs, two or more.
	notice_found_songs_in_folder = {
		en = "Found %s songs in 1 folder.",
	},
	-- The first %s is the number of songs, and the second the number of folders, two or more of each.
	notice_found_songs = {
		en = "Found %s songs in %s folders.",
	},
	-- The skipped files follow the songs found, and their names and reasons are in diagnostic.log.
	notice_skipped_format_file = {
		en = "Skipped 1 file in a format the mod does not play. Details in diagnostic.log.",
	},
	-- %s is the number of files, two or more.
	notice_skipped_format_files = {
		en = "Skipped %s files in formats the mod does not play. Details in diagnostic.log.",
	},
	notice_skipped_unopenable_file = {
		en = "Skipped 1 file Windows cannot open. Details in diagnostic.log.",
	},
	-- %s is the number of files, two or more.
	notice_skipped_unopenable_files = {
		en = "Skipped %s files Windows cannot open. Details in diagnostic.log.",
	},
	-- The first %s is the number of files skipped.
	-- The second is those in a format the mod does not play, and the third those Windows cannot open.
	notice_skipped_files = {
		en = "Skipped %s files: %s in other formats, %s Windows cannot open. Details in diagnostic.log.",
	},
	-- Shown once Even Out Loudness has measured every song that needed it.
	notice_measured_song = {
		en = "Even Out Loudness measured 1 song.",
	},
	-- %s is the number of songs, two or more.
	notice_measured_songs = {
		en = "Even Out Loudness measured %s songs.",
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
		en = "The color of the messages that For Key Presses and For Song Changes show. Its opacity sets how see-through they are.",
	},
	notice_color = {
		en = "Notice Color",
	},
	notice_color_tooltip = {
		en = "The color of the messages that For Notices shows. Its opacity sets how see-through they are.",
	},
	error_color = {
		en = "Error Color",
	},
	error_color_tooltip = {
		en = "The color of the messages that For Errors shows. Its opacity sets how see-through they are.",
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
		en = "Moves the on-screen messages sideways, away from their corner toward the middle of the screen, in pixels.\n\n" ..
			"At " .. highlight("0") .. ", their backdrop touches the corner's side.",
	},
	message_offset_y = {
		en = "Message Offset Y",
	},
	message_offset_y_tooltip = {
		en = "Moves the on-screen messages up or down, away from their corner toward the middle of the screen, in pixels.\n\n" ..
			"At " .. highlight("0") .. ", their backdrop touches the corner's top or bottom edge.",
	},
	-- Where a song from an override folder plays, in the key messages below.
	-- The first %s is the situation's name, such as "Boss", and the second is the override folder's name, such as "chaos_spawn".
	override_folder_label = {
		en = "%s (%s)",
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
	-- Restart Song and Previous Song show this when the song's file left the folder while the song played on.
	control_song_gone = {
		en = "No longer in %s: %s",
	},
	-- %s is where the song plays, such as "Hub" or "Boss (chaos_spawn)".
	control_no_songs_left = {
		en = "No songs left in %s",
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
	-- The %s is the situation's name, such as "Boss", whose own Restore Removed Songs was pressed.
	control_restored_song_in = {
		en = "Restored 1 song in %s",
	},
	-- The first %s is how many songs, and the second the situation's name.
	control_restored_songs_in = {
		en = "Restored %s songs in %s",
	},
	control_nothing_removed_in = {
		en = "No songs are removed in %s",
	},
	control_shuffle_on = {
		en = "Shuffle on",
	},
	control_shuffle_off = {
		en = "Shuffle off",
	},
	control_repeat_song_on = {
		en = "Repeat song on",
	},
	control_repeat_song_off = {
		en = "Repeat song off",
	},
	-- The %s is the situation's name, such as "Boss", whose own choice the key changed.
	control_shuffle_on_for = {
		en = "Shuffle on for %s",
	},
	control_shuffle_off_for = {
		en = "Shuffle off for %s",
	},
	control_repeat_song_on_for = {
		en = "Repeat song on for %s",
	},
	control_repeat_song_off_for = {
		en = "Repeat song off for %s",
	},

	music_per_situation = {
		en = "Music per Situation",
	},
	situation_title = {
		en = "Situation",
	},
	shown_situation_tooltip = {
		en = "The situation whose settings show below. Each situation keeps its own settings, whichever one is shown.",
	},
	situation_music = {
		en = "Music",
	},
	situation_shuffle = {
		en = "Shuffle",
	},
	situation_shuffle_tooltip = {
		en = "Whether this situation's songs play in a random order, as " .. highlight("Shuffle") .. " in the Playback group does for all of them.\n\n" ..
			highlight("Default") .. " follows that setting. " .. highlight("On") .. " and " .. highlight("Off") .. " decide for this situation alone.",
	},
	situation_repeat = {
		en = "Repeat Song",
	},
	situation_repeat_tooltip = {
		en = "Whether this situation's song loops, as " .. highlight("Repeat Song") .. " in the Playback group does for all of them.\n\n" ..
			highlight("Default") .. " follows that setting. " .. highlight("On") .. " and " .. highlight("Off") .. " decide for this situation alone.",
	},
	situation_own_fade = {
		en = "Own Fade Length",
	},
	situation_own_fade_tooltip = {
		en = "Gives this situation a Fade Length of its own, set below, in place of " .. highlight("Fade Length") .. " in the Playback group.\n\n" ..
			highlight("Off") .. " follows that setting.",
	},
	situation_fade_seconds = {
		en = "Fade Length",
	},
	situation_fade_seconds_tooltip = {
		en = "How long the music crossfades as this situation takes over, and how long its songs fade out at their end.\n\n" ..
			"Set to " .. highlight("0") .. " to switch at once.",
	},
	situation_restore_removed = {
		en = "Restore Removed Songs",
	},
	situation_restore_removed_tooltip = {
		en = "Puts the songs that Remove from Rotation took out of this situation's folder and its override folders back into their rotation, " ..
			"and a message says how many came back.",
	},
	situation_default = {
		en = "Default",
	},
	situation_on = {
		en = "On",
	},
	situation_off = {
		en = "Off",
	},
	situation_volume = {
		en = "Volume",
	},
	situation_volume_tooltip = {
		en = "How loud this situation's songs play, as a share of " .. highlight("Custom Music Volume") .. ".\n\n" ..
			highlight("100%%") .. " plays them at the full Custom Music Volume.",
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
	source_skip = {
		en = "Skip",
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
		en = source_tooltip("on the character select screen, also while creating a character, and while picking a mission or waiting for one from there, as some mods allow"),
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
		en = source_tooltip("on every loading screen, wherever it leads: after starting the game, into a mission and out of one, and on the way to Meat Grinder"),
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
		en = source_tooltip("in the briefing after the preparation screen, and when joining a mission in progress"),
	},
	source_mission_intro = {
		en = "Mission Intro",
	},
	source_mission_intro_tooltip = {
		en = source_tooltip("in the cutscene that opens a mission, before you can move"),
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
		en = source_tooltip("in a mission while enemies attack you, outside a horde or a boss fight", nil, "Explore plays through fights"),
	},
	source_horde = {
		en = "Horde",
	},
	source_horde_tooltip = {
		en = source_tooltip("during a horde", nil, "Combat plays through hordes"),
	},
	source_boss_near = {
		en = "Boss Near",
	},
	source_boss_near_tooltip = {
		en = source_tooltip("while a boss is near you, before its fight starts", nil,
			"Horde, Combat, or Explore plays until the fight starts",
			"whatever " .. highlight("Boss") .. " is set to, " .. highlight("Skip") .. " included, " ..
				"and Boss's songs go on playing once the fight starts"),
	},
	source_boss = {
		en = "Boss",
	},
	source_boss_tooltip = {
		en = source_tooltip("in a boss fight, from the moment the boss's HP bar shows until the boss is gone", nil,
			"Horde, Combat, or Explore, whichever is going on, plays through boss fights"),
	},
	source_event = {
		en = "Event",
	},
	source_event_tooltip = {
		en = source_tooltip("while a mission event plays its music, and through a whole Operation", nil,
			"whatever is less urgent, such as Combat or Explore, plays through events"),
	},
	source_last_stand = {
		en = "Last Stand",
	},
	source_last_stand_tooltip = {
		en = source_tooltip("while only one player of the team is left alive", nil,
			"whatever is less urgent, such as Boss or Combat, plays through a last stand"),
	},
	source_victory = {
		en = "Victory",
	},
	source_victory_tooltip = {
		en = source_tooltip("after a mission is won, until the loading screen or a cutscene"),
	},
	source_defeat = {
		en = "Defeat",
	},
	source_defeat_tooltip = {
		en = source_tooltip("after a mission is lost, until the loading screen or a cutscene"),
	},
	source_cutscene = {
		en = "Cutscene",
	},
	source_cutscene_tooltip = {
		en = source_tooltip("in a cutscene, such as a story mission's cutscene or a scene in the Mourningstar", "With " ..
			highlight("Custom") .. " or " .. highlight("Silence") .. ", only the cutscene's music stops, and its voices and sounds stay. " ..
			highlight("Vanilla") .. " is the default, so cutscenes keep the game's music."),
	},
	source_mortis_trials_wave = {
		en = "Mortis Trials Wave",
	},
	source_mortis_trials_wave_tooltip = {
		en = source_tooltip("in Mortis Trials, during a wave or an objective round, through to the final win", nil, "Mortis Trials Break plays through waves"),
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
		en = source_tooltip("during a fight in an Expedition", nil, "Explore plays through an Expedition's fights"),
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
		en = source_tooltip("while an Expedition's extraction runs", nil,
			"whatever is less urgent, such as Expedition Combat or Explore, plays through the extraction"),
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
			highlight("Like a Mission") .. " follows the game as a mission does, with Explore, Combat, and Boss.\n\n" ..
			"The boss dummies stand there from the start, so " .. highlight("Like a Mission") ..
			" plays Boss for as long as one of them is still alive.",
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
			"It plays by its choice in Music per Situation. With " .. highlight("Boss") .. ", a boss dummy plays the override folder named after its boss type, " ..
			"a folder inside Boss's folder such as " .. highlight("boss\\chaos_spawn") .. ".",
	},

	volume = {
		en = "Volume",
	},
	-- DMF formats this string, since the mod names it, so it shows as a single percent sign.
	meters_unit = {
		en = "m",
	},
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
	boss_near_meters = {
		en = "Boss Distance",
	},
	boss_near_meters_tooltip = {
		en = "How close a boss has to be for " .. highlight("Boss Near") .. " to play. " ..
			"It lets go once the boss is 40 m farther away than that, so moving back and forth at the edge keeps the music steady.\n\n" ..
			"The default, " .. highlight("80 m") .. ", is the distance the game's own boss music uses. " ..
			"Daemonhosts use " .. highlight("Daemonhost Distance") .. " instead.",
	},
	captain_boss_music = {
		en = "Boss Music for Captains",
	},
	captain_boss_music_tooltip = {
		en = "Counts captains as bosses, for " .. highlight("Boss Near") .. " while one is near " ..
			"and " .. highlight("Boss") .. " from its HP bar until it is gone. " ..
			"A captain that comes as part of a mission event, such as the Karnak Twins, plays " .. highlight("Event") .. " instead.\n\n" ..
			highlight("Off") .. " follows the game, which plays no boss music for captains.",
	},
	daemonhost_boss_music = {
		en = "Boss Music for Daemonhosts",
	},
	daemonhost_boss_music_tooltip = {
		en = "Counts daemonhosts as bosses, for " .. highlight("Boss Near") .. " while one is within " ..
			highlight("Daemonhost Distance") .. " and " .. highlight("Boss") .. " from its HP bar, which shows once it is angered, until it is gone.\n\n" ..
			highlight("Off") .. " follows the game, which plays no boss music for daemonhosts.",
	},
	daemonhost_near_meters = {
		en = "Daemonhost Distance",
	},
	daemonhost_near_meters_tooltip = {
		en = "How close a daemonhost has to be for " .. highlight("Boss Near") .. " to play, " ..
			"with " .. highlight("Boss Music for Daemonhosts") .. " on. It lets go once the daemonhost is 40 m farther away than that.\n\n" ..
			"The default, " .. highlight("20 m") .. ", is shorter than " .. highlight("Boss Distance") ..
			", since some levels keep you near a sleeping daemonhost for a long time.",
	},
	weakened_boss_music = {
		en = "Boss Music for Weakened Monstrosities",
	},
	weakened_boss_music_tooltip = {
		en = "Counts weakened monstrosities as bosses, for " .. highlight("Boss Near") .. " and " .. highlight("Boss") .. ". " ..
			"A weakened monstrosity is one the game spawns with less than its full health.\n\n" ..
			highlight("Off") .. " follows the game, which plays no boss music for weakened monstrosities.",
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
		en = "How long Combat keeps playing after the game stops reporting a fight. " ..
			"The game drops that signal every few seconds during a fight, so a short lull does not switch to Explore.\n\n" ..
			"Set to " .. highlight("0") .. " to follow the game exactly.",
	},
	horde_hold_seconds = {
		en = "Horde Music Hold",
	},
	horde_hold_seconds_tooltip = {
		en = "How long Horde keeps playing after the game stops reporting a horde. " ..
			"The game drops that signal for a moment whenever few enemies are on you.\n\n" ..
			"Set to " .. highlight("0") .. " to follow the game exactly.",
	},
	event_hold_seconds = {
		en = "Event Music Hold",
	},
	event_hold_seconds_tooltip = {
		en = "How long Event keeps playing after the game stops reporting an event. " ..
			"Some events drop that signal for a few seconds between their stages.\n\n" ..
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
			"each time the mod silences it, the game's sound events, and the bosses in the level.\n\n" ..
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
	debug_overlay_keybind = {
		en = "Toggle Debug Overlay",
	},
	debug_overlay_keybind_tooltip = {
		en = "Shows or hides the debug overlay, the same as turning Debug Overlay on or off.",
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
