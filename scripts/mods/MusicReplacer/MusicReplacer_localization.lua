return {
	diagnostic_mode = {
		en = "Diagnostic Logging",
	},
	diagnostic_mode_description = {
		en = "Log Wwise state transitions, boss events, and playback decisions to %%APPDATA%%/Fatshark/Darktide/MusicReplacer/diagnostic.log. Off by default. Turn it on only while troubleshooting, since it writes a lot.",
	},
	combat_hold_seconds = {
		en = "Combat Music Hold",
	},
	combat_hold_seconds_description = {
		en = "How long combat music keeps playing after a fight quiets down, so a short lull does not switch to exploration music. Set to 0 to switch immediately.",
	},
	horde_hold_seconds = {
		en = "Horde Music Hold",
	},
	horde_hold_seconds_description = {
		en = "How long horde music keeps playing after the game stops reporting a horde. The game drops its horde signal for a second or two whenever few enemies are on you, so a short hold keeps the track from restarting. Set to 0 to follow the game exactly.",
	},
	event_hold_seconds = {
		en = "Event Music Hold",
	},
	event_hold_seconds_description = {
		en = "How long event music keeps playing after the game ends an event's music. Some events pause their music for a few seconds between stages, so a short hold keeps the event's song from starting over at every stage. Set to 0 to follow the game exactly.",
	},
	resume_songs = {
		en = "Resume Songs",
	},
	resume_songs_description = {
		en = "When explore or combat music, or a Mortis Trials wave or break, comes back, its song continues from where it stopped instead of a new song starting. A horde, boss, or event song also continues after higher-priority music interrupts it, such as a boss during a horde or a last stand during an event, as long as that horde, fight, or event did not end in between. A new song is picked once one ends on its own. Every mission and hub visit starts with fresh songs.",
	},
	meat_grinder_music = {
		en = "Music in Meat Grinder",
	},
	meat_grinder_music_description = {
		en = "Off keeps custom music out of the Meat Grinder training area and also silences the game's own combat music there. On plays your explore and combat music there, which is a quick way to test your files without starting a mission.",
	},
	daemonhost_boss_music = {
		en = "Boss Music for Daemonhosts",
	},
	daemonhost_boss_music_description = {
		en = "Off follows the game, which plays no music for an angered daemonhost. On plays your boss music from the moment a daemonhost is angered until it dies.",
	},
	rescan_audio = {
		en = "Rescan Audio Folders",
	},
	rescan_audio_description = {
		en = "Picks up audio files added or removed since the game started, without a restart. A track that is playing keeps playing.",
	},
	rescan_audio_button = {
		en = "Rescan",
	},
	captain_boss_music = {
		en = "Boss Music for Captains",
	},
	captain_boss_music_description = {
		en = "On plays your boss music for a captain, including the Karnak Twins, from the moment it engages until it dies. Off leaves captains to the game's own music. Event music still plays during an event.",
	},
	debug = {
		en = "Debug",
	},
	reset_log_on_launch = {
		en = "Reset Log on Launch",
	},
	reset_log_on_launch_description = {
		en = "Clear diagnostic.log at the start of each session instead of appending to it. Only takes effect while Diagnostic Logging is also on.",
	},
}
