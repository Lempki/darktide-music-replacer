-- The mod options, grouped and ordered by how often players need them.
-- Their songs, how they play, the keys, and how loud come first, then the on-screen messages.
-- What plays where follows, then fine timing, and troubleshooting last.
-- Every setting names its tooltip: DMF formats named strings, turning "%%" into "%", but shows an implicit description's "%%" as it is.

local Contexts = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/modules/situations/contexts")
local Reverb = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/modules/playback/reverb")

local reverb_room_options = {}
for _, room in ipairs(Reverb.ROOMS) do
	reverb_room_options[#reverb_room_options + 1] = { text = "reverb_room_" .. room.id, value = room.id }
end

-- What a context plays. Custom keeps the mod's plain behavior: custom songs where there are files, the game's music elsewhere.
-- A ranked situation with one below it also offers Skip, which lets that one play instead.
local function source_widget(context)
	local context_name = context.id
	local options = {
		{ text = "source_custom", value = "custom" },
		{ text = "source_game", value = "game" },
		{ text = "source_silence", value = "silence" },
	}
	if Contexts.can_skip(context_name) then
		options[#options + 1] = { text = "source_skip", value = "skip" }
	end

	return {
		setting_id = "source_" .. context_name,
		-- The Situation dropdown above it names the situation, so its own title only says what it sets.
		title = "situation_music",
		type = "dropdown",
		tooltip = "source_" .. context_name .. "_tooltip",
		default_value = context.default_source or "custom",
		options = options,
	}
end

-- One Situation dropdown, whose choice shows only that situation's settings, so the menu does not grow by a row per situation.
-- Every situation's settings exist all along, hidden while another is chosen, so their saved values stay as they are.
-- Meat Grinder's situations to choose from come from the same list.
-- A situation's own choice of a Playback setting: Default follows the Playback group, and On and Off decide for it alone.
local function own_choice_widget(setting_id, title)
	return {
		setting_id = setting_id,
		title = title,
		type = "dropdown",
		tooltip = title .. "_tooltip",
		default_value = "default",
		options = {
			{ text = "situation_default", value = "default" },
			{ text = "situation_on", value = "on" },
			{ text = "situation_off", value = "off" },
		},
	}
end

-- A situation's own settings, which show below its Music choice.
local function situation_settings(context)
	return {
		source_widget(context),
		{
			setting_id = "volume_" .. context.id,
			title = "situation_volume",
			type = "numeric",
			tooltip = "situation_volume_tooltip",
			default_value = 100,
			range = { 0, 100 },
			decimals_number = 0,
			unit_text = "percent_unit",
		},
		own_choice_widget("shuffle_" .. context.id, "situation_shuffle"),
		own_choice_widget("repeat_" .. context.id, "situation_repeat"),
		own_choice_widget("effects_" .. context.id, "situation_effects"),
		{
			setting_id = "own_fade_" .. context.id,
			title = "situation_own_fade",
			type = "checkbox",
			tooltip = "situation_own_fade_tooltip",
			default_value = false,
			-- A checkbox shows its sub-settings only while it is on, so the slider shows only for a situation with its own fade.
			sub_widgets = {
				{
					setting_id = "fade_seconds_" .. context.id,
					title = "situation_fade_seconds",
					type = "numeric",
					tooltip = "situation_fade_seconds_tooltip",
					default_value = 2,
					range = { 0, 10 },
					decimals_number = 1,
					unit_text = "seconds_unit",
				},
			},
		},
		{
			setting_id = "restore_removed_" .. context.id,
			title = "situation_restore_removed",
			type = "button",
			tooltip = "situation_restore_removed_tooltip",
			button_text = "restore_removed_songs_button",
			function_name = "restore_removed_" .. context.id,
		},
	}
end

local situation_widgets = {}
local situation_options = {}
local meat_grinder_situations = {}
for _, context in ipairs(Contexts.list) do
	if not context.own_settings then
		local shown = {}
		for _, widget in ipairs(situation_settings(context)) do
			situation_widgets[#situation_widgets + 1] = widget
			shown[#shown + 1] = #situation_widgets
		end
		situation_options[#situation_options + 1] = { text = "source_" .. context.id, value = context.id, show_widgets = shown }
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
				setting_id = "your_songs",
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
						setting_id = "restore_removed_songs",
						type = "button",
						tooltip = "restore_removed_songs_tooltip",
						button_text = "restore_removed_songs_button",
						function_name = "restore_removed_songs",
					},
				},
			},
			{
				setting_id = "playback",
				type = "group",
				sub_widgets = {
					{
						setting_id = "shuffle",
						type = "checkbox",
						tooltip = "shuffle_tooltip",
						default_value = true,
					},
					{
						setting_id = "repeat_song",
						type = "checkbox",
						tooltip = "repeat_song_tooltip",
						default_value = false,
					},
					{
						setting_id = "let_songs_finish",
						type = "checkbox",
						tooltip = "let_songs_finish_tooltip",
						default_value = false,
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
					{
						setting_id = "previous_song_keybind",
						type = "keybind",
						tooltip = "previous_song_keybind_tooltip",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "previous_song",
					},
					{
						setting_id = "restart_song_keybind",
						type = "keybind",
						tooltip = "restart_song_keybind_tooltip",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "restart_song",
					},
					{
						setting_id = "pause_song_keybind",
						type = "keybind",
						tooltip = "pause_song_keybind_tooltip",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "pause_song",
					},
					{
						setting_id = "remove_song_keybind",
						type = "keybind",
						tooltip = "remove_song_keybind_tooltip",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "remove_song",
					},
					{
						setting_id = "shuffle_keybind",
						type = "keybind",
						tooltip = "shuffle_keybind_tooltip",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "toggle_shuffle",
					},
					{
						setting_id = "repeat_song_keybind",
						type = "keybind",
						tooltip = "repeat_song_keybind_tooltip",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "toggle_repeat_song",
					},
					{
						setting_id = "key_fade_seconds",
						type = "numeric",
						tooltip = "key_fade_seconds_tooltip",
						default_value = 0.5,
						range = { 0, 10 },
						decimals_number = 1,
						unit_text = "seconds_unit",
					},
				},
			},
			{
				setting_id = "volume",
				type = "group",
				sub_widgets = {
					{
						setting_id = "normalize_loudness",
						type = "checkbox",
						tooltip = "normalize_loudness_tooltip",
						default_value = true,
					},
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
				-- How the effects sound is shared, while each situation's own Effects choice decides where they play.
				setting_id = "audio_effects",
				type = "group",
				sub_widgets = {
					{
						setting_id = "effects",
						type = "checkbox",
						tooltip = "effects_tooltip",
						default_value = false,
					},
					{
						setting_id = "use_reverb",
						type = "checkbox",
						tooltip = "use_reverb_tooltip",
						default_value = true,
						sub_widgets = {
							{
								setting_id = "reverb_room",
								type = "dropdown",
								tooltip = "reverb_room_tooltip",
								default_value = Reverb.DEFAULT_ROOM,
								options = reverb_room_options,
							},
							{
								setting_id = "reverb_mix",
								type = "numeric",
								tooltip = "reverb_mix_tooltip",
								default_value = 30,
								range = { 0, 100 },
								decimals_number = 0,
								unit_text = "percent_unit",
							},
							{
								setting_id = "reverb_strength",
								type = "numeric",
								tooltip = "reverb_strength_tooltip",
								default_value = 0,
								range = { -20, 20 },
								decimals_number = 0,
								unit_text = "decibels_unit",
							},
						},
					},
					{
						setting_id = "use_eq",
						type = "checkbox",
						tooltip = "use_eq_tooltip",
						default_value = false,
						-- The EQ's bands, as equalizer.lua lists them, from the lowest frequencies to the highest.
						sub_widgets = {
							{
								setting_id = "eq_bass",
								type = "numeric",
								tooltip = "eq_bass_tooltip",
								default_value = 0,
								range = { -18, 18 },
								decimals_number = 0,
								unit_text = "decibels_unit",
							},
							{
								setting_id = "eq_low_mids",
								type = "numeric",
								tooltip = "eq_low_mids_tooltip",
								default_value = 0,
								range = { -18, 18 },
								decimals_number = 0,
								unit_text = "decibels_unit",
							},
							{
								setting_id = "eq_high_mids",
								type = "numeric",
								tooltip = "eq_high_mids_tooltip",
								default_value = 0,
								range = { -18, 18 },
								decimals_number = 0,
								unit_text = "decibels_unit",
							},
							{
								setting_id = "eq_treble",
								type = "numeric",
								tooltip = "eq_treble_tooltip",
								default_value = 0,
								range = { -18, 18 },
								decimals_number = 0,
								unit_text = "decibels_unit",
							},
						},
					},
				},
			},
			{
				setting_id = "on_screen_messages",
				type = "group",
				sub_widgets = {
					{
						setting_id = "key_press_messages",
						type = "checkbox",
						tooltip = "key_press_messages_tooltip",
						default_value = true,
					},
					{
						setting_id = "song_change_messages",
						type = "checkbox",
						tooltip = "song_change_messages_tooltip",
						default_value = true,
					},
					{
						setting_id = "notice_messages",
						type = "checkbox",
						tooltip = "notice_messages_tooltip",
						default_value = true,
					},
					{
						setting_id = "error_messages",
						type = "checkbox",
						tooltip = "error_messages_tooltip",
						default_value = true,
					},
					{
						setting_id = "message_seconds",
						type = "numeric",
						tooltip = "message_seconds_tooltip",
						default_value = 4,
						range = { 1, 10 },
						decimals_number = 1,
						unit_text = "seconds_unit",
					},
					{
						setting_id = "message_fade_out_seconds",
						type = "numeric",
						tooltip = "message_fade_out_seconds_tooltip",
						default_value = 1,
						range = { 0, 3 },
						decimals_number = 1,
						unit_text = "seconds_unit",
					},
					{
						-- Default draws the default look and hides the look's settings, which keep their values for when Custom is chosen again.
						setting_id = "message_look",
						type = "dropdown",
						tooltip = "message_look_tooltip",
						default_value = "default",
						options = {
							{ text = "look_default", value = "default" },
							{ text = "look_custom", value = "custom", show_widgets = { 1, 2, 3, 4, 5, 6, 7, 8 } },
						},
						sub_widgets = {
							{
								setting_id = "message_scale",
								type = "numeric",
								tooltip = "message_scale_tooltip",
								default_value = 100,
								range = { 50, 200 },
								decimals_number = 0,
								unit_text = "percent_unit",
							},
							{
								-- ARGB. The alpha, 217, is 85% opacity.
								setting_id = "message_color",
								type = "color",
								tooltip = "message_color_tooltip",
								default_value = { 217, 200, 200, 195 },
								has_alpha = true,
							},
							{
								-- ARGB, an amber at the same 85% opacity as Message Color.
								setting_id = "notice_color",
								type = "color",
								tooltip = "notice_color_tooltip",
								default_value = { 217, 235, 180, 80 },
								has_alpha = true,
							},
							{
								-- ARGB, a red at the same 85% opacity as Message Color.
								setting_id = "error_color",
								type = "color",
								tooltip = "error_color_tooltip",
								default_value = { 217, 240, 100, 90 },
								has_alpha = true,
							},
							{
								setting_id = "message_backdrop_opacity",
								type = "numeric",
								tooltip = "message_backdrop_opacity_tooltip",
								default_value = 70,
								range = { 0, 100 },
								decimals_number = 0,
								unit_text = "percent_unit",
							},
							{
								setting_id = "message_corner",
								type = "dropdown",
								tooltip = "message_corner_tooltip",
								default_value = "bottom_left",
								options = {
									{ text = "corner_bottom_left", value = "bottom_left" },
									{ text = "corner_bottom_right", value = "bottom_right" },
									{ text = "corner_top_left", value = "top_left" },
									{ text = "corner_top_right", value = "top_right" },
								},
							},
							{
								-- The range is wide enough for any screen, so it assumes no resolution or aspect ratio.
								-- DMF lets a player type the exact number.
								setting_id = "message_offset_x",
								type = "numeric",
								tooltip = "message_offset_x_tooltip",
								default_value = 0,
								range = { 0, 10000 },
								decimals_number = 0,
								unit_text = "pixels_unit",
							},
							{
								setting_id = "message_offset_y",
								type = "numeric",
								tooltip = "message_offset_y_tooltip",
								default_value = 0,
								range = { 0, 10000 },
								decimals_number = 0,
								unit_text = "pixels_unit",
							},
						},
					},
				},
			},
			{
				setting_id = "music_per_situation",
				type = "group",
				sub_widgets = {
					{
						setting_id = "shown_situation",
						title = "situation_title",
						type = "dropdown",
						tooltip = "shown_situation_tooltip",
						default_value = "explore",
						options = situation_options,
						sub_widgets = situation_widgets,
					},
				},
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
						setting_id = "weakened_boss_music",
						type = "checkbox",
						tooltip = "weakened_boss_music_tooltip",
						default_value = false,
					},
					{
						setting_id = "daemonhost_boss_music",
						type = "checkbox",
						tooltip = "daemonhost_boss_music_tooltip",
						default_value = false,
					},
					{
						setting_id = "boss_near_meters",
						type = "numeric",
						tooltip = "boss_near_meters_tooltip",
						-- The game's own boss music starts within 80 m.
						default_value = 80,
						range = { 20, 160 },
						decimals_number = 0,
						unit_text = "meters_unit",
					},
					{
						setting_id = "daemonhost_near_meters",
						type = "numeric",
						tooltip = "daemonhost_near_meters_tooltip",
						default_value = 20,
						range = { 5, 80 },
						decimals_number = 0,
						unit_text = "meters_unit",
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
						setting_id = "event_hold_seconds",
						type = "numeric",
						tooltip = "event_hold_seconds_tooltip",
						default_value = 8,
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
					{
						-- It sits outside Debug Overlay's own settings, so it shows while the overlay is off.
						setting_id = "debug_overlay_keybind",
						type = "keybind",
						tooltip = "debug_overlay_keybind_tooltip",
						default_value = {},
						keybind_trigger = "pressed",
						keybind_type = "function_call",
						function_name = "toggle_debug_overlay",
					},
				},
			},
		},
	},
}
