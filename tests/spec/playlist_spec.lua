-- Pins the order songs play in: a folder's rounds, and the songs Previous Song and Next Song move between.

local PLAYLIST_FILE = package.searchpath("scripts/mods/MusicReplacer/playlist", package.path)

-- A playlist.lua over `folders`, which maps a folder to its file paths, a table a spec can change as a rescan would.
-- Its module state lives in the file, so each spec loads a fresh copy.
local function new_playlist(folders, random)
	local Playlist = dofile(PLAYLIST_FILE)

	Playlist.init({
		random = random,
		usable_entries = function(folder)
			local entries = {}
			for index, file_path in ipairs(folders[folder] or {}) do
				entries[index] = { file_path = file_path, duration = 100 }
			end
			return #entries > 0 and entries or nil
		end,
		find_file = function(folder, file_path)
			for _, listed_path in ipairs(folders[folder] or {}) do
				if listed_path == file_path then
					return file_path, 100, #folders[folder] == 1
				end
			end
			return nil
		end,
	})

	return Playlist
end

local function first_left(first)
	return first
end

-- The next `count` songs from the folder, each following the one before.
local function play_songs(Playlist, folder, count, playing)
	local songs = {}
	for index = 1, count do
		playing = Playlist.next(folder, playing)
		songs[index] = playing
	end
	return songs
end

describe("playlist.lua rounds", function()
	it("plays every song of a folder once before any song repeats", function()
		math.randomseed(1)
		local folders = { hub = { "a", "b", "c", "d", "e" } }
		local Playlist = new_playlist(folders)

		for _ = 1, 20 do
			local seen = {}
			for _, song in ipairs(play_songs(Playlist, "hub", 5)) do
				assert_equal(seen[song], nil, song .. " played twice in one round")
				seen[song] = true
			end
		end
	end)

	it("never starts a round with the song that ended the last one", function()
		math.randomseed(1)
		local Playlist = new_playlist({ combat = { "a", "b", "c" } })
		local previous = nil

		for _, song in ipairs(play_songs(Playlist, "combat", 60)) do
			assert_equal(song ~= previous, true, song .. " played twice in a row")
			previous = song
		end
	end)

	it("alternates between two songs", function()
		local Playlist = new_playlist({ hub = { "a", "b" } }, first_left)

		assert_deep_equal(play_songs(Playlist, "hub", 4), { "a", "b", "a", "b" })
	end)

	it("keeps a folder's round apart from other folders and through a new situation", function()
		local Playlist = new_playlist({ hub = { "a", "b", "c" }, combat = { "x", "y" } }, first_left)

		assert_equal(Playlist.next("hub"), "a")
		assert_equal(Playlist.next("combat"), "x")
		Playlist.forget_history()

		assert_equal(Playlist.next("hub"), "b")
	end)

	it("never picks the song playing now, and counts a resumed one as played", function()
		local Playlist = new_playlist({ hub = { "a", "b", "c" } }, first_left)

		assert_equal(Playlist.next("hub", "a"), "b")
		assert_equal(Playlist.next("hub", "b"), "c")
		assert_equal(Playlist.next("hub", "c"), "a")
	end)

	it("avoids both the song playing now and the last pick as a new round starts", function()
		local Playlist = new_playlist({ hub = { "a", "b", "c" } }, first_left)

		assert_deep_equal(play_songs(Playlist, "hub", 3), { "a", "b", "c" })
		assert_equal(Playlist.next("hub", "a"), "b")
	end)

	it("still picks a folder's only song while it plays", function()
		local Playlist = new_playlist({ hub = { "a" } })

		assert_deep_equal({ Playlist.next("hub", "a") }, { "a", 100, true })
		assert_deep_equal({ Playlist.next("hub", "a") }, { "a", 100, true })
	end)

	it("returns nil for a folder with no songs", function()
		local Playlist = new_playlist({})

		assert_equal(Playlist.next("hub"), nil)
	end)

	it("adds a song a rescan brought to the round, and leaves out one it took away", function()
		local folders = { hub = { "a", "b", "c" } }
		local Playlist = new_playlist(folders, first_left)

		assert_equal(Playlist.next("hub"), "a")
		folders.hub = { "a", "c", "d" }

		assert_deep_equal(play_songs(Playlist, "hub", 2, "a"), { "c", "d" })
	end)
end)

describe("playlist.lua history", function()
	-- A folder that has played a and b, with c playing now.
	local function after_three_songs()
		local folders = { hub = { "a", "b", "c", "d" } }
		local Playlist = new_playlist(folders, first_left)
		assert_deep_equal(play_songs(Playlist, "hub", 3), { "a", "b", "c" })
		Playlist.add_played("a")
		Playlist.add_played("b")
		return Playlist, folders
	end

	it("goes back through the songs that played, latest first", function()
		local Playlist = after_three_songs()

		assert_deep_equal({ Playlist.previous("hub", "c") }, { "b", 100, false })
		assert_equal(Playlist.previous("hub", "b"), "a")
		assert_equal(Playlist.previous("hub", "a"), nil)
	end)

	it("returns to the songs it went back past, nearest first, before it picks a new one", function()
		local Playlist = after_three_songs()
		Playlist.previous("hub", "c")
		Playlist.previous("hub", "b")

		assert_deep_equal({ Playlist.next("hub", "a") }, { "b", 100, false })
		assert_equal(Playlist.next("hub", "b"), "c")
		assert_equal(Playlist.next("hub", "c"), "d")
	end)

	it("passes over songs a rescan took out of the folder, in both directions", function()
		local Playlist, folders = after_three_songs()
		Playlist.previous("hub", "c")
		folders.hub = { "a", "b", "d" }

		assert_equal(Playlist.next("hub", "b"), "d")

		Playlist.add_played("b")
		folders.hub = { "a", "d" }
		assert_equal(Playlist.previous("hub", "d"), "a")
	end)

	it("keeps the song playing now off the way forward when there is nothing to go back to", function()
		local Playlist = new_playlist({ hub = { "a", "b" } }, first_left)

		assert_equal(Playlist.next("hub"), "a")
		assert_equal(Playlist.previous("hub", "a"), nil)
		assert_equal(Playlist.next("hub", "a"), "b")
	end)

	it("forgets both directions in a new situation, but not the round", function()
		local Playlist = after_three_songs()
		Playlist.previous("hub", "c")
		Playlist.forget_history()

		assert_equal(Playlist.previous("hub", "b"), nil)
		assert_equal(Playlist.next("hub", "b"), "d")
	end)

	it("keeps only the latest songs of a long stay in one situation", function()
		local Playlist = new_playlist({ hub = { "a", "b" } }, first_left)
		Playlist.add_played("b")
		for _ = 1, 100 do
			Playlist.add_played("a")
		end

		for _ = 1, 100 do
			assert_equal(Playlist.previous("hub", "a"), "a")
		end
		assert_equal(Playlist.previous("hub", "a"), nil)
	end)
end)
