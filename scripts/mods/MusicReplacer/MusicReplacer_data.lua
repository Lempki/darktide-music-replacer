-- The mod options, grouped and ordered by how often players need them.
-- Their songs come first, then what plays where and how loud, then fine timing, and troubleshooting last.
-- Every setting names its tooltip, since DMF only formats named tooltips, which turns "%%" in them into "%".

-- What a context plays. The default keeps the mod's plain behavior: custom songs where there are files, the game's music elsewhere.
local function source_widget(context_name)
	return {
		setting_id = "source_" .. context_name,
		type = "dropdown",
		tooltip = "source_" .. context_name .. "_tooltip",
		default_value = "custom",
		options = {
			{ text = "source_custom", value = "custom" },
			{ text = "source_custom_play_to_end", value = "custom_play_to_end" },
			{ text = "source_game", value = "game" },
			{ text = "source_silence", value = "silence" },
		},
	}
end

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
				setting_id = "music_per_context",
				type = "group",
				sub_widgets = {
					source_widget("hub"),
					source_widget("mission_explore"),
					source_widget("mission_combat"),
					source_widget("mission_horde"),
					source_widget("mission_boss"),
					source_widget("mission_event"),
					source_widget("mission_last_stand"),
					source_widget("mission_victory"),
					source_widget("mission_defeat"),
					source_widget("mortis_trials_wave"),
					source_widget("mortis_trials_break"),
					{
						setting_id = "source_meat_grinder",
						type = "dropdown",
						tooltip = "source_meat_grinder_tooltip",
						default_value = "silence",
						options = {
							{ text = "source_custom", value = "custom" },
							{ text = "source_game", value = "game" },
							{ text = "source_silence", value = "silence" },
						},
					},
				},
			},
			{
				setting_id = "volume",
				type = "group",
				sub_widgets = {
					{
						setting_id = "custom_music_volume",
						type = "numeric",
						tooltip = "custom_music_volume_tooltip",
						default_value = 100,
						range = { 0, 100 },
						decimals_number = 0,
						unit_text = "percent_unit",
					},
					{
						setting_id = "menu_volume",
						type = "numeric",
						tooltip = "menu_volume_tooltip",
						default_value = 50,
						range = { 0, 100 },
						decimals_number = 0,
						unit_text = "percent_unit",
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
						unit_text = "seconds_unit",
					},
					{
						setting_id = "horde_hold_seconds",
						type = "numeric",
						tooltip = "horde_hold_seconds_tooltip",
						default_value = 3,
						range = { 0, 30 },
						decimals_number = 0,
						unit_text = "seconds_unit",
					},
					{
						setting_id = "event_hold_seconds",
						type = "numeric",
						tooltip = "event_hold_seconds_tooltip",
						default_value = 5,
						range = { 0, 30 },
						decimals_number = 0,
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
					},
				},
			},
		},
	},
}
