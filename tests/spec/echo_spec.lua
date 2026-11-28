-- Pins the parameters echo.lua gives XAPOFX's echo for the Echo settings.

local FakeEngine = require("tests.helpers.fake_engine")

local function load_echo()
	return FakeEngine.new():load("modules/playback/echo")
end

describe("echo.lua", function()
	it("turns the mix and the feedback from percents into the fractions the echo takes, and keeps the delay in milliseconds", function()
		assert_deep_equal(load_echo().native({ mix = 30, feedback = 45, delay = 500 }), { WetDryMix = 0.3, Feedback = 0.45, Delay = 500 })
	end)

	it("keeps every value within the ranges in xapofx.h", function()
		local Echo = load_echo()

		assert_deep_equal(Echo.native({ mix = 150, feedback = 120, delay = 5000 }), { WetDryMix = 1, Feedback = 1, Delay = 2000 })
		assert_deep_equal(Echo.native({ mix = -10, feedback = -5, delay = 0 }), { WetDryMix = 0, Feedback = 0, Delay = 1 })
	end)
end)
