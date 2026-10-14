-- Decodes an audio file to 16-bit PCM with Windows Media Foundation, a chunk at a time, through LuaJIT's ffi.
-- Media Foundation ships with Windows and handles mp3, m4a/aac, wav, flac, and wma. It has no Ogg or Opus support.
-- The source reader runs synchronously on the calling thread, so no Media Foundation thread ever calls back into Lua.
-- Docs: https://learn.microsoft.com/en-us/windows/win32/medfound/using-the-source-reader-to-process-media-data

local MediaDecoder = {}

local CDEF = [[
typedef struct { uint16_t vt; uint16_t reserved1; uint16_t reserved2; uint16_t reserved3; int64_t value; int64_t padding; } MusicReplacer_PROPVARIANT;

int32_t MusicReplacer_MFStartup(uint32_t version, uint32_t flags) __asm__("MFStartup");
int32_t MusicReplacer_MFCreateMediaType(void **media_type) __asm__("MFCreateMediaType");
int32_t MusicReplacer_MFCreateWaveFormatExFromMFMediaType(void *media_type, MusicReplacer_WAVEFORMATEX **format, uint32_t *size,
	uint32_t flags) __asm__("MFCreateWaveFormatExFromMFMediaType");
int32_t MusicReplacer_MFCreateSourceReaderFromURL(const uint16_t *url, void *attributes, void **reader)
	__asm__("MFCreateSourceReaderFromURL");
]]

local MF_VERSION = 0x00020070
local MFSTARTUP_LITE = 1 -- Local files only, no network sources.

local FIRST_AUDIO_STREAM = 0xFFFFFFFD
local ALL_STREAMS = 0xFFFFFFFE
local MEDIA_SOURCE = 0xFFFFFFFF
local END_OF_STREAM_FLAG = 0x2
local VT_I8 = 20
local HUNDRED_NANOSECONDS = 10000000

-- Signatures with the object pointer first. Indexes are vtable slots, counting IUnknown's three.
local SET_GUID = { 24, "int32_t (*)(void *, const MusicReplacer_GUID *, const MusicReplacer_GUID *)" } -- IMFAttributes
local SET_UINT32 = { 21, "int32_t (*)(void *, const MusicReplacer_GUID *, uint32_t)" }
local SET_STREAM_SELECTION = { 4, "int32_t (*)(void *, uint32_t, int32_t)" } -- IMFSourceReader
local GET_CURRENT_MEDIA_TYPE = { 6, "int32_t (*)(void *, uint32_t, void **)" }
local SET_CURRENT_MEDIA_TYPE = { 7, "int32_t (*)(void *, uint32_t, uint32_t *, void *)" }
local SET_CURRENT_POSITION = { 8, "int32_t (*)(void *, const MusicReplacer_GUID *, const MusicReplacer_PROPVARIANT *)" }
local READ_SAMPLE = { 9, "int32_t (*)(void *, uint32_t, uint32_t, uint32_t *, uint32_t *, int64_t *, void **)" }
local GET_PRESENTATION_ATTRIBUTE = { 12, "int32_t (*)(void *, uint32_t, const MusicReplacer_GUID *, MusicReplacer_PROPVARIANT *)" }
local CONVERT_TO_CONTIGUOUS_BUFFER = { 41, "int32_t (*)(void *, void **)" } -- IMFSample
local LOCK = { 3, "int32_t (*)(void *, uint8_t **, uint32_t *, uint32_t *)" } -- IMFMediaBuffer
local UNLOCK = { 4, "int32_t (*)(void *)" }

local NativeFfi = nil
local ffi = nil
local mfplat = nil
local mfreadwrite = nil
local guids = {}
local init_error = nil

local function call(object, method, ...)
	return NativeFfi.call(object, method[1], method[2], ...)
end

-- `native_ffi` is a loaded native_ffi.lua.
function MediaDecoder.init(native_ffi)
	NativeFfi = native_ffi
	ffi = native_ffi and native_ffi.ffi
end

