-- Pins how context.lua resolves bosses from the boss music state and the boss encounter events.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission, with a zone when one is given.
local function in_mission(zone, settings)
	local harness = Harness.new(settings)
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission(zone and "lm_cooling" or "zoneless_mission", zone)
	harness:clear_changes()

	return harness
end

describe("context.lua boss signals", function()
	it("resolves boss from the boss music state", function()
		local harness = in_mission("zone_3")

		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "boss")
	end)

	it("resolves boss from the boss music state in a zoneless mission", function()
		local harness = in_mission(nil)

		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "boss")
	end)

	-- renegade_captain and renegade_wizard never set the boss music state, and the game plays no boss music for them.
	it("resolves no boss from the encounter events alone", function()
		local harness = in_mission("zone_2_depths")
		local boss = harness:new_boss("renegade_captain")

		harness:boss_start(boss)

		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.changes, {})
	end)

	-- The boss music state can come more than a minute before the encounter start event.
	it("resolves boss from the boss music state long before the start event", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_ogryn_houndmaster")

		harness:state("music_combat", "boss")
		harness:wait(79)
		harness:boss_start(boss)
		harness:boss_end(boss)
		harness:state("music_combat", "None")

		assert_deep_equal(harness.changes, { "boss", "explore" })
	end)

	-- The boss music state can stay on for minutes with no start event, as it does for a raid's final boss.
	it("keeps boss for a boss with no start event until the boss music state ends", function()
		local harness = in_mission("zone_5")

		harness:state("music_combat", "boss")
		harness:wait(720)

		assert_equal(harness:current(), "boss")

		harness:state("music_game_state", "victory")

		assert_deep_equal(harness.changes, { "boss", "victory" })
	end)

	-- The combat hold starts only from normal or horde combat, so a boss that ends straight into "None" gets only its own hold.
	it("follows a boss with combat and its hold only when combat is still going", function()
		local harness = in_mission("zone_3")

		harness:state("music_combat", "boss")
		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness:wait(7.8)

		assert_equal(harness:current(), "combat")

		harness:wait(0.3)

		assert_deep_equal(harness.changes, { "boss", "combat", "explore" })
	end)

	it("offers the breed of the latest open encounter as the boss's override folder", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_spawn")

		harness:state("music_combat", "boss")
		harness:boss_start(boss)

		assert_equal(harness:current(), "boss")
		assert_equal(harness.Context.override_keys(harness.engine.mod, "boss")[1], "chaos_spawn")
	end)
end)

describe("context.lua boss hold", function()
	-- The game can drop the boss music state for a second or two while the boss is still alive.
	it("holds boss through a short gap in the boss music state while the boss's window is open", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_ogryn_houndmaster")
		harness:state("music_combat", "boss")
		harness:boss_start(boss)

		harness:state("music_combat", "None")
		harness:wait(2.8)
		assert_equal(harness:current(), "boss")

		harness:state("music_combat", "boss")
		assert_deep_equal(harness.changes, { "boss" })
	end)

	it("lets the hold run out after the setting's seconds", function()
		local harness = in_mission("zone_3", { boss_hold_seconds = 5 })
		harness:state("music_combat", "boss")

		harness:state("music_combat", "None")
		harness:wait(4.8)
		assert_equal(harness:current(), "boss")

		harness:wait(0.3)
		assert_deep_equal(harness.changes, { "boss", "explore" })
	end)

	-- A monstrosity can leave the boss music state a few seconds before its encounter end event.
	it("ends the hold at once when the boss's window closes", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_beast_of_nurgle")
		harness:state("music_combat", "boss")
		harness:boss_start(boss)
		harness:state("music_combat", "None")

		harness:boss_end(boss)

		assert_equal(harness:current(), "explore")
	end)

	it("adds no hold when the boss's window closes before the boss music state ends", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_spawn")
		harness:state("music_combat", "boss")
		harness:boss_start(boss)

		harness:boss_end(boss)
		harness:state("music_combat", "normal")

		assert_equal(harness:current(), "combat")
	end)

	it("keeps holding while another boss's window is still open", function()
		local harness = in_mission("zone_3")
		local first = harness:new_boss("chaos_spawn")
		local second = harness:new_boss("chaos_plague_ogryn")
		harness:state("music_combat", "boss")
		harness:boss_start(first)
		harness:boss_start(second)
		harness:state("music_combat", "None")

		harness:boss_end(first)

		assert_equal(harness:current(), "boss")
	end)

	it("ignores the window of a daemonhost that plays no boss music", function()
		local harness = in_mission("zone_3")
		local daemonhost = harness:new_boss("chaos_daemonhost")
		harness:boss_start(daemonhost)
		harness:state("music_combat", "boss")
		harness:state("music_combat", "None")

		harness:boss_end(daemonhost)

		assert_equal(harness:current(), "boss")
	end)

	it("holds again in the next boss fight after the last boss died", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_spawn")
		harness:state("music_combat", "boss")
		harness:boss_start(boss)
		harness:boss_end(boss)
		harness:state("music_combat", "None")

		harness:state("music_combat", "boss")
		harness:state("music_combat", "None")

		assert_equal(harness:current(), "boss")
		assert_deep_equal(harness.changes, { "boss", "explore", "boss" })
	end)

	it("keeps combat's own hold running under the held boss", function()
		local harness = in_mission("zone_3")
		harness:state("music_combat", "boss")

		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")
		harness:wait(3.1)
		assert_equal(harness:current(), "combat")

		harness:wait(5)
		assert_deep_equal(harness.changes, { "boss", "combat", "explore" })
	end)

	it("follows the game exactly with the hold set to 0", function()
		local harness = in_mission("zone_3", { boss_hold_seconds = 0 })
		harness:state("music_combat", "boss")

		harness:state("music_combat", "None")

		assert_equal(harness:current(), "explore")
	end)
end)

