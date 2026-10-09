-- Pins how context.lua resolves bosses from the boss music state and the boss encounter events.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission, with a zone when one is given.
local function in_mission(zone)
	local harness = Harness.new()
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission(zone and "lm_cooling" or "op_train", zone)
	harness:clear_changes()

	return harness
end

describe("context.lua boss signals", function()
	it("resolves mission_boss from the boss music state alone", function()
		local harness = in_mission("zone_3")

		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "mission_boss")
	end)

	-- Like renegade_captain and renegade_wizard, which never set the boss music state.
	it("resolves mission_boss from the encounter events alone, also in a zoneless mission", function()
		local harness = in_mission(nil)
		local boss = harness:new_boss("renegade_captain")

		harness:boss_start(boss)

		assert_equal(harness:current(), "mission_boss")
	end)

	-- dm_forge in diagnostic-2026-10-06.log had 79 seconds between the two signals.
	it("resolves mission_boss from the boss music state long before the start event", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_ogryn_houndmaster")

		harness:state("music_combat", "boss")
		harness:wait(79)
		harness:boss_start(boss)
		harness:boss_end(boss)
		harness:state("music_combat", "None")

		assert_deep_equal(harness.changes, { "mission_boss", "mission_explore" })
	end)

	-- A raid's final boss set the boss music state with no start event for about 12 minutes.
	it("keeps mission_boss for a boss with no start event until the boss music state ends", function()
		local harness = in_mission("zone_5")

		harness:state("music_combat", "boss")
		harness:wait(720)

		assert_equal(harness:current(), "mission_boss")

		harness:state("music_game_state", "victory")

		assert_deep_equal(harness.changes, { "mission_boss", "mission_victory" })
	end)

	-- chaos_beast_of_nurgle in diagnostic-2026-10-09.log left the boss music state 3 seconds before its end event.
	it("keeps mission_boss while the encounter is open after the boss music state ends", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_beast_of_nurgle")

		harness:state("music_combat", "boss")
		harness:boss_start(boss)
		harness:state("music_combat", "None")

		assert_equal(harness:current(), "mission_boss")

		harness:boss_end(boss)

		assert_equal(harness:current(), "mission_explore")
	end)

	-- The hold starts only from normal or horde combat, so a boss that ends straight into "None" gets none.
	it("follows a boss with mission_combat and its hold only when combat is still going", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_daemonhost")

		harness:boss_start(boss)
		harness:state("music_combat", "normal")
		harness:boss_end(boss)
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "mission_combat")

		harness:wait(0.3)

		assert_deep_equal(harness.changes, { "mission_boss", "mission_combat", "mission_explore" })
	end)

	it("reports the breed of the open encounter", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_daemonhost")

		harness:boss_start(boss)

		assert_deep_equal({ harness.Context.current() }, { "mission_boss", "chaos_daemonhost" })
	end)
end)

describe("context.lua boss encounter windows", function()
	-- The renegade_wizard encounter in diagnostic-2026-10-06.log lasted from 19:38:37 to 19:47:44.
	it("keeps a boss open for as long as the encounter lasts", function()
		local harness = in_mission("zone_2_depths")
		local boss = harness:new_boss("renegade_wizard")

		harness:boss_start(boss)
		harness:wait(547)

		assert_equal(harness:current(), "mission_boss")

		harness:boss_end(boss)

		assert_equal(harness:current(), "mission_explore")
	end)

	it("stays on mission_boss until every open boss has ended", function()
		local harness = in_mission("zone_3")
		local first = harness:new_boss("chaos_beast_of_nurgle")
		local second = harness:new_boss("chaos_plague_ogryn")

		harness:boss_start(first)
		harness:boss_start(second)
		harness:boss_end(first)

		assert_deep_equal({ harness.Context.current() }, { "mission_boss", "chaos_plague_ogryn" })

		harness:boss_end(second)

		assert_equal(harness:current(), "mission_explore")
	end)

	-- The daemonhost in diagnostic-2026-10-09.log fired two starts and one end.
	it("needs only one end event for a boss whose start event repeated", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_daemonhost")

		harness:boss_start(boss)
		harness:boss_start(boss)
		harness:boss_end(boss)

		assert_equal(harness:current(), "mission_explore")
	end)

	it("ignores an end event for a boss that has no open window", function()
		local harness = in_mission("zone_3")
		local open = harness:new_boss("renegade_captain")
		local other = harness:new_boss("chaos_spawn")

		harness:boss_start(open)
		harness:boss_end(other)

		assert_equal(harness:current(), "mission_boss")
	end)

	it("closes every window and clears the boss music state on a real zone change", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_spawn")

		harness:state("music_combat", "boss")
		harness:boss_start(boss)
		harness:state("music_zone", "hub")

		assert_equal(harness:current(), "hub")
	end)
end)

describe("context.lua bosses outside missions", function()
	-- The sequence from leaving Meat Grinder with its boss dummies, as logged on 2026-10-06, 2026-10-08, and 2026-10-09.
	it("resolves no context on the loading screen after Meat Grinder, with the boss music state stuck", function()
		local harness = Harness.new({ meat_grinder_music = false })
		local boss = harness:new_boss("chaos_ogryn_houndmaster")
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:mission("tg_shooting_range")
		harness:state("music_game_state", "mission")
		harness:boss_start(boss)
		harness:state("music_combat", "boss")
		harness:clear_changes()

		harness:boss_end(boss)
		harness:state("music_game_state", "loading")
		harness:mission(nil)

		assert_equal(harness:current(), nil)

		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "nil", "hub" })
	end)
end)