-- Starts Media Foundation once. Returns false, with MediaDecoder.error() saying why, when it cannot.
function MediaDecoder.available()
	if mfreadwrite then
		return true
	end

	if init_error then
		return false
	end

	if not NativeFfi or not NativeFfi.load() then
		init_error = NativeFfi and NativeFfi.error() or "native_ffi.lua is not loaded"
		return false
	end

	local ok, err = pcall(function()
		if not pcall(ffi.typeof, "MusicReplacer_PROPVARIANT") then
			ffi.cdef(CDEF)
		end

		mfplat = ffi.load("mfplat")
		mfreadwrite = ffi.load("mfreadwrite")
	end)

	if not ok then
		mfreadwrite = nil
		init_error = "loading Media Foundation failed: " .. tostring(err)
		return false
	end

	local guid = NativeFfi.guid
	guids.major_type = guid(0x48EBA18E, 0xF8C9, 0x4687, { 0xBF, 0x11, 0x0A, 0x74, 0xC9, 0xF9, 0x6A, 0x8F })
	guids.subtype = guid(0xF7E34C9A, 0x42E8, 0x4714, { 0xB7, 0x4B, 0xCB, 0x29, 0xD7, 0x2C, 0x35, 0xE5 })
	guids.audio = guid(0x73647561, 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71 })
	guids.pcm = guid(0x00000001, 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71 })
	guids.bits_per_sample = guid(0xF2DEB57F, 0x40FA, 0x4764, { 0xAA, 0x33, 0xED, 0x4F, 0x2D, 0x1F, 0xF6, 0x69 })
	guids.duration = guid(0x6C990D33, 0xBB8E, 0x477A, { 0x85, 0x98, 0x0D, 0x5D, 0x96, 0xFC, 0xD8, 0x8A })
	guids.null = guid(0, 0, 0, { 0, 0, 0, 0, 0, 0, 0, 0 })

	NativeFfi.ensure_com()

	local hresult = mfplat.MusicReplacer_MFStartup(MF_VERSION, MFSTARTUP_LITE)
	if not NativeFfi.succeeded(hresult) then
		mfreadwrite = nil
		init_error = "MFStartup failed with " .. NativeFfi.hex(hresult)
		return false
	end

	return true
end

function MediaDecoder.error()
	return init_error
end

local Decoder = {}
Decoder.__index = Decoder

-- Asks the reader for 16-bit PCM from the first audio stream, then reads back the exact format it chose.
local function configure_pcm(reader)
	local out = ffi.new("void *[1]")
	local succeeded = NativeFfi.succeeded

	call(reader, SET_STREAM_SELECTION, ALL_STREAMS, 0)
	call(reader, SET_STREAM_SELECTION, FIRST_AUDIO_STREAM, 1)

	if not succeeded(mfplat.MusicReplacer_MFCreateMediaType(out)) then
		return nil, "creating a media type failed"
	end
	local wanted = out[0]
	call(wanted, SET_GUID, guids.major_type, guids.audio)
	call(wanted, SET_GUID, guids.subtype, guids.pcm)
	call(wanted, SET_UINT32, guids.bits_per_sample, 16)
	local hresult = call(reader, SET_CURRENT_MEDIA_TYPE, FIRST_AUDIO_STREAM, nil, wanted)
	NativeFfi.release(wanted)

	if not succeeded(hresult) then
		return nil, "the file has no audio stream Windows can decode to PCM (" .. NativeFfi.hex(hresult) .. ")"
	end

	if not succeeded(call(reader, GET_CURRENT_MEDIA_TYPE, FIRST_AUDIO_STREAM, out)) then
		return nil, "reading the decoded format failed"
	end
	local actual = out[0]
	local format_out = ffi.new("MusicReplacer_WAVEFORMATEX *[1]")
	local size = ffi.new("uint32_t[1]")
	hresult = mfplat.MusicReplacer_MFCreateWaveFormatExFromMFMediaType(actual, format_out, size, 0)
	NativeFfi.release(actual)

	if not succeeded(hresult) then
		return nil, "converting the decoded format failed"
	end

	-- A plain PCM format with no extension, copied so Windows' allocation can be freed at once.
	local format = ffi.new("MusicReplacer_WAVEFORMATEX")
	format.wFormatTag = 1
	format.nChannels = format_out[0].nChannels
	format.nSamplesPerSec = format_out[0].nSamplesPerSec
	format.wBitsPerSample = 16
	format.nBlockAlign = format.nChannels * 2
	format.nAvgBytesPerSec = format.nSamplesPerSec * format.nBlockAlign
	format.cbSize = 0
	NativeFfi.ole32().MusicReplacer_CoTaskMemFree(format_out[0])

	return format
