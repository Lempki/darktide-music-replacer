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

	-- Boss Dummies Count as Bosses only shows with Like a Mission, so it must not hide a breed from One Situation.
	it("offers the boss dummy's breed whatever Boss Dummies Count as Bosses says", function()
		local harness = in_meat_grinder({ source_meat_grinder = "situation", meat_grinder_situation = "boss", meat_grinder_boss_dummies = false })

		fight_dummies(harness)

		assert_equal(harness.Context.override_keys(harness.engine.mod, "boss")[1], "chaos_spawn")
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

	it("resolves boss for a boss dummy while boss dummies count as bosses", function()
		local harness = in_meat_grinder({ source_meat_grinder = "mission" })

		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "boss")
	end)

	-- The game reports only the boss while a boss dummy is alive, so combat cannot show through it.
	it("resolves explore while a boss dummy is alive once boss dummies do not count", function()
		local harness = in_meat_grinder({ source_meat_grinder = "mission", meat_grinder_boss_dummies = false })

		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "explore"), { "tg_shooting_range" })
	end)

	it("ends the boss music at once when boss dummies stop counting during the fight", function()
		local harness = in_meat_grinder({ source_meat_grinder = "mission" })
		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:state("music_combat", "boss")
		harness:clear_changes()

		harness:set_setting("meat_grinder_boss_dummies", false)

		assert_deep_equal(harness.changes, { "explore" })
	end)

	-- Without the mission name check, a player who left the boss dummies out would lose boss music in every mission.
	it("keeps boss music in a real mission while boss dummies do not count", function()
		local harness = Harness.new({ source_meat_grinder = "mission", meat_grinder_boss_dummies = false })
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")

		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:state("music_combat", "boss")

		assert_equal(harness:current(), "boss")
		assert_equal(harness.Context.override_keys(harness.engine.mod, "boss")[1], "chaos_spawn")
	end)
end)
