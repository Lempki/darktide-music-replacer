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
			mission_explore = { { name = "x.mp3", duration = 300 }, { name = "y.mp3", duration = 300 } },
			mission_combat = { { name = "c.mp3", duration = 200 }, { name = "d.mp3", duration = 200 } },
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
			played_combat = played_combat or play.file_path:find("^mission_combat/") ~= nil
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
		assert_equal(harness:logged("[playback] mission_explore: no file available, using native music"), true)

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
		assert_equal(harness:logged("using native music until the game restarts or the folders are rescanned"), true)
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
		assert_equal(harness:playing():find("^mission_combat/") ~= nil, true)

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

describe("MusicReplacer.lua music per context", function()
	it("leaves a context set to Game's Own to the game, even with songs in its folder", function()
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
		loading = { { name = "l1.mp3", duration = 300 }, { name = "l2.mp3", duration = 300 } },
		mission_preparation = { { name = "p.mp3", duration = 300 } },
		mission_explore = { { name = "x.mp3", duration = 300 } },
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

	it("continues a loading song the preparation screen interrupted in the briefing, then plays the game's stinger, then explore", function()
		local harness = in_hub_with(FILES)
		harness:leave_hub()
		harness:wait(5)
		assert_equal(harness:playing(), "loading/l2.mp3")
		harness.client.position = 42

		harness:state("music_game_state", "loadout")
		harness:settle()
		assert_equal(harness:playing(), "mission_preparation/p.mp3")

		harness:state("music_game_state", "loading")
		harness:state("music_game_state", "mission_briefing")
		harness:state("music_zone", "zone_3")
		harness:mission("lm_cooling")
		harness:wait(3.1)

		assert_equal(harness:playing(), "loading/l2.mp3")
		assert_equal(harness:last_play().opts.start_position, 42)

		harness:state("music_game_state", "mission_intro")
		harness:settle()

		assert_equal(harness:playing(), nil)
		assert_equal(harness.engine:wwise_state("music_game_state"), "mission_intro")

		harness:state("music_game_state", "mission")
		harness:settle()

		assert_equal(harness:playing(), "mission_explore/x.mp3")
	end)

	it("leaves loading screens to the game's own music while the loading folder is empty", function()
		local harness = in_hub_with({ hub = FILES.hub })

		harness:leave_hub()
		harness:wait(3.1)

		assert_equal(harness:playing(), nil)
		assert_equal(harness.engine:wwise_state("music_game_state"), "loading")
		assert_equal(harness:logged("[playback] loading: no file available, using native music"), true)
	end)
end)

describe("MusicReplacer.lua debug overlay", function()
	it("follows its settings", function()
		local harness = in_hub()
		assert_equal(harness.overlay.enabled, false)

		harness:set_setting("debug_overlay_corner", "top_right")
		harness:set_setting("debug_overlay_scale", 150)
		harness:set_setting("debug_overlay", true)

		assert_equal(harness.overlay.enabled, true)
		assert_equal(harness.overlay.corner, "top_right")
		assert_equal(harness.overlay.scale, 1.5)
	end)

	it("reports the context, its choice, and the song playing", function()
		local harness = in_hub()
		harness.client.position = 12

		local snapshot = harness.overlay.options.snapshot()

		assert_equal(snapshot.context, "hub")
		assert_equal(snapshot.status, "Custom")
		assert_equal(snapshot.song, "a.mp3")
		assert_equal(snapshot.position, 12)
		assert_equal(snapshot.duration, 200)
		assert_equal(snapshot.pending, nil)
	end)

	it("reports why the game's music plays, and a change that is still settling", function()
		local harness = in_hub({ hub = {} })

		local snapshot = harness.overlay.options.snapshot()
		assert_equal(snapshot.status, "game's music, no songs")
		assert_equal(snapshot.song, nil)

		harness:state("music_game_state", "mission_board")
		harness:state("music_zone", "None")
		harness:tick(0.2)

		snapshot = harness.overlay.options.snapshot()
		assert_equal(snapshot.pending, "none")
		assert_equal(math.abs(snapshot.pending_seconds - 0.4) < 1e-9, true)
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
			mission_explore = { { name = "x.mp3", duration = 300 } },
			["mission_explore/lm_cooling"] = { { name = "cooling.mp3", duration = 300 } },
		})

		assert_equal(harness:playing(), "mission_explore/lm_cooling/cooling.mp3")
	end)

	it("plays the context's own folder while no override folder has songs", function()
		local harness = in_cooling({
			mission_explore = { { name = "x.mp3", duration = 300 } },
			["mission_explore/fm_cargo"] = { { name = "cargo.mp3", duration = 300 } },
		})

		assert_equal(harness:playing(), "mission_explore/x.mp3")
	end)

	it("switches to the boss's folder once the game names the boss, after its music already started", function()
		local harness = in_cooling({
			mission_boss = { { name = "b.mp3", duration = 300 } },
			["mission_boss/chaos_spawn"] = { { name = "spawn.mp3", duration = 300 } },
		})
		harness:state("music_combat", "boss")
		harness:settle()
		assert_equal(harness:playing(), "mission_boss/b.mp3")

		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:wait(0.6)

		assert_equal(harness:playing(), "mission_boss/chaos_spawn/spawn.mp3")
		assert_equal(harness:logged("[playback] mission_boss: switching from the mission_boss folder to the mission_boss/chaos_spawn folder"), true)
	end)

	it("plays an event kind's folder even while the event's own folder is empty", function()
		local harness = in_cooling({
			["mission_event/escape_event"] = { { name = "escape.mp3", duration = 300 } },
		})

		harness:state("music_objective", "kill_event")
		harness:settle()
		assert_equal(harness:playing(), nil)

		harness:state("music_objective", "escape_event")
		harness:wait(0.6)
		assert_equal(harness:playing(), "mission_event/escape_event/escape.mp3")
	end)

	it("looks for no override while a context is set to the game's own music", function()
		local harness = in_cooling({
			["mission_boss/chaos_spawn"] = { { name = "spawn.mp3", duration = 300 } },
		}, { source_mission_boss = "game" })
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
end)

describe("MusicReplacer.lua turned off and on", function()
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
