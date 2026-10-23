-- Pins how context.lua resolves mission event music, which the game sets in music_objective.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission, with a zone when one is given.
local function in_mission(zone)
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission(zone and "fm_cargo" or "zoneless_mission", zone)
	harness:clear_changes()

	return harness
end

describe("context.lua mission events", function()
	it("resolves event over explore and combat while the event lasts, then follows the other states again", function()
		local harness = in_mission("zone_3")
		harness:state("music_combat", "normal")

		harness:state("music_objective", "hacking_event")
		harness:state("music_combat", "None")
		harness:wait(120)
		harness:state("music_objective", "None")
		harness:wait(5.1)

		assert_deep_equal(harness.changes, { "combat", "event", "explore" })
	end)

	it("resolves event in a zoneless mission", function()
		local harness = in_mission(nil)

		harness:state("music_objective", "operation_stage_1")

		assert_equal(harness:current(), "event")
	end)

	-- Spillway's mid-mission captain starts at the same moment as its kill event.
	it("resolves event for a scripted boss that starts with its event", function()
		local harness = in_mission("zone_2_depths")
		local boss = harness:new_boss("renegade_captain")

		harness:state("music_objective", "kill_event")
		harness:boss_start(boss)
		harness:boss_end(boss)
		harness:state("music_objective", "None")
		harness:wait(5.1)

		assert_deep_equal(harness.changes, { "event", "explore" })
	end)

	-- Spillway's end event ends a few seconds before Rodin Karnak's encounter window closes.
	it("returns to explore, not boss, when an event ends before its scripted boss's window closes", function()
		local harness = in_mission("zone_2_depths")
		local boss = harness:new_boss("renegade_wizard")

		harness:state("music_objective", "kill_event_3")
		harness:boss_start(boss)
		harness:wait(480)
		harness:state("music_objective", "None")
		harness:wait(9)
		harness:boss_end(boss)

		assert_deep_equal(harness.changes, { "event", "explore" })
	end)

	-- A monstrosity can spawn during a holdout and set the boss music state, and the game keeps playing event music.
	it("keeps event over a monster that sets the boss music state during the event", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_spawn")
		harness:state("music_objective", "fortification_event")

		harness:state("music_combat", "boss")
		harness:boss_start(boss)

		assert_equal(harness:current(), "event")

		harness:state("music_objective", "None")
		harness:wait(5.1)

		assert_equal(harness:current(), "boss")
	end)

	-- Cargo's end event clears its music for 1, 1, and 4 seconds between stages, then for 10 seconds before the escape.
	it("holds event through short gaps between an event's stages, and lets a longer gap end the event", function()
		local harness = in_mission("zone_3")

		harness:state("music_objective", "fortification_event")
		for _, gap in ipairs({ 1, 1, 4 }) do
			harness:wait(60)
			harness:state("music_objective", "None")
			harness:wait(gap)
			harness:state("music_objective", "fortification_event")
		end
		assert_deep_equal(harness.changes, { "event" })

		harness:wait(60)
		harness:state("music_objective", "None")
		harness:wait(10)
		harness:state("music_objective", "escape_event")

		assert_deep_equal(harness.changes, { "event", "explore", "event" })
	end)

	it("holds for as long as the setting says, and follows the game at once at 0", function()
		local harness = in_mission("zone_3")
		harness:set_setting("event_hold_seconds", 0)

		harness:state("music_objective", "fortification_event")
		harness:state("music_objective", "None")

		assert_deep_equal(harness.changes, { "event", "explore" })

		harness:set_setting("event_hold_seconds", 12)
		harness:state("music_objective", "fortification_event")
		harness:state("music_objective", "None")
		harness:wait(11.9)
		assert_equal(harness:current(), "event")
		harness:wait(0.2)
		assert_equal(harness:current(), "explore")
	end)

	it("shortens a running event hold at once when its setting is lowered", function()
		local harness = in_mission("zone_3")
		harness:set_setting("event_hold_seconds", 30)
		harness:state("music_objective", "fortification_event")
		harness:state("music_objective", "None")
		harness:wait(1)

		-- Written straight into the settings, as the mod options do, with no refresh, since the hold settings ask for none.
		harness.settings.event_hold_seconds = 0
		harness:wait(0.1)

		assert_equal(harness:current(), "explore")
	end)

	it("lets a last stand take over during the hold, and still ends the event once the hold runs out", function()
		local harness = in_mission("zone_3")
		harness:state("music_objective", "fortification_event")
		harness:state("music_objective", "None")
		harness:wait(1)

		harness:state("music_objective", "last_man_standing")
		harness:wait(10)
		harness:state("music_objective", "None")

		assert_deep_equal(harness.changes, { "event", "last_stand", "explore" })
	end)

	it("follows a change from one event to the next without leaving event", function()
		local harness = in_mission("zone_3")

		harness:state("music_objective", "fortification_event")
		harness:state("music_objective", "escape_event")

		assert_deep_equal(harness.changes, { "event" })
	end)

	it("gives way to victory", function()
		local harness = in_mission("zone_3")
		harness:state("music_objective", "escape_event")

		harness:state("music_game_state", "victory")

		assert_deep_equal(harness.changes, { "event", "victory" })
	end)

	it("resolves the hub even when quitting mid-event left the event music set", function()
		local harness = in_mission("zone_3")
		harness:state("music_objective", "fortification_event")

		harness:state("music_zone", "None")
		harness:state("music_game_state", "loading")
		harness:mission(nil)
		harness:arrive_in_hub()

		assert_equal(harness:current(), "hub")
	end)

	it("resolves no event outside the hub and missions", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:clear_changes()

		harness:state("music_objective", "end_event")

		assert_deep_equal(harness.changes, {})
	end)
end)
