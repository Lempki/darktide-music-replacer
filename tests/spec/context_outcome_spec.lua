-- Pins how context.lua resolves mission endings and cutscenes.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission with a zone.
local function in_mission()
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("lm_cooling", "zone_3")
	harness:clear_changes()

	return harness
end

describe("context.lua mission endings", function()
	-- The order seen in diagnostic-2026-10-09.log from 20:58:12.
	it("plays mission_victory from victory through the score screen, then nothing while loading, then hub", function()
		local harness = in_mission()

		harness:end_with_victory("zone_3")

		assert_equal(harness:current(), nil)

		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "mission_victory", "nil", "hub" })
	end)

	it("resolves mission_victory over combat and boss signals that are still set", function()
		local harness = in_mission()
		local boss = harness:new_boss("chaos_beast_of_nurgle")
		harness:state("music_combat", "boss")
		harness:boss_start(boss)
		harness:clear_changes()

		harness:state("music_game_state", "victory")

		assert_deep_equal(harness.changes, { "mission_victory" })
	end)

	-- The order seen in diagnostic-2026-10-09.log from 20:33:14.
	it("plays mission_defeat from defeat through the score screen, then nothing while loading, then hub", function()
		local harness = in_mission()

		harness:end_with_defeat()

		assert_equal(harness:current(), nil)

		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "mission_defeat", "nil", "hub" })
	end)

	it("resolves mission_defeat over a boss encounter that a wipe left open", function()
		local harness = in_mission()
		local boss = harness:new_boss("renegade_wizard")
		harness:boss_start(boss)
		harness:clear_changes()

		harness:state("music_game_state", "defeat")

		assert_deep_equal(harness.changes, { "mission_defeat" })
	end)

	-- The order seen in diagnostic-2026-10-04.log from 20:40:22, after fm_cargo.
	it("resolves no context during a debrief cutscene, and hub once it ends", function()
		local harness = in_mission()

		harness:end_with_victory("zone_3")
		harness:debrief_cutscene_to_hub()

		assert_deep_equal(harness.changes, { "mission_victory", "nil", "hub" })
	end)

	-- The order seen in diagnostic-2026-10-04.log from 21:38:28, after the story mission fm_resurgence.
	-- The score screen goes straight into the cutscene, with no loading screen to clear the outcome.
	it("does not carry mission_victory into the hub after a story mission's cutscene", function()
		local harness = in_mission()

		harness:state("music_game_state", "victory")
		harness:wait(8)
		harness:state("music_game_state", "mission")
		harness:state("music_zone", "None")
		harness:state("music_game_state", "game_score_win")
		harness:wait(56)
		harness:state("music_game_state", "cinematic")

		assert_equal(harness:current(), nil)

		harness:wait(11)
		harness:state("music_zone", "hub")
		harness:mission("hub_ship")
		harness:wait(41)
		harness:state("music_game_state", "mission")

		assert_deep_equal(harness.changes, { "mission_victory", "nil", "hub" })
	end)

	it("clears the outcome when the next mission's intro starts", function()
		local harness = in_mission()
		harness:state("music_game_state", "victory")
		harness:clear_changes()

		harness:state("music_game_state", "mission_intro")
		harness:state("music_game_state", "mission")

		assert_equal(harness:current(), "mission_explore")
	end)
end)
