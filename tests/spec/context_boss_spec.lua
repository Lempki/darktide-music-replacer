-- Pins how context.lua resolves bosses from the boss encounter events, which open and close with a boss's HP bar.

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

describe("context.lua boss fights", function()
	it("resolves boss from a monstrosity's HP bar until its window closes", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_spawn")

		harness:boss_start(boss)
		assert_equal(harness:current(), "boss")

		harness:boss_end(boss)
		assert_deep_equal(harness.changes, { "boss", "explore" })
	end)

	it("resolves boss in a zoneless mission", function()
		local harness = in_mission(nil)

		harness:boss_start(harness:new_boss("chaos_spawn"))

		assert_equal(harness:current(), "boss")
	end)

	-- The game reports "boss" from the moment a monstrosity comes near, before anyone has hurt it.
	it("resolves no boss from the boss music state alone", function()
		local harness = in_mission("zone_3")

		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "explore")
	end)

	-- The game's boss music state can drop for a moment while the boss lives, which the window does not.
	it("keeps boss for as long as the window is open, whatever the boss music state does", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_ogryn_houndmaster")
		harness:combat({ boss_near = true })
		harness:boss_start(boss)

		harness:combat({})
		harness:wait(60)
		harness:combat({ boss_near = true })

		assert_deep_equal(harness.changes, { "boss" })
	end)

	it("plays the fight going on once the boss's window closes", function()
		local harness = in_mission("zone_3")
		local boss = harness:new_boss("chaos_spawn")
		harness:combat({ boss_near = true, intensity = 40 })
		harness:boss_start(boss)

		harness:boss_end(boss)

		assert_equal(harness:current(), "combat")
	end)

	it("stays on boss until every window that counts has closed", function()
		local harness = in_mission("zone_3")
		local first = harness:new_boss("chaos_spawn")
		local second = harness:new_boss("chaos_plague_ogryn")
		harness:boss_start(first)
		harness:boss_start(second)

		harness:boss_end(first)
		assert_equal(harness:current(), "boss")

		harness:boss_end(second)
		assert_equal(harness:current(), "explore")
	end)

	it("leaves out a weakened monstrosity, as the game's boss music does", function()
		local harness = in_mission("zone_3")

		harness:boss_start(harness:new_boss("chaos_spawn", { weakened = true }))

		assert_equal(harness:current(), "explore")
	end)

	-- Rodin Karnak in Spillway opens an encounter window, though his breed turns his HP bar off.
	it("leaves out a boss whose breed shows no HP bar", function()
		local harness = in_mission("zone_2_depths", { captain_boss_music = true, daemonhost_boss_music = true })

		harness:boss_start(harness:new_boss("renegade_wizard"))

		assert_equal(harness:current(), "explore")
	end)

	-- renegade_captain gets no boss music in the game, so its window counts only with its setting on.
	it("resolves no boss from a captain's window with its setting off", function()
		local harness = in_mission("zone_2_depths")

		harness:boss_start(harness:new_boss("renegade_captain"))

		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.changes, {})
	end)

	it("resolves no boss in an Expedition, which keeps to its own situations", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("exp_wastes", "expeditions")
		harness.engine:set_mission("exp_wastes", { game_mode_name = "expedition" })
		harness:tick(0)
		harness:state("music_combat", "no_combat")

		harness:boss_start(harness:new_boss("chaos_spawn"))

		assert_equal(harness:current(), "explore")
	end)

	it("offers the breed of the first open window as the boss's override folder, until that window closes", function()
		local harness = in_mission("zone_3")
		local first = harness:new_boss("chaos_spawn")
		local second = harness:new_boss("chaos_plague_ogryn")

		harness:boss_start(first)
		harness:boss_start(second)
		local while_first = harness.Context.override_keys(harness.engine.mod, "boss")[1]
		harness:boss_end(first)
		local after_first = harness.Context.override_keys(harness.engine.mod, "boss")[1]

		assert_equal(while_first, "chaos_spawn")
		assert_equal(after_first, "chaos_plague_ogryn")
	end)

	-- The log names the breed of a change, and a window left open under an event says nothing about the event's music.
	it("names the boss's breed only for a change to boss, not for an event while its window is open", function()
		local harness = in_mission("zone_3")
		local breeds = {}
		harness.Context.on_change(function(new_context, _, boss_breed)
			breeds[#breeds + 1] = tostring(new_context) .. "=" .. tostring(boss_breed)
		end)

		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:state("music_objective", "kill_event")

		assert_deep_equal(breeds, { "boss=chaos_spawn", "event=nil" })
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

	-- The mutators' daemonhost shows no HP bar, so it never counts.
	it("counts every daemonhost breed that shows an HP bar with the setting on", function()
		for _, breed in ipairs({ "chaos_daemonhost", "chaos_daemonhost_torment" }) do
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

-- These use a daemonhost with its setting on, whose window opens as it notices the player.
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

describe("context.lua combat under the game's boss state", function()
	it("leaves the game's own combat state as it is", function()
		local harness = in_mission("zone_3")

		assert_equal(harness:combat({ boss_near = true, intensity = 40 }), "boss")
		assert_equal(harness.engine:wwise_state("music_combat"), "boss")
	end)

	it("logs once when the game's combat check fails without the boss, and counts no fight under it", function()
		local lines = {}
		local harness = Harness.new({ source_boss = "skip" }, function(line) lines[#lines + 1] = line end)
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		local broken = function() error("no intensity", 0) end
		local extension = { boss_near = function() return true end, intensity_percent = broken, horde_near = broken }
		local check = package.loaded["scripts/managers/wwise_game_sync/wwise_state_groups/wwise_state_group_combat"]._default_wwise_state

		assert_equal(check({ _music_parameter_extension = extension }), "boss")
		check({ _music_parameter_extension = extension })
		harness:state("music_combat", "boss")

		assert_deep_equal(lines, { "[context] could not read the combat under the game's boss state: no intensity" })
		assert_equal(harness:current(), "explore")
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
