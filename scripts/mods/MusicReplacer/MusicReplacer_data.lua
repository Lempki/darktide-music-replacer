-- The mod options, grouped and ordered by how often players need them.
-- Their songs come first, then what plays where and how loud, then fine timing, and troubleshooting last.
-- Every setting names its tooltip: DMF formats named strings, turning "%%" into "%", but shows an implicit description's "%%" as it is.

local Contexts = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/contexts")

-- What a context plays. Custom keeps the mod's plain behavior: custom songs where there are files, the game's music elsewhere.
local function source_widget(context_name, default_value)
	return {
		setting_id = "source_" .. context_name,
		type = "dropdown",
		tooltip = "source_" .. context_name .. "_tooltip",
		default_value = default_value or "custom",
		options = {
			{ text = "source_custom", value = "custom" },
			{ text = "source_game", value = "game" },
			{ text = "source_silence", value = "silence" },
		},
	}
end

-- One dropdown per context, in the catalog's order.
local source_widgets = {}
for _, context in ipairs(Contexts.list) do
	source_widgets[#source_widgets + 1] = source_widget(context.id, context.default_source)
end

return {
	name = "Music Replacer",
	description = "Plays your own music in the hub and missions, chosen by what is happening in the game, and keeps the game's music wherever you add none.",
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "playback",
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
					{
						setting_id = "fade_seconds",
						type = "numeric",
						tooltip = "fade_seconds_tooltip",
						default_value = 2,
						range = { 0, 10 },
						decimals_number = 1,
						unit_text = "seconds_unit",
					},
				},
			},
			{
				setting_id = "music_per_situation",
				type = "group",
				sub_widgets = source_widgets,
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
					{
						setting_id = "normalize_loudness",
						type = "checkbox",
						tooltip = "normalize_loudness_tooltip",
						default_value = false,
					},
				},
			},
			{
				setting_id = "boss_music",
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
				setting_id = "music_holds",
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
						setting_id = "boss_hold_seconds",
						type = "numeric",
						tooltip = "boss_hold_seconds_tooltip",
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
					{
						setting_id = "debug_overlay",
						type = "checkbox",
						tooltip = "debug_overlay_tooltip",
						default_value = false,
						sub_widgets = {
							{
								setting_id = "debug_overlay_scale",
								type = "numeric",
								tooltip = "debug_overlay_scale_tooltip",
								default_value = 100,
								range = { 50, 200 },
								decimals_number = 0,
								unit_text = "percent_unit",
							},
							{
								setting_id = "debug_overlay_opacity",
								type = "numeric",
								tooltip = "debug_overlay_opacity_tooltip",
								default_value = 70,
								range = { 0, 100 },
								decimals_number = 0,
								unit_text = "percent_unit",
							},
						},
					},
				},
			},
		},
	},
}
