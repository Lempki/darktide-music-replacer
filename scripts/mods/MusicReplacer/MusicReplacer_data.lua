-- The mod options, grouped and ordered by how often players need them.
-- Their songs and the keys that control them come first, then what plays where and how loud, then fine timing, and troubleshooting last.
-- Every setting names its tooltip: DMF formats named strings, turning "%%" into "%", but shows an implicit description's "%%" as it is.

local Contexts = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/contexts")

-- What a context plays. Custom keeps the mod's plain behavior: custom songs where there are files, the game's music elsewhere.
local function source_widget(context_name)
	return {
		setting_id = "source_" .. context_name,
		type = "dropdown",
		tooltip = "source_" .. context_name .. "_tooltip",
		default_value = "custom",
		options = {
			{ text = "source_custom", value = "custom" },
			{ text = "source_game", value = "game" },
			{ text = "source_silence", value = "silence" },
		},
	}
end

-- One dropdown per context, in the catalog's order, and Meat Grinder's situations to choose from.
local source_widgets = {}
local meat_grinder_situations = {}
for _, context in ipairs(Contexts.list) do
	if not context.own_settings then
		source_widgets[#source_widgets + 1] = source_widget(context.id)
		meat_grinder_situations[#meat_grinder_situations + 1] = { text = "source_" .. context.id, value = context.id }
	end
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
				-- An empty default leaves a key unbound, since DMF does not check whether another mod already uses a key.
				-- DMF calls each key's function once per press.
				setting_id = "playback_controls",
				type = "group",
				sub_widgets = {
					{
						setting_id = "next_song_keybind",
						type = "keybind",
						tooltip = "next_song_keybind_tooltip",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "next_song",
					},
				},
			},
			{
				setting_id = "music_per_situation",
				type = "group",
				sub_widgets = source_widgets,
			},
			{
				setting_id = "meat_grinder",
				type = "group",
				sub_widgets = {
					{
						-- Its id fits source_of() in MusicReplacer.lua, which reads "silence" and "custom" as for any context.
						setting_id = "source_meat_grinder",
						title = "meat_grinder_music",
						type = "dropdown",
						tooltip = "source_meat_grinder_tooltip",
						-- The game plays no music in Meat Grinder, so it starts silent like an unmodified game.
						default_value = "silence",
						options = {
							{ text = "source_silence", value = "silence" },
							{ text = "meat_grinder_folder", value = "custom" },
							{ text = "meat_grinder_one_situation", value = "situation", show_widgets = { 1 } },
							{ text = "meat_grinder_like_a_mission", value = "mission" },
						},
						sub_widgets = {
							{
								setting_id = "meat_grinder_situation",
								type = "dropdown",
								tooltip = "meat_grinder_situation_tooltip",
								default_value = "explore",
								options = meat_grinder_situations,
							},
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
