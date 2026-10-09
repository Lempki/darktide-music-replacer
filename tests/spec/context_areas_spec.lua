-- Pins how context.lua resolves the hub, missions, menus, and loading screens.

local Harness = require("tests.helpers.context_harness")

describe("context.lua areas", function()
	it("resolves hub on the first launch, as soon as the hub zone arrives", function()
		local harness = Harness.new()

		harness:cold_start_to_hub()

		assert_deep_equal(harness.changes, { "hub" })
	end)

	it("resolves no context in the title screen, the main menu, or the first loading screen", function()
		local harness = Harness.new()

		harness:state("music_game_state", "title")
		harness:state("music_game_state", "main_menu")
		harness:state("music_game_state", "loading")
		harness:wait(30)

		assert_equal(harness:current(), nil)
		assert_deep_equal(harness.changes, {})
	end)

	it("stays on hub while the mission board is used", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()

		harness:state("music_game_state", "mission_board")
		harness:state("music_game_state", "mission")
		harness:state("music_game_state", "mission_ready")

		assert_equal(harness:current(), "hub")
		assert_deep_equal(harness.changes, { "hub" })
	end)

	-- The zone clears one step before the loading state, so explore resolves for an instant.
	-- The debounce in MusicReplacer.lua keeps that instant from playing anything.
	it("passes through mission_explore for an instant when leaving the hub", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:clear_changes()

		harness:leave_hub()

		assert_deep_equal(harness.changes, { "mission_explore", "nil" })
	end)

	it("resolves no context through the loadout and the briefing until the zone arrives", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:state("music_game_state", "loadout")
		harness:wait(50)
		harness:state("music_game_state", "loading")
		harness:state("music_game_state", "mission_briefing")
		harness:wait(30)

		assert_equal(harness:current(), nil)
		assert_deep_equal(harness.changes, {})
	end)

	-- Seen in diagnostic-2026-10-09.log at 20:36:32, during the lm_cooling briefing.
	it("resolves mission_explore as soon as the mission zone arrives, still during the briefing", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:enter_mission("lm_cooling", "zone_3")

		assert_equal(harness:current(), "mission_explore")
		assert_deep_equal(harness.changes, { "mission_explore" })
	end)

	it("treats the zone \"None\" like no zone at all", function()
		local harness = Harness.new()

		harness:state("music_game_state", "loading")
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
