-- Pins the effect profiles' defaults in effect_profiles.lua.

local FakeEngine = require("tests.helpers.fake_engine")

local function load(module)
	return FakeEngine.new():load(module)
end

describe("effect_profiles.lua", function()
	it("starts Global with every effect off", function()
		local EffectProfiles = load("modules/playback/effect_profiles")

		for _, name in ipairs({ "use_reverb", "use_eq", "use_echo", "use_speed" }) do
			assert_equal(EffectProfiles.default(name, EffectProfiles.GLOBAL), false, name)
		end
	end)

	it("gives each numbered profile its own defaults, and every other setting the shared one", function()
		local EffectProfiles = load("modules/playback/effect_profiles")

		assert_equal(EffectProfiles.default("reverb_room", 1), "concert_hall")
		assert_equal(EffectProfiles.default("reverb_room", 2), "cave")
		assert_equal(EffectProfiles.default("echo_delay", 2), 350)
		assert_equal(EffectProfiles.default("playback_speed", 3), 150)
		assert_equal(EffectProfiles.default("use_reverb", 3), false)
		assert_equal(EffectProfiles.default("reverb_mix", 2), 30)
	end)

	it("names only rooms that Reverb Room offers", function()
		local EffectProfiles = load("modules/playback/effect_profiles")
		local rooms = {}
		for _, room in ipairs(load("modules/playback/reverb").ROOMS) do
			rooms[room.id] = true
		end

		for profile = EffectProfiles.GLOBAL, EffectProfiles.COUNT do
			local room = EffectProfiles.default("reverb_room", profile)
			assert_equal(rooms[room], true, room)
		end
	end)

	it("names a profile's setting by the setting and the profile's number", function()
		assert_equal(load("modules/playback/effect_profiles").setting_id("reverb_room", 2), "reverb_room_2")
	end)
end)
