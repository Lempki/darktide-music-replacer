-- Loads context.lua through the fake engine and checks a few basic resolutions.

local FakeEngine = require("tests.helpers.fake_engine")

-- Returns a fake engine and a freshly loaded and initialized context.lua.
local function load_context(settings)
	local engine = FakeEngine.new({ settings = settings })
	local Context = engine:load("context")
	Context.init(engine.mod)

	return engine, Context
end

describe("context.lua", function()
	it("resolves no context before any music state is set", function()
		local _, Context = load_context()

		assert_equal((Context.current()), nil)
	end)

	it("resolves hub in the hub zone", function()
		local engine, Context = load_context()

		engine:set_state("music_game_state", "loading")
		engine:set_state("music_zone", "hub")

		assert_equal((Context.current()), "hub")
	end)

	it("reports each change to its listeners when leaving the hub", function()
		local engine, Context = load_context()
		local changes = {}

		Context.on_change(function(new_context, old_context)
			changes[#changes + 1] = { tostring(old_context), tostring(new_context) }
		end)

		-- The order the game sets these states in on a cold start into the hub and on leaving it.
		engine:set_state("music_game_state", "loading")
		engine:set_state("music_zone", "hub")
		engine:set_state("music_game_state", "mission")
		engine:set_state("music_zone", "None")
		engine:set_state("music_game_state", "loading")

		assert_deep_equal(changes, {
			{ "nil", "hub" },
			{ "hub", "mission_explore" },
			{ "mission_explore", "nil" },
		})
	end)

	it("starts from a clean state on every load", function()
		local engine = load_context()
		engine:set_state("music_game_state", "loading")
		engine:set_state("music_zone", "hub")

		local _, Context = load_context()

		assert_equal((Context.current()), nil)
	end)
end)

local BOSS = { _breed = { name = "chaos_ogryn_houndmaster" } }

-- Starts a mission, with a zone when one is given, then lets the first update register the boss event callbacks.
local function start_mission(engine, Context, zone)
	engine:set_state("music_game_state", "loading")
	engine:set_mission("dm_forge")
	if zone then
		engine:set_state("music_zone", zone)
	end
	engine:set_state("music_game_state", "mission")
	Context.update(engine.mod, 0.1)
end

describe("context.lua bosses", function()

	it("resolves mission_boss from the boss music state in a mission", function()
		local engine, Context = load_context()
		start_mission(engine, Context, "zone_3")

		engine:set_state("music_combat", "boss")

		assert_equal((Context.current()), "mission_boss")
	end)

	it("resolves mission_boss from the encounter events in a zoneless mission", function()
		local engine, Context = load_context()
		start_mission(engine, Context, nil)
		local unit = {}

		engine:fire_event("boss_encounter_start", unit, BOSS)

		assert_equal((Context.current()), "mission_boss")
	end)

	-- The sequence from leaving Meat Grinder with its boss dummies, as logged on 2026-10-06 and 2026-10-08.
	it("resolves no context on the loading screen after Meat Grinder, with the boss music state stuck", function()
		local engine, Context = load_context({ meat_grinder_music = false })
		local changes = {}
		Context.on_change(function(new_context)
			changes[#changes + 1] = tostring(new_context)
		end)

		engine:set_state("music_game_state", "loading")
		engine:set_mission("tg_shooting_range")
		Context.update(engine.mod, 0.1)
		engine:set_state("music_game_state", "mission")
		local unit = {}
		engine:fire_event("boss_encounter_start", unit, BOSS)
		engine:set_state("music_combat", "boss")

		engine:fire_event("boss_encounter_end", unit, BOSS)
		engine:set_state("music_game_state", "loading")
		engine:set_mission(nil)
		Context.update(engine.mod, 0.1)

		assert_equal((Context.current()), nil)

		engine:set_state("music_zone", "hub")
		engine:set_mission("hub_ship")
		Context.update(engine.mod, 0.1)

		assert_deep_equal(changes, { "silence", "nil", "hub" })
	end)
end)

describe("context.lua boss encounter windows", function()
	-- Returns a fake boss unit and its boss extension.
	local function new_boss_unit(breed_name)
		return { breed_name = breed_name }, { _breed = { name = breed_name } }
	end

	-- The renegade_wizard encounter in diagnostic-2026-10-06.log lasted from 19:38:37 to 19:47:44.
	it("keeps a living boss open for as long as the encounter lasts", function()
		local engine, Context = load_context()
		start_mission(engine, Context, "zone_2_depths")
		local unit, extension = new_boss_unit("renegade_wizard")

		engine:fire_event("boss_encounter_start", unit, extension)
		for _ = 1, 547 do
			Context.update(engine.mod, 1)
		end

		assert_equal((Context.current()), "mission_boss")

		engine:fire_event("boss_encounter_end", unit, extension)

		assert_equal((Context.current()), "mission_explore")
	end)

	it("stays on mission_boss until every open boss has ended", function()
		local engine, Context = load_context()
		start_mission(engine, Context, "zone_3")
		local first, first_extension = new_boss_unit("chaos_beast_of_nurgle")
		local second, second_extension = new_boss_unit("chaos_plague_ogryn")

		engine:fire_event("boss_encounter_start", first, first_extension)
		engine:fire_event("boss_encounter_start", second, second_extension)
		engine:fire_event("boss_encounter_end", first, first_extension)

		assert_deep_equal({ Context.current() }, { "mission_boss", "chaos_plague_ogryn" })

		engine:fire_event("boss_encounter_end", second, second_extension)

		assert_equal((Context.current()), "mission_explore")
	end)

	it("needs only one end event for a boss whose start event repeated", function()
		local engine, Context = load_context()
		start_mission(engine, Context, "zone_3")
		local unit, extension = new_boss_unit("chaos_ogryn_houndmaster")

		engine:fire_event("boss_encounter_start", unit, extension)
		engine:fire_event("boss_encounter_start", unit, extension)
		engine:fire_event("boss_encounter_end", unit, extension)

		assert_equal((Context.current()), "mission_explore")
	end)

	it("ignores an end event for a boss that has no open window", function()
		local engine, Context = load_context()
		start_mission(engine, Context, "zone_3")
		local open_unit, open_extension = new_boss_unit("renegade_captain")
		local other_unit, other_extension = new_boss_unit("chaos_spawn")

		engine:fire_event("boss_encounter_start", open_unit, open_extension)
		engine:fire_event("boss_encounter_end", other_unit, other_extension)

		assert_equal((Context.current()), "mission_boss")
	end)

	it("closes every window on a real zone change", function()
		local engine, Context = load_context()
		start_mission(engine, Context, "zone_3")
		local unit, extension = new_boss_unit("chaos_spawn")

		engine:fire_event("boss_encounter_start", unit, extension)
		engine:set_state("music_zone", "hub")

		assert_equal((Context.current()), "hub")
	end)
end)
