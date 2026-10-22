-- Pins how context.lua catches up with the game's music states it did not see change.
-- That happens when the mod loads partway through a level, as after a mod reload.
-- It also happens when the mod is turned back on, since DMF disables the mod's hooks while it is off.
-- The game sets every group again on every tick, which is what the catch-up relies on.

local FakeEngine = require("tests.helpers.fake_engine")

local GROUPS = { "music_game_state", "music_zone", "music_combat", "music_objective" }

-- Returns a fake engine, a context.lua loaded after `states` were already set, the contexts it reports, and its log lines.
-- As in the game, the hub_ship template is the hub.
local function load_partway(states, mission_name, settings)
	local engine = FakeEngine.new({ settings = settings })
	for _, group_name in ipairs(GROUPS) do
		if states[group_name] then
			engine:set_state_unseen(group_name, states[group_name])
		end
	end
	engine:set_mission(mission_name, mission_name == "hub_ship" and { is_hub = true } or nil)

	local Context = engine:load("context")
	local changes = {}
	local lines = {}
	Context.on_change(function(new_context) changes[#changes + 1] = tostring(new_context) end)
	Context.init(engine.mod, function(line) lines[#lines + 1] = line end)
	Context.update(engine.mod, 0)

	return engine, Context, changes, lines
end

describe("context.lua catching up after being turned off", function()
	it("counts a trip into a mission as over when it catches up inside the mission", function()
		local Harness = require("tests.helpers.context_harness")
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()

		-- Turned off on the way in, so the hook sees none of the trip.
		for _, step in ipairs({ { "music_game_state", "loadout" }, { "music_game_state", "mission_briefing" },
			{ "music_zone", "zone_3" }, { "music_game_state", "mission_intro" }, { "music_game_state", "mission" } }) do
			harness.engine:set_state_unseen(step[1], step[2])
		end
		harness:mission("lm_cooling")

		harness.Context.relearn()
		harness.engine:reassert_states(GROUPS)
		assert_equal(harness:current(), "explore")

		harness:state("music_zone", "None")
		harness:state("music_game_state", "loading")

		assert_equal(harness:current(), "loading")
	end)
end)

describe("context.lua catching up", function()
	it("resolves nothing until the game's next tick, then the hub, when loaded in the hub", function()
		local engine, Context, changes = load_partway({ music_game_state = "mission", music_zone = "hub" }, "hub_ship")

		assert_equal((Context.current()), nil)

		engine:reassert_states(GROUPS)

		assert_equal((Context.current()), "hub")
		assert_deep_equal(changes, { "hub" })
	end)

	it("logs a group it caught up with as read again", function()
		local engine, _, _, lines = load_partway({ music_game_state = "mission", music_zone = "hub" }, "hub_ship")

		engine:reassert_states({ "music_zone" })

		assert_deep_equal(lines, { "[raw] music_zone: nil -> hub" })

		engine:reassert_states({ "music_game_state" })

		assert_equal(lines[2], "[raw] music_game_state: mission, read again")
	end)

	it("keeps a victory when the zone is caught up after the game state", function()
		local engine, Context = load_partway({ music_game_state = "victory", music_zone = "zone_4" }, "lm_cooling")

		engine:reassert_states({ "music_game_state", "music_zone" })

		assert_equal((Context.current()), "victory")
	end)

	it("catches up with changes it missed after relearn, as when the mod is turned back on", function()
		local engine, Context, changes = load_partway({ music_game_state = "mission", music_zone = "hub" }, "hub_ship")
		engine:reassert_states(GROUPS)

		engine:set_state_unseen("music_zone", "None")
		engine:set_state_unseen("music_game_state", "loading")
		engine:set_state_unseen("music_zone", "zone_3")
		engine:set_mission("lm_cooling")
		engine:set_state_unseen("music_game_state", "mission")

		Context.relearn()
		Context.update(engine.mod, 0)
		engine:reassert_states(GROUPS)

		assert_equal((Context.current()), "explore")
		assert_equal(changes[#changes], "explore")
	end)

	it("reports the context again after relearn, even when it has not changed", function()
		local engine, Context, changes = load_partway({ music_game_state = "mission", music_zone = "hub" }, "hub_ship")
		engine:reassert_states(GROUPS)

		Context.relearn()
		engine:reassert_states(GROUPS)

		assert_deep_equal(changes, { "hub", "hub" })
	end)

	it("passes caught-up values to its state listeners, so suppression knows the real ones again", function()
		local engine, Context = load_partway({ music_game_state = "mission", music_zone = "hub" }, "hub_ship")
		engine:reassert_states(GROUPS)
		local seen = {}
		Context.on_state_change(function(group_name, value) seen[#seen + 1] = group_name .. "=" .. value end)

		Context.relearn()
		engine:reassert_states({ "music_zone", "music_game_state" })

		assert_deep_equal(seen, { "music_zone=hub", "music_game_state=mission" })
	end)

	it("keeps an open boss window through relearn", function()
		local engine, Context = load_partway({ music_game_state = "mission", music_zone = "zone_3" }, "lm_cooling", { captain_boss_music = true })
		engine:reassert_states(GROUPS)
		local captain = { extension = { _breed = { name = "renegade_captain" } } }
		engine:fire_event("boss_encounter_start", captain, captain.extension)
		assert_equal((Context.current()), "boss")

		Context.relearn()
		engine:reassert_states(GROUPS)

		assert_equal((Context.current()), "boss")
	end)
end)
