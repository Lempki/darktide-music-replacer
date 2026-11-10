-- Pins how context.lua passes over a situation set to Skip, so the one ranked below it resolves instead.

local FakeEngine = require("tests.helpers.fake_engine")
local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission with a zone, with `settings` over the defaults.
local function in_mission(settings)
	local harness = Harness.new(settings)
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("lm_cooling", "zone_3")
	harness:clear_changes()

	return harness
end

describe("context.lua Skip", function()
	it("plays explore through a fight with combat skipped", function()
		local harness = in_mission({ source_combat = "skip" })

		harness:state("music_combat", "normal")

		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.Context.skipped(), { "combat" })
	end)

	it("plays combat through a horde with horde skipped, and keeps combat's hold after it", function()
		local harness = in_mission({ source_horde = "skip", combat_hold_seconds = 8 })

		harness:state("music_combat", "horde_high")
		assert_equal(harness:current(), "combat")
		assert_deep_equal(harness.Context.skipped(), { "horde" })

		harness:state("music_combat", "None")
		harness:wait(5)
		assert_equal(harness:current(), "combat")
		assert_deep_equal(harness.Context.skipped(), {})
	end)

	it("plays combat through a boss fight with boss skipped, since a boss fight is a fight", function()
		local harness = in_mission({ source_boss = "skip" })

		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "combat")
		assert_deep_equal(harness.Context.skipped(), { "boss" })
	end)

	it("plays explore through a boss fight with boss and combat skipped", function()
		local harness = in_mission({ source_boss = "skip", source_combat = "skip" })

		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.Context.skipped(), { "boss", "combat" })
	end)

	it("plays what ranks below through an event with event skipped, and holds no event after it", function()
		local harness = in_mission({ source_event = "skip" })

		harness:state("music_objective", "hacking_event")
		assert_equal(harness:current(), "explore")
		harness:state("music_combat", "normal")
		assert_equal(harness:current(), "combat")
		assert_deep_equal(harness.Context.skipped(), { "event" })

		harness:state("music_combat", "None")
		harness:state("music_objective", "None")
		harness:wait(30)
		assert_equal(harness:current(), "explore")
	end)

	it("plays what ranks below through a last stand with last stand skipped", function()
		local harness = in_mission({ source_last_stand = "skip" })

		harness:state("music_combat", "normal")
		harness:state("music_objective", "last_man_standing")

		assert_equal(harness:current(), "combat")
		assert_deep_equal(harness.Context.skipped(), { "last_stand" })
	end)

	it("takes over or gives way at once when the setting changes during its situation", function()
		local harness = in_mission()
		harness:state("music_combat", "boss")
		assert_equal(harness:current(), "boss")

		harness:set_setting("source_boss", "skip")
		assert_equal(harness:current(), "combat")

		harness:set_setting("source_boss", "custom")
		assert_equal(harness:current(), "boss")
	end)

	it("plays Mortis Trials' break through a wave with the wave skipped", function()
		local harness = Harness.new({ source_mortis_trials_wave = "skip" })
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("psykhanium", "horde_mode")

		harness:state("music_objective", "horde_mode_wave")

		assert_equal(harness:current(), "mortis_trials_break")
		assert_deep_equal(harness.Context.skipped(), { "mortis_trials_wave" })
	end)

	it("plays explore through an Expedition's fight and its extraction with both skipped", function()
		local harness = Harness.new({ source_expedition_combat = "skip", source_expedition_extraction = "skip" })
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("exp_wastes", "expeditions")

		harness:state("music_combat", "high_combat")
		assert_equal(harness:current(), "explore")

		harness:state("music_combat", "extraction")
		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.Context.skipped(), { "expedition_extraction" })
	end)

	it("ignores a stored Skip for a situation that does not offer it", function()
		local harness = in_mission({ source_explore = "skip" })

		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.Context.skipped(), {})
	end)
end)

describe("contexts.lua Skip", function()
	it("offers Skip for every ranked situation above the lowest rank", function()
		local Contexts = FakeEngine.new():load("contexts")
		local offered = {}
		for _, context in ipairs(Contexts.list) do
			if Contexts.can_skip(context.id) then
				offered[#offered + 1] = context.id
			end
		end

		assert_deep_equal(offered, {
			"combat", "horde", "boss", "event", "last_stand", "mortis_trials_wave", "expedition_combat", "expedition_extraction",
		})
	end)
end)
