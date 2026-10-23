-- Lists, checks, creates, and watches the audio folders through Windows' own file functions, and measures durations with Media Foundation.
-- Names go through the wide-character functions, so files named in any script work.
-- Media Foundation's durations match the decoded audio to within milliseconds.

local AudioFolders = {}

-- These are the formats Media Foundation decodes in a desktop program.
-- Ogg and Opus are left out, since Microsoft's Web Media Extensions only add them for Store apps.
local EXTENSIONS = { mp3 = true, m4a = true, aac = true, wav = true, flac = true, wma = true }

local INVALID_HANDLE = -1
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
local FILE_ATTRIBUTE_DIRECTORY = 0x10
local WAIT_OBJECT_0 = 0

-- It watches file names, folder names, sizes, and write times, which covers files being added, removed, renamed, copied, or replaced.
local CHANGE_FILTER = 0x01 + 0x02 + 0x08 + 0x10

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

-- The audio files directly inside `folder`, a UTF-8 path, sorted by name. Nil when the folder does not exist.
-- The second value maps each name to a stamp of its size and write time, which changes whenever the file does.
function AudioFolders.list(folder)
	local names = {}
	local stamps = {}

	local found = for_each_entry(folder, function(data)
		if not is_directory(data.dwFileAttributes) then
			local name = NativeFfi.utf8(data.cFileName)
			local extension = name:match("%.([^.]+)$")
			if extension and EXTENSIONS[extension:lower()] then
				names[#names + 1] = name
				local write_time = data.ftLastWriteTime
				stamps[name] = string.format("%.0f:%.0f:%.0f", data.nFileSizeHigh * 4294967296 + data.nFileSizeLow, write_time.high, write_time.low)
			end
		end
	end)

	if not found then
		return nil
	end

	table.sort(names)
	return names, stamps
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
