-- Pins how context.lua resolves boss_approaching from each boss's distance, as bosses.lua reads it.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has just entered a mission.
local function in_mission(settings)
	local harness = Harness.new(settings)
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("lm_cooling", "zone_3")
	harness:clear_changes()

	return harness
end

local SPAWN = "unit_spawn"
local OGRYN = "unit_ogryn"
local DAEMONHOST = "unit_daemonhost"

local function spawn_at(distance)
	return { unit = SPAWN, breed = "chaos_spawn", distance = distance }
end

describe("context.lua boss_approaching", function()
	it("resolves boss_approaching once a boss is within 80 m, and not before", function()
		local harness = in_mission()

		harness:bosses({ spawn_at(81) })
		assert_equal(harness:current(), "explore")

		harness:bosses({ spawn_at(80) })
		assert_equal(harness:current(), "boss_approaching")
	end)

	it("keeps a boss approaching until it is farther than 120 m", function()
		local harness = in_mission()

		harness:bosses({ spawn_at(60) })
		harness:bosses({ spawn_at(100) })
		harness:bosses({ spawn_at(120) })
		assert_equal(harness:current(), "boss_approaching")

		harness:bosses({ spawn_at(121) })
		assert_deep_equal(harness.changes, { "boss_approaching", "explore" })

		-- Once let go, the boss has to come within 80 m again.
		harness:bosses({ spawn_at(100) })
		assert_equal(harness:current(), "explore")
	end)

	it("lets go of a boss the game no longer lists, as once it has died", function()
		local harness = in_mission()

		harness:bosses({ spawn_at(30) })
		harness:bosses({})

		assert_deep_equal(harness.changes, { "boss_approaching", "explore" })
	end)

	it("keeps a boss as it was while its distance is unknown", function()
		local harness = in_mission()

		harness:bosses({ spawn_at(30) })
		harness:bosses({ spawn_at(nil) })

		assert_equal(harness:current(), "boss_approaching")
	end)

	it("ranks above a horde, and below the boss music state", function()
		local harness = in_mission()

		harness:state("music_combat", "horde_high")
		harness:bosses({ spawn_at(30) })
		assert_equal(harness:current(), "boss_approaching")

		harness:state("music_combat", "boss")
		assert_equal(harness:current(), "boss")
	end)

	it("plays whatever ranks below while it is set to Skip", function()
		local harness = in_mission({ source_boss_approaching = "skip" })

		harness:state("music_combat", "horde_high")
		harness:bosses({ spawn_at(30) })

		assert_equal(harness:current(), "horde")
	end)

	it("leaves weakened monstrosities out, as the game's boss music does", function()
		local harness = in_mission()

		harness:bosses({ { unit = SPAWN, breed = "chaos_spawn", distance = 30, weakened = true } })

		assert_equal(harness:current(), "explore")
	end)

	it("counts a daemonhost only with its setting on, within 20 m, until it is farther than 60 m", function()
		local harness = in_mission()
		local function daemonhost_at(distance)
			return { unit = DAEMONHOST, breed = "chaos_daemonhost", distance = distance }
		end

		harness:bosses({ daemonhost_at(10) })
		assert_equal(harness:current(), "explore")

		harness:set_setting("daemonhost_boss_music", true)
		harness:bosses({ daemonhost_at(10) })
		assert_equal(harness:current(), "boss_approaching")

		harness:bosses({ daemonhost_at(60) })
		assert_equal(harness:current(), "boss_approaching")

		harness:bosses({ daemonhost_at(61) })
		harness:bosses({ daemonhost_at(21) })
		assert_equal(harness:current(), "explore")
	end)

	it("names the first boss to come near in its override folders, until it is gone", function()
		local harness = in_mission()
		local ogryn = { unit = OGRYN, breed = "chaos_plague_ogryn", distance = 70 }

		harness:bosses({ spawn_at(50), ogryn })
		harness:bosses({ spawn_at(40), ogryn })
		local first = harness.Context.override_keys(harness.engine.mod, "boss_approaching")[1]

		harness:bosses({ ogryn })
		local after = harness.Context.override_keys(harness.engine.mod, "boss_approaching")[1]

		assert_equal(first, "chaos_spawn")
		assert_equal(after, "chaos_plague_ogryn")
	end)

	it("forgets every boss on a loading screen", function()
		local harness = in_mission()

		harness:bosses({ spawn_at(30) })
		harness:state("music_game_state", "loading")
		harness:state("music_game_state", "mission")

		assert_equal(harness:current(), "explore")
	end)

	it("resolves no boss_approaching in an Expedition, which keeps to its own situations", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("exp_wastes", "expeditions")
		harness.engine:set_mission("exp_wastes", { game_mode_name = "expedition" })
		harness:tick(0)
		harness:state("music_combat", "no_combat")

		harness:bosses({ spawn_at(30) })

		assert_equal(harness:current(), "explore")
	end)
end)
