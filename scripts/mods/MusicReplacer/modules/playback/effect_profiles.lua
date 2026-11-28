-- The effect profiles and each one's default settings, which the mod options start from and a profile's Reset button goes back to.
-- A profile's setting ids are the names below with the profile's number on the end, such as reverb_room_2, or reverb_room_0 for Global.

local EffectProfiles = {}

-- Global, which every situation plays unless its own Effects picks another profile, then Profiles 1 to COUNT.
EffectProfiles.GLOBAL = 0
EffectProfiles.COUNT = 3

-- Every profile setting in the order the mod options list them, with the default every profile starts from.
-- Global keeps these, so nothing plays with effects until a player turns an effect on.
EffectProfiles.SETTINGS = {
	{ name = "use_reverb", default = false },
	{ name = "reverb_room", default = "large_hall" },
	{ name = "reverb_mix", default = 30 },
	{ name = "reverb_strength", default = 0 },
	{ name = "reverb_decay", default = 100 },
	{ name = "reverb_pre_delay", default = 0 },
	{ name = "reverb_damping", default = 0 },
	{ name = "use_eq", default = false },
	{ name = "eq_bass", default = 0 },
	{ name = "eq_low_mids", default = 0 },
	{ name = "eq_high_mids", default = 0 },
	{ name = "eq_treble", default = 0 },
	{ name = "use_echo", default = false },
	{ name = "echo_mix", default = 30 },
	{ name = "echo_feedback", default = 30 },
	{ name = "echo_delay", default = 500 },
	{ name = "use_speed", default = false },
	{ name = "playback_speed", default = 100 },
}

-- What each numbered profile starts with instead, so each one shows off something else as soon as a situation picks it.
local OWN_DEFAULTS = {
	-- A hall, loud enough to hear at once.
	[1] = { use_reverb = true, reverb_room = "concert_hall" },
	-- A cave with an echo.
	[2] = { use_reverb = true, reverb_room = "cave", use_echo = true, echo_mix = 25, echo_feedback = 35, echo_delay = 350 },
	-- Half again as fast, and higher with it.
	[3] = { use_speed = true, playback_speed = 150 },
}

local defaults_by_name = {}
for _, setting in ipairs(EffectProfiles.SETTINGS) do
	defaults_by_name[setting.name] = setting.default
end

-- The default of the setting `name` for profile `profile`.
function EffectProfiles.default(name, profile)
	local own = OWN_DEFAULTS[profile]
	if own and own[name] ~= nil then
		return own[name]
	end
	return defaults_by_name[name]
end

-- The setting id of the setting `name` for profile `profile`, such as reverb_room_2.
function EffectProfiles.setting_id(name, profile)
	return name .. "_" .. profile
end

return EffectProfiles
