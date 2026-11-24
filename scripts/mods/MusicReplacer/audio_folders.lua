-- Lists, checks, creates, and watches the audio folders through Windows' own file functions, and measures durations with Media Foundation.
-- It also compares two files byte for byte.
-- Names go through the wide-character functions, so files named in any script work.
-- Media Foundation's durations match the decoded audio to within milliseconds.

local AudioFolders = {}

-- These are the formats Media Foundation decodes in a desktop program.
-- Ogg and Opus are left out, since Microsoft's Web Media Extensions only add them for Store apps.
local EXTENSIONS = { mp3 = true, m4a = true, aac = true, wav = true, flac = true, wma = true }

-- Audio and video formats a player could drop in that the mod does not play, so a listing can say they were skipped.
-- Any other file, such as cover art, desktop.ini, or a playlist, is not audio and is left out without a word.
local OTHER_AUDIO_EXTENSIONS = {
	ogg = true, oga = true, opus = true, aif = true, aiff = true, ape = true, wv = true, mka = true, webm = true,
	mp4 = true, mid = true, midi = true, tta = true, dsf = true, dff = true, mpc = true, spx = true,
}

local INVALID_HANDLE = -1
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
local FILE_ATTRIBUTE_DIRECTORY = 0x10
local WAIT_OBJECT_0 = 0

-- It watches file names, folder names, sizes, and write times, which covers files being added, removed, renamed, copied, or replaced.
local CHANGE_FILTER = 0x01 + 0x02 + 0x08 + 0x10

local GENERIC_READ = 0x80000000
-- Other programs can still read, write, rename, and delete a file while it is compared, so a comparison never locks a song.
local FILE_SHARE_READ_WRITE_DELETE = 0x01 + 0x02 + 0x04
local OPEN_EXISTING = 3
local FILE_FLAG_SEQUENTIAL_SCAN = 0x08000000

-- Read from each file per step. Reading a chunk from disk takes far less than a millisecond, so a step fits the loudness budget.
local COMPARE_CHUNK_BYTES = 65536

local NativeFfi = nil
local MediaDecoder = nil

-- `native_ffi` is a loaded native_ffi.lua, and `media_decoder` an initialized media_decoder.lua.
function AudioFolders.init(native_ffi, media_decoder)
	NativeFfi = native_ffi
	MediaDecoder = media_decoder
end

function AudioFolders.available()
	return NativeFfi ~= nil and NativeFfi.load()
end

local function is_directory(attributes)
	return bit.band(attributes, FILE_ATTRIBUTE_DIRECTORY) ~= 0
end

-- Calls `visit(data)` for every entry directly inside `folder`, a UTF-8 path. Returns false when the folder does not exist.
-- `data` is one MusicReplacer_WIN32_FIND_DATAW, reused for every entry, so `visit` reads what it needs before it returns.
local function for_each_entry(folder, visit)
	local ffi = NativeFfi.ffi
	local kernel32 = NativeFfi.kernel32()
	local data = ffi.new("MusicReplacer_WIN32_FIND_DATAW")
	local find = kernel32.MusicReplacer_FindFirstFileW(NativeFfi.wide(folder .. "/*"), data)

	if tonumber(ffi.cast("intptr_t", find)) == INVALID_HANDLE then
		return false
	end

	repeat
		visit(data)
	until kernel32.MusicReplacer_FindNextFileW(find, data) == 0

	kernel32.MusicReplacer_FindClose(find)
	return true
end

-- Sorts `names` as File Explorer does, ignoring case and reading digits as numbers, so "2.mp3" comes before "10.mp3".
-- With Shuffle off this is the order a folder plays in, so it has to match what the player sees.
local function sort_like_explorer(names)
	local wide_names = {}
	for _, name in ipairs(names) do
		wide_names[name] = NativeFfi.wide(name)
	end

	local shlwapi = NativeFfi.shlwapi()
	table.sort(names, function(first, second)
		return shlwapi.MusicReplacer_StrCmpLogicalW(wide_names[first], wide_names[second]) < 0
	end)
end

