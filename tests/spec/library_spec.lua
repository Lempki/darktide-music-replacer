-- Pins how library.lua lists the audio folders through audio_folders.lua and picks a file for a context.

local FakeEngine = require("tests.helpers.fake_engine")

local ROOT = "./../mods/MusicReplacer/audio"

-- A fake audio_folders.lua over `disk`, which maps a context to its file names, and `lengths`, which maps a file path to seconds.
-- `missing` lists file paths that are listed but gone from disk, and `broken` maps a file path Windows cannot open to why.
-- Setting `changes` to true makes the watcher report a change on its next check, and `watch_error` makes watching fail.
local function new_audio_folders(disk, lengths, missing, broken)
	local folders = { created = {}, measured = {}, missing = missing or {}, broken = broken or {}, changes = false, closed = false }

	function folders.available() return true end
	-- Each file's stamp is its name and how many times the folder was listed, as if every file changed between listings.
	folders.listings = 0
	function folders.list(folder)
		local names = disk[folder:sub(#ROOT + 2)]
		if not names then
			return nil
		end
		local stamps = {}
		for _, name in ipairs(names) do
			stamps[name] = name .. "@" .. folders.listings
		end
		return { unpack(names) }, stamps
	end
	-- An override folder is a key with a slash, such as "boss/chaos_spawn", listed under its context.
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
	function folders.exists(path)
		return not folders.missing[path:sub(#ROOT + 2)]
	end
	function folders.create(folder) folders.created[#folders.created + 1] = folder end
	function folders.watch(folder)
		if folders.watch_error then
			return nil, folders.watch_error
		end
		folders.watched = folder
		return {
			changed = function()
				local changed = folders.changes
				folders.changes = false
				return changed
			end,
			close = function() folders.closed = true end,
		}
	end
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

-- The folder's first usable song as file_path, duration, and is_only_file, or nil.
local function first_file(Library, folder_key)
	local entries = Library.usable_entries(folder_key)
	if not entries then
		return nil
	end
	return entries[1].file_path, entries[1].duration, #entries == 1
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
		assert_equal(folders.created[2], ROOT .. "/title_screen")
		assert_equal(folders.created[21], ROOT .. "/meat_grinder")
		assert_equal(#folders.created, 21)
	end)

	it("creates the folders again when Rescan Audio Folders is pressed, so one deleted while the game runs comes back", function()
		local Library, folders = listed_library({})
		folders.created = {}

		Library.request_rescan()

		assert_equal(folders.created[1], ROOT)
		assert_equal(folders.created[3], ROOT .. "/character_select")
		assert_equal(#folders.created, 21)
	end)

	it("leaves the folders alone on a listing the watcher asks for", function()
		local Library, folders = listed_library({})
		folders.created = {}

		folders.changes = true
		Library.update(0.016)
		Library.update(3.1)

		assert_deep_equal(folders.created, {})
	end)

	it("lists every folder on the first update, and logs how many files each has", function()
		local Library, _, lines = listed_library({ hub = { "a.mp3" }, boss = { "b.mp3", "c.mp3" } })

		assert_equal(first_file(Library, "hub"), "hub/a.mp3")
		assert_equal(lines[1]:find("[library] listed the audio folders: title_screen=0 character_select=0 hub=1 ", 1, true) ~= nil, true, lines[1])
		assert_equal(lines[1]:find("boss=2", 1, true) ~= nil, true, lines[1])
	end)

	it("passes every listing on, with each file's stamp, in context order", function()
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		local folders = new_audio_folders({ hub = { "a.mp3" }, boss = { "b.mp3" } }, {})
		local listings = {}
		Library.on_listed(function(entries) listings[#listings + 1] = entries end)
		Library.init(nil, folders)

		Library.update(0.016)
		folders.listings = 1
		Library.request_rescan()
		Library.update(0.016)

		assert_deep_equal(listings, {
			{ { file_path = "hub/a.mp3", stamp = "a.mp3@0" }, { file_path = "boss/b.mp3", stamp = "b.mp3@0" } },
			{ { file_path = "hub/a.mp3", stamp = "a.mp3@1" }, { file_path = "boss/b.mp3", stamp = "b.mp3@1" } },
		})
	end)

	it("reports its first listing as finished, so a context that resolved before it can start its song", function()
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		Library.init(nil, new_audio_folders({ title_screen = { "t.mp3" } }, {}))

		assert_equal(Library.update(0.016), true)
		assert_equal(first_file(Library, "title_screen"), "title_screen/t.mp3")
		assert_equal(Library.update(0.016), false)
	end)

	it("takes two files for one song when they share a name and a size", function()
		local disk = { title_screen = { "a.mp3" }, character_select = { "a.mp3", "b.mp3" }, hub = { "a.mp3" } }
		local sizes = { ["title_screen/a.mp3"] = "100:1:2", ["character_select/a.mp3"] = "100:3:4", ["character_select/b.mp3"] = "100:1:2", ["hub/a.mp3"] = "200:1:2" }
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		local folders = new_audio_folders(disk, {})
		local list = folders.list
		function folders.list(folder)
			local names = list(folder)
			local key = folder:match("([^/]+)$")
			local stamps = {}
			for _, name in ipairs(names or {}) do
				stamps[name] = sizes[key .. "/" .. name]
			end
			return names, names and stamps
		end
		Library.init(nil, folders)
		Library.update(0.016)

		assert_equal(Library.same_song("title_screen/a.mp3", "character_select/a.mp3"), true)
		assert_equal(Library.same_song("title_screen/a.mp3", "character_select/b.mp3"), false)
		assert_equal(Library.same_song("title_screen/a.mp3", "hub/a.mp3"), false)
		assert_equal(Library.same_song("title_screen/a.mp3", nil), false)
	end)

	it("lists nothing before the first update", function()
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		Library.init(nil, new_audio_folders({ hub = { "a.mp3" } }, {}))

		assert_equal(first_file(Library, "hub"), nil)
	end)

	it("lists nothing without a working audio_folders.lua", function()
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		Library.init(nil, { available = function() return false end })
		Library.update(0.016)

		assert_equal(first_file(Library, "hub"), nil)
		assert_equal(Library.update(0.016), false)
	end)

	it("measures one file's duration per update, and serves it once measured", function()
		local Library, folders, lines = listed_library(
			{ hub = { "a.mp3" }, combat = { "b.mp3" } },
			{ ["hub/a.mp3"] = 245.5, ["combat/b.mp3"] = 120 }
		)
		assert_deep_equal({ first_file(Library, "hub") }, { "hub/a.mp3", nil, true })

		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3" })
		assert_deep_equal({ first_file(Library, "hub") }, { "hub/a.mp3", 245.5, true })

		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3", "combat/b.mp3" })
		assert_equal(lines[#lines]:find("[library] measured every file's duration", 1, true) ~= nil, true, lines[#lines])
	end)

	it("serves a file that opens but reports no duration with no duration", function()
		local Library = listed_library({ hub = { "a.mp3" } })

		Library.update(0.016)

		assert_deep_equal({ first_file(Library, "hub") }, { "hub/a.mp3", nil, true })
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
			assert_deep_equal({ first_file(Library, "hub") }, { "hub/good.mp3", nil, true })
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

		assert_equal(first_file(Library, "hub"), "hub/bad.mp3")
		Library.update(0.016)
		assert_equal(first_file(Library, "hub"), nil)
	end)

	it("tries a skipped file again on a rescan, in case it was replaced", function()
		local Library, folders = listed_library({ hub = { "a.mp3" } }, { ["hub/a.mp3"] = 100 }, {}, { ["hub/a.mp3"] = "unsupported" })
		Library.update(0.016)
		assert_equal(first_file(Library, "hub"), nil)

		folders.broken = {}
		Library.request_rescan()
		Library.update(0.016)
		Library.update(0.016)

		assert_deep_equal({ first_file(Library, "hub") }, { "hub/a.mp3", 100, true })
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

describe("library.lua checking a listing", function()
	-- Returns a library.lua that has listed `disk`, the fake folders, and every count its on_checked listener was called with.
	local function checked_library(disk, lengths, broken)
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		local folders = new_audio_folders(disk, lengths or {}, {}, broken)
		local checks = {}
		Library.on_checked(function(counts) checks[#checks + 1] = counts end)
		Library.init(nil, folders)
		Library.update(0.016)
		return Library, folders, checks
	end

	it("reports the songs and the folders that hold them once every file is measured, override folders included", function()
		local Library, _, checks = checked_library({ hub = { "a.mp3" }, boss = { "b.mp3", "c.mp3" }, ["boss/chaos_spawn"] = { "d.mp3" } })

		for _ = 1, 3 do
			Library.update(0.016)
		end
		assert_deep_equal(checks, {})

		Library.update(0.016)
		assert_deep_equal(checks, { { songs = 4, folders = 3 } })
	end)

	it("leaves out a file Windows cannot open, and a folder with no song it can play", function()
		local Library, _, checks = checked_library({ hub = { "bad.mp3" }, combat = { "good.mp3" } }, {}, { ["hub/bad.mp3"] = "unsupported" })

		Library.update(0.016)
		Library.update(0.016)

		assert_deep_equal(checks, { { songs = 1, folders = 1 } })
	end)

	it("reports no songs on the update after a listing of empty folders", function()
		local Library, _, checks = checked_library({})

		Library.update(0.016)

		assert_deep_equal(checks, { { songs = 0, folders = 0 } })
	end)

	it("reports a listing with nothing new to measure on the update after it", function()
		local Library, folders, checks = checked_library({ hub = { "a.mp3" } })
		Library.update(0.016)
		folders.measured = {}

		Library.request_listing()
		Library.update(0.016)
		Library.update(0.016)

		assert_deep_equal(folders.measured, {})
		assert_deep_equal(checks, { { songs = 1, folders = 1 }, { songs = 1, folders = 1 } })
	end)

	it("reports only the newer listing when one comes before the measuring finishes", function()
		local disk = { hub = { "a.mp3", "b.mp3" } }
		local Library, _, checks = checked_library(disk)
		Library.update(0.016)

		disk.hub = { "a.mp3", "b.mp3", "c.mp3" }
		Library.request_rescan()
		for _ = 1, 10 do
			Library.update(0.016)
		end

		assert_deep_equal(checks, { { songs = 3, folders = 1 } })
	end)
end)

describe("library.lua watching the folders", function()
	it("watches the audio folder once it has created the folders", function()
		local _, folders = listed_library({})

		assert_equal(folders.watched, ROOT)
	end)

	it("lists the folders again once changes have stopped for 3 seconds", function()
		local disk = { hub = { "a.mp3" } }
		local Library, folders, lines = listed_library(disk)
		disk.hub = { "a.mp3", "b.mp3" }

		folders.changes = true
		assert_equal(Library.update(1), false)
		assert_equal(Library.update(2), false)
		folders.changes = true
		assert_equal(Library.update(1), false)
		assert_equal(Library.update(2.5), false)
		assert_equal(Library.update(0.6), true)

		assert_equal(Library.find_file("hub", "hub/b.mp3"), "hub/b.mp3")
		assert_equal(lines[#lines]:find("[library] listed the audio folders again", 1, true) ~= nil, true, lines[#lines])
	end)

	it("measures only the new and changed files when the watcher lists the folders again", function()
		local disk = { hub = { "a.mp3", "b.mp3" } }
		local Library, folders = listed_library(disk, { ["hub/a.mp3"] = 100, ["hub/b.mp3"] = 200, ["hub/c.mp3"] = 300 })
		Library.update(0.016)
		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/a.mp3", "hub/b.mp3" })

		-- b.mp3 is replaced, which changes its stamp, and c.mp3 is added.
		disk.hub = { "a.mp3", "b.mp3", "c.mp3" }
		local list = folders.list
		function folders.list(folder)
			local names, stamps = list(folder)
			if stamps and stamps["b.mp3"] then
				stamps["b.mp3"] = "replaced"
			end
			return names, stamps
		end
		folders.changes = true
		Library.update(0.016)
		Library.update(3.1)
		Library.update(0.016)
		Library.update(0.016)

		assert_deep_equal(folders.measured, { "hub/a.mp3", "hub/b.mp3", "hub/b.mp3", "hub/c.mp3" })
		assert_equal(select(2, Library.find_file("hub", "hub/a.mp3")), 100)
	end)

	it("does not list the folders again while nothing changes", function()
		local Library = listed_library({ hub = { "a.mp3" } })

		for _ = 1, 10 do
			assert_equal(Library.update(1), false)
		end
	end)

	it("says so in the log when Windows cannot watch the folders, and still lists them", function()
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		local folders = new_audio_folders({ hub = { "a.mp3" } }, {})
		folders.watch_error = "Windows cannot report changes in the audio folders"
		local lines = {}
		Library.init(function(line) lines[#lines + 1] = line end, folders)
		Library.update(0.016)

		assert_equal(lines[1], "[library] Windows cannot report changes in the audio folders, so changed files need Rescan Audio Folders")
		assert_equal(first_file(Library, "hub"), "hub/a.mp3")
		assert_equal(Library.update(5), false)
	end)

	it("stops watching on shutdown", function()
		local Library, folders = listed_library({})

		Library.shutdown()

		assert_equal(folders.closed, true)
	end)
end)

describe("library.lua file selection", function()
	it("returns nil for an empty or missing folder, and for a context it does not know", function()
		local Library = listed_library({ hub = {} })

		assert_equal(first_file(Library, "hub"), nil)
		assert_equal(first_file(Library, "horde"), nil)
		assert_equal(first_file(Library, "not_a_context"), nil)
	end)

	it("skips a listed file that has since been deleted, whatever its name, and logs it once", function()
		local missing = {}
		local Library, _, lines = listed_library({ hub = { "Mötley.mp3", "kept.mp3" } }, {}, missing)
		missing["hub/Mötley.mp3"] = true

		for _ = 1, 10 do
			assert_deep_equal({ first_file(Library, "hub") }, { "hub/kept.mp3", nil, true })
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

		assert_equal(first_file(Library, "hub"), nil)
	end)

	it("finds a specific file with the same values as a pick, or nil once the folder no longer has it", function()
		local Library = listed_library({ explore = { "a.mp3", "b.mp3" } }, {}, { ["explore/c.mp3"] = true })

		assert_deep_equal({ Library.find_file("explore", "explore/b.mp3") }, { "explore/b.mp3", nil, false })
		assert_equal(Library.find_file("explore", "explore/gone.mp3"), nil)
	end)
end)

describe("library.lua songs removed from rotation", function()
	-- Returns a library that has listed `disk` with `removed` as its removed songs, the fake folders, and every listing it passed on.
	local function library_with_removed(disk, removed)
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		local folders = new_audio_folders(disk, { ["hub/a.mp3"] = 100, ["hub/b.mp3"] = 100 })
		local listings = {}
		Library.on_listed(function(entries) listings[#listings + 1] = entries end)
		Library.init(nil, folders, { is_removed = function(file_path) return removed[file_path] == true end })
		Library.update(0.016)
		return Library, folders, listings
	end

	it("leaves a removed song out of the listing, the picks, and what it passes on", function()
		local Library, folders, listings = library_with_removed({ hub = { "a.mp3", "b.mp3" } }, { ["hub/a.mp3"] = true })

		for _ = 1, 5 do
			assert_equal(first_file(Library, "hub"), "hub/b.mp3")
		end
		assert_equal(Library.find_file("hub", "hub/a.mp3"), nil)
		assert_equal(#listings[1], 1)
		assert_equal(listings[1][1].file_path, "hub/b.mp3")

		Library.update(0.016)
		Library.update(0.016)
		assert_deep_equal(folders.measured, { "hub/b.mp3" })
	end)

	it("leaves a folder whose every song is removed with no files", function()
		local Library = library_with_removed({ hub = { "a.mp3" } }, { ["hub/a.mp3"] = true })

		assert_equal(Library.has_files("hub"), false)
		assert_equal(first_file(Library, "hub"), nil)
	end)

	it("takes a removed song out of its folder at once, before the next listing", function()
		local Library = library_with_removed({ hub = { "a.mp3", "b.mp3" } }, {})

		Library.remove_file("hub/a.mp3")

		for _ = 1, 5 do
			assert_equal(first_file(Library, "hub"), "hub/b.mp3")
		end
	end)

	it("brings a song back on the next listing once it is no longer removed, keeping what was measured", function()
		local removed = { ["hub/a.mp3"] = true }
		local Library, folders = library_with_removed({ hub = { "a.mp3", "b.mp3" } }, removed)
		Library.update(0.016)
		local measured = #folders.measured

		removed["hub/a.mp3"] = nil
		Library.request_listing()
		assert_equal(Library.update(0.016), true)
		Library.update(0.016)

		assert_equal(Library.find_file("hub", "hub/a.mp3"), "hub/a.mp3")
		assert_deep_equal({ unpack(folders.measured, measured + 1) }, { "hub/a.mp3" })
	end)
end)
