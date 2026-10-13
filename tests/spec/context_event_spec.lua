-- Pins how context.lua resolves mission event music, which the game sets in music_objective.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission, with a zone when one is given.
local function in_mission(zone)
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission(zone and "fm_cargo" or "op_train", zone)
	harness:clear_changes()

	return harness
end

describe("context.lua mission events", function()
	it("resolves mission_event over explore and combat while the event lasts, then follows the other states again", function()
		local harness = in_mission("zone_3")
		harness:state("music_combat", "normal")

		harness:state("music_objective", "hacking_event")
		harness:state("music_combat", "None")
		harness:wait(120)
		harness:state("music_objective", "None")

		assert_deep_equal(harness.changes, { "mission_combat", "mission_event", "mission_explore" })
	end)

	it("resolves mission_event in a zoneless mission", function()
		local harness = in_mission(nil)

		harness:state("music_objective", "operation_stage_1")

		assert_equal(harness:current(), "mission_event")
	end)

	-- Spillway's mid-mission captain starts at the same moment as its kill event.
	it("resolves mission_event for a scripted boss that starts with its event", function()
		local harness = in_mission("zone_2_depths")
		local boss = harness:new_boss("renegade_captain")

		harness:state("music_objective", "kill_event")
		harness:boss_start(boss)
		harness:boss_end(boss)
		harness:state("music_objective", "None")

		assert_deep_equal(harness.changes, { "mission_event", "mission_explore" })
	end)

	-- Spillway's end event ends a few seconds before the wizard's encounter window closes.
	it("returns to explore, not mission_boss, when an event ends before its scripted boss's window closes", function()
		local harness = in_mission("zone_2_depths")
		local boss = harness:new_boss("renegade_wizard")

		harness:state("music_objective", "kill_event_3")
		harness:boss_start(boss)
		harness:wait(480)
		harness:state("music_objective", "None")
		harness:wait(9)
		harness:boss_end(boss)

		assert_deep_equal(harness.changes, { "mission_event", "mission_explore" })
	end)

	-- A monstrosity can spawn during a holdout and set the boss music state, and the game keeps playing event music.
	it("keeps mission_event over a monster that sets the boss music state during the event", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_spawn")
		harness:state("music_objective", "fortification_event")

		harness:state("music_combat", "boss")
		harness:boss_start(boss)

		assert_equal(harness:current(), "mission_event")

		harness:state("music_objective", "None")

		assert_equal(harness:current(), "mission_boss")
	end)

	it("follows a change from one event to the next without leaving mission_event", function()
		local harness = in_mission("zone_3")

		harness:state("music_objective", "fortification_event")
		harness:state("music_objective", "escape_event")

		assert_deep_equal(harness.changes, { "mission_event" })
	end)

	it("gives way to mission_victory", function()
		local harness = in_mission("zone_3")
		harness:state("music_objective", "escape_event")

		harness:state("music_game_state", "victory")

		assert_deep_equal(harness.changes, { "mission_event", "mission_victory" })
	end)

	it("resolves no event outside the hub and missions", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:state("music_objective", "end_event")

		assert_deep_equal(harness.changes, {})
	end)
end)
