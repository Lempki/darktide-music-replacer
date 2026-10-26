-- Pins the override folders inside a context folder: which names context.lua offers, and how library.lua lists them.
-- MusicReplacer.lua's use of them is pinned in music_replacer_spec.lua.

local FakeEngine = require("tests.helpers.fake_engine")
local Harness = require("tests.helpers.context_harness")

local ROOT = "./../mods/MusicReplacer/audio"

-- Returns a harness that has just entered `mission_name` in zone_3.
local function in_mission(mission_name, settings)
	local harness = Harness.new(settings)
	harness:cold_start_to_hub()
	harness:leave_hub()
	harness:enter_mission(mission_name or "fm_cargo", "zone_3")
	return harness
end

describe("context.lua override names", function()
	it("offers the mission's code for any mission context, and nothing of the hub", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "hub"), {})

		harness:leave_hub()
		harness:enter_mission("fm_cargo", "zone_3")

		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "explore"), { "fm_cargo" })
	end)

	it("offers the event's kind first, keeps it through the event hold, and drops it once the event is over", function()
		local harness = in_mission()

		harness:state("music_objective", "fortification_event")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "event"), { "fortification_event", "fm_cargo" })

		harness:state("music_objective", "None")
		harness:wait(2)
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "event"), { "fortification_event", "fm_cargo" })

		harness:state("music_objective", "escape_event")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "event"), { "escape_event", "fm_cargo" })

		harness:state("music_objective", "None")
		harness:wait(5.2)
		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "event"), { "fm_cargo" })
	end)

	it("keeps the event's kind through a cutscene in the middle of the event", function()
		local harness = in_mission()
		harness:state("music_objective", "fortification_event")

		harness:state("music_game_state", "cinematic")
		assert_equal(harness:current(), nil)
		harness:state("music_game_state", "mission")

		assert_equal(harness:current(), "event")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "event"), { "fortification_event", "fm_cargo" })
	end)

	it("offers the boss's kind once the game names it", function()
		local harness = in_mission()
		harness:state("music_combat", "boss")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "boss"), { "fm_cargo" })

		harness:boss_start(harness:new_boss("chaos_spawn"))

		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "boss"), { "chaos_spawn", "fm_cargo" })
	end)

	it("offers a captain's kind during another boss only while captains play boss music", function()
		local harness = in_mission()
		harness:state("music_combat", "boss")
		harness:boss_start(harness:new_boss("chaos_spawn"))
		harness:boss_start(harness:new_boss("renegade_captain"))

		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "boss"), { "chaos_spawn", "fm_cargo" })

		harness:set_setting("captain_boss_music", true)

		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "boss"), { "renegade_captain", "fm_cargo" })
	end)

	-- The game state returns to "mission" for up to a second between matchmaking and the loading screen.
	it("offers matchmaking in the hub by the game's name for it, and nothing 2 seconds after it ends", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()

		harness:state("music_game_state", "mission_ready")
		assert_equal(harness:current(), "hub")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "hub"), { "mission_ready" })

		harness:state("music_game_state", "mission")
		harness:wait(1.9)
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "hub"), { "mission_ready" })

		harness:wait(0.2)
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "hub"), {})
	end)

	it("offers character creation inside character select", function()
		local harness = Harness.new()
		harness:state("music_game_state", "title")
		harness:state("music_game_state", "main_menu")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "character_select"), {})

		harness:state("music_game_state", "character_creation")
		assert_equal(harness:current(), "character_select")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "character_select"), { "character_creation" })
	end)

	it("offers the score screen inside victory and defeat, but not the moment of the win or loss", function()
		local won = in_mission()
		won:state("music_game_state", "victory")
		assert_deep_equal(won.Context.override_keys(won.engine.mod, "victory"), { "fm_cargo" })

		won:state("music_game_state", "mission")
		won:state("music_zone", "None")
		won:state("music_game_state", "game_score_win")
		assert_equal(won:current(), "victory")
		assert_deep_equal(won.Context.override_keys(won.engine.mod, "victory"), { "game_score_win", "fm_cargo" })

		local lost = in_mission()
		lost:state("music_game_state", "defeat")
		lost:state("music_game_state", "mission")
		lost:state("music_zone", "None")
		lost:state("music_game_state", "game_score_lose")
		assert_equal(lost:current(), "defeat")
		assert_deep_equal(lost.Context.override_keys(lost.engine.mod, "defeat"), { "game_score_lose", "fm_cargo" })
	end)

	it("offers the kind of Mortis Trials wave first", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness.engine:set_mechanism_mission("psykhanium", { game_mode_name = "survival" })
		harness:enter_mission("psykhanium", "horde_mode")

		harness:state("music_objective", "horde_mode_wave_last")

		assert_equal(harness:current(), "mortis_trials_wave")
		assert_equal(harness.Context.override_keys(harness.engine.mod, "mortis_trials_wave")[1], "horde_mode_wave_last")
	end)

	it("offers an Expedition fight's level first, keeps it through the combat hold, and drops it once the fight is over", function()
		local harness = Harness.new({ combat_hold_seconds = 8 })
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness:enter_mission("exp_wastes", "expeditions")

		harness:state("music_combat", "low_combat")
		assert_equal(harness.Context.override_keys(harness.engine.mod, "expedition_combat")[1], "low_combat")

		harness:state("music_combat", "high_combat")
		harness:state("music_combat", "no_combat")
		harness:wait(2)
		assert_equal(harness:current(), "expedition_combat")
		assert_equal(harness.Context.override_keys(harness.engine.mod, "expedition_combat")[1], "high_combat")

		harness:wait(7)
		assert_equal(harness:current(), "explore")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "expedition_combat"), { "exp_wastes" })
	end)

	it("offers expeditions during an Expedition, by its game mode", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness.engine:set_mission("exp_wastes", { game_mode_name = "expedition" })
		harness:tick(0)

		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "combat"), { "exp_wastes", "expeditions" })
	end)

	it("offers mortis_trials during Mortis Trials, by its game mode", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness.engine:set_mission("psykhanium", { game_mode_name = "survival" })
		harness:tick(0)

		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "mortis_trials_wave"), { "psykhanium", "mortis_trials" })
	end)

	-- The level names its mission only seconds before the briefing ends, so the briefing would get its override too late.
	it("offers the upcoming mission and its game mode from the mechanism data on the way into a mission", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness.engine:set_mechanism_mission("hub_ship", { is_hub = true })
		harness:state("music_game_state", "mission_board")
		harness:state("music_game_state", "mission_ready")
		harness:tick(0)
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "hub"), { "mission_ready" })

		harness:leave_hub()
		harness.engine:set_mechanism_mission("psykhanium", { game_mode_name = "survival" })
		harness:tick(0)

		assert_equal(harness:current(), "mission_briefing")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "mission_briefing"), { "psykhanium", "mortis_trials" })
	end)

	it("offers an upcoming Expedition through the preparation screen and the briefing", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness.engine:set_mechanism_mission("exp_wastes", { game_mode_name = "expedition" })
		harness:state("music_game_state", "loadout")
		harness:tick(0)

		assert_equal(harness:current(), "mission_preparation")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "mission_preparation"), { "exp_wastes", "expeditions" })

		harness:state("music_game_state", "loading")
		harness:state("music_game_state", "mission_briefing")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "mission_briefing"), { "exp_wastes", "expeditions" })
	end)

	-- After a mission, the mechanism data still names it until the hub loads.
	it("offers no upcoming mission on a loading screen out of a mission", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		harness.engine:set_mechanism_mission("psykhanium", { game_mode_name = "survival" })
		harness:enter_mission("psykhanium", "horde_mode")
		harness:end_with_victory("horde_mode")
		harness:tick(0)

		assert_equal(harness:current(), "loading")
		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "loading"), {})
	end)

	it("offers havoc while the game has Havoc data, which is how the game itself tells a Havoc run apart", function()
		local harness = Harness.new()
		harness:cold_start_to_hub()
		harness:leave_hub()
		rawset(Managers.state, "difficulty", { get_parsed_havoc_data = function() return { rank = 20 } end })
		harness:enter_mission("fm_cargo", "zone_3")

		assert_deep_equal(harness.Context.override_keys(harness.engine.mod, "horde"), { "fm_cargo", "havoc" })
	end)