end

local function read_duration(reader)
	local value = ffi.new("MusicReplacer_PROPVARIANT")
	if NativeFfi.succeeded(call(reader, GET_PRESENTATION_ATTRIBUTE, MEDIA_SOURCE, guids.duration, value)) then
		return tonumber(value.value) / HUNDRED_NANOSECONDS
	end
	return nil
end

-- Opens `path`, a UTF-8 file path. Returns a decoder, or nil and why.
function MediaDecoder.open(path)
	if not MediaDecoder.available() then
		return nil, init_error
	end

	local out = ffi.new("void *[1]")
	local hresult = mfreadwrite.MusicReplacer_MFCreateSourceReaderFromURL(NativeFfi.wide(path), nil, out)
	if not NativeFfi.succeeded(hresult) then
		return nil, "opening the file failed with " .. NativeFfi.hex(hresult)
	end
	local reader = out[0]

	local format, err = configure_pcm(reader)
	if not format then
		NativeFfi.release(reader)
		return nil, err
	end

	return setmetatable({
		reader = reader,
		format = format,
		duration = read_duration(reader),
		ended = false,
	}, Decoder)
end

-- Decodes at least `seconds` of audio, or what is left of the file.
-- Returns a byte buffer owned by Lua and its length, or nil at the end of the file.
function Decoder:read(seconds)
	if self.ended or self.reader == nil then
		return nil
	end

	local wanted_bytes = math.floor(seconds * self.format.nAvgBytesPerSec)
	local chunks = {}
	local total = 0
	local stream_index = ffi.new("uint32_t[1]")
	local flags = ffi.new("uint32_t[1]")
	local timestamp = ffi.new("int64_t[1]")
	local out = ffi.new("void *[1]")
	local data = ffi.new("uint8_t *[1]")
	local length = ffi.new("uint32_t[1]")

	while total < wanted_bytes do
		out[0] = nil
		local hresult = call(self.reader, READ_SAMPLE, FIRST_AUDIO_STREAM, 0, stream_index, flags, timestamp, out)
		if not NativeFfi.succeeded(hresult) or math.floor(flags[0] / END_OF_STREAM_FLAG) % 2 == 1 then
			self.ended = true
		end

		local sample = out[0]
		if sample ~= nil then
			if NativeFfi.succeeded(call(sample, CONVERT_TO_CONTIGUOUS_BUFFER, out)) then
				local buffer = out[0]
				if NativeFfi.succeeded(call(buffer, LOCK, data, nil, length)) then
					local copy = ffi.new("uint8_t[?]", length[0])
					ffi.copy(copy, data[0], length[0])
					chunks[#chunks + 1] = { copy, length[0] }
					total = total + length[0]
					call(buffer, UNLOCK)
				end
				NativeFfi.release(buffer)
			end
			NativeFfi.release(sample)
		end

		if self.ended then
			break
		end
	end

	if total == 0 then
		return nil
	end

	local joined = ffi.new("uint8_t[?]", total)
	local offset = 0
	for _, chunk in ipairs(chunks) do
		ffi.copy(joined + offset, chunk[1], chunk[2])
		offset = offset + chunk[2]
	end

	return joined, total
end

-- Moves to `seconds` into the file. Returns true on success.
function Decoder:seek(seconds)
	local position = ffi.new("MusicReplacer_PROPVARIANT")
	position.vt = VT_I8
	position.value = math.floor(seconds * HUNDRED_NANOSECONDS)

	local ok = NativeFfi.succeeded(call(self.reader, SET_CURRENT_POSITION, guids.null, position))
	if ok then
		self.ended = false
	end
	return ok
end

function Decoder:close()
	if self.reader ~= nil then
		NativeFfi.release(self.reader)
		self.reader = nil
	end
end

return MediaDecoder
