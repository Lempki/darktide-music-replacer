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
		en = "How long combat music keeps playing after a fight quiets down before switching back to exploration music. Set to 0 to switch back immediately.",
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
