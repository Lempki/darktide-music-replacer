-- Pins how context.lua resolves missions that never report a zone, such as op_train.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a zoneless mission.
local function in_zoneless_mission()
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("op_train", nil)

	return harness
end

describe("context.lua zoneless missions", function()
	it("resolves no context through the briefing and the intro", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:state("music_game_state", "mission_briefing")
		harness:mission("op_train")
		harness:state("music_game_state", "mission_intro")

		assert_deep_equal(harness.changes, {})
	end)

	it("resolves mission_explore once the game state returns to mission", function()
		local harness = in_zoneless_mission()

		assert_equal(harness:current(), "mission_explore")
	end)

	it("switches between mission_explore and mission_combat with the hold", function()
		local harness = in_zoneless_mission()
		harness:clear_changes()

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness:wait(8.2)

		assert_deep_equal(harness.changes, { "mission_combat", "mission_explore" })
	end)

	-- The order seen for op_train in diagnostic-2026-10-06.log, with no zone line at the end.
	it("ends with mission_victory and does not fall back to mission_explore in the transient mission state", function()
		local harness = in_zoneless_mission()
		harness:clear_changes()

		harness:end_with_victory(nil)
		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "mission_victory", "nil", "hub" })
	end)
end)
