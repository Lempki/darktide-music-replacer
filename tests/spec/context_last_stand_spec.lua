-- Pins how context.lua resolves the last stand, when the game sets music_objective to "last_man_standing".

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission, with a zone when one is given.
local function in_mission(zone)
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission(zone and "lm_cooling" or "zoneless_mission", zone)
	harness:clear_changes()

	return harness
end

describe("context.lua last stand", function()
	it("resolves mission_last_stand over explore", function()
		local harness = in_mission("zone_3")

		harness:state("music_objective", "last_man_standing")

		assert_deep_equal(harness.changes, { "mission_last_stand" })
	end)

	it("resolves mission_last_stand over combat and a horde", function()
		local harness = in_mission("zone_3")
		harness:state("music_combat", "horde_high")

		harness:state("music_objective", "last_man_standing")

		assert_equal(harness:current(), "mission_last_stand")
	end)

	it("resolves mission_last_stand in a zoneless mission", function()
		local harness = in_mission(nil)

		harness:state("music_objective", "last_man_standing")

		assert_equal(harness:current(), "mission_last_stand")
	end)

	-- In the game, last stand music replaces boss music, and boss music returns after a rescue while the bosses live.
	it("resolves mission_last_stand over bosses, and mission_boss again once it ends with the bosses alive", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_beast_of_nurgle")
		harness:state("music_combat", "boss")
		harness:boss_start(boss)

		harness:state("music_objective", "last_man_standing")
		harness:wait(60)
		harness:state("music_objective", "None")

		assert_deep_equal(harness.changes, { "mission_boss", "mission_last_stand", "mission_boss" })
	end)

	it("returns to mission_combat and its hold once it ends during combat", function()
		local harness = in_mission("zone_3")
		harness:state("music_combat", "normal")

		harness:state("music_objective", "last_man_standing")
		harness:state("music_objective", "None")
		harness:state("music_combat", "None")
		harness:wait(8.2)

		assert_deep_equal(harness.changes, { "mission_combat", "mission_last_stand", "mission_combat", "mission_explore" })
	end)

	it("gives way to mission_defeat when the last player falls", function()
		local harness = in_mission("zone_3")
		harness:state("music_objective", "last_man_standing")

		harness:end_with_defeat()

		assert_deep_equal(harness.changes, { "mission_last_stand", "mission_defeat", "loading" })
	end)

	it("gives way to mission_victory", function()
		local harness = in_mission("zone_3")
		harness:state("music_objective", "last_man_standing")

		harness:state("music_game_state", "victory")

		assert_deep_equal(harness.changes, { "mission_last_stand", "mission_victory" })
	end)

	-- The game replaces event music with last stand music in the same state group, and returns to the event afterward.
	it("replaces mission_event, and gives it back once the last stand ends", function()
		local harness = in_mission("zone_2_depths")
		harness:state("music_objective", "kill_event_3")

		harness:state("music_objective", "last_man_standing")
		harness:state("music_objective", "kill_event_3")

		assert_deep_equal(harness.changes, { "mission_event", "mission_last_stand", "mission_event" })
	end)
end)
