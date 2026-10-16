-- The mod options, grouped and ordered by how often players need them.
-- Their songs come first, then where music plays, then fine timing, and troubleshooting last.
-- Every setting names its tooltip, since DMF only formats named tooltips, which turns "%%" in them into "%".
return {
	name = "Music Replacer",
	description = "Plays your own music in the hub and missions, chosen by what is happening in the game.",
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "songs",
				type = "group",
				sub_widgets = {
					{
						setting_id = "rescan_audio",
						type = "button",
						tooltip = "rescan_audio_tooltip",
						button_text = "rescan_audio_button",
						function_name = "rescan_audio",
					},
					{
						setting_id = "resume_songs",
						type = "checkbox",
						tooltip = "resume_songs_tooltip",
						default_value = true,
					},
				},
			},
			{
				setting_id = "where_music_plays",
				type = "group",
				sub_widgets = {
					{
						setting_id = "captain_boss_music",
						type = "checkbox",
						tooltip = "captain_boss_music_tooltip",
						default_value = false,
					},
					{
						setting_id = "daemonhost_boss_music",
						type = "checkbox",
						tooltip = "daemonhost_boss_music_tooltip",
						default_value = false,
					},
					{
						setting_id = "meat_grinder_music",
						type = "checkbox",
						tooltip = "meat_grinder_music_tooltip",
						default_value = false,
					},
				},
			},
			{
				setting_id = "timing",
				type = "group",
				sub_widgets = {
					{
						setting_id = "combat_hold_seconds",
						type = "numeric",
						tooltip = "combat_hold_seconds_tooltip",
						default_value = 8,
						range = { 0, 30 },
						decimals_number = 0,
						step_size_value = 1,
						unit_text = "seconds_unit",
					},
					{
						setting_id = "horde_hold_seconds",
						type = "numeric",
						tooltip = "horde_hold_seconds_tooltip",
						default_value = 3,
						range = { 0, 30 },
						decimals_number = 0,
						step_size_value = 1,
						unit_text = "seconds_unit",
					},
					{
						setting_id = "event_hold_seconds",
						type = "numeric",
						tooltip = "event_hold_seconds_tooltip",
						default_value = 5,
						range = { 0, 30 },
						decimals_number = 0,
						step_size_value = 1,
						unit_text = "seconds_unit",
					},
				},
			},
			{
				setting_id = "debug",
				type = "group",
				sub_widgets = {
					{
						setting_id = "diagnostic_mode",
						type = "checkbox",
						tooltip = "diagnostic_mode_tooltip",
						default_value = false,
						-- DMF shows a checkbox's sub-widgets only while it is on, which is the only time this one matters.
						sub_widgets = {
							{
								setting_id = "reset_log_on_launch",
								type = "checkbox",
								tooltip = "reset_log_on_launch_tooltip",
								default_value = true,
							},
						},
					},
				},
			},
		},
	},
}
