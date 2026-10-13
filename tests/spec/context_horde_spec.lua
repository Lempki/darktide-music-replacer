-- Pins how context.lua resolves hordes from the game's horde music states.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission with a zone, with the given hold.
local function in_mission(hold_seconds)
	local harness = Harness.new({ combat_hold_seconds = hold_seconds })
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("lm_cooling", "zone_3")
	harness:clear_changes()

	return harness
end

describe("context.lua hordes", function()
	it("resolves mission_horde for both horde states, without switching between them", function()
		local harness = in_mission(8)

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "horde_low")
		harness:state("music_combat", "horde_high")

		assert_deep_equal(harness.changes, { "mission_horde" })
	end)

	it("switches from mission_combat to mission_horde at once when a horde arrives", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:state("music_combat", "horde_high")

		assert_deep_equal(harness.changes, { "mission_combat", "mission_horde" })
	end)

	-- A horde often drops out for a second or two and returns.
	it("keeps mission_horde through a short drop out of the horde state", function()
		local harness = in_mission(8)

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "None")
		harness:wait(2)
		harness:state("music_combat", "horde_low")
		harness:state("music_combat", "normal")
		harness:wait(3)
		harness:state("music_combat", "horde_high")

		assert_deep_equal(harness.changes, { "mission_horde" })
	end)

	it("returns to mission_explore once the hold runs out after a horde ends into no combat", function()
		local harness = in_mission(8)

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "mission_horde")

		harness:wait(0.3)

		assert_deep_equal(harness.changes, { "mission_horde", "mission_explore" })
	end)

	it("returns to mission_combat and its own hold once the horde hold runs out during plain combat", function()
		local harness = in_mission(8)

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "normal")
		harness:wait(8.2)

		assert_equal(harness:current(), "mission_combat")

		harness:state("music_combat", "None")
		harness:wait(8.2)

		assert_deep_equal(harness.changes, { "mission_horde", "mission_combat", "mission_explore" })
	end)

	it("gives way to a boss, and returns once the boss is gone while the horde lasts", function()
		local harness = in_mission(8)

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "boss")
		harness:state("music_combat", "horde_high")

		assert_deep_equal(harness.changes, { "mission_horde", "mission_boss", "mission_horde" })
	end)

	it("gives way to event music", function()
		local harness = in_mission(8)
		harness:state("music_combat", "horde_high")

		harness:state("music_objective", "fortification_event")

		assert_deep_equal(harness.changes, { "mission_horde", "mission_event" })
	end)

	it("drops the horde hold on a real zone change", function()
		local harness = in_mission(8)

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "None")
		harness:state("music_zone", "zone_4")

		assert_equal(harness:current(), "mission_explore")
	end)

	it("returns to mission_explore at once with a hold of zero", function()
		local harness = in_mission(0)

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "None")

		assert_deep_equal(harness.changes, { "mission_horde", "mission_explore" })
	end)
end)
