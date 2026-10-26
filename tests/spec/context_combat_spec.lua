-- Pins how context.lua switches between explore and combat, including the combat hold.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission with a zone, with the given combat hold.
local function in_mission(hold_seconds)
	local harness = Harness.new({ combat_hold_seconds = hold_seconds })
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("lm_cooling", "zone_3")
	harness:clear_changes()

	return harness
end

describe("context.lua combat", function()
	it("switches to combat at once when combat starts", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")

		assert_deep_equal(harness.changes, { "combat" })
	end)

	it("holds combat for the full hold after combat goes quiet, then returns to explore", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:wait(3)
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "combat")

		harness:wait(0.3)

		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.changes, { "combat", "explore" })
	end)

	it("shortens a running hold at once when its setting is lowered, and ends it when set to 0", function()
		local harness = in_mission(30)
		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness:wait(1)

		-- Written straight into the settings, as the mod options do, with no refresh, since the hold settings ask for none.
		harness.settings.combat_hold_seconds = 2
		harness:wait(1.9)
		assert_equal(harness:current(), "combat")
		harness:wait(0.2)
		assert_equal(harness:current(), "explore")

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness.settings.combat_hold_seconds = 0
		harness:wait(0.1)
		assert_equal(harness:current(), "explore")
	end)

	it("reports the combat hold and its seconds left while it keeps combat", function()
		local harness = in_mission(8)
		harness:state("music_combat", "normal")
		assert_equal(harness.Context.hold(), nil)

		harness:state("music_combat", "None")
		harness:wait(3)

		local hold, seconds = harness.Context.hold()
		assert_equal(hold, "combat")
		assert_equal(math.abs(seconds - 5) < 0.15, true)

		harness:wait(5.2)
		assert_equal(harness.Context.hold(), nil)
	end)

	it("does not drain the hold while combat is still going", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:wait(60)
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "combat")
	end)

	it("counts the hold from the last time combat went quiet when combat flaps", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:wait(2)
		harness:state("music_combat", "None")
		harness:wait(5)
		harness:state("music_combat", "normal")
		harness:wait(1)
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "combat")

		harness:wait(0.3)

		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.changes, { "combat", "explore" })
	end)

	it("returns to explore at once with a hold of zero", function()
		local harness = in_mission(0)

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")

		assert_deep_equal(harness.changes, { "combat", "explore" })
	end)

	it("drops the hold on a real zone change", function()
		local harness = in_mission(8)

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness:state("music_zone", "zone_4")

		assert_equal(harness:current(), "explore")
	end)
end)

describe("context.lua unknown combat states", function()
	-- A value the game adds later must not be silenced under an explore song, so the game's own music for it plays.
	it("hands an unknown music_combat value to the game's music, and logs it once", function()
		local lines = {}
		local harness = Harness.new({ combat_hold_seconds = 0 }, function(line) lines[#lines + 1] = line end)
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		assert_equal(harness:current(), "explore")

		harness:state("music_combat", "new_state")
		assert_equal(harness:current(), nil)

		harness:state("music_combat", "None")
		assert_equal(harness:current(), "explore")
		harness:state("music_combat", "new_state")

		assert_deep_equal(lines, { "[context] music_combat has a value the mod does not know, new_state, so the game's music plays" })
	end)

	it("still plays event and last stand music over an unknown value", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		harness:state("music_combat", "new_state")

		harness:state("music_objective", "kill_event")
		assert_equal(harness:current(), "event")

		harness:state("music_objective", "last_man_standing")
		assert_equal(harness:current(), "last_stand")
	end)

	it("gives the debug overlay a reason while no situation resolves", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		assert_equal(harness.Context.idle_reason(), nil)

		harness:state("music_combat", "new_state")
		assert_equal(harness.Context.idle_reason(), "unknown_state")

		harness:state("music_combat", "None")
		harness:state("music_game_state", "cinematic")
		assert_equal(harness.Context.idle_reason(), "cutscene")
	end)

	it("knows every value the game sends today, the Expedition ones included", function()
		local harness = Harness.new({ combat_hold_seconds = 0 })
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("exp_wastes", "expeditions")

		for _, state in ipairs({ "no_combat", "low_combat", "med_combat", "high_combat", "safe_room", "extraction" }) do
			harness:state("music_combat", state)
			assert_equal(harness:current() ~= nil, true, state)
		end
	end)
end)
