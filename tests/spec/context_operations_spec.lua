-- Pins how context.lua treats an Operation as one event from its start to its end.
-- Operations script their own music across the whole mission in stages, with short gaps before, between, and after them.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered an Operation, zoneless like op_train unless a zone is given.
local function in_operation(name, zone)
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission(name, zone)
	return harness
end

describe("context.lua operations", function()
	it("resolves mission_event from the start, before the first stage sets the event music", function()
		local harness = in_operation("op_train")

		assert_equal(harness:current(), "mission_event")
	end)

	it("keeps mission_event through the gap between a stage and the escape", function()
		local harness = in_operation("op_train")
		harness:clear_changes()

		harness:state("music_objective", "operation_stage_1")
		harness:state("music_combat", "normal")
		harness:state("music_objective", "None")
		harness:wait(25)
		harness:state("music_objective", "escape_event")

		assert_deep_equal(harness.changes, {})
		assert_equal(harness:current(), "mission_event")
	end)

	it("keeps mission_event over hordes and bosses, in an Operation with a zone too", function()
		local harness = in_operation("op_no_mans_land", "operations")
		harness:clear_changes()

		harness:state("music_combat", "horde_high")
		harness:state("music_combat", "boss")
		harness:state("music_combat", "None")
		harness:wait(30)

		assert_deep_equal(harness.changes, {})
	end)

	it("still gives way to a last stand", function()
		local harness = in_operation("op_train")
		harness:clear_changes()

		harness:state("music_objective", "last_man_standing")
		harness:state("music_objective", "None")

		assert_deep_equal(harness.changes, { "mission_last_stand", "mission_event" })
	end)

	it("ends with mission_victory", function()
		local harness = in_operation("op_train")
		harness:clear_changes()

		harness:end_with_victory()

		assert_equal(harness.changes[1], "mission_victory")
	end)

	it("plays a regular mission's explore music after an Operation", function()
		local harness = in_operation("op_train")
		harness:end_with_victory()
		harness:arrive_in_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:enter_mission("lm_cooling", "zone_3")

		assert_equal(harness:current(), "mission_explore")
	end)
end)
