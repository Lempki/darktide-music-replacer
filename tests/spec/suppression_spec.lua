-- Pins how suppression.lua silences and restores the game's own music.
-- context.lua feeds it every real state transition, wired the same way as in MusicReplacer.lua.
-- The assertions read the value Wwise last received, which is what the player hears.

local FakeEngine = require("tests.helpers.fake_engine")

local EXPLORATION_EVENT = "wwise/events/music/play_exploration_music"

-- Returns a fake engine and a freshly loaded suppression.lua that sees every real state transition.
local function load_suppression()
	local engine = FakeEngine.new()
	local Context = engine:load("context")
	local Suppression = engine:load("suppression")

	Suppression.init()
	Context.on_state_change(Suppression.on_state_change)
	Context.init(engine.mod)

	return engine, Suppression
end

describe("suppression.lua hub", function()
	it("forces the hub zone to None while engaged, and restores it on release", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_zone", "hub")

		Suppression.engage("hub")

		assert_equal(engine:wwise_state("music_zone"), "None")

		Suppression.release()

		assert_equal(engine:wwise_state("music_zone"), "hub")
	end)

	it("restores the hub zone when the context moves on to a mission context", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_zone", "hub")
		Suppression.engage("hub")

		Suppression.engage("explore")

		assert_equal(engine:wwise_state("music_zone"), "hub")
	end)

	it("leaves a real zone change alone, and restores nothing over it", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_zone", "hub")
		Suppression.engage("hub")

		engine:set_state("music_zone", "None")
		Suppression.release()

		assert_equal(engine:wwise_state("music_zone"), "None")
	end)

	it("does not force the zone for a mission context", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_zone", "zone_3")

		Suppression.engage("explore")

		assert_equal(engine:wwise_state("music_zone"), "zone_3")
	end)
end)

