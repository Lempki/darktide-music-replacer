-- Pins how context.lua resolves Meat Grinder, which reports no zone and is recognized by its mission name.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has walked from the hub into Meat Grinder.
-- `source` is the Meat Grinder setting: "custom", "game", or "silence".
local function in_meat_grinder(source)
	local harness = Harness.new({ source_meat_grinder = source })
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:wait(15)
	harness:mission("tg_shooting_range")
	harness:state("music_game_state", "mission")

	return harness
end

describe("context.lua Meat Grinder", function()
	it("resolves meat_grinder when set to silence, once the visit starts", function()
		local harness = in_meat_grinder("silence")

		assert_deep_equal(harness.changes, { "loading", "hub", "nil", "loading", "meat_grinder" })
	end)

	it("resolves meat_grinder when set to the game's own music", function()
		local harness = in_meat_grinder("game")

		assert_equal(harness:current(), "meat_grinder")
	end)

	it("stays on meat_grinder through combat and boss signals unless set to custom", function()
		local harness = in_meat_grinder("silence")
		local boss = harness:new_boss("chaos_ogryn_houndmaster")

		harness:boss_start(boss)
		harness:state("music_combat", "boss")
		harness:state("music_combat", "normal")

		assert_equal(harness:current(), "meat_grinder")
	end)

	it("resolves mission_explore and mission_combat when set to custom", function()
		local harness = in_meat_grinder("custom")
		harness:clear_changes()

		harness:state("music_combat", "normal")

		assert_equal(harness:current(), "mission_combat")
	end)

	it("re-resolves at once when the setting changes during a visit", function()
		local harness = in_meat_grinder("silence")
		harness:clear_changes()

		harness:set_setting("source_meat_grinder", "custom")
		harness:set_setting("source_meat_grinder", "silence")

		assert_deep_equal(harness.changes, { "mission_explore", "meat_grinder" })
	end)

	it("resolves hub after leaving", function()
		local harness = in_meat_grinder("silence")
		harness:clear_changes()

		harness:state("music_game_state", "loading")
		harness:mission(nil)
		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "loading", "hub" })
	end)
end)
