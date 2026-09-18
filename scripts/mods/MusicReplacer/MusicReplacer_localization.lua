return {
	diagnostic_mode = {
		en = "Diagnostic Logging",
	},
	diagnostic_mode_description = {
		en = "Log Wwise state transitions, boss events, and playback decisions to %%APPDATA%%/Fatshark/Darktide/MusicReplacer/diagnostic.log. Off by default -- turn on only while troubleshooting, since it is much higher volume than normal.",
	},
	combat_hold_seconds = {
		en = "Combat Music Hold",
	},
	combat_hold_seconds_description = {
		en = "How long combat music keeps playing after a fight quiets down before switching back to exploration music. Set to 0 to switch back immediately.",
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
