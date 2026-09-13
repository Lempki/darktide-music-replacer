return {
	name = "Music Replacer",
	description = "Context-aware music replacement.",
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "diagnostic_mode",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "combat_hold_seconds",
				type = "numeric",
				default_value = 8,
				range = { 0, 30 },
				decimals_number = 0,
				step_size_value = 1,
				unit_text = "s",
			},
		},
	},
}
