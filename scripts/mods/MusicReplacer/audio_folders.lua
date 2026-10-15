-- Lists, checks, and creates the audio folders through Windows' own file functions, and measures durations with Media Foundation.
-- It replaces the Audio Plugin's file handler, which lists folders through DarktideLocalServer.
-- Names go through the wide-character functions, so files named in any script work.
-- Media Foundation's durations match the decoded audio, while DarktideLocalServer's ran over a second short for mp3 files.

local AudioFolders = {}

-- Media Foundation decodes the first five. Ogg and Opus are listed for ffplay, and direct playback falls back from them.
local EXTENSIONS = { mp3 = true, m4a = true, aac = true, wav = true, flac = true, wma = true, ogg = true, opus = true }

local INVALID_HANDLE = -1
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF
local FILE_ATTRIBUTE_DIRECTORY = 0x10

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
	return math.floor(attributes / FILE_ATTRIBUTE_DIRECTORY) % 2 == 1
end

-- The audio files directly inside `folder`, a UTF-8 path, sorted by name. Nil when the folder does not exist.
function AudioFolders.list(folder)
	local ffi = NativeFfi.ffi
	local kernel32 = NativeFfi.kernel32()
	local data = ffi.new("MusicReplacer_WIN32_FIND_DATAW")
	local find = kernel32.MusicReplacer_FindFirstFileW(NativeFfi.wide(folder .. "/*"), data)

	if tonumber(ffi.cast("intptr_t", find)) == INVALID_HANDLE then
		return nil
	end

	local names = {}
	repeat
		if not is_directory(data.dwFileAttributes) then
			local name = NativeFfi.utf8(data.cFileName)
			local extension = name:match("%.([^.]+)$")
			if extension and EXTENSIONS[extension:lower()] then
				names[#names + 1] = name
			end
		end
	until kernel32.MusicReplacer_FindNextFileW(find, data) == 0

	kernel32.MusicReplacer_FindClose(find)
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

-- The duration of the file at `path` in seconds, or nil when Media Foundation cannot open it.
function AudioFolders.duration(path)
	local decoder = MediaDecoder and MediaDecoder.open(path)
	if not decoder then
		return nil
	end

	local duration = decoder.duration
	decoder:close()
	return duration
end

return AudioFolders
