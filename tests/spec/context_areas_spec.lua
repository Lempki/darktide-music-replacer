-- Pins how context.lua resolves the hub, missions, menus, and loading screens.

local Harness = require("tests.helpers.context_harness")

describe("context.lua areas", function()
	-- The hub zone arrives about 10 seconds before the loading screen ends.
	it("resolves hub on the first launch once the loading screen ends, not when the hub zone arrives", function()
		local harness = Harness.new()

		harness:state("music_game_state", "title")
		harness:state("music_game_state", "main_menu")
		harness:state("music_game_state", "loading")
		harness:state("music_zone", "hub")
		harness:mission("hub_ship")
		harness:wait(10)

		assert_equal(harness:current(), "loading")

		harness:state("music_game_state", "mission")

		assert_deep_equal(harness.changes, { "loading", "hub" })
	end)

	it("resolves hub after a mission once the loading screen ends, not when the hub zone arrives", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		harness:end_with_victory("zone_3")
		harness:clear_changes()

		harness:wait(9)
		harness:state("music_zone", "hub")
		harness:mission("hub_ship")
		harness:wait(10)

		assert_equal(harness:current(), "loading")

		harness:state("music_game_state", "mission")

		assert_deep_equal(harness.changes, { "hub" })
	end)

	it("resolves no context in the title screen or the main menu, and loading on the first loading screen", function()
		local harness = Harness.new()

		harness:state("music_game_state", "title")
		harness:state("music_game_state", "main_menu")
		harness:wait(10)

		assert_equal(harness:current(), nil)

		harness:state("music_game_state", "loading")
		harness:wait(30)

		assert_deep_equal(harness.changes, { "loading" })
	end)

	it("stays on hub while the mission board is used", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:state("music_game_state", "mission_board")
		harness:state("music_game_state", "mission")
		harness:state("music_game_state", "mission_ready")

		assert_equal(harness:current(), "hub")
		assert_deep_equal(harness.changes, {})
	end)

	-- The zone clears one step before the game state changes, while the hub is still loaded.
	it("resolves no context from the moment the zone clears when leaving the hub for a mission, then loading", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:leave_hub()

		assert_deep_equal(harness.changes, { "nil", "loading" })
	end)

	-- Going back to character select leaves about a second between the two, longer than the debounce.
	it("resolves no context while leaving the hub for the main menu", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:state("music_zone", "None")
		harness:wait(1)
		harness:state("music_game_state", "main_menu")

		assert_deep_equal(harness.changes, { "nil" })
	end)

	it("resolves mission_preparation on the mission preparation screen, and loading again for the briefing", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:state("music_game_state", "loadout")
		harness:wait(50)

		assert_equal(harness:current(), "mission_preparation")

		harness:state("music_game_state", "loading")
		harness:state("music_game_state", "mission_briefing")
		harness:wait(30)

		assert_equal(harness:current(), "loading")
		assert_deep_equal(harness.changes, { "mission_preparation", "loading" })
	end)

	-- The game sends a mission's zone partway through the briefing.
	it("stays on loading through the briefing once the mission zone has arrived, and resolves no context during the intro", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:state("music_game_state", "loadout")
		harness:state("music_game_state", "loading")
		harness:state("music_game_state", "mission_briefing")
		harness:state("music_zone", "zone_3")
		harness:mission("lm_cooling")
		harness:state("music_combat", "normal")

		assert_equal(harness:current(), "loading")

		harness:state("music_game_state", "mission_intro")

		assert_equal(harness:current(), nil)

		harness:state("music_game_state", "mission")

		assert_deep_equal(harness.changes, { "mission_preparation", "loading", "nil", "mission_combat" })
	end)

	it("treats the zone \"None\" like no zone at all", function()
		local harness = Harness.new()

		harness:state("music_game_state", "mission")
		harness:state("music_zone", "None")

		assert_equal(harness:current(), nil)
	end)

	it("tolerates a missing mission manager before a level loads", function()
		local harness = Harness.new()

		harness:mission(nil)
		harness:wait(1)

		assert_equal(harness:current(), nil)
	end)
end)
