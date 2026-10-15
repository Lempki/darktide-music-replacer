-- Pins how library.lua lists the audio folders through audio_folders.lua and picks a file for a context.

local FakeEngine = require("tests.helpers.fake_engine")

local ROOT = "./../mods/MusicReplacer/audio"

-- A fake audio_folders.lua over `disk`, which maps a context to its file names, and `lengths`, which maps a file path to seconds.
-- `missing` lists file paths that are listed but no longer exist, and `broken` maps a file path Windows cannot open to why.
local function new_audio_folders(disk, lengths, missing, broken)
	local folders = { created = {}, measured = {}, missing = missing or {}, broken = broken or {} }

	function folders.available() return true end
	function folders.list(folder)
		local names = disk[folder:sub(#ROOT + 2)]
		return names and { unpack(names) } or nil
	end
	function folders.exists(path)
		return not folders.missing[path:sub(#ROOT + 2)]
	end
	function folders.create(folder) folders.created[#folders.created + 1] = folder end
	function folders.duration(path)
		local file_path = path:sub(#ROOT + 2)
		folders.measured[#folders.measured + 1] = file_path
		if folders.broken[file_path] then
			return nil, folders.broken[file_path]
		end
		return lengths[file_path]
	end

	return folders
end

-- Returns a library.lua that has listed `disk`, the fake folders, and the logged lines.
local function listed_library(disk, lengths, missing, broken)
	local engine = FakeEngine.new()
	local Library = engine:load("library")
	local folders = new_audio_folders(disk, lengths or {}, missing, broken)
	local lines = {}
	Library.init(function(line) lines[#lines + 1] = line end, folders)
	Library.update(0.016)

	return Library, folders, lines
end

describe("library.lua listing", function()
	it("creates the audio folder and every context folder", function()
		local _, folders = listed_library({})

		assert_equal(folders.created[1], ROOT)
		assert_equal(folders.created[2], ROOT .. "/hub")
		assert_equal(#folders.created, 12)
	end)

	it("lists every folder on the first update, and logs how many files each has", function()
		local Library, _, lines = listed_library({ hub = { "a.mp3" }, mission_boss = { "b.mp3", "c.mp3" } })

		assert_equal(Library.pick_file("hub"), "hub/a.mp3")
		assert_equal(lines[1]:find("[library] listed the audio folders: hub=1 ", 1, true) ~= nil, true, lines[1])
		assert_equal(lines[1]:find("mission_boss=2", 1, true) ~= nil, true, lines[1])
	end)

	it("lists nothing before the first update", function()
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		Library.init(nil, new_audio_folders({ hub = { "a.mp3" } }, {}))

		assert_equal(Library.pick_file("hub"), nil)
	end)

	it("lists nothing without a working audio_folders.lua", function()
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		Library.init(nil, { available = function() return false end })
		Library.update(0.016)

		assert_equal(Library.pick_file("hub"), nil)
		assert_equal(Library.update(0.016), false)
	end)

	it("measures one file's duration per update, and serves it once measured", function()
		local Library, folders, lines = listed_library(
			{ hub = { "a.mp3" }, mission_combat = { "b.mp3" } },
			{ ["hub/a.mp3"] = 245.5, ["mission_combat/b.mp3"] = 120 }
		)
		assert_deep_equal({ Library.pick_file("hub") }, { "hub/a.mp3", nil, true })

		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3" })
		assert_deep_equal({ Library.pick_file("hub") }, { "hub/a.mp3", 245.5, true })

		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3", "mission_combat/b.mp3" })
		assert_equal(lines[#lines]:find("[library] measured every file's duration", 1, true) ~= nil, true, lines[#lines])
	end)

	it("serves a file that opens but reports no duration with no duration", function()
		local Library = listed_library({ hub = { "a.mp3" } })

		Library.update(0.016)

		assert_deep_equal({ Library.pick_file("hub") }, { "hub/a.mp3", nil, true })
	end)

	it("skips a file Windows cannot open once it is measured, and logs why once", function()
		local Library, _, lines = listed_library(
			{ hub = { "bad.mp3", "good.mp3" } },
			{ ["hub/good.mp3"] = 100 },
			{},
			{ ["hub/bad.mp3"] = "opening the file failed with 0xC00D36C4" }
		)
		Library.update(0.016)

		for _ = 1, 10 do
			assert_deep_equal({ Library.pick_file("hub") }, { "hub/good.mp3", nil, true })
		end
		assert_equal(Library.find_file("hub", "hub/bad.mp3"), nil)

		local bad_lines = {}
		for _, line in ipairs(lines) do
			if line:find("bad.mp3", 1, true) then
				bad_lines[#bad_lines + 1] = line
			end
		end
		assert_deep_equal(bad_lines, { "[library] hub/bad.mp3 cannot be played, skipping it: opening the file failed with 0xC00D36C4" })
	end)

	it("returns nil when Windows can open none of a folder's files, so the game's music plays", function()
		local Library = listed_library({ hub = { "bad.mp3" } }, {}, {}, { ["hub/bad.mp3"] = "unsupported" })

		assert_equal(Library.pick_file("hub"), "hub/bad.mp3")
		Library.update(0.016)
		assert_equal(Library.pick_file("hub"), nil)
	end)

	it("tries a skipped file again on a rescan, in case it was replaced", function()
		local Library, folders = listed_library({ hub = { "a.mp3" } }, { ["hub/a.mp3"] = 100 }, {}, { ["hub/a.mp3"] = "unsupported" })
		Library.update(0.016)
		assert_equal(Library.pick_file("hub"), nil)

		folders.broken = {}
		Library.request_rescan()
		Library.update(0.016)
		Library.update(0.016)

		assert_deep_equal({ Library.pick_file("hub") }, { "hub/a.mp3", 100, true })
	end)

	it("picks up an added file on a rescan, and measures every file again", function()
		local disk = { hub = { "a.mp3" } }
		local Library, folders = listed_library(disk, { ["hub/a.mp3"] = 100, ["hub/b.mp3"] = 200 })
		Library.update(0.016)

		disk.hub = { "a.mp3", "b.mp3" }
		Library.request_rescan()

		assert_equal(Library.update(0.016), true)
		assert_equal(Library.find_file("hub", "hub/b.mp3"), "hub/b.mp3")

		Library.update(0.016)
		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3", "hub/a.mp3", "hub/b.mp3" })
	end)

	it("reports no finished rescan when none was requested", function()
		local Library = listed_library({ hub = { "a.mp3" } })

		for _ = 1, 5 do
			assert_equal(Library.update(0.016), false)
		end
	end)
end)

describe("library.lua file selection", function()
	it("returns nil for an empty or missing folder, and for a context it does not know", function()
		local Library = listed_library({ hub = {} })

		assert_equal(Library.pick_file("hub"), nil)
		assert_equal(Library.pick_file("mission_horde"), nil)
		assert_equal(Library.pick_file("not_a_context"), nil)
	end)

	it("never picks the same file twice in a row when there is a choice", function()
		math.randomseed(1)
		local Library = listed_library({ mission_combat = { "a.mp3", "b.mp3", "c.mp3" } })
		local previous = Library.pick_file("mission_combat")

		for _ = 1, 50 do
			local file_path, _, is_only_file = Library.pick_file("mission_combat")

			assert_equal(file_path ~= previous, true, "picked " .. file_path .. " twice in a row")
			assert_equal(is_only_file, false)
			previous = file_path
		end
	end)

	it("alternates between two files", function()
		local Library = listed_library({ hub = { "a.mp3", "b.mp3" } })
		local picks = {}

		for index = 1, 4 do
			picks[index] = Library.pick_file("hub")
		end

		assert_equal(picks[1] ~= picks[2] and picks[1] == picks[3] and picks[2] == picks[4], true, table.concat(picks, ", "))
	end)

	it("skips a listed file that has since been deleted, whatever its name, and logs it once", function()
		local missing = {}
		local Library, _, lines = listed_library({ hub = { "Mötley.mp3", "kept.mp3" } }, {}, missing)
		missing["hub/Mötley.mp3"] = true

		for _ = 1, 10 do
			assert_deep_equal({ Library.pick_file("hub") }, { "hub/kept.mp3", nil, true })
		end

		local missing_lines = 0
		for _, line in ipairs(lines) do
			if line:find("Mötley", 1, true) then
				missing_lines = missing_lines + 1
			end
		end
		assert_equal(missing_lines, 1)
	end)

	it("returns nil when every listed file is missing on disk", function()
		local Library = listed_library({ hub = { "gone.mp3" } }, {}, { ["hub/gone.mp3"] = true })

		assert_equal(Library.pick_file("hub"), nil)
	end)

	it("finds a specific file with the same values as a pick, or nil once the folder no longer has it", function()
		local Library = listed_library({ mission_explore = { "a.mp3", "b.mp3" } }, {}, { ["mission_explore/c.mp3"] = true })

		assert_deep_equal({ Library.find_file("mission_explore", "mission_explore/b.mp3") }, { "mission_explore/b.mp3", nil, false })
		assert_equal(Library.find_file("mission_explore", "mission_explore/gone.mp3"), nil)
	end)

	it("does not change which file pick_file avoids next when finding one", function()
		local Library = listed_library({ hub = { "a.mp3", "b.mp3" } })
		local first = Library.pick_file("hub")

		Library.find_file("hub", first == "hub/a.mp3" and "hub/b.mp3" or "hub/a.mp3")

		assert_equal(Library.pick_file("hub") ~= first, true)
	end)
end)
