-- Pins how context.lua resolves a mission that never reports a zone and is not an Operation.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a zoneless mission.
local function in_zoneless_mission()
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("zoneless_mission", nil)

	return harness
end

describe("context.lua zoneless missions", function()
	it("resolves no context through the briefing and the intro", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:state("music_game_state", "mission_briefing")
		harness:mission("zoneless_mission")
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

	-- With no zone change between two zoneless levels, only the loading screen can end a window whose end event never came.
	it("does not carry a boss window across a loading screen into the next zoneless mission", function()
		local harness = Harness.new({ captain_boss_music = true })
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("zoneless_mission", nil)
		harness:boss_start(harness:new_boss("renegade_captain"))
		assert_equal(harness:current(), "mission_boss")

		harness:state("music_game_state", "loading")
		harness:mission(nil)
		harness:enter_mission("zoneless_mission", nil)

		assert_equal(harness:current(), "mission_explore")
	end)

	-- A zoneless mission's victory has no zone change to end it.
	it("ends with mission_victory and does not fall back to mission_explore in the transient mission state", function()
		local harness = in_zoneless_mission()
		harness:clear_changes()

		harness:end_with_victory(nil)
		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "mission_victory", "nil", "hub" })
	end)
end)
