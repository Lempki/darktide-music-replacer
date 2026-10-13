-- Pins how context.lua resolves Meat Grinder, which reports no zone and is recognized by its mission name.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has walked from the hub into Meat Grinder, in the order seen in diagnostic-2026-10-09.log.
local function in_meat_grinder(meat_grinder_music)
	local harness = Harness.new({ meat_grinder_music = meat_grinder_music })
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:wait(15)
	harness:mission("tg_shooting_range")
	harness:state("music_game_state", "mission")

	return harness
end

describe("context.lua Meat Grinder", function()
	it("resolves silence with the setting off, once the visit starts", function()
		local harness = in_meat_grinder(false)

		assert_deep_equal(harness.changes, { "hub", "nil", "silence" })
	end)

	it("stays on silence through combat and boss signals with the setting off", function()
		local harness = in_meat_grinder(false)
		local boss = harness:new_boss("chaos_ogryn_houndmaster")

		harness:boss_start(boss)
		harness:state("music_combat", "boss")
		harness:state("music_combat", "normal")

		assert_equal(harness:current(), "silence")
	end)

	it("resolves mission_explore and mission_combat with the setting on", function()
		local harness = in_meat_grinder(true)
		harness:clear_changes()

		harness:state("music_combat", "normal")

		assert_equal(harness:current(), "mission_combat")
	end)

	it("re-resolves at once when the setting changes during a visit", function()
		local harness = in_meat_grinder(false)
		harness:clear_changes()

		harness:set_setting("meat_grinder_music", true)
		harness:set_setting("meat_grinder_music", false)

		assert_deep_equal(harness.changes, { "mission_explore", "silence" })
	end)

	it("resolves hub after leaving", function()
		local harness = in_meat_grinder(false)
		harness:clear_changes()

		harness:state("music_game_state", "loading")
		harness:mission(nil)
		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "nil", "hub" })
	end)
end)