end)

-- A fake audio_folders.lua over `disk`, which maps a folder key to its file names, with subfolders found from the keys.
local function new_audio_folders(disk)
	local folders = {}

	function folders.available() return true end
	function folders.create() end
	function folders.watch() return { changed = function() return false end, close = function() end } end
	function folders.exists() return true end
	function folders.duration() return 100 end
	-- Windows ignores case in paths, so the fake does too.
	function folders.list(folder)
		local wanted = folder:sub(#ROOT + 2):lower()
		for key, names in pairs(disk) do
			if key:lower() == wanted then
				return { unpack(names) }
			end
		end
		return nil
	end
	function folders.subfolders(folder)
		local context_name = folder:sub(#ROOT + 2)
		local names = {}
		for key in pairs(disk) do
			local name = key:match("^" .. context_name .. "/(.+)$")
			if name then
				names[#names + 1] = name
			end
		end
		table.sort(names)
		return names
	end

	return folders
end

local function listed_library(disk)
	local engine = FakeEngine.new()
	local Library = engine:load("library")
	local lines = {}
	local listings = {}
	Library.on_listed(function(entries) listings[#listings + 1] = entries end)
	Library.init(function(line) lines[#lines + 1] = line end, new_audio_folders(disk))
	Library.update(0.016)
	return Library, lines, listings
end

describe("library.lua override folders", function()
	it("lists each override folder under its lowercase key, and logs how many files it has", function()
		local Library, lines = listed_library({
			boss = { "b.mp3" },
			["boss/Chaos_Spawn"] = { "spawn.mp3" },
		})

		assert_equal(Library.has_files("boss/chaos_spawn"), true)
		assert_equal(Library.pick_file("boss/chaos_spawn"), "boss/chaos_spawn/spawn.mp3")
		assert_equal(lines[1]:find("boss=1 boss/chaos_spawn=1", 1, true) ~= nil, true, lines[1])
	end)

	it("reports no files for an empty or missing override folder", function()
		local Library = listed_library({ ["event/escape_event"] = {} })

		assert_equal(Library.has_files("event/escape_event"), false)
		assert_equal(Library.has_files("event/kill_event"), false)
		assert_equal(Library.pick_file("event/escape_event"), nil)
	end)

	it("passes override files on with every listing, after their context's own files", function()
		local _, _, listings = listed_library({
			boss = { "b.mp3" },
			["boss/chaos_spawn"] = { "spawn.mp3" },
		})

		local file_paths = {}
		for _, entry in ipairs(listings[1]) do
			file_paths[#file_paths + 1] = entry.file_path
		end
		assert_deep_equal(file_paths, { "boss/b.mp3", "boss/chaos_spawn/spawn.mp3" })
	end)
end)
