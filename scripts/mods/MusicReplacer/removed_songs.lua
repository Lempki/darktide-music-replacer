-- Keeps the songs the Remove from Rotation key took out of their folder's rotation, in removed.txt beside loudness.txt.
-- The files stay on disk, and the library only leaves a removed song out of its listings.
-- A song is its path in the audio folder, such as "hub/Song.mp3", compared without case, since Windows ignores case in file names.
-- The file holds one song per line, so a player can put a song back by deleting its line.
-- It is read when the mod loads and again on Rescan Audio Folders, so a line edited by hand takes effect then.

local RemovedSongs = {}

local _io = Mods and Mods.lua and Mods.lua.io

local FILE_NAME = "removed.txt"
local HEADER = "# Songs Music Replacer leaves out of their folder's rotation, one per line. Deleting a line puts that song back."

local log = function() end -- It does nothing unless RemovedSongs.init is given a real logger.
local file_path_on_disk = nil
local songs = {} -- lowercased song path -> the path as written.

-- A song path as the library writes it: forward slashes, with no spaces around it.
-- Players editing the file by hand tend to write Windows paths.
local function normalized(song)
	return (song:gsub("\\", "/"):match("^%s*(.-)%s*$"))
end

local function save()
	if not (_io and file_path_on_disk) then
		return
	end

	local file = _io.open(file_path_on_disk, "w")
	if not file then
		log(string.format("[removed] could not write %s, so the change lasts until the game restarts", FILE_NAME))
		return
	end

	local lines = {}
	for _, song in pairs(songs) do
		lines[#lines + 1] = song
	end
	table.sort(lines)

	file:write(HEADER, "\n")
	for _, song in ipairs(lines) do
		file:write(song, "\n")
	end
	file:close()
end

-- Reads the file again, replacing what was kept. A missing file means no song is removed.
function RemovedSongs.load()
	songs = {}
	if not (_io and file_path_on_disk) then
		return
	end

	local file = _io.open(file_path_on_disk, "r")
	if not file then
		return
	end
	local text = file:read("*a") or ""
	file:close()

	local count = 0
	for line in text:gmatch("[^\r\n]+") do
		local song = normalized(line)
		if song ~= "" and song:sub(1, 1) ~= "#" and not songs[song:lower()] then
			songs[song:lower()] = song
			count = count + 1
		end
	end

	if count > 0 then
		log(string.format("[removed] %d song(s) are out of rotation", count))
	end
end

-- `folder` is where the file lives, the same folder as loudness.txt and the log.
function RemovedSongs.init(logger, folder)
	log = logger or log
	file_path_on_disk = folder and (folder .. "/" .. FILE_NAME)
	RemovedSongs.load()
end

function RemovedSongs.contains(file_path)
	return songs[normalized(file_path):lower()] ~= nil
end

function RemovedSongs.add(file_path)
	songs[normalized(file_path):lower()] = normalized(file_path)
	save()
end

-- Puts every removed song back, and returns how many there were.
function RemovedSongs.clear()
	local count = 0
	for _ in pairs(songs) do
		count = count + 1
	end

	songs = {}
	save()
	return count
end

return RemovedSongs
