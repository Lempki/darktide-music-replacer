-- Pins how context.lua splits Mortis Trials into waves and the breaks between them.
-- The game marks Mortis Trials with its own music zone, and every wave, objective round, and the final win with music_objective.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered Mortis Trials.
local function in_mortis_trials()
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("psykhanium", "horde_mode")
	return harness
end

describe("context.lua Mortis Trials", function()
	it("resolves mortis_trials_break before the first wave", function()
		local harness = in_mortis_trials()

		assert_equal(harness:current(), "mortis_trials_break")
	end)

	it("switches between waves and breaks as the game sets and clears the wave music", function()
		local harness = in_mortis_trials()
		harness:clear_changes()

		harness:state("music_objective", "horde_mode_objective")
		harness:wait(100)
		harness:state("music_objective", "None")
		harness:wait(28)
		harness:state("music_objective", "horde_mode_wave")
		harness:wait(80)
		harness:state("music_objective", "None")
		harness:wait(18)
		harness:state("music_objective", "horde_mode_wave_last")
		harness:wait(200)
		harness:state("music_objective", "None")
		harness:wait(5)
		harness:state("music_objective", "horde_mode_win")
		harness:wait(14)
		harness:state("music_objective", "None")

		assert_deep_equal(harness.changes, {
			"mortis_trials_wave", "mortis_trials_break",
			"mortis_trials_wave", "mortis_trials_break",
			"mortis_trials_wave", "mortis_trials_break",
			"mortis_trials_wave", "mortis_trials_break",
		})
	end)

	it("keeps a wave through bosses, hordes, and combat", function()
		local harness = in_mortis_trials()
		harness:state("music_objective", "horde_mode_wave")
		harness:clear_changes()

		local spawn = harness:new_boss("chaos_spawn")
		harness:state("music_combat", "normal")
		harness:state("music_combat", "boss")
		harness:boss_start(spawn)
		harness:state("music_combat", "horde_high")
		harness:boss_end(spawn)
		harness:state("music_combat", "None")
		harness:wait(30)

		assert_deep_equal(harness.changes, {})
	end)

	it("keeps a break through combat and a boss that lingers from the wave", function()
		local harness = in_mortis_trials()
		local ogryn = harness:new_boss("chaos_plague_ogryn")
		harness:state("music_objective", "horde_mode_wave")
		harness:boss_start(ogryn)
		harness:state("music_combat", "boss")
		harness:state("music_objective", "None")
		harness:clear_changes()

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness:wait(30)

		assert_deep_equal(harness.changes, {})
		assert_equal(harness:current(), "mortis_trials_break")
	end)

	it("still gives way to a last stand, and returns to the wave after it", function()
		local harness = in_mortis_trials()
		harness:state("music_objective", "horde_mode_wave")
		harness:clear_changes()

		harness:state("music_objective", "last_man_standing")
		harness:state("music_objective", "horde_mode_wave")

		assert_deep_equal(harness.changes, { "mission_last_stand", "mortis_trials_wave" })
	end)

	it("ends with mission_victory", function()
		local harness = in_mortis_trials()
		harness:clear_changes()

		harness:end_with_victory("horde_mode")

		assert_equal(harness.changes[1], "mission_victory")
	end)

	it("plays a regular mission's explore music after Mortis Trials", function()
		local harness = in_mortis_trials()
		harness:end_with_victory("horde_mode")
		harness:arrive_in_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:enter_mission("lm_cooling", "zone_3")

		assert_equal(harness:current(), "mission_explore")
	end)
end)
