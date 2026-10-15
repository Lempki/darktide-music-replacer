return {
	name = "Music Replacer",
	description = "Context-aware music replacement.",
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "combat_hold_seconds",
				type = "numeric",
				default_value = 8,
				range = { 0, 30 },
				decimals_number = 0,
				step_size_value = 1,
				unit_text = "s",
			},
			{
				setting_id = "horde_hold_seconds",
				type = "numeric",
				default_value = 3,
				range = { 0, 30 },
				decimals_number = 0,
				step_size_value = 1,
				unit_text = "s",
			},
			{
				setting_id = "event_hold_seconds",
				type = "numeric",
				default_value = 5,
				range = { 0, 30 },
				decimals_number = 0,
				step_size_value = 1,
				unit_text = "s",
			},
			{
				setting_id = "resume_songs",
				type = "checkbox",
				default_value = true,
			},
			{
				setting_id = "meat_grinder_music",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "daemonhost_boss_music",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "captain_boss_music",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "rescan_audio",
				type = "button",
				button_text = "rescan_audio_button",
				function_name = "rescan_audio",
			},
			{
				setting_id = "debug",
				type = "group",
				sub_widgets = {
					{
						setting_id = "diagnostic_mode",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "reset_log_on_launch",
						type = "checkbox",
						default_value = true,
					},
				},
			},
		},
	},
}
