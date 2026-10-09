-- Checks the fake engine itself, so the specs that rely on it can trust it.

local FakeEngine = require("tests.helpers.fake_engine")

describe("FakeEngine", function()
	it("calls Wwise.set_state only on a real transition, like the game", function()
		local engine = FakeEngine.new()

		engine:set_state("music_zone", "None")
		engine:set_state("music_zone", "hub")
		engine:set_state("music_zone", "hub")

		assert_deep_equal(engine.wwise_calls, { { "music_zone", "hub" } })
	end)

	it("reports the value Wwise last received for a state group", function()
		local engine = FakeEngine.new()

		assert_equal(engine:wwise_state("music_zone"), "None")

		engine:set_state("music_zone", "hub")
		Wwise.set_state("music_zone", "None")

		assert_equal(engine:wwise_state("music_zone"), "None")
		assert_equal(engine.wwise_game_sync._wwise_state_group_states.music_zone, "hub")
	end)

	it("runs a hook handler with the original function first", function()
		local engine = FakeEngine.new()
		local Manager = require("scripts/managers/wwise_game_sync/wwise_game_sync_manager")
		local seen = {}

		engine.mod:hook(Manager, "_set_state", function(func, self, group_name, new_state)
			seen[#seen + 1] = new_state
			return func(self, group_name, new_state)
		end)
		engine:set_state("music_combat", "normal")

		assert_deep_equal(seen, { "normal" })
		assert_deep_equal(engine.wwise_calls, { { "music_combat", "normal" } })
	end)

	it("rejects a second hook on the same method", function()
		local engine = FakeEngine.new()
		local Manager = require("scripts/managers/wwise_game_sync/wwise_game_sync_manager")
		local handler = function(func, ...) return func(...) end

		engine.mod:hook(Manager, "_set_state", handler)

		assert_equal(pcall(engine.mod.hook, engine.mod, Manager, "_set_state", handler), false)
	end)

	it("gives each engine a fresh state manager", function()
		FakeEngine.new():set_state("music_zone", "hub")
		local engine = FakeEngine.new()

		assert_equal(engine.wwise_game_sync._wwise_state_group_states.music_zone, "None")
	end)

	it("returns settings and other mods", function()
		local audio = {}
		local engine = FakeEngine.new({ settings = { combat_hold_seconds = 5 }, mods = { Audio = audio } })

		assert_equal(engine.mod:get("combat_hold_seconds"), 5)
		assert_equal(get_mod("MusicReplacer"), engine.mod)
		assert_equal(get_mod("Audio"), audio)
		assert_equal(get_mod("DarktideLocalServer"), nil)
	end)

	it("calls registered event listeners by method name", function()
		local engine = FakeEngine.new()
		local listener = {}
		local received

		function listener:on_ping(value)
			received = value
		end

		Managers.event:register(listener, "ping", "on_ping")
		engine:fire_event("ping", 7)
		assert_equal(received, 7)

		Managers.event:unregister(listener, "ping")
		engine:fire_event("ping", 8)
		assert_equal(received, 7)
	end)

	it("reports the mission name, and no mission manager before a level loads", function()
		local engine = FakeEngine.new()
		assert_equal(Managers.state.mission, nil)

		engine:set_mission("hub_ship")
		assert_equal(Managers.state.mission:mission_name(), "hub_ship")

		engine:set_mission(nil)
		assert_equal(Managers.state.mission, nil)
	end)
end)
