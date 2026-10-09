-- Pins how context.lua switches between mission_explore and mission_combat, including the combat hold.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission with a zone, with the given combat hold.
local function in_mission(hold_seconds)
	local harness = Harness.new({ combat_hold_seconds = hold_seconds })
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("lm_cooling", "zone_3")
	harness:clear_changes()

	return harness
end

describe("context.lua combat", function()
	it("switches to mission_combat at once when combat starts", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")

		assert_deep_equal(harness.changes, { "mission_combat" })
	end)

	it("resolves mission_combat for both horde states", function()
		local harness = in_mission(8)

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "horde_low")
		harness:state("music_combat", "horde_high")

		assert_deep_equal(harness.changes, { "mission_combat" })
	end)

	it("holds mission_combat for the full hold after combat goes quiet, then returns to mission_explore", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:wait(3)
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "mission_combat")

		harness:wait(0.3)

		assert_equal(harness:current(), "mission_explore")
		assert_deep_equal(harness.changes, { "mission_combat", "mission_explore" })
	end)

	it("does not drain the hold while combat is still going", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:wait(60)
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "mission_combat")
	end)

	it("counts the hold from the last time combat went quiet when combat flaps", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:wait(2)
		harness:state("music_combat", "None")
		harness:wait(5)
		harness:state("music_combat", "normal")
		harness:wait(1)
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "mission_combat")

		harness:wait(0.3)

		assert_equal(harness:current(), "mission_explore")
		assert_deep_equal(harness.changes, { "mission_combat", "mission_explore" })
	end)

	it("returns to mission_explore at once with a hold of zero", function()
		local harness = in_mission(0)

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")

		assert_deep_equal(harness.changes, { "mission_combat", "mission_explore" })
	end)

	it("drops the hold on a real zone change", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness:state("music_zone", "zone_4")

		assert_equal(harness:current(), "mission_explore")
	end)
end)
