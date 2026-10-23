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
	it("stays on loading through the briefing, and resolves no context during the intro", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:state("music_game_state", "mission_briefing")
		harness:mission("zoneless_mission")
		harness:state("music_game_state", "mission_intro")

		assert_deep_equal(harness.changes, { "nil" })
	end)

	it("resolves explore once the game state returns to mission", function()
		local harness = in_zoneless_mission()

		assert_equal(harness:current(), "explore")
	end)

	it("switches between explore and combat with the hold", function()
		local harness = in_zoneless_mission()
		harness:clear_changes()

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness:wait(8.2)

		assert_deep_equal(harness.changes, { "combat", "explore" })
	end)

	-- With no zone change between two zoneless levels, only the loading screen can end a window whose end event never came.
	it("does not carry a boss window across a loading screen into the next zoneless mission", function()
		local harness = Harness.new({ captain_boss_music = true })
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("zoneless_mission", nil)
		harness:boss_start(harness:new_boss("renegade_captain"))
		assert_equal(harness:current(), "boss")

		harness:state("music_game_state", "loading")
		harness:mission(nil)
		harness:enter_mission("zoneless_mission", nil)

		assert_equal(harness:current(), "explore")
	end)

	-- Leaving the hub for character select clears the zone and unloads the hub, but leaves the game state on "mission" for a few seconds.
	it("resolves no mission when the hub is left for character select", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:state("music_zone", "None")
		harness:mission(nil)
		harness:wait(3)
		harness:state("music_game_state", "main_menu")
		harness:state("music_game_state", "loading")
		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "nil", "character_select", "loading", "hub" })
	end)

	-- A zoneless mission's victory has no zone change to end it.
	it("ends with victory and does not fall back to explore in the transient mission state", function()
		local harness = in_zoneless_mission()
		harness:clear_changes()

		harness:end_with_victory(nil)
		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "victory", "loading", "hub" })
	end)
end)
