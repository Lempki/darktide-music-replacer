-- Pins how context.lua resolves captains, which the game does not report as bosses.

local Harness = require("tests.helpers.context_harness")

local CAPTAINS = { "renegade_captain", "renegade_twin_captain", "renegade_twin_captain_two", "cultist_captain" }

-- Returns a harness that has just entered a mission, with the given settings.
local function in_mission(settings)
	local harness = Harness.new(settings)
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("lm_cooling", "zone_3")
	harness:clear_changes()

	return harness
end

describe("context.lua captains", function()
	it("resolves no boss for a captain by default", function()
		for _, breed in ipairs(CAPTAINS) do
			local harness = in_mission()
			local captain = harness:new_boss(breed)
			harness:state("music_combat", "normal")

			harness:boss_start(captain)

			assert_equal(harness:current(), "mission_combat", breed)
		end
	end)

	it("resolves mission_boss for every captain from its encounter start to its end with the setting on", function()
		for _, breed in ipairs(CAPTAINS) do
			local harness = in_mission({ captain_boss_music = true })
			local captain = harness:new_boss(breed)

			harness:boss_start(captain)

			assert_equal(harness:current(), "mission_boss", breed)

			harness:boss_end(captain)

			assert_equal(harness:current(), "mission_explore", breed)
		end
	end)

	-- Scripted captains appear during events, whose music wins over bosses.
	it("keeps event music for a captain during an event, even with the setting on", function()
		local harness = in_mission({ captain_boss_music = true })
		local captain = harness:new_boss("renegade_captain")

		harness:state("music_objective", "kill_event")
		harness:boss_start(captain)

		assert_deep_equal(harness.changes, { "mission_event" })
	end)

	it("re-resolves at once when the setting changes during the encounter", function()
		local harness = in_mission()
		local captain = harness:new_boss("cultist_captain")
		harness:boss_start(captain)

		harness:set_setting("captain_boss_music", true)
		harness:set_setting("captain_boss_music", false)

		assert_deep_equal(harness.changes, { "mission_boss", "mission_explore" })
	end)

	it("does not count Spillway's psyker, which is not a captain", function()
		local harness = in_mission({ captain_boss_music = true, daemonhost_boss_music = true })
		local wizard = harness:new_boss("renegade_wizard")

		harness:boss_start(wizard)

		assert_equal(harness:current(), "mission_explore")
	end)
end)