describe("context.lua daemonhosts", function()
	it("resolves no boss for an angered daemonhost by default, as the game plays no music for it", function()
		local harness = in_mission("zone_3")
		local daemonhost = harness:new_boss("chaos_daemonhost")
		harness:state("music_combat", "normal")

		harness:boss_start(daemonhost)

		assert_equal(harness:current(), "combat")
	end)

	it("resolves boss for an angered daemonhost with the setting on", function()
		local harness = in_mission("zone_3", { daemonhost_boss_music = true })
		local daemonhost = harness:new_boss("chaos_daemonhost")

		harness:boss_start(daemonhost)

		assert_equal(harness:current(), "boss")

		harness:boss_end(daemonhost)

		assert_equal(harness:current(), "explore")
	end)

	it("re-resolves at once when the setting changes during the encounter", function()
		local harness = in_mission("zone_3")
		local daemonhost = harness:new_boss("chaos_daemonhost")
		harness:boss_start(daemonhost)

		harness:set_setting("daemonhost_boss_music", true)
		harness:set_setting("daemonhost_boss_music", false)

		assert_deep_equal(harness.changes, { "boss", "explore" })
	end)

	it("counts every daemonhost breed with the setting on", function()
		for _, breed in ipairs({ "chaos_daemonhost", "chaos_daemonhost_torment", "chaos_mutator_daemonhost" }) do
			local harness = in_mission("zone_3", { daemonhost_boss_music = true })
			local daemonhost = harness:new_boss(breed)

			harness:boss_start(daemonhost)

			assert_equal(harness:current(), "boss", breed)
		end
	end)

	it("counts only daemonhost windows, not other bosses' windows, with the setting on", function()
		local harness = in_mission("zone_2_depths", { daemonhost_boss_music = true })
		local captain = harness:new_boss("renegade_captain")

		harness:boss_start(captain)

		assert_equal(harness:current(), "explore")
	end)
end)

-- Encounter windows only decide a boss for daemonhosts with the setting on, so these use that setting.
describe("context.lua boss encounter windows", function()
	-- A daemonhost can stay angered for a long time while the players avoid it.
	it("keeps a window open for as long as the encounter lasts", function()
		local harness = in_mission("zone_3", { daemonhost_boss_music = true })
		local daemonhost = harness:new_boss("chaos_daemonhost")

		harness:boss_start(daemonhost)
		harness:wait(547)

		assert_equal(harness:current(), "boss")

		harness:boss_end(daemonhost)

		assert_equal(harness:current(), "explore")
	end)

	it("stays on boss until every open window has ended", function()
		local harness = in_mission("zone_3", { daemonhost_boss_music = true })
		local first = harness:new_boss("chaos_daemonhost")
		local second = harness:new_boss("chaos_daemonhost")

		harness:boss_start(first)
		harness:boss_start(second)
		harness:boss_end(first)

		assert_equal(harness:current(), "boss")

		harness:boss_end(second)

		assert_equal(harness:current(), "explore")
	end)

	-- The game can send the start event more than once for one boss.
	it("needs only one end event for a window whose start event repeated", function()
		local harness = in_mission("zone_3", { daemonhost_boss_music = true })
		local daemonhost = harness:new_boss("chaos_daemonhost")

		harness:boss_start(daemonhost)
		harness:boss_start(daemonhost)
		harness:boss_end(daemonhost)

		assert_equal(harness:current(), "explore")
	end)

	it("ignores an end event for a boss that has no open window", function()
		local harness = in_mission("zone_3", { daemonhost_boss_music = true })
		local daemonhost = harness:new_boss("chaos_daemonhost")
		local other = harness:new_boss("chaos_daemonhost")

		harness:boss_start(daemonhost)
		harness:boss_end(other)

		assert_equal(harness:current(), "boss")
	end)

	it("closes every window and clears the boss music state on a real zone change", function()
		local harness = in_mission("zone_3", { daemonhost_boss_music = true })
		local daemonhost = harness:new_boss("chaos_daemonhost")

		harness:state("music_combat", "boss")
		harness:boss_start(daemonhost)
		harness:state("music_zone", "hub")

		assert_equal(harness:current(), "hub")
	end)
end)

describe("context.lua bosses outside missions", function()
	-- Meat Grinder's boss dummies leave the boss music state set after leaving, until the next mission's intro ends.
	it("resolves loading, not a boss, on the loading screen after Meat Grinder, with the boss music state stuck", function()
		local harness = Harness.new({ source_meat_grinder = "silence" })
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

		assert_equal(harness:current(), "loading")

		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "loading", "hub" })
	end)
end)
