-- Pins the parameters equalizer.lua gives XAPOFX's EQ for the band settings.

local FakeEngine = require("tests.helpers.fake_engine")

local function load_equalizer()
	return FakeEngine.new():load("modules/playback/equalizer")
end

local function assert_near(actual, expected, field)
	assert_equal(math.abs(actual - expected) < 1e-9, true, string.format("%s: %s, expected %s", field, tostring(actual), tostring(expected)))
end

describe("equalizer.lua", function()
	it("keeps each band at xapofx.h's default center frequency and bandwidth", function()
		local native = load_equalizer().native({})

		assert_equal(native.FrequencyCenter0, 100)
		assert_equal(native.FrequencyCenter1, 800)
		assert_equal(native.FrequencyCenter2, 2000)
		assert_equal(native.FrequencyCenter3, 10000)
		for band = 0, 3 do
			assert_equal(native["Bandwidth" .. band], 1)
		end
	end)

	it("plays a band with no gain, or 0 dB, unchanged", function()
		local native = load_equalizer().native({ eq_low_mids = 0 })

		for band = 0, 3 do
			assert_equal(native["Gain" .. band], 1)
		end
	end)

	it("turns each band's decibels into the amplitude ratio the EQ takes", function()
		local native = load_equalizer().native({ eq_bass = 6, eq_low_mids = -6, eq_high_mids = 12, eq_treble = -12 })

		assert_near(native.Gain0, 10 ^ (6 / 20), "Gain0")
		assert_near(native.Gain1, 10 ^ (-6 / 20), "Gain1")
		assert_near(native.Gain2, 10 ^ (12 / 20), "Gain2")
		assert_near(native.Gain3, 10 ^ (-12 / 20), "Gain3")
	end)

	it("keeps the setting's ends, -18 and +18 dB, within the gains the EQ takes", function()
		local native = load_equalizer().native({ eq_bass = -18, eq_treble = 18 })

		assert_equal(native.Gain0, 0.126)
		assert_equal(native.Gain3, 7.94)
	end)

	it("gives exactly the twelve fields of FXEQ_PARAMETERS", function()
		local count = 0
		for _ in pairs(load_equalizer().native({ eq_bass = 3 })) do
			count = count + 1
		end

		assert_equal(count, 12)
	end)
end)
