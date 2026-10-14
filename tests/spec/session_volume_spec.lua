-- Checks that session_volume.lua stays harmless where its COM calls cannot run.
-- The COM calls themselves need a real Windows audio session, so they are checked against a running ffplay outside these specs.

local FakeEngine = require("tests.helpers.fake_engine")

describe("session_volume.lua without ffi", function()
	it("reports itself unavailable, and why", function()
		local engine = FakeEngine.new()
		local SessionVolume = engine:load("session_volume")

		assert_equal(SessionVolume.available(), false)
		assert_equal(SessionVolume.error(), "ffi is not available")
	end)

	it("reads nothing and sets nothing", function()
		local engine = FakeEngine.new()
		local SessionVolume = engine:load("session_volume")

		assert_equal(SessionVolume.get(42), nil)
		assert_equal(SessionVolume.set(42, 0.5), false)
	end)
end)
