-- Checks when library.lua scans the audio folders.

local FakeEngine = require("tests.helpers.fake_engine")

local CONTEXTS = { "hub", "mission_explore", "mission_combat", "mission_boss", "mission_event", "mission_last_stand", "mission_victory", "mission_defeat" }

-- A fake Audio Plugin whose files handlers list `files_by_context` and record which folders were scanned.
local function new_audio_mod(files_by_context)
	local audio = { scanned = {} }

	function audio.new_files_handler(_, context_name)
		audio.scanned[#audio.scanned + 1] = context_name
		local files = files_by_context and files_by_context[context_name] or {}

		return {
			count = function() return #files end,
			lookup = function(_, index) return { file_path = files[index], duration = 60 } end,
		}
	end

	return audio
end

-- Returns a fake engine, the fake Audio Plugin, and a freshly loaded and initialized library.lua.
local function load_library(audio, backend)
	local engine = FakeEngine.new({ mods = { Audio = audio }, backend = backend })
	local Library = engine:load("library")
	Library.init()

	return engine, Library
end

describe("library.lua", function()
	it("does not scan before the game backend is ready", function()
		local audio = new_audio_mod()
		local _, Library = load_library(audio)

		for _ = 1, 100 do
			Library.update(0.1)
		end

		assert_deep_equal(audio.scanned, {})
		assert_equal(Library.pick_file("hub"), nil)
	end)

	it("scans every context folder once, on the first update after the backend is ready", function()
		local audio = new_audio_mod()
		local engine, Library = load_library(audio)

		Library.update(0.1)
		engine:initialize_backend()
		Library.update(0.1)
		Library.update(0.1)

		assert_deep_equal(audio.scanned, CONTEXTS)
	end)

	it("picks a file only once the scan has run", function()
		local audio = new_audio_mod({ hub = { "hub/track.ogg" } })
		local engine, Library = load_library(audio)

		assert_equal(Library.pick_file("hub"), nil)

		engine:initialize_backend()
		Library.update(0.1)

		assert_equal(Library.pick_file("hub"), "hub/track.ogg")
	end)

	it("scans after 30 seconds when the backend gives no ready signal", function()
		local audio = new_audio_mod()
		local _, Library = load_library(audio, {})

		for _ = 1, 29 do
			Library.update(1)
		end
		assert_deep_equal(audio.scanned, {})

		Library.update(1)
		assert_deep_equal(audio.scanned, CONTEXTS)
	end)

	it("does nothing without the Audio Plugin", function()
		local engine, Library = load_library(nil)

		engine:initialize_backend()
		Library.update(60)

		assert_equal(Library.pick_file("hub"), nil)
	end)
end)
