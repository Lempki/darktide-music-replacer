-- Pins how context.lua resolves Meat Grinder, which reports no zone and is recognized by its mission name.
-- Its own setting picks Silence, its own folder, one situation the player chooses, or the mission contexts.

local Harness = require("tests.helpers.context_harness")

-- Returns a harness that has walked from the hub into Meat Grinder, with `settings` over the defaults.
-- The way to Meat Grinder skips the mission board, so its loading screen is a plain one.
local function in_meat_grinder(settings)
	local harness = Harness.new(settings)
	harness:cold_start_to_hub()
	harness:state("music_zone", "None")
	harness:state("music_game_state", "loading")
	harness:mission(nil)
	harness:wait(3)
	harness:mission("tg_shooting_range")
	harness:state("music_game_state", "mission")

	return harness
end

-- The dummies fight like a mission's enemies, and the boss dummies open boss windows and report the boss state.
local function fight_dummies(harness)
	local boss = harness:new_boss("chaos_spawn")
	harness:state("music_combat", "normal")
	harness:boss_start(boss)
	harness:state("music_combat", "boss")
	harness:state("music_combat", "horde_high")
	harness:wait(30)
	return boss
end

describe("context.lua Meat Grinder", function()
	it("resolves meat_grinder once the visit starts", function()
		local harness = in_meat_grinder()

		assert_deep_equal(harness.changes, { "title_screen", "character_select", "loading", "hub", "nil", "loading", "meat_grinder" })
	end)

	for _, source in ipairs({ "silence", "custom" }) do
		it("stays on meat_grinder through the dummies' combat and boss signals, set to " .. source, function()
			local harness = in_meat_grinder({ source_meat_grinder = source })
			harness:clear_changes()

			fight_dummies(harness)

			assert_deep_equal(harness.changes, {})
			assert_equal(harness:current(), "meat_grinder")
		end)
	end

	it("stays on meat_grinder when the setting moves between Silence and its folder during a visit", function()
		local harness = in_meat_grinder({ source_meat_grinder = "silence" })
		harness:clear_changes()

		harness:set_setting("source_meat_grinder", "custom")
		harness:set_setting("source_meat_grinder", "silence")

		assert_deep_equal(harness.changes, {})
	end)

	it("resolves hub after leaving", function()
		local harness = in_meat_grinder({ source_meat_grinder = "silence" })
		harness:clear_changes()

		harness:state("music_game_state", "loading")
		harness:mission(nil)
		harness:arrive_in_hub()

		assert_deep_equal(harness.changes, { "loading", "hub" })
	end)
end)

describe("context.lua Meat Grinder with One Situation", function()
	it("resolves the chosen situation through the dummies' fights", function()
		local harness = in_meat_grinder({ source_meat_grinder = "situation", meat_grinder_situation = "event" })
		harness:clear_changes()

		fight_dummies(harness)

		assert_equal(harness:current(), "event")
		assert_deep_equal(harness.changes, {})
	end)

	it("follows a change of the mode or the situation at once", function()
		local harness = in_meat_grinder({ source_meat_grinder = "silence" })
		harness:clear_changes()

		harness:set_setting("source_meat_grinder", "situation")
		harness:set_setting("meat_grinder_situation", "last_stand")
		harness:set_setting("source_meat_grinder", "custom")

		assert_deep_equal(harness.changes, { "explore", "last_stand", "meat_grinder" })
	end)

	-- So a player can try out an override folder there, as the debug overlay's Folder line shows.
	it("offers the boss dummy's breed and the mission's code as override names", function()
		local harness = in_meat_grinder({ source_meat_grinder = "situation", meat_grinder_situation = "boss" })

		fight_dummies(harness)

		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "boss"), { "chaos_spawn", "tg_shooting_range" })
	end)

	-- Meat Grinder runs no wave, so its music_objective is "None", which names no moment.
	it("offers no moment for a Mortis Trials wave while no wave runs", function()
		local harness = in_meat_grinder({ source_meat_grinder = "situation", meat_grinder_situation = "mortis_trials_wave" })
		harness:state("music_objective", "None")

		assert_equal(harness:current(), "mortis_trials_wave")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "mortis_trials_wave"), { "tg_shooting_range" })
	end)

	it("resolves no situation for a stored situation the mod does not know, so the game's music plays", function()
		local harness = in_meat_grinder({ source_meat_grinder = "situation", meat_grinder_situation = "not_a_situation" })

		assert_equal(harness:current(), nil)
	end)
end)

describe("context.lua Meat Grinder like a mission", function()
	it("resolves explore, then combat while the player hits the dummies", function()
		local harness = in_meat_grinder({ source_meat_grinder = "mission" })
		assert_equal(harness:current(), "explore")

		harness:state("music_combat", "normal")

		assert_equal(harness:current(), "combat")
	end)

	it("resolves boss for a boss dummy, with its breed as the override name", function()
		local harness = in_meat_grinder({ source_meat_grinder = "mission" })

		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "boss")
		assert_equal(harness.Context.override_keys(harness.engine.mod, "boss")[1], "chaos_spawn")
	end)
end)