-- The audio files directly inside `folder`, a UTF-8 path, sorted by name as File Explorer does. Nil when the folder does not exist.
-- `extra_names`, if given, maps lowercase names of other files to list along with the audio files, such as a marker file.
-- The second value maps each name to a stamp of its size and write time, which changes whenever the file does.
-- The third lists the names of audio files in a format the mod does not play, such as Ogg, unsorted.
function AudioFolders.list(folder, extra_names)
	local names = {}
	local stamps = {}
	local other_formats = {}

	local found = for_each_entry(folder, function(data)
		if not is_directory(data.dwFileAttributes) then
			local name = NativeFfi.utf8(data.cFileName)
			local extension = name:match("%.([^.]+)$")
			if (extension and EXTENSIONS[extension:lower()]) or (extra_names and extra_names[name:lower()]) then
				names[#names + 1] = name
				local write_time = data.ftLastWriteTime
				stamps[name] = string.format("%.0f:%.0f:%.0f", data.nFileSizeHigh * 4294967296 + data.nFileSizeLow, write_time.high, write_time.low)
			elseif extension and OTHER_AUDIO_EXTENSIONS[extension:lower()] then
				other_formats[#other_formats + 1] = name
			end
		end
	end)

	if not found then
		return nil
	end

	sort_like_explorer(names)
	return names, stamps, other_formats
end

-- The names of the folders directly inside `folder`, a UTF-8 path, sorted. Nil when the folder does not exist.
function AudioFolders.subfolders(folder)
	local names = {}

	local found = for_each_entry(folder, function(data)
		if is_directory(data.dwFileAttributes) then
			local name = NativeFfi.utf8(data.cFileName)
			if name ~= "." and name ~= ".." then
				names[#names + 1] = name
			end
		end
	end)

	if not found then
		return nil
	end

	table.sort(names)
	return names
end

-- True when `path` is an existing file.
function AudioFolders.exists(path)
	local attributes = NativeFfi.kernel32().MusicReplacer_GetFileAttributesW(NativeFfi.wide(path))
	return attributes ~= INVALID_FILE_ATTRIBUTES and not is_directory(attributes)
end

-- Creates `folder` if it is missing. Its parent must exist.
function AudioFolders.create(folder)
	NativeFfi.kernel32().MusicReplacer_CreateDirectoryW(NativeFfi.wide(folder), nil)
end

local Watcher = {}
Watcher.__index = Watcher

-- Starts watching `folder` and everything below it for changes. Returns a watcher, or nil and why.
-- Windows only raises a flag, so checking it costs nothing and never waits.
function AudioFolders.watch(folder)
	local handle = NativeFfi.kernel32().MusicReplacer_FindFirstChangeNotificationW(NativeFfi.wide_full_path(folder), 1, CHANGE_FILTER)
	if tonumber(NativeFfi.ffi.cast("intptr_t", handle)) == INVALID_HANDLE then
		return nil, "Windows cannot report changes in the audio folders"
	end

	return setmetatable({ handle = handle }, Watcher)
end

-- True when something changed since the last call.
function Watcher:changed()
	if self.handle == nil then
		return false
	end

	local kernel32 = NativeFfi.kernel32()
	if kernel32.MusicReplacer_WaitForSingleObject(self.handle, 0) ~= WAIT_OBJECT_0 then
		return false
	end

	-- Raising the flag disarms it, so it is armed again for the next change.
	kernel32.MusicReplacer_FindNextChangeNotification(self.handle)
	return true
end

function Watcher:close()
	if self.handle ~= nil then
		NativeFfi.kernel32().MusicReplacer_FindCloseChangeNotification(self.handle)
		self.handle = nil
	end
end

local Comparison = {}
Comparison.__index = Comparison

local function open_for_reading(path)
	local ffi = NativeFfi.ffi
	local handle = NativeFfi.kernel32().MusicReplacer_CreateFileW(
		NativeFfi.wide(path), GENERIC_READ, FILE_SHARE_READ_WRITE_DELETE, nil, OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN, nil)
	if tonumber(ffi.cast("intptr_t", handle)) == INVALID_HANDLE then
		return nil
	end
	return handle
end

-- Starts comparing the files at `path` and `other_path` byte for byte, a chunk per Comparison:step().
-- Returns a comparison, or nil when either file cannot be opened or there is no memory to read them into.
function AudioFolders.compare(path, other_path)
	local first = open_for_reading(path)
	if not first then
		return nil
	end

	local second = open_for_reading(other_path)
	local buffer = second and NativeFfi.alloc(2 * COMPARE_CHUNK_BYTES)
	if not buffer then
		local kernel32 = NativeFfi.kernel32()
		kernel32.MusicReplacer_CloseHandle(first)
		if second then
			kernel32.MusicReplacer_CloseHandle(second)
		end
		return nil
	end

	return setmetatable({
		first = first,
		second = second,
		buffer = buffer,
		bytes_read = NativeFfi.ffi.new("uint32_t[2]"),
	}, Comparison)
end

-- Compares the next chunk of both files.
-- Returns true once both ended with every byte the same, false once a byte, the length, or a read differs, and nil while more is left.
function Comparison:step()
	if self.first == nil then
		return false
	end

	local kernel32 = NativeFfi.kernel32()
	local first_bytes, second_bytes = self.buffer, self.buffer + COMPARE_CHUNK_BYTES
	local first_ok = kernel32.MusicReplacer_ReadFile(self.first, first_bytes, COMPARE_CHUNK_BYTES, self.bytes_read, nil)
	local second_ok = kernel32.MusicReplacer_ReadFile(self.second, second_bytes, COMPARE_CHUNK_BYTES, self.bytes_read + 1, nil)
	local count = self.bytes_read[0]
	if first_ok == 0 or second_ok == 0 or count ~= self.bytes_read[1] then
		return false
	end

	-- Comparing four bytes at a time keeps the loop short, and the bytes past the last whole word are compared one by one.
	local words = math.floor(count / 4)
	local first_words = NativeFfi.ffi.cast("const uint32_t *", first_bytes)
	local second_words = NativeFfi.ffi.cast("const uint32_t *", second_bytes)
	for index = 0, words - 1 do
		if first_words[index] ~= second_words[index] then
			return false
		end
	end
	for index = words * 4, count - 1 do
		if first_bytes[index] ~= second_bytes[index] then
			return false
		end
	end

	-- A read of a file comes back short only at its end, and both came back equally short.
	if count < COMPARE_CHUNK_BYTES then
		return true
	end
	return nil
end

function Comparison:close()
	if self.first ~= nil then
		local kernel32 = NativeFfi.kernel32()
		kernel32.MusicReplacer_CloseHandle(self.first)
		kernel32.MusicReplacer_CloseHandle(self.second)
		NativeFfi.free(self.buffer)
		self.first = nil
		self.second = nil
		self.buffer = nil
	end
end

-- The duration of the file at `path` in seconds, or nil when Media Foundation cannot tell.
-- When Media Foundation works but cannot open this file, the second value says why.
function AudioFolders.duration(path)
	if not (MediaDecoder and MediaDecoder.available()) then
		return nil
	end

	local decoder, err = MediaDecoder.open(path)
	if not decoder then
		return nil, err
	end

	local duration = decoder.duration
	decoder:close()
	return duration
end

return AudioFolders
