-- Pins how library.lua lists the audio folders directly through audio_folders.lua, without the Audio Plugin.

local FakeEngine = require("tests.helpers.fake_engine")

local ROOT = "./../mods/MusicReplacer/audio"

-- A fake audio_folders.lua over `disk`, which maps a context to its file names, and `lengths`, which maps a file path to seconds.
local function new_audio_folders(disk, lengths)
	local folders = { created = {}, measured = {} }

	function folders.available() return true end
	function folders.list(folder)
		local context_name = folder:sub(#ROOT + 2)
		local names = disk[context_name]
		return names and { unpack(names) } or nil
	end
	function folders.exists(path)
		local context_name, name = path:sub(#ROOT + 2):match("^([^/]+)/(.+)$")
		for _, listed in ipairs(disk[context_name] or {}) do
			if listed == name then
				return true
			end
		end
		return false
	end
	function folders.create(folder) folders.created[#folders.created + 1] = folder end
	function folders.duration(path)
		local file_path = path:sub(#ROOT + 2)
		folders.measured[#folders.measured + 1] = file_path
		return lengths[file_path]
	end

	return folders
end

-- Returns a library.lua listing `disk` directly, the fake folders, and the logged lines. No Audio Plugin is installed.
local function load_library(disk, lengths)
	local engine = FakeEngine.new()
	local Library = engine:load("library")
	local folders = new_audio_folders(disk, lengths or {})
	local lines = {}
	Library.init(function(line) lines[#lines + 1] = line end, folders)

	return Library, folders, lines
end

describe("library.lua listing folders directly", function()
	it("creates the audio folder and every context folder", function()
		local _, folders = load_library({})

		assert_equal(folders.created[1], ROOT)
		assert_equal(folders.created[2], ROOT .. "/hub")
		assert_equal(#folders.created, 18)
	end)

	it("lists the folders on the first update, without waiting for the game's backend or the Audio Plugin", function()
		local Library, _, lines = load_library({ hub = { "a.mp3" } })

		Library.update(0.016)

		assert_equal(Library.pick_file("hub"), "hub/a.mp3")
		assert_equal(lines[1], "[library] scanning audio folders after 0.0s, listing them directly")
	end)

	it("measures one file's duration per update, and serves it once measured", function()
		local Library, folders, lines = load_library(
			{ hub = { "a.mp3" }, mission_combat = { "b.mp3" } },
			{ ["hub/a.mp3"] = 245.5, ["mission_combat/b.mp3"] = 120 }
		)
		Library.update(0.016)
		assert_deep_equal({ Library.pick_file("hub") }, { "hub/a.mp3", nil, true })

		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3" })
		assert_deep_equal({ Library.pick_file("hub") }, { "hub/a.mp3", 245.5, true })

		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3", "mission_combat/b.mp3" })
		assert_equal(lines[#lines]:find("[library] measured every file's duration", 1, true) ~= nil, true, lines[#lines])
	end)

	it("serves a file that could not be measured with no duration", function()
		local Library = load_library({ hub = { "a.ogg" } })

		for _ = 1, 3 do
			Library.update(0.016)
		end

		assert_deep_equal({ Library.pick_file("hub") }, { "hub/a.ogg", nil, true })
	end)

	it("skips a listed file that has since been deleted, whatever its name", function()
		local disk = { hub = { "Mötley.mp3", "kept.mp3" } }
		local Library = load_library(disk)
		Library.update(0.016)

		disk.hub = { "kept.mp3" }

		for _ = 1, 10 do
			assert_equal(Library.pick_file("hub"), "hub/kept.mp3")
		end
	end)

	it("picks up an added file on a rescan, and measures again", function()
		local disk = { hub = { "a.mp3" } }
		local Library, folders = load_library(disk, { ["hub/a.mp3"] = 100, ["hub/b.mp3"] = 200 })
		Library.update(0.016)
		Library.update(0.016)

		disk.hub = { "a.mp3", "b.mp3" }
		Library.request_rescan()

		assert_equal(Library.update(0.016), true)
		assert_equal(Library.find_file("hub", "hub/b.mp3"), "hub/b.mp3")

		Library.update(0.016)
		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3", "hub/a.mp3", "hub/b.mp3" })
	end)

	it("returns nil for a missing folder", function()
		local Library = load_library({})
		Library.update(0.016)

		assert_equal(Library.pick_file("hub"), nil)
	end)
end)
