-- Pins which songs resume_points.lua remembers, and when it forgets them.

local FakeEngine = require("tests.helpers.fake_engine")

-- Returns a freshly loaded resume_points.lua, with the setting on unless `settings` says otherwise.
local function load_resume_points(settings)
	local engine = FakeEngine.new({ settings = settings or { resume_songs = true } })
	local ResumePoints = engine:load("resume_points")
	ResumePoints.init(engine.mod)

	return ResumePoints
end

describe("resume_points.lua ranking", function()
	it("ranks the mission contexts as context.lua resolves them, and nothing outside them", function()
		local ResumePoints = load_resume_points()

		assert_equal(ResumePoints.outranks("mission_boss", "mission_explore"), true)
		assert_equal(ResumePoints.outranks("mission_explore", "mission_boss"), false)
		assert_equal(ResumePoints.outranks("mission_last_stand", "mission_event"), true)
		assert_equal(ResumePoints.outranks("mortis_trials_wave", "mortis_trials_break"), true)
		assert_equal(ResumePoints.outranks("mission_boss", nil), false)
		assert_equal(ResumePoints.outranks("mission_boss", "hub"), false)
	end)
end)

describe("resume_points.lua", function()
	it("gives back an explore song's position once, then forgets it", function()
		local ResumePoints = load_resume_points()

		assert_equal(ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 63.5, 200, false), 63.5)

		assert_deep_equal({ ResumePoints.take("mission_explore") }, { "mission_explore/a.mp3", 63.5 })
		assert_equal(ResumePoints.take("mission_explore"), nil)
	end)

	it("keeps explore and combat apart", function()
		local ResumePoints = load_resume_points()

		ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false)
		ResumePoints.remember("mission_combat", "mission_combat/b.mp3", 40, 200, false)

		assert_deep_equal({ ResumePoints.take("mission_combat") }, { "mission_combat/b.mp3", 40 })
		assert_deep_equal({ ResumePoints.take("mission_explore") }, { "mission_explore/a.mp3", 30 })
	end)

	it("remembers no hub, last stand, or mission end song", function()
		local ResumePoints = load_resume_points()

		for _, context_name in ipairs({ "hub", "mission_last_stand", "mission_victory", "mission_defeat" }) do
			assert_equal(ResumePoints.remember(context_name, context_name .. "/a.mp3", 30, 200, false, "mission_explore"), nil)
			assert_equal(ResumePoints.take(context_name), nil)
		end
	end)

	it("keeps explore and combat songs through any other context", function()
		local ResumePoints = load_resume_points()
		ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false, "mission_combat")
		ResumePoints.remember("mission_combat", "mission_combat/b.mp3", 40, 200, false, "mission_explore")

		for _, context_name in ipairs({ "mission_horde", "mission_boss", "mission_event", "mission_combat", "mission_explore" }) do
			ResumePoints.enter(context_name)
		end

		assert_deep_equal({ ResumePoints.take("mission_explore") }, { "mission_explore/a.mp3", 30 })
		assert_deep_equal({ ResumePoints.take("mission_combat") }, { "mission_combat/b.mp3", 40 })
	end)

	it("remembers nothing with the setting off", function()
		local ResumePoints = load_resume_points({ resume_songs = false })

		assert_equal(ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false), nil)
		assert_equal(ResumePoints.take("mission_explore"), nil)
	end)

	it("does not keep a song within 10 seconds of its end, and drops the older point for that context", function()
		local ResumePoints = load_resume_points()
		ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false)

		assert_equal(ResumePoints.remember("mission_explore", "mission_explore/b.mp3", 191, 200, false), nil)
		assert_equal(ResumePoints.take("mission_explore"), nil)
	end)

	it("wraps a single file's loop back into the file", function()
		local ResumePoints = load_resume_points()

		assert_equal(ResumePoints.remember("mission_combat", "mission_combat/only.mp3", 250, 100, true), 50)
	end)

	it("keeps a song of unknown duration at its position", function()
		local ResumePoints = load_resume_points()

		assert_equal(ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 500, nil, false), 500)
	end)

	it("continues Mortis Trials' wave and break songs every time either comes back", function()
		local ResumePoints = load_resume_points()

		for round = 1, 3 do
			ResumePoints.enter("mortis_trials_wave")
			ResumePoints.take("mortis_trials_wave")
			assert_equal(ResumePoints.remember("mortis_trials_wave", "mortis_trials_wave/a.mp3", 60 * round, 400, false, "mortis_trials_break"), 60 * round)

			ResumePoints.enter("mortis_trials_break")
			ResumePoints.take("mortis_trials_break")
			assert_equal(ResumePoints.remember("mortis_trials_break", "mortis_trials_break/b.mp3", 20 * round, 400, false, "mortis_trials_wave"), 20 * round)
		end

		ResumePoints.enter("mortis_trials_wave")
		assert_deep_equal({ ResumePoints.take("mortis_trials_wave") }, { "mortis_trials_wave/a.mp3", 180 })
		assert_deep_equal({ ResumePoints.take("mortis_trials_break") }, { "mortis_trials_break/b.mp3", 60 })
	end)

	it("forgets everything at a loading screen, so the next mission starts fresh", function()
		local ResumePoints = load_resume_points()
		ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false)
		ResumePoints.remember("mission_combat", "mission_combat/b.mp3", 40, 200, false)

		ResumePoints.on_state_change("music_game_state", "loading")

		assert_equal(ResumePoints.take("mission_explore"), nil)
		assert_equal(ResumePoints.take("mission_combat"), nil)
	end)

	-- Leaving a mission can report the loading state before the context change that stops the song.
	it("remembers nothing while loading, and again once the next mission starts", function()
		local ResumePoints = load_resume_points()

		ResumePoints.on_state_change("music_game_state", "loading")
		assert_equal(ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false), nil)

		ResumePoints.on_state_change("music_game_state", "mission_intro")
		ResumePoints.on_state_change("music_game_state", "mission")
		ResumePoints.enter("mission_explore")
		assert_equal(ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false), 30)
	end)

	-- The debounced change away from the old level can arrive after the game state has already moved past loading.
	it("keeps nothing from the old level when its change arrives after the loading screen ended", function()
		local ResumePoints = load_resume_points()

		ResumePoints.on_state_change("music_game_state", "loading")
		ResumePoints.on_state_change("music_game_state", "mission_briefing")
		ResumePoints.enter(nil)

		assert_equal(ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false, nil), nil)
		assert_equal(ResumePoints.take("mission_explore"), nil)
	end)

	-- The loading context lasts from leaving the hub until the intro, so a song from the old level can still stop during it.
	it("keeps nothing during the loading context, which belongs to the loading screen", function()
		local ResumePoints = load_resume_points()

		ResumePoints.on_state_change("music_game_state", "loading")
		ResumePoints.enter("loading")

		assert_equal(ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false, "loading"), nil)
		assert_equal(ResumePoints.take("mission_explore"), nil)
	end)

	it("keeps a loading song that the preparation screen interrupts through the loading state of the briefing", function()
		local ResumePoints = load_resume_points()
		ResumePoints.on_state_change("music_game_state", "loading")
		ResumePoints.enter("loading")

		assert_equal(ResumePoints.remember("loading", "loading/a.mp3", 30, 200, false, "mission_preparation"), 30)

		ResumePoints.enter("mission_preparation")
		ResumePoints.on_state_change("music_game_state", "loading")
		ResumePoints.enter("loading")

		assert_deep_equal({ ResumePoints.take("loading") }, { "loading/a.mp3", 30 })
	end)

	it("keeps no loading song for anything but the preparation screen, or with Resume Songs off", function()
		local ResumePoints = load_resume_points()
		assert_equal(ResumePoints.remember("loading", "loading/a.mp3", 30, 200, false, "hub"), nil)
		ResumePoints.remember("loading", "loading/a.mp3", 30, 200, false, "mission_preparation")
		ResumePoints.enter(nil)
		assert_equal(ResumePoints.take("loading"), nil)

		local off = load_resume_points({ resume_songs = false })
		assert_equal(off.remember("loading", "loading/a.mp3", 30, 200, false, "mission_preparation"), nil)
	end)

	it("keeps its points through a mid-mission cutscene and other state groups", function()
		local ResumePoints = load_resume_points()
		ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false)

		ResumePoints.on_state_change("music_game_state", "cinematic")
		ResumePoints.on_state_change("music_game_state", "mission")
		ResumePoints.on_state_change("music_zone", "None")

		assert_deep_equal({ ResumePoints.take("mission_explore") }, { "mission_explore/a.mp3", 30 })
	end)

	it("forgets everything on request, as when the setting is turned off", function()
		local ResumePoints = load_resume_points()
		ResumePoints.remember("mission_explore", "mission_explore/a.mp3", 30, 200, false)

		ResumePoints.forget_all()

		assert_equal(ResumePoints.take("mission_explore"), nil)
	end)

	describe("hordes, boss fights, and events", function()
		it("continues a horde song after a boss, an event, or a last stand interrupts the horde", function()
			for _, interruption in ipairs({ "mission_boss", "mission_event", "mission_last_stand" }) do
				local ResumePoints = load_resume_points()

				assert_equal(ResumePoints.remember("mission_horde", "mission_horde/a.mp3", 45, 200, false, interruption), 45)
				ResumePoints.enter(interruption)
				ResumePoints.enter("mission_horde")

				assert_deep_equal({ ResumePoints.take("mission_horde") }, { "mission_horde/a.mp3", 45 }, interruption)
			end
		end)

		it("does not keep a horde song when the horde ends into combat or explore", function()
			for _, next_context in ipairs({ "mission_combat", "mission_explore" }) do
				local ResumePoints = load_resume_points()

				assert_equal(ResumePoints.remember("mission_horde", "mission_horde/a.mp3", 45, 200, false, next_context), nil)
				assert_equal(ResumePoints.take("mission_horde"), nil)
			end
		end)

		it("forgets an interrupted horde's song once the music drops to combat or explore", function()
			for _, next_context in ipairs({ "mission_combat", "mission_explore" }) do
				local ResumePoints = load_resume_points()
				ResumePoints.remember("mission_horde", "mission_horde/a.mp3", 45, 200, false, "mission_boss")
				ResumePoints.enter("mission_boss")

				ResumePoints.enter(next_context)

				assert_equal(ResumePoints.take("mission_horde"), nil, next_context)
			end
		end)

		it("continues a boss song after an event or a last stand", function()
			for _, interruption in ipairs({ "mission_event", "mission_last_stand" }) do
				local ResumePoints = load_resume_points()

				assert_equal(ResumePoints.remember("mission_boss", "mission_boss/a.mp3", 45, 200, false, interruption), 45)
				ResumePoints.enter(interruption)
				ResumePoints.enter("mission_boss")

				assert_deep_equal({ ResumePoints.take("mission_boss") }, { "mission_boss/a.mp3", 45 }, interruption)
			end
		end)

		it("ends a boss fight's song when the music drops to a horde, combat, or explore", function()
			for _, next_context in ipairs({ "mission_horde", "mission_combat", "mission_explore" }) do
				local ResumePoints = load_resume_points()
				assert_equal(ResumePoints.remember("mission_boss", "mission_boss/a.mp3", 45, 200, false, next_context), nil, next_context)

				ResumePoints.remember("mission_boss", "mission_boss/a.mp3", 45, 200, false, "mission_event")
				ResumePoints.enter("mission_event")
				ResumePoints.enter(next_context)

				assert_equal(ResumePoints.take("mission_boss"), nil, next_context)
			end
		end)

		-- A boss that spawns on top of a horde and dies while the horde goes on.
		it("continues the horde song and forgets the boss song when a boss ends back into the same horde", function()
			local ResumePoints = load_resume_points()
			ResumePoints.remember("mission_horde", "mission_horde/a.mp3", 45, 200, false, "mission_boss")
			ResumePoints.enter("mission_boss")

			ResumePoints.remember("mission_boss", "mission_boss/b.mp3", 20, 200, false, "mission_horde")
			ResumePoints.enter("mission_horde")

			assert_deep_equal({ ResumePoints.take("mission_horde") }, { "mission_horde/a.mp3", 45 })
			assert_equal(ResumePoints.take("mission_boss"), nil)
		end)

		it("continues an event song after a last stand", function()
			local ResumePoints = load_resume_points()

			assert_equal(ResumePoints.remember("mission_event", "mission_event/a.mp3", 45, 200, false, "mission_last_stand"), 45)
			ResumePoints.enter("mission_last_stand")
			ResumePoints.enter("mission_event")

			assert_deep_equal({ ResumePoints.take("mission_event") }, { "mission_event/a.mp3", 45 })
		end)

		it("ends an event's song when the music drops to a boss, a horde, combat, or explore", function()
			for _, next_context in ipairs({ "mission_boss", "mission_horde", "mission_combat", "mission_explore" }) do
				local ResumePoints = load_resume_points()
				assert_equal(ResumePoints.remember("mission_event", "mission_event/a.mp3", 45, 200, false, next_context), nil, next_context)

				ResumePoints.remember("mission_event", "mission_event/a.mp3", 45, 200, false, "mission_last_stand")
				ResumePoints.enter("mission_last_stand")
				ResumePoints.enter(next_context)

				assert_equal(ResumePoints.take("mission_event"), nil, next_context)
			end
		end)
	end)
end)
