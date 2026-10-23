-- Pins how context.lua resolves an Expedition with its heat on, which reports its own states in music_combat.
-- The heat system rates fights as low_combat, med_combat, or high_combat, and also reports safe rooms and the extraction.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered an Expedition.
local function in_expedition(settings)
	local harness = Harness.new(settings)
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("exp_wastes", "expeditions")
	harness:state("music_combat", "no_combat")
	harness:clear_changes()

	return harness
end

describe("context.lua Expeditions with the heat on", function()
	it("resolves explore while calm, and expedition_combat at every fight level", function()
		local harness = in_expedition({ combat_hold_seconds = 0 })
		assert_equal(harness:current(), "explore")

		for _, level in ipairs({ "low_combat", "med_combat", "high_combat" }) do
			harness:state("music_combat", level)
			assert_equal(harness:current(), "expedition_combat", level)
		end

		harness:state("music_combat", "no_combat")
		assert_equal(harness:current(), "explore")
	end)

	it("holds expedition_combat through a short lull for as long as the combat hold says", function()
		local harness = in_expedition({ combat_hold_seconds = 8 })

		harness:state("music_combat", "med_combat")
		harness:state("music_combat", "no_combat")
		harness:wait(7.8)
		assert_equal(harness:current(), "expedition_combat")

		harness:wait(0.3)
		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.changes, { "expedition_combat", "explore" })
	end)

	it("resolves expedition_safe_room in a safe room, and expedition_extraction once the extraction starts", function()
		local harness = in_expedition({ combat_hold_seconds = 0 })

		harness:state("music_combat", "safe_room")
		assert_equal(harness:current(), "expedition_safe_room")

		harness:state("music_combat", "high_combat")
		harness:state("music_combat", "extraction")
		assert_deep_equal(harness.changes, { "expedition_safe_room", "expedition_combat", "expedition_extraction" })
	end)

	it("lets a last stand take over from the extraction", function()
		local harness = in_expedition()
		harness:state("music_combat", "extraction")

		harness:state("music_objective", "last_man_standing")

		assert_equal(harness:current(), "last_stand")
	end)

	it("plays boss music over a fight only for an opted-in captain, since the heat system reports no boss", function()
		local harness = in_expedition({ captain_boss_music = true })
		harness:state("music_combat", "med_combat")

		harness:boss_start(harness:new_boss("renegade_captain"))

		assert_equal(harness:current(), "boss")
	end)
end)
