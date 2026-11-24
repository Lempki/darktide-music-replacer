-- Decides which song a folder plays next, and which song Previous Song goes back to.
-- library.lua knows what each folder holds, and this module knows the order the songs play in.
--
-- With Shuffle on, a folder plays each of its songs once before any song repeats, in a random order.
-- A small folder would repeat songs soon if a pick only avoided the last song.
-- A folder's round lasts the whole game session, so a short visit to a situation does not start it over.
-- Each pick works from what the folder holds at that moment, so a rescan's added and removed songs need no bookkeeping here.
--
-- The songs played earlier and the songs gone back past belong to the current situation, which forget_history() ends.
--
-- With Shuffle off, a folder plays in the order library.lua lists it, and wraps around at either end.
-- That order alone says what comes before and after a song, so the history plays no part.
-- A folder continues after the song it played last, for the whole game session.

local Playlist = {}

-- Previous Song reaches back this many songs, which also keeps a long stay in one situation from growing the list without end.
local MAX_HISTORY = 100

local usable_entries = function() return nil end
local find_file = function() return nil end
local random = math.random
local is_shuffled = true

local rounds = {} -- folder -> file_path -> true, for the songs that played in the folder's current round.
local last_picked = {} -- folder -> the file path most recently picked.
local positions = {} -- folder -> where its last song stood in name order.
local played_before = {} -- The songs that played earlier in the current situation, oldest first.
local gone_back_past = {} -- The songs Previous Song left, in the order it left them, which Next Song returns to from the last one.

-- `options.usable_entries(folder)` returns the folder's songs as { file_path, duration } entries, or nil when it has none.
-- `options.find_file(folder, file_path)` returns file_path, duration, and is_only_file, or nil once the folder no longer has the song.
-- `options.random(first, last)`, if given, replaces math.random.
function Playlist.init(options)
	usable_entries = options.usable_entries
	find_file = options.find_file
	random = options.random or random
end

-- The songs of `entries` that have not played in `round`.
local function left_in_round(entries, round)
	local left = {}
	for _, entry in ipairs(entries) do
		if not round[entry.file_path] then
			left[#left + 1] = entry
		end
	end
	return left
end

-- `entries` without `file_path`, or `entries` itself when that would leave none.
local function without_file(entries, file_path)
	local kept = {}
	for _, entry in ipairs(entries) do
		if entry.file_path ~= file_path then
			kept[#kept + 1] = entry
		end
	end
	return #kept > 0 and kept or entries
end

-- A random song the folder's round has not played yet, starting a new round once it has played them all.
-- A new round never starts with the song that ended the last one, as long as another song is left.
local function pick_from_round(folder, playing)
	local entries = usable_entries(folder)
	if not entries then
		return nil
	end

	local round = rounds[folder] or {}
	rounds[folder] = round

	-- A resumed song is found rather than picked, so the song playing now counts as played here.
	if playing then
		round[playing] = true
	end

	local pool = left_in_round(entries, round)
	if #pool == 0 then
		round = {}
		rounds[folder] = round
		pool = without_file(without_file(entries, playing), last_picked[folder])
	end

	local picked = pool[random(1, #pool)]
	round[picked.file_path] = true
	last_picked[folder] = picked.file_path

	return picked.file_path, picked.duration, #entries == 1
end

local function index_of(entries, file_path)
	for index, entry in ipairs(entries) do
		if entry.file_path == file_path then
			return index
		end
	end
	return nil
end

-- Moves the folder's name order to `index`, and returns that song as Playlist.next() does.
local function pick_position(folder, entries, index)
	local picked = entries[index]
	positions[folder] = index
	last_picked[folder] = picked.file_path
	return picked.file_path, picked.duration, #entries == 1
end

-- The song after `playing`, or after the folder's last song when `playing` is from another folder.
-- A song that left the folder, as Remove from Rotation does, leaves the song after it at its position.
local function next_in_name_order(folder, playing)
	local entries = usable_entries(folder)
	if not entries then
		return nil
	end

	local index = index_of(entries, playing) or index_of(entries, last_picked[folder])
	local next_index = index and index + 1 or positions[folder] or 1
	if next_index > #entries then
		next_index = 1
	end

	return pick_position(folder, entries, next_index)
end

-- The song before `playing`, wrapping from the folder's first song to its last, or nil in a folder with no other song.
local function previous_in_name_order(folder, playing)
	local entries = usable_entries(folder)
	if not entries or #entries == 1 then
		return nil
	end

	local index = index_of(entries, playing) or positions[folder] or 1
	local previous_index = index - 1
	if previous_index < 1 then
		previous_index = #entries
	end

	return pick_position(folder, entries, previous_index)
end

-- The latest song of `songs` that `folder` still holds, taken off the list, or nil.
-- Songs a rescan removed since they played are passed over.
local function take_latest(songs, folder)
	while #songs > 0 do
		local file_path, duration, is_only_file = find_file(folder, table.remove(songs))
		if file_path then
			return file_path, duration, is_only_file
		end
	end
	return nil
end

-- Returns file_path, duration_seconds, and is_only_file for the song that follows `playing`, or nil if `folder` has no song to play.
-- With Shuffle on, a song Previous Song went back past comes first, and otherwise the folder's round picks one.
-- The caller should fall back to the game's music on nil.
-- duration is nil until the file has been measured, or when it could not be.
-- is_only_file flags a folder with exactly one usable file, which loops.
function Playlist.next(folder, playing)
	if not is_shuffled then
		return next_in_name_order(folder, playing)
	end

	local file_path, duration, is_only_file = take_latest(gone_back_past, folder)
	if file_path then
		return file_path, duration, is_only_file
	end

	return pick_from_round(folder, playing)
end

-- Returns the same values as Playlist.next() for the song that played before `playing`, or nil with no earlier song.
-- Going back does not add `playing` to the songs played earlier, so another press keeps going back, and Next Song returns to it.
function Playlist.previous(folder, playing)
	if not is_shuffled then
		return previous_in_name_order(folder, playing)
	end

	local file_path, duration, is_only_file = take_latest(played_before, folder)
	if file_path then
		gone_back_past[#gone_back_past + 1] = playing
	end
	return file_path, duration, is_only_file
end

-- Notes that `file_path` played in the current situation, for Previous Song.
function Playlist.add_played(file_path)
	if #played_before >= MAX_HISTORY then
		table.remove(played_before, 1)
	end
	played_before[#played_before + 1] = file_path
end

-- Turns Shuffle on or off. The history of one order says nothing about the other, so it ends here.
function Playlist.set_shuffle(on)
	is_shuffled = on == true
	Playlist.forget_history()
end

-- Previous Song stays within one situation, so a new one starts with no earlier songs.
function Playlist.forget_history()
	played_before = {}
	gone_back_past = {}
end

return Playlist
