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

		assert_deep_equal(harness.changes, { "title_screen", "character_select", "loading", "hub" })
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

	it("resolves title_screen on the title screen, character_select on character select, and loading on the first loading screen", function()
		local harness = Harness.new()

		harness:state("music_game_state", "title")
		assert_equal(harness:current(), "title_screen")
		harness:state("music_game_state", "main_menu")
		harness:wait(10)

		assert_equal(harness:current(), "character_select")

		harness:state("music_game_state", "loading")
		harness:wait(30)

		assert_deep_equal(harness.changes, { "title_screen", "character_select", "loading" })
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
	it("resolves no context from the moment the zone clears when leaving the hub for a mission, then mission_briefing", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:leave_hub()

		assert_deep_equal(harness.changes, { "nil", "mission_briefing" })
	end)

	it("resolves loading, not mission_briefing, on the loading screens of starting the game and leaving a mission", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		harness:clear_changes()

		harness:end_with_victory("zone_3")

		assert_deep_equal(harness.changes, { "victory", "loading" })
	end)

	-- Joining a mission in progress skips the preparation screen and the briefing.
	it("resolves mission_briefing when joining a mission in progress, from the mission board's ready state", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:state("music_game_state", "mission_board")
		harness:state("music_game_state", "mission_ready")
		harness:state("music_game_state", "mission")
		harness:state("music_zone", "None")
		harness:state("music_game_state", "loading")
		harness:mission(nil)
		harness:wait(20)
		harness:state("music_zone", "zone_3")
		harness:mission("lm_cooling")
		harness:state("music_game_state", "mission")

		assert_deep_equal(harness.changes, { "nil", "mission_briefing", "explore" })
	end)

	-- Matchmaking that finds a mission returns the game state to "mission" for about a second before the loading screen.
	it("keeps the trip into a mission through the second between matchmaking and its loading screen", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:state("music_game_state", "mission_ready")
		harness:wait(16)
		harness:state("music_game_state", "mission")
		harness:wait(1)
		harness:state("music_zone", "None")
		harness:state("music_game_state", "loading")
		harness:mission(nil)

		assert_deep_equal(harness.changes, { "nil", "mission_briefing" })
	end)

	-- Matchmaking can end without a mission while the mission board is closed, as after a declined party vote.
	it("ends the trip once matchmaking ends without a mission, so the next plain loading screen resolves loading", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()

		harness:state("music_game_state", "mission_board")
		harness:state("music_game_state", "mission")
		harness:state("music_game_state", "mission_ready")
		harness:wait(30)
		harness:state("music_game_state", "mission")
		harness:wait(60)
		harness:clear_changes()

		harness:state("music_zone", "None")
		harness:state("music_game_state", "loading")
		harness:mission(nil)

		assert_deep_equal(harness.changes, { "nil", "loading" })
	end)

	-- Going back to character select leaves about a second between the two, longer than the debounce.
	it("resolves no context while leaving the hub, then character_select once character select opens", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:state("music_zone", "None")
		harness:wait(1)
		harness:state("music_game_state", "main_menu")

		assert_deep_equal(harness.changes, { "nil", "character_select" })
	end)

	it("keeps character_select while a character is created", function()
		local harness = Harness.new()
		harness:state("music_game_state", "title")
		harness:state("music_game_state", "main_menu")
		harness:clear_changes()

		harness:state("music_game_state", "character_creation")
		harness:state("music_game_state", "main_menu")

		assert_deep_equal(harness.changes, {})
		assert_equal(harness:current(), "character_select")
	end)

	it("resolves mission_preparation on the mission preparation screen, and mission_briefing again for the briefing", function()
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

		assert_equal(harness:current(), "mission_briefing")
		assert_deep_equal(harness.changes, { "mission_preparation", "mission_briefing" })
	end)

	-- The game sends a mission's zone partway through the briefing.
	it("stays on mission_briefing through the briefing once the mission zone has arrived, and resolves no context during the intro", function()
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

		assert_equal(harness:current(), "mission_briefing")

		harness:state("music_game_state", "mission_intro")

		assert_equal(harness:current(), nil)

		harness:state("music_game_state", "mission")

		assert_deep_equal(harness.changes, { "mission_preparation", "mission_briefing", "nil", "combat" })
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
