-- Pins removed_songs.lua: the songs out of rotation, kept in removed.txt, and read back with a player's own edits.
-- The file system is a stand-in.

local FakeEngine = require("tests.helpers.fake_engine")

local FOLDER = "C:/AppData/Fatshark/Darktide/MusicReplacer"
local FILE = FOLDER .. "/removed.txt"
local HEADER = "# Songs Music Replacer leaves out of their folder's rotation, one per line. Deleting a line puts that song back.\n"

-- A file system that keeps whole files in `files`, by path, and refuses every write while `read_only` is set.
local function new_file_system(files)
	local fs = { files = files or {}, read_only = false }

	fs.io = {
		open = function(path, mode)
			if mode == "r" then
				if fs.files[path] == nil then
					return nil, "no such file"
				end
				return {
					read = function() return fs.files[path] end,
					close = function() end,
				}
			end

			if fs.read_only then
				return nil, "access denied"
			end
			fs.files[path] = ""
			return {
				write = function(_, ...) fs.files[path] = fs.files[path] .. table.concat({ ... }) end,
				close = function() end,
			}
		end,
	}

	return fs
end

-- Returns an initialized removed_songs.lua over a file system whose removed.txt holds `text`, the file system, and the logged lines.
local function load_removed_songs(text)
	local fs = new_file_system({ [FILE] = text })
	local engine = FakeEngine.new({ lua = { io = fs.io } })
	local RemovedSongs = engine:load("removed_songs")
	local lines = {}
	RemovedSongs.init(function(line) lines[#lines + 1] = line end, FOLDER)
	return RemovedSongs, fs, lines
end

describe("removed_songs.lua", function()
	it("removes no song while the file is missing, and writes nothing", function()
		local RemovedSongs, fs = load_removed_songs(nil)

		assert_equal(RemovedSongs.contains("hub/a.mp3"), false)
		assert_equal(fs.files[FILE], nil)
	end)

	it("writes each removed song on its own line, sorted, under a header", function()
		local RemovedSongs, fs = load_removed_songs(nil)

		RemovedSongs.add("hub/b.mp3")
		RemovedSongs.add("boss/chaos_spawn/A.mp3")

		assert_equal(fs.files[FILE], HEADER .. "boss/chaos_spawn/A.mp3\nhub/b.mp3\n")
		assert_equal(RemovedSongs.contains("hub/b.mp3"), true)
	end)

	it("matches a song whatever its case, since Windows ignores case in file names", function()
		local RemovedSongs = load_removed_songs(nil)

		RemovedSongs.add("hub/Song.mp3")

		assert_equal(RemovedSongs.contains("HUB/song.MP3"), true)
		assert_equal(RemovedSongs.contains("hub/other.mp3"), false)
	end)

	it("reads a file edited by hand, with blank lines, comments, spaces, backslashes, and repeats", function()
		local RemovedSongs, _, lines = load_removed_songs(HEADER .. "\n  hub\\Song.mp3  \r\n# a note\r\nhub/song.mp3\r\ncombat/x.mp3\n")

		assert_equal(RemovedSongs.contains("hub/Song.mp3"), true)
		assert_equal(RemovedSongs.contains("combat/x.mp3"), true)
		assert_equal(RemovedSongs.contains("# a note"), false)
		assert_deep_equal(lines, { "[removed] 2 song(s) are out of rotation" })
	end)

	it("reads the file again on load, so a deleted line puts its song back", function()
		local RemovedSongs, fs = load_removed_songs(HEADER .. "hub/a.mp3\nhub/b.mp3\n")

		fs.files[FILE] = HEADER .. "hub/b.mp3\n"
		RemovedSongs.load()

		assert_equal(RemovedSongs.contains("hub/a.mp3"), false)
		assert_equal(RemovedSongs.contains("hub/b.mp3"), true)
	end)

	it("puts every song back on clear, says how many there were, and keeps the header", function()
		local RemovedSongs, fs = load_removed_songs(HEADER .. "hub/a.mp3\nhub/b.mp3\n")

		assert_equal(RemovedSongs.clear(), 2)

		assert_equal(RemovedSongs.contains("hub/a.mp3"), false)
		assert_equal(fs.files[FILE], HEADER)
		assert_equal(RemovedSongs.clear(), 0)
	end)

	it("keeps a removed song for the session when the file cannot be written", function()
		local fs = new_file_system()
		local engine = FakeEngine.new({ lua = { io = { open = function(path, mode) return mode == "r" and fs.io.open(path, mode) or nil end } } })
		local RemovedSongs = engine:load("removed_songs")
		local lines = {}
		RemovedSongs.init(function(line) lines[#lines + 1] = line end, FOLDER)

		RemovedSongs.add("hub/a.mp3")

		assert_equal(RemovedSongs.contains("hub/a.mp3"), true)
		assert_deep_equal(lines, { "[removed] could not write removed.txt, so the change lasts until the game restarts" })
	end)

	it("keeps a removal the file could not take through a reload, and writes it once the file can be written", function()
		local RemovedSongs, fs = load_removed_songs(nil)
		fs.read_only = true

		RemovedSongs.add("hub/a.mp3")
		RemovedSongs.load()
		assert_equal(RemovedSongs.contains("hub/a.mp3"), true)

		fs.read_only = false
		RemovedSongs.load()
		assert_equal(RemovedSongs.contains("hub/a.mp3"), true)
		assert_equal(fs.files[FILE], HEADER .. "hub/a.mp3\n")
	end)

	it("keeps a restore the file could not take through a reload", function()
		local RemovedSongs, fs = load_removed_songs(HEADER .. "hub/a.mp3\n")
		fs.read_only = true

		RemovedSongs.clear()
		RemovedSongs.load()

		assert_equal(RemovedSongs.contains("hub/a.mp3"), false)
	end)
end)
