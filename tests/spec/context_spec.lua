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
	it("hands the game's return values back through its state hook", function()
		local engine = FakeEngine.new()
		local Manager = require("scripts/managers/wwise_game_sync/wwise_game_sync_manager")
		local original = Manager._set_state
		Manager._set_state = function(...)
			original(...)
			return "first", nil, "third"
		end
		local Context = engine:load("context")
		Context.init(engine.mod)

		local results = { n = 0 }
		local function collect(...)
			results = { n = select("#", ...), ... }
		end
		collect(engine.wwise_game_sync:_set_state("music_zone", "hub"))

		assert_deep_equal(results, { n = 3, "first", nil, "third" })
		assert_equal(engine:wwise_state("music_zone"), "hub")
	end)

	it("reports a failing listener with its error text intact, even with a percent sign in it", function()
		local engine, Context = load_context()
		Context.on_change(function() error("disk at 100% full", 0) end)
		Context.on_state_change(function() error("volume at 50% now", 0) end)

		engine:set_state("music_game_state", "loading")

		assert_deep_equal(engine.messages, {
			{ level = "error", text = "Music Replacer could not follow a change of the game's music state: volume at 50% now" },
			{ level = "error", text = "Music Replacer could not switch the music for a change in the game: disk at 100% full" },
		})
	end)

	it("lets the game's combat group decide again at each mission's end whether it runs an Expedition", function()
		load_context()
		local Group = require("scripts/managers/wwise_game_sync/wwise_state_groups/wwise_state_group_combat")
		local group = { _is_expedition_init = true, _is_expedition = true }

		Group.on_gameplay_shutdown(group)

		assert_equal(group._is_expedition_init, nil)
	end)

	it("resolves no context before any music state is set", function()
		local _, Context = load_context()

		assert_equal((Context.current()), nil)
	end)

	it("resolves hub in the hub zone", function()
		local engine, Context = load_context()

		engine:set_state("music_game_state", "loading")
		engine:set_state("music_zone", "hub")
		engine:set_state("music_game_state", "mission")

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
		engine:set_mission("hub_ship", { is_hub = true })
		Context.update(engine.mod, 0)
		engine:set_state("music_game_state", "mission")
		engine:set_state("music_zone", "None")
		engine:set_state("music_game_state", "loading")

		assert_deep_equal(changes, {
			{ "nil", "loading" },
			{ "loading", "hub" },
			{ "hub", "nil" },
			{ "nil", "loading" },
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

describe("context.lua state logging", function()
	it("logs transitions of the music state groups it does not act on, and changes no context", function()
		local engine = FakeEngine.new()
		local Context = engine:load("context")
		local lines = {}
		Context.init(engine.mod, function(line) lines[#lines + 1] = line end)

		engine:set_state("music_objective", "end_event")
		engine:set_state("music_objective", "last_man_standing")
		engine:set_state("player_state", "knocked_down")
		engine:set_state("circumstance", "darkness_01")

		assert_deep_equal(lines, {
			"[raw] music_objective: None -> end_event",
			"[raw] music_objective: end_event -> last_man_standing",
			"[raw] circumstance: None -> darkness_01",
		})
		assert_equal((Context.current()), nil)
	end)

	it("logs expeditions_intensity only on the Expedition values it does not share with music_combat", function()
		local engine = FakeEngine.new()
		local Context = engine:load("context")
		local lines = {}
		Context.init(engine.mod, function(line) lines[#lines + 1] = line end)

		engine:set_state("expeditions_intensity", "normal")
		engine:set_state("expeditions_intensity", "None")
		engine:set_state("expeditions_intensity", "safe_room")
		engine:set_state("expeditions_intensity", "high_combat")
		engine:set_state("expeditions_intensity", "None")
		engine:set_state("expeditions_intensity", "boss")

		assert_deep_equal(lines, {
			"[raw] expeditions_intensity: None -> safe_room",
			"[raw] expeditions_intensity: safe_room -> high_combat",
			"[raw] expeditions_intensity: high_combat -> None",
		})
		assert_equal((Context.current()), nil)
	end)

	it("logs a boss encounter's start once, however often the game repeats it, and its end with the breed", function()
		local engine = FakeEngine.new()
		local Context = engine:load("context")
		local lines = {}
		Context.init(engine.mod, function(line) lines[#lines + 1] = line end)
		Context.update(engine.mod, 0)

		local dummy = { extension = { _breed = { name = "chaos_spawn" } } }
		for _ = 1, 25 do
			engine:fire_event("boss_encounter_start", dummy, dummy.extension)
		end
		engine:fire_event("boss_encounter_end", dummy, dummy.extension)
		engine:fire_event("boss_encounter_start", dummy, dummy.extension)

		assert_deep_equal(lines, {
			"[raw] boss_encounter_start breed=chaos_spawn",
			"[raw] boss_encounter_end breed=chaos_spawn",
			"[raw] boss_encounter_start breed=chaos_spawn",
		})
	end)
end)

describe("context.lua menus", function()
	it("reports a menu as open while the game sets the options group, and logs it without changing the context", function()
		local engine = FakeEngine.new()
		local Context = engine:load("context")
		local lines = {}
		local changes = 0
		Context.on_change(function() changes = changes + 1 end)
		Context.init(engine.mod, function(line) lines[#lines + 1] = line end)

		assert_equal(Context.menu_open(), false)
		engine:set_state("options", "ingame_menu")
		assert_equal(Context.menu_open(), true)
		engine:set_state("options", "vendor_menu")
		assert_equal(Context.menu_open(), true)
		engine:set_state("options", "None")
		assert_equal(Context.menu_open(), false)

		assert_deep_equal(lines, {
			"[raw] options: None -> ingame_menu",
			"[raw] options: ingame_menu -> vendor_menu",
			"[raw] options: vendor_menu -> None",
		})
		assert_equal(changes, 0)
	end)
end)
