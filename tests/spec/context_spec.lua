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