describe("suppression.lua combat", function()
	it("forces the current combat state to None when engaged", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_combat", "normal")

		Suppression.engage("combat")

		assert_equal(engine:wwise_state("music_combat"), "None")
	end)

	it("forces combat to None again after every real transition while engaged", function()
		local engine, Suppression = load_suppression()
		Suppression.engage("combat")

		for _, state in ipairs({ "normal", "horde_high", "horde_low", "boss" }) do
			engine:set_state("music_combat", state)

			assert_equal(engine:wwise_state("music_combat"), "None", state)
		end
	end)

	-- A boss that started under a custom track must get the game's music back when the track stops.
	-- The game only re-sends a state when it changes, so the release has to restore it.
	it("restores the real combat state on release", function()
		local engine, Suppression = load_suppression()
		Suppression.engage("explore")
		engine:set_state("music_combat", "boss")

		Suppression.release()

		assert_equal(engine:wwise_state("music_combat"), "boss")
	end)

	it("sends nothing to Wwise for a real None, on engage or on release", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_combat", "normal")
		engine:set_state("music_combat", "None")
		local calls_before = #engine.wwise_calls

		Suppression.engage("explore")
		Suppression.release()

		assert_equal(#engine.wwise_calls, calls_before)
	end)

	it("forces expeditions_intensity with music_combat, again after every transition, and restores it on release", function()
		local engine, Suppression = load_suppression()
		engine:set_state("expeditions_intensity", "no_combat")

		Suppression.engage("explore")
		assert_equal(engine:wwise_state("expeditions_intensity"), "None")

		engine:set_state("expeditions_intensity", "med_combat")
		assert_equal(engine:wwise_state("expeditions_intensity"), "None")

		Suppression.release()
		assert_equal(engine:wwise_state("expeditions_intensity"), "med_combat")
	end)

	it("forces combat for Meat Grinder set to silence too", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_combat", "boss")

		Suppression.engage("meat_grinder")

		assert_equal(engine:wwise_state("music_combat"), "None")
	end)
end)

describe("suppression.lua victory and defeat", function()
	for _, context_name in ipairs({ "victory", "defeat" }) do
		it("forces the game state to None for " .. context_name .. " and again after every transition", function()
			local engine, Suppression = load_suppression()
			engine:set_state("music_game_state", "victory")

			Suppression.engage(context_name)

			assert_equal(engine:wwise_state("music_game_state"), "None")

			for _, state in ipairs({ "mission", "game_score_win" }) do
				engine:set_state("music_game_state", state)

				assert_equal(engine:wwise_state("music_game_state"), "None", state)
			end
		end)
	end

	it("restores the real game state on release", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_game_state", "defeat")
		Suppression.engage("defeat")
		engine:set_state("music_game_state", "game_score_lose")

		Suppression.release()

		assert_equal(engine:wwise_state("music_game_state"), "game_score_lose")
	end)

	it("needs no restore once the game itself has set None", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_game_state", "victory")
		Suppression.engage("victory")
		engine:set_state("music_game_state", "None")
		local calls_before = #engine.wwise_calls

		Suppression.release()

		assert_equal(#engine.wwise_calls, calls_before)
	end)

	it("does not force the game state for other contexts", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_game_state", "mission")

		Suppression.engage("boss")

		assert_equal(engine:wwise_state("music_game_state"), "mission")
	end)
end)

describe("suppression.lua loading", function()
	it("forces the game state to None for the mission preparation screen", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_game_state", "loadout")

		Suppression.engage("mission_preparation")

		assert_equal(engine:wwise_state("music_game_state"), "None")
	end)

	it("forces the game state to None for loading, through the briefing, and restores it on release", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_game_state", "loading")

		Suppression.engage("loading")

		assert_equal(engine:wwise_state("music_game_state"), "None")

		for _, state in ipairs({ "loading", "mission_briefing" }) do
			engine:set_state("music_game_state", state)

			assert_equal(engine:wwise_state("music_game_state"), "None", state)
		end

		Suppression.release()

		assert_equal(engine:wwise_state("music_game_state"), "mission_briefing")
	end)
end)

describe("suppression.lua last stand", function()
	it("forces the objective music to None for last_stand and again after every transition", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_objective", "last_man_standing")

		Suppression.engage("last_stand")

		assert_equal(engine:wwise_state("music_objective"), "None")

		engine:set_state("music_objective", "end_event")
		engine:set_state("music_objective", "last_man_standing")

		assert_equal(engine:wwise_state("music_objective"), "None")
	end)

	it("restores the real objective music on release", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_objective", "last_man_standing")
		Suppression.engage("last_stand")
		engine:set_state("music_objective", "end_event")

		Suppression.release()

		assert_equal(engine:wwise_state("music_objective"), "end_event")
	end)

	it("restores the real objective music when the context moves on to boss", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_objective", "last_man_standing")
		Suppression.engage("last_stand")

		Suppression.engage("boss")

		assert_equal(engine:wwise_state("music_objective"), "last_man_standing")
	end)

	it("forces the event music to None for event, and restores it on release", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_objective", "fortification_event")

		Suppression.engage("event")

		assert_equal(engine:wwise_state("music_objective"), "None")

		Suppression.release()

		assert_equal(engine:wwise_state("music_objective"), "fortification_event")
	end)

	it("forces Mortis Trials' wave music to None for mortis_trials_wave, and leaves it to the game between waves", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_objective", "horde_mode_wave")

		Suppression.engage("mortis_trials_wave")

		assert_equal(engine:wwise_state("music_objective"), "None")

		Suppression.engage("mortis_trials_break")

		assert_equal(engine:wwise_state("music_objective"), "horde_mode_wave")
	end)

	it("leaves event music alone for other contexts", function()
		local engine, Suppression = load_suppression()
		engine:set_state("music_objective", "end_event")

		Suppression.engage("boss")

		assert_equal(engine:wwise_state("music_objective"), "end_event")
	end)
end)

describe("suppression.lua events", function()
	it("stops the game's exploration music event only while engaged", function()
		local _, Suppression = load_suppression()

		assert_equal(Suppression.should_stop_event(EXPLORATION_EVENT), false)

		Suppression.engage("explore")

		assert_equal(Suppression.should_stop_event(EXPLORATION_EVENT), true)

		Suppression.release()

		assert_equal(Suppression.should_stop_event(EXPLORATION_EVENT), false)
	end)

	it("lets every other event through while engaged", function()
		local _, Suppression = load_suppression()
		Suppression.engage("explore")

		assert_equal(Suppression.should_stop_event("wwise/events/music/play_music_manager"), false)
		assert_equal(Suppression.should_stop_event("wwise/events/ui/play_ui_silence"), false)
		assert_equal(Suppression.should_stop_event(nil), false)
	end)
end)
