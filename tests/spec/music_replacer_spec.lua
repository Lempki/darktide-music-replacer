-- Pins MusicReplacer.lua, which ties the context to the library, the audio client, suppression, and resume points.
-- The context, suppression, and resume logic are real. The library and the audio client are stand-ins from main_harness.lua.

local MainHarness = require("tests.helpers.main_harness")

local TWO_HUB_SONGS = { hub = { { name = "a.mp3", duration = 200 }, { name = "b.mp3", duration = 180 } } }

-- Returns a harness that has settled in the hub, with `files` in the library.
local function in_hub(files, options)
	options = options or {}
	options.files = files or TWO_HUB_SONGS
	local harness = MainHarness.new(options)
	harness:cold_start_to_hub()
	harness:settle()
	return harness
end

-- Returns a harness that has settled into a mission's explore music, with explore and combat songs.
local function in_mission(settings)
	local harness = MainHarness.new({
		settings = settings,
		files = {
			explore = { { name = "x.mp3", duration = 300 }, { name = "y.mp3", duration = 300 } },
			combat = { { name = "c.mp3", duration = 200 }, { name = "d.mp3", duration = 200 } },
		},
	})
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission("lm_cooling", "zone_3")
	harness:settle()
	return harness
end

describe("MusicReplacer.lua context changes", function()
	it("plays a context's song once the change has settled for 0.6 seconds, fading in and fading out at its end", function()
		local harness = MainHarness.new({ files = TWO_HUB_SONGS })
		harness:cold_start_to_hub()

		harness:wait(0.5)
		assert_equal(harness:last_play(), nil)

		harness:wait(0.2)
		local play = harness:last_play()
		assert_equal(play.file_path, "hub/a.mp3")
		assert_equal(play.opts.fade_in, true)
		assert_equal(play.opts.loop, false)
		assert_equal(play.opts.duration_seconds, 200)
		assert_equal(harness.engine:wwise_state("music_zone"), "None")
	end)

	it("loops a folder's only song, with no end fade", function()
		local harness = in_hub({ hub = { { name = "only.mp3", duration = 200 } } })

		assert_equal(harness:last_play().opts.loop, true)
		assert_equal(harness:last_play().opts.duration_seconds, nil)
	end)

	it("does not restart the song for a state that flickers and returns within the debounce", function()
		local harness = in_mission({ combat_hold_seconds = 0 })
		local plays = #harness.client.plays

		harness:state("music_combat", "normal")
		harness:wait(0.2)
		harness:state("music_combat", "None")
		harness:wait(2)

		assert_equal(#harness.client.plays, plays)
	end)

	-- With both holds at 0, a fight's combat state drops out for a moment every half second or so.
	-- The pending change then commits whichever context is pending once 3 seconds have passed.
	it("still switches to combat within about 3 seconds while a fight keeps flickering", function()
		local harness = in_mission({ combat_hold_seconds = 0 })

		for _ = 1, 5 do
			harness:state("music_combat", "normal")
			harness:wait(0.5)
			harness:state("music_combat", "None")
			harness:wait(0.2)
		end

		local played_combat = false
		for _, play in ipairs(harness.client.plays) do
			played_combat = played_combat or play.file_path:find("^combat/") ~= nil
		end
		assert_equal(played_combat, true)
	end)

	it("leaves the game's own music alone for a context with no songs", function()
		local harness = MainHarness.new({ files = TWO_HUB_SONGS })
		harness:cold_start_to_hub()
		harness:settle()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		harness:settle()

		assert_equal(harness:playing(), nil)
		assert_equal(harness:logged("[playback] explore: no file available, playing the game's music"), true)

		harness:state("music_combat", "normal")
		assert_equal(harness.engine:wwise_state("music_combat"), "normal")
	end)
end)

describe("MusicReplacer.lua songs that end", function()
	it("moves on to the next song when one plays to its end", function()
		local harness = in_hub()

		for _ = 1, 5 do
			harness:finish_song(190, false)
		end

		assert_equal(#harness.client.plays, 6)
		assert_equal(harness:last_play().opts.fade_in, false)
		assert_equal(harness:playing() ~= nil, true)
	end)

	it("gives up on a context after 3 songs in a row fail to open, and hands the music back to the game", function()
		local harness = in_hub()

		for _ = 1, 3 do
			harness:finish_song(0, true)
		end

		assert_equal(#harness.client.plays, 3)
		assert_equal(harness:playing(), nil)
		assert_equal(harness.engine:wwise_state("music_zone"), "hub")
		assert_equal(harness:logged("playing the game's music until the game restarts or the folders are rescanned"), true)
	end)

	it("does not count a short song that played through, by its decoder's length while the library has none", function()
		local harness = in_hub({ hub = { { name = "short.mp3" }, { name = "other.mp3" } } })

		for _ = 1, 3 do
			harness:finish_song(2, false, 2)
		end

		assert_equal(#harness.client.plays, 4)
		assert_equal(harness:playing() ~= nil, true)
	end)

	it("tries a context again after a rescan, once it gave up", function()
		local harness = in_hub()
		for _ = 1, 3 do
			harness:finish_song(0, true)
		end

		harness.mod.rescan_audio()
		harness:tick(0.1)

		assert_equal(#harness.client.plays, 4)
		assert_equal(harness:playing() ~= nil, true)
	end)

	it("counts songs of unknown length that end at once, so they cannot reopen every frame", function()
		local harness = in_hub({ hub = { { name = "a.mp3" }, { name = "b.mp3" } } })

		for _ = 1, 3 do
			harness:finish_song(0.1, false)
		end

		assert_equal(harness:playing(), nil)
		assert_equal(#harness.client.plays, 3)
	end)

	it("does not count short songs that play through", function()
		local harness = in_hub({ hub = { { name = "a.mp3", duration = 2 }, { name = "b.mp3", duration = 2 } } })

		for _ = 1, 5 do
			harness:finish_song(2, false)
		end

		assert_equal(#harness.client.plays, 6)
		assert_equal(harness:playing() ~= nil, true)
	end)
end)

describe("MusicReplacer.lua resume points", function()
	it("resumes the explore song where it stopped once combat is over", function()
		local harness = in_mission()
		local explore_song = harness:playing()
		harness.client.position = 42

		harness:state("music_combat", "normal")
		harness:settle()
		assert_equal(harness:playing():find("^combat/") ~= nil, true)

		harness:state("music_combat", "None")
		harness:wait(8)
		harness:settle()

		assert_equal(harness:playing(), explore_song)
		assert_equal(harness:last_play().opts.start_position, 42)
	end)

	it("forgets where songs stopped when Resume Songs is turned off", function()
		local harness = in_mission()
		harness.client.position = 42
		harness:state("music_combat", "normal")
		harness:settle()

		harness:set_setting("resume_songs", false)
		harness:state("music_combat", "None")
		harness:wait(8)
		harness:settle()

		assert_equal(harness:last_play().opts.start_position, nil)
	end)
end)

describe("MusicReplacer.lua rescans", function()
	it("keeps the song that is playing", function()
		local harness = in_hub()
		local plays = #harness.client.plays

		harness.mod.rescan_audio()
		harness:tick(0.1)

		assert_equal(#harness.client.plays, plays)
	end)

	it("starts a song at once for a context that had none", function()
		local harness = in_hub({ hub = {} })
		assert_equal(harness:playing(), nil)

		harness.library.files.hub = { { name = "new.mp3", duration = 200 } }
		harness.mod.rescan_audio()
		harness:tick(0.1)

		assert_equal(harness:playing(), "hub/new.mp3")
	end)
end)

describe("MusicReplacer.lua music per situation", function()
	it("leaves a context set to Vanilla to the game, even with songs in its folder", function()
		local harness = in_hub(nil, { settings = { source_hub = "game" } })

		assert_equal(harness:last_play(), nil)
		assert_equal(harness.engine:wwise_state("music_zone"), "hub")
		assert_equal(harness:logged("[playback] hub: set to the game's own music"), true)
	end)

	it("silences a context set to Silence, playing nothing", function()
		local harness = in_hub(nil, { settings = { source_hub = "silence" } })

		assert_equal(harness:last_play(), nil)
		assert_equal(harness.engine:wwise_state("music_zone"), "None")
	end)

	it("follows a changed setting for the context playing now at once", function()
		local harness = in_hub()

		harness:set_setting("source_hub", "game")
		assert_equal(harness:playing(), nil)
		assert_equal(harness.engine:wwise_state("music_zone"), "hub")

		harness:set_setting("source_hub", "custom")
		assert_equal(harness:playing() ~= nil, true)
		assert_equal(harness.engine:wwise_state("music_zone"), "None")
	end)

	it("follows a Meat Grinder change between Silence and Vanilla at once, during the visit", function()
		local harness = MainHarness.new({ settings = { source_meat_grinder = "silence" }, files = {} })
		harness:cold_start_to_hub()
		harness:state("music_zone", "None")
		harness:state("music_game_state", "loading")
		harness:mission(nil)
		harness:wait(3)
		harness:mission("tg_shooting_range")
		harness:state("music_game_state", "mission")
		harness:settle()
		assert_equal(harness:logged("[playback] meat_grinder: set to silence"), true)

		harness:set_setting("source_meat_grinder", "game")

		assert_equal(harness:logged("[playback] meat_grinder: set to the game's own music"), true)
	end)
end)

describe("MusicReplacer.lua menus", function()
	it("plays the title screen's songs over the game's menu music, and leaves an empty character select to the game", function()
		local harness = MainHarness.new({ files = { title_screen = { { name = "t.mp3", duration = 200 } } } })

		harness:state("music_game_state", "title")
		harness:settle()
		assert_equal(harness:playing(), "title_screen/t.mp3")
		assert_equal(harness.engine:wwise_state("music_game_state"), "None")

		harness:state("music_game_state", "main_menu")
		harness:settle()
		assert_equal(harness:playing(), nil)
		assert_equal(harness.engine:wwise_state("music_game_state"), "main_menu")
	end)
end)

describe("MusicReplacer.lua the same lone song in two folders", function()
	-- Returns a harness that plays the title screen's song, with `character_select` as character select's files.
	local function on_title_screen(character_select)
		local harness = MainHarness.new({ files = { title_screen = { { name = "a.mp3", duration = 200 } }, character_select = character_select } })
		harness:state("music_game_state", "title")
		harness:settle()
		return harness
	end

	it("keeps playing it into the next context instead of starting it over", function()
		local harness = on_title_screen({ { name = "a.mp3", duration = 200 } })

		harness:state("music_game_state", "main_menu")
		harness:settle()

		assert_equal(#harness.client.plays, 1)
		assert_equal(harness:playing(), "character_select/a.mp3")
		assert_equal(harness:logged("[playback] character_select: continuing character_select/a.mp3, the same song as title_screen/a.mp3"), true)
		assert_equal(harness.engine:wwise_state("music_game_state"), "None")
	end)

	it("counts a failure of the continued song against the context it continued into", function()
		local harness = on_title_screen({ { name = "a.mp3", duration = 200 } })
		harness:state("music_game_state", "main_menu")
		harness:settle()

		harness:finish_song(0, true)

		assert_equal(harness:last_play().file_path, "character_select/a.mp3")
	end)

	it("starts over for a different file of the same name, or a folder with more than that song", function()
		local resized = on_title_screen({ { name = "a.mp3", duration = 200, size = 2 } })
		resized:state("music_game_state", "main_menu")
		resized:settle()
		assert_equal(#resized.client.plays, 2)

		local several = on_title_screen({ { name = "a.mp3", duration = 200 }, { name = "b.mp3", duration = 200 } })
		several:state("music_game_state", "main_menu")
		several:settle()
		assert_equal(#several.client.plays, 2)
	end)
end)

describe("MusicReplacer.lua music events from the game", function()
	local EXPLORATION_EVENT = "wwise/events/music/play_exploration_music"

	it("stops the game's exploration music event at once while a custom song plays, and returns the game's IDs", function()
		local harness = in_mission()

		local playing_id, source_id = CLASS.WwiseWorld.trigger_resource_event({}, EXPLORATION_EVENT)

		assert_deep_equal(harness.engine.started_events, { EXPLORATION_EVENT })
		assert_deep_equal(harness.engine.stopped_events, { playing_id })
		assert_equal(source_id ~= nil, true)
	end)

	it("lets cutscene music play, and stops it once a custom song takes over", function()
		local harness = in_mission({ source_explore = "game" })
		local playing_id = CLASS.WwiseWorld.trigger_resource_event({}, "wwise/events/cinematics/play_cs03_music_116bpm")
		assert_deep_equal(harness.engine.stopped_events, {})

		harness:set_setting("source_explore", "custom")
		harness:settle()

		assert_deep_equal(harness.engine.stopped_events, { playing_id })
	end)

	-- A story mission's score screen leads through its debrief cutscene into the hub, with no loading screen in between.
	it("forgets a level's cutscene music once the level ends, even with no loading screen after it", function()
		local harness = MainHarness.new({
			files = { explore = { { name = "x.mp3", duration = 300 } }, hub = TWO_HUB_SONGS.hub },
		})
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		harness:settle()
		CLASS.WwiseWorld.trigger_resource_event({}, "wwise/events/cinematics/play_cs03_music_116bpm")

		harness:state("music_game_state", "victory")
		harness:wait(8)
		harness:state("music_game_state", "mission")
		harness:state("music_zone", "None")
		harness:state("music_game_state", "game_score_win")
		harness:wait(56)
		harness.engine.wwise_game_sync:on_gameplay_shutdown()
		harness:mission(nil)
		harness:debrief_cutscene_to_hub()
		harness:settle()

		assert_equal(harness:playing():match("^hub/") ~= nil, true)
		assert_deep_equal(harness.engine.stopped_events, {})
	end)

	-- DMF disables the mod's hooks while it is off, so the level the cutscene music belonged to may have ended unseen.
	it("forgets cutscene music when the mod is turned off", function()
		local harness = in_mission({ source_explore = "game" })
		CLASS.WwiseWorld.trigger_resource_event({}, "wwise/events/cinematics/play_cs03_music_116bpm")

		harness.mod.on_disabled(false)
		harness.mod.on_enabled(false)
		harness.engine:reassert_states({ "music_game_state", "music_zone", "music_combat", "music_objective" })
		harness:set_setting("source_explore", "custom")
		harness:settle()

		assert_equal(harness:playing() ~= nil, true)
		assert_deep_equal(harness.engine.stopped_events, {})
	end)

	it("lets the event play while the game's music plays", function()
		local harness = in_mission({ source_explore = "game" })

		local playing_id = CLASS.WwiseWorld.trigger_resource_event({}, EXPLORATION_EVENT)

		assert_equal(playing_id ~= nil, true)
		assert_deep_equal(harness.engine.stopped_events, {})
	end)
end)

describe("MusicReplacer.lua volume", function()
	it("sets the Custom Music Volume at startup and follows its changes", function()
		local harness = in_hub(nil, { settings = { custom_music_volume = 80 } })
		assert_equal(harness.client.volume, 0.8)

		harness:set_setting("custom_music_volume", 30)
		assert_equal(harness.client.volume, 0.3)
	end)

	it("lowers the music to the Menu Volume while a menu is open, and raises it once the menu closes", function()
		local harness = in_hub(nil, { settings = { menu_volume = 40 } })
		assert_equal(harness.client.menu_volume, 1)

		harness:state("options", "ingame_menu")
		harness:tick(0.1)
		assert_equal(harness.client.menu_volume, 0.4)

		harness:state("options", "None")
		harness:wait(0.6)
		assert_equal(harness.client.menu_volume, 1)
	end)

	it("keeps the music lowered while moving from one menu to another", function()
		local harness = in_hub(nil, { settings = { menu_volume = 40 } })
		harness:state("options", "vendor_menu")
		harness:tick(0.1)

		harness:state("options", "None")
		harness:wait(0.3)
		assert_equal(harness.client.menu_volume, 0.4)

		harness:state("options", "ingame_menu")
		harness:wait(1)
		assert_equal(harness.client.menu_volume, 0.4)
	end)
end)

describe("MusicReplacer.lua evening out loudness", function()
	it("measures in the background only while the mod is on, starting with the context playing now", function()
		local harness = in_hub()
		assert_equal(harness.loudness.preferred_contexts[#harness.loudness.preferred_contexts], "hub")

		local updates = #harness.loudness.preferred_contexts
		harness.mod.on_disabled(false)
		harness:wait(1)
		assert_equal(#harness.loudness.preferred_contexts, updates)
	end)

	it("turns evening out on and off with its setting, applying it to the songs playing now", function()
		local harness = in_hub()
		assert_equal(harness.loudness.enabled, false)

		harness:set_setting("normalize_loudness", true)

		assert_equal(harness.loudness.enabled, true)
		assert_equal(harness.client.levels_refreshed, 1)
		assert_equal(harness:logged("[loudness] evening out turned on"), true)
	end)

	it("logs each song's loudness with its playback line while evening out is on", function()
		local harness = MainHarness.new({ files = TWO_HUB_SONGS, settings = { normalize_loudness = true } })
		harness.loudness.levels["hub/a.mp3"] = 0.5
		harness:cold_start_to_hub()
		harness:settle()

		assert_equal(harness:logged("[playback] hub: playing hub/a.mp3 (duration=200, level 0.50)"), true)
	end)
end)

describe("MusicReplacer.lua loading", function()
	local FILES = {
		hub = { { name = "h.mp3", duration = 300 } },
		loading = { { name = "l1.mp3", duration = 300 } },
		mission_briefing = { { name = "m1.mp3", duration = 300 }, { name = "m2.mp3", duration = 300 } },
		mission_preparation = { { name = "p.mp3", duration = 300 } },
		explore = { { name = "x.mp3", duration = 300 } },
	}

	-- Returns a harness that has settled in the hub, after the first loading screen played l1.mp3.
	local function in_hub_with(files)
		local harness = MainHarness.new({ files = files })
		harness:cold_start_to_hub()
		harness:settle()
		return harness
	end

	it("carries the hub song straight into the preparation song past the short loading screen before it", function()
		local harness = in_hub_with(FILES)
		local plays = #harness.client.plays

		harness:leave_hub()
		harness:wait(2)
		harness:state("music_game_state", "loadout")
		harness:settle()

		assert_equal(#harness.client.plays, plays + 1)
		assert_equal(harness:playing(), "mission_preparation/p.mp3")
		assert_equal(harness.engine:wwise_state("music_game_state"), "None")
	end)

	it("continues a Mission Briefing song the preparation screen interrupted in the briefing, then plays the game's stinger, then explore", function()
		local harness = in_hub_with(FILES)
		harness:leave_hub()
		harness:wait(5)
		assert_equal(harness:playing(), "mission_briefing/m1.mp3")
		harness.client.position = 42

		harness:state("music_game_state", "loadout")
		harness:settle()
		assert_equal(harness:playing(), "mission_preparation/p.mp3")

		harness:state("music_game_state", "loading")
		harness:state("music_game_state", "mission_briefing")
		harness:state("music_zone", "zone_3")
		harness:mission("lm_cooling")
		harness:wait(3.1)

		assert_equal(harness:playing(), "mission_briefing/m1.mp3")
		assert_equal(harness:last_play().opts.start_position, 42)

		harness:state("music_game_state", "mission_intro")
		harness:settle()

		assert_equal(harness:playing(), nil)
		assert_equal(harness.engine:wwise_state("music_game_state"), "mission_intro")

		harness:state("music_game_state", "mission")
		harness:settle()

		assert_equal(harness:playing(), "explore/x.mp3")
	end)

	it("starts the briefing song within the normal wait after the preparation screen, so the game's briefing music barely plays", function()
		local harness = in_hub_with(FILES)
		harness:leave_hub()
		harness:wait(2)
		harness:state("music_game_state", "loadout")
		harness:settle()
		assert_equal(harness:playing(), "mission_preparation/p.mp3")

		harness:state("music_game_state", "loading")
		harness:state("music_game_state", "mission_briefing")
		harness:wait(0.7)

		assert_equal(harness:playing():find("^mission_briefing/") ~= nil, true)
	end)

	-- The prologue reports its level for about two seconds before its intro starts.
	it("waits out an intro that follows a level's arrival straight from a loading screen, and plays nothing of the level before it", function()
		local harness = in_hub_with(FILES)
		harness:leave_hub()
		harness:wait(5)
		local plays = #harness.client.plays

		harness:state("music_zone", "prologue")
		harness:mission("prologue")
		harness:state("music_game_state", "mission")
		harness:wait(2)
		harness:state("music_game_state", "mission_intro")
		harness:settle()

		assert_equal(#harness.client.plays, plays)
		assert_equal(harness:playing(), nil)
	end)

	it("plays a level reached straight from a loading screen after the long wait, as when joining a mission in progress", function()
		local harness = in_hub_with(FILES)
		harness:leave_hub()
		harness:wait(5)

		harness:state("music_zone", "zone_3")
		harness:mission("lm_cooling")
		harness:state("music_game_state", "mission")
		harness:wait(2.5)
		assert_equal(harness:playing():find("^mission_briefing/") ~= nil, true)

		harness:wait(0.6)
		assert_equal(harness:playing(), "explore/x.mp3")
	end)

	it("leaves loading screens to the game's own music while the loading folder is empty", function()
		local harness = in_hub_with({ hub = FILES.hub })

		harness:leave_hub()
		harness:wait(3.1)

		assert_equal(harness:playing(), nil)
		assert_equal(harness.engine:wwise_state("music_game_state"), "loading")
		assert_equal(harness:logged("[playback] mission_briefing: no file available, playing the game's music"), true)
	end)

	it("plays the loading folder, not the mission briefing one, on the way back to the hub", function()
		local harness = in_hub_with(FILES)
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		harness:settle()

		harness:end_with_victory("zone_3")
		harness:wait(3.1)

		assert_equal(harness:playing(), "loading/l1.mp3")
	end)
end)

describe("MusicReplacer.lua fade length", function()
	it("gives the audio client the Fade Length at start and whenever it changes", function()
		local harness = MainHarness.new({ files = { hub = { { name = "a.mp3", duration = 200 } } } })
		assert_equal(harness.client.fade_seconds, 2)

		harness:set_setting("fade_seconds", 4.5)

		assert_equal(harness.client.fade_seconds, 4.5)
	end)
end)

describe("MusicReplacer.lua debug overlay", function()
	it("follows its settings", function()
		local harness = in_hub()
		assert_equal(harness.overlay.enabled, false)

		harness:set_setting("debug_overlay_scale", 150)
		harness:set_setting("debug_overlay_opacity", 40)
		harness:set_setting("debug_overlay", true)

		assert_equal(harness.overlay.enabled, true)
		assert_equal(harness.overlay.scale, 1.5)
		assert_equal(harness.overlay.opacity, 0.4)
	end)

	it("reports the context, its choice, and the song playing", function()
		local harness = in_hub()
		harness.client.position = 12

		local snapshot = harness.overlay.options.snapshot()

		assert_equal(snapshot.context, "hub")
		assert_equal(snapshot.situation, "<source_hub>")
		assert_equal(snapshot.status, "Custom")
		assert_equal(snapshot.song, "a.mp3")
		assert_equal(snapshot.position, 12)
		assert_equal(snapshot.duration, 200)
		assert_equal(snapshot.pending, nil)
	end)

	it("reports why the game's music plays, and a change that is still settling", function()
		local harness = in_hub({ hub = {} })

		local snapshot = harness.overlay.options.snapshot()
		assert_equal(snapshot.status, "Vanilla, no songs")
		assert_equal(snapshot.song, nil)

		harness:state("music_game_state", "mission_board")
		harness:state("music_zone", "None")
		harness:tick(0.2)

		snapshot = harness.overlay.options.snapshot()
		assert_equal(snapshot.pending, "none")
		assert_equal(math.abs(snapshot.pending_seconds - 0.4) < 1e-9, true)
	end)

	-- A mission always offers its code as an override name, but a situation that plays no folder looks for none.
	it("reports override names only while the situation plays from a folder", function()
		local harness = in_mission()
		assert_equal(harness.overlay.options.snapshot().overrides, "lm_cooling")

		harness:set_setting("source_explore", "game")
		assert_equal(harness.overlay.options.snapshot().overrides, nil)

		harness:set_setting("source_explore", "silence")
		assert_equal(harness.overlay.options.snapshot().overrides, nil)
	end)

	it("reports that the mod is turned off", function()
		local harness = in_hub()
		harness.mod.on_disabled(false)

		assert_deep_equal(harness.overlay.options.snapshot(), { turned_off = true })
	end)
end)

describe("MusicReplacer.lua override folders", function()
	-- Returns a harness that has settled into lm_cooling's explore music, with `files` in the library.
	local function in_cooling(files, settings)
		local harness = MainHarness.new({ files = files, settings = settings })
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		harness:settle()
		return harness
	end

	it("plays the mission's override folder over the context's own", function()
		local harness = in_cooling({
			explore = { { name = "x.mp3", duration = 300 } },
			["explore/lm_cooling"] = { { name = "cooling.mp3", duration = 300 } },
		})

		assert_equal(harness:playing(), "explore/lm_cooling/cooling.mp3")
	end)

	it("plays the context's own folder while no override folder has songs", function()
		local harness = in_cooling({
			explore = { { name = "x.mp3", duration = 300 } },
			["explore/fm_cargo"] = { { name = "cargo.mp3", duration = 300 } },
		})

		assert_equal(harness:playing(), "explore/x.mp3")
	end)

	it("switches to the boss's folder once the game names the boss, after its music already started", function()
		local harness = in_cooling({
			boss = { { name = "b.mp3", duration = 300 } },
			["boss/chaos_spawn"] = { { name = "spawn.mp3", duration = 300 } },
		})
		harness:state("music_combat", "boss")
		harness:settle()
		assert_equal(harness:playing(), "boss/b.mp3")

		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:wait(0.6)

		assert_equal(harness:playing(), "boss/chaos_spawn/spawn.mp3")
		assert_equal(harness:logged("[playback] boss: switching from the boss folder to the boss/chaos_spawn folder"), true)
	end)

	it("falls back to the context's own folder once an override folder's songs would not play", function()
		local harness = in_cooling({
			boss = { { name = "b.mp3", duration = 300 } },
			["boss/chaos_spawn"] = { { name = "spawn.mp3", duration = 300 }, { name = "spawn2.mp3", duration = 300 } },
		})
		harness:state("music_combat", "boss")
		harness:settle()
		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:wait(0.6)
		assert_equal(harness:playing(), "boss/chaos_spawn/spawn.mp3")

		for _ = 1, 3 do
			harness:finish_song(0, true)
		end

		assert_equal(harness:playing(), "boss/b.mp3")
		assert_equal(harness:logged("from the boss/chaos_spawn folder ended within 3s, trying the next folder"), true)

		harness:wait(1)
		assert_equal(harness:playing(), "boss/b.mp3")
	end)

	it("plays the context's own folder when an override folder's files are gone from disk, without switching back", function()
		local harness = MainHarness.new({ files = {
			explore = { { name = "x.mp3", duration = 300 } },
			["explore/lm_cooling"] = { { name = "cooling.mp3", duration = 300 } },
		} })
		harness.library.gone["explore/lm_cooling"] = true
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("lm_cooling", "zone_3")
		harness:settle()
		local plays = #harness.client.plays

		harness:wait(2)

		assert_equal(harness:playing(), "explore/x.mp3")
		assert_equal(#harness.client.plays, plays)
		assert_equal(harness:logged("[playback] explore: the explore/lm_cooling folder has no songs left, trying the next folder"), true)
	end)

	it("plays an event kind's folder even while the event's own folder is empty", function()
		local harness = in_cooling({
			["event/escape_event"] = { { name = "escape.mp3", duration = 300 } },
		})

		harness:state("music_objective", "kill_event")
		harness:settle()
		assert_equal(harness:playing(), nil)

		harness:state("music_objective", "escape_event")
		harness:wait(0.6)
		assert_equal(harness:playing(), "event/escape_event/escape.mp3")
	end)

	it("looks for no override while a context is set to the game's own music", function()
		local harness = in_cooling({
			["boss/chaos_spawn"] = { { name = "spawn.mp3", duration = 300 } },
		}, { source_boss = "game" })
		harness:state("music_combat", "boss")
		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:wait(1.2)

		assert_equal(harness:playing(), nil)
	end)
end)

describe("MusicReplacer.lua when playback stops working", function()
	it("hands the music back to the game at once, and takes over again once playback works", function()
		local harness = in_hub()

		harness.client.available = false
		harness:tick(0.1)
		assert_equal(harness.engine:wwise_state("music_zone"), "hub")

		harness.client.available = true
		harness:tick(0.1)
		assert_equal(harness:playing() ~= nil, true)
		assert_equal(harness.engine:wwise_state("music_zone"), "None")
	end)

	it("continues the song where it was once playback works again", function()
		local harness = in_hub()
		local song = harness:playing()
		harness.client.position = 64
		harness:tick(0.1)

		-- Losing the output takes the song with it.
		harness.client.available = false
		harness.client.current = nil
		harness:tick(0.1)
		harness.client.available = true
		harness:tick(0.1)

		assert_equal(harness:playing(), song)
		assert_equal(harness:last_play().opts.start_position, 64)
	end)

	it("starts a new song once playback works again when none was playing as it stopped", function()
		local harness = in_hub()
		harness:set_setting("source_hub", "game")
		harness:tick(0.1)

		harness.client.available = false
		harness:tick(0.1)
		harness.client.available = true
		harness:set_setting("source_hub", "custom")
		harness:tick(0.1)

		assert_equal(harness:last_play().opts.start_position, nil)
	end)
end)

describe("MusicReplacer.lua during a change that is still settling", function()
	it("waits for the change to commit before following a changed setting, so the music switches once", function()
		local harness = in_mission({ combat_hold_seconds = 0 })
		local stops = harness.client.stops
		harness:state("music_combat", "normal")

		harness:set_setting("source_explore", "game")
		assert_equal(harness.client.stops, stops)

		harness:wait(0.7)
		assert_equal(harness:playing():find("^combat/") ~= nil, true)
	end)

	it("still follows the changed setting when the change settles back on the same context", function()
		local harness = in_mission({ combat_hold_seconds = 0 })
		harness:state("music_combat", "normal")
		harness:state("music_combat", "None")

		harness:set_setting("source_explore", "game")
		harness:wait(0.7)

		assert_equal(harness:playing(), nil)
		assert_equal(harness:logged("[playback] explore: set to the game's own music"), true)
	end)
end)

describe("MusicReplacer.lua turned off and on", function()
	it("lets playback try again after giving up when turned back on or when Rescan is pressed", function()
		local harness = in_hub()

		harness.mod.on_disabled(false)
		harness.mod.on_enabled(false)
		harness.mod.rescan_audio()

		assert_equal(harness.client.tries_again, 2)
	end)

	it("hands the music back to the game at once when turned off, and plays again when turned back on", function()
		local harness = in_hub()

		harness.mod.on_disabled(false)
		assert_equal(harness:playing(), nil)
		assert_equal(harness.engine:wwise_state("music_zone"), "hub")

		harness:wait(5)
		assert_equal(harness:playing(), nil)

		harness.mod.on_enabled(false)
		harness.engine:reassert_states({ "music_game_state", "music_zone", "music_combat", "music_objective" })
		harness:settle()
		assert_equal(harness:playing() ~= nil, true)
	end)

	it("continues the mission's song where it was turned off", function()
		local harness = in_mission()
		local explore_song = harness:playing()
		harness.client.position = 64

		harness.mod.on_disabled(false)
		harness.mod.on_enabled(false)
		harness.engine:reassert_states({ "music_game_state", "music_zone", "music_combat", "music_objective" })
		harness:settle()

		assert_equal(harness:playing(), explore_song)
		assert_equal(harness:last_play().opts.start_position, 64)
	end)

	it("plays nothing while it starts turned off", function()
		local harness = MainHarness.new({ files = TWO_HUB_SONGS, turned_off = true })
		harness:cold_start_to_hub()
		harness:wait(5)

		assert_equal(harness:last_play(), nil)
	end)

	it("finishes every other shutdown step on a reload when one of them fails, and logs it", function()
		local harness = in_hub()
		harness.library.shutdown = function() error("the folder watcher would not close", 0) end

		harness.mod.on_unload(false)

		assert_equal(harness.client.shut_down, true)
		assert_equal(harness.loudness.shut_down, true)
		assert_equal(harness.engine:wwise_state("music_zone"), "hub")
		assert_equal(harness:logged("[mod] shutting down the library failed: the folder watcher would not close"), true)
	end)

	it("hands the music back to the game on a mod reload, but leaves it on game exit", function()
		local harness = in_hub()
		harness.mod.on_unload(false)
		assert_equal(harness.engine:wwise_state("music_zone"), "hub")
		assert_equal(harness.client.shut_down, true)

		local exiting = in_hub()
		exiting.mod.on_unload(true)
		assert_equal(exiting.engine:wwise_state("music_zone"), "None")
	end)
end)
