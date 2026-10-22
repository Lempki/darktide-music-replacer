-- Decodes an audio file to 16-bit PCM with Windows Media Foundation, a chunk at a time, through LuaJIT's ffi.
-- Media Foundation ships with Windows and handles mp3, m4a/aac, wav, flac, and wma. It has no Ogg or Opus support.
-- The source reader runs synchronously on the calling thread, so no Media Foundation thread ever calls back into Lua.
-- Docs: https://learn.microsoft.com/en-us/windows/win32/medfound/using-the-source-reader-to-process-media-data

local MediaDecoder = {}

local CDEF = [[
typedef struct { uint16_t vt; uint16_t reserved1; uint16_t reserved2; uint16_t reserved3; int64_t value; int64_t padding; } MusicReplacer_PROPVARIANT;

int32_t MusicReplacer_MFStartup(uint32_t version, uint32_t flags) __asm__("MFStartup");
int32_t MusicReplacer_MFShutdown(void) __asm__("MFShutdown");
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
local ERROR_FLAG = 0x1
local END_OF_STREAM_FLAG = 0x2
local MEDIA_TYPE_CHANGED_FLAG = 0x20

-- Reads in a row that bring no sample before the file counts as ended. Real files bring one with nearly every read.
local MAX_EMPTY_READS = 100
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
		NativeFfi.define(CDEF)

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

-- Call from mod.on_unload, after every decoder is closed. It pairs the MFStartup in MediaDecoder.available().
-- Otherwise a mod reload leaves Media Foundation's work threads running in a DLL the old module's handle may unload.
function MediaDecoder.shutdown()
	if mfreadwrite then
		mfplat.MusicReplacer_MFShutdown()
		mfreadwrite = nil
	end
end

function MediaDecoder.error()
	return init_error
end

local Decoder = {}
Decoder.__index = Decoder

-- Reads back the exact format the reader decodes to now, as a plain 16-bit PCM format, or nil and why.
local function read_format(reader)
	local out = ffi.new("void *[1]")
	local succeeded = NativeFfi.succeeded

	if not succeeded(call(reader, GET_CURRENT_MEDIA_TYPE, FIRST_AUDIO_STREAM, out)) then
		return nil, "reading the decoded format failed"
	end
	local actual = out[0]
	local format_out = ffi.new("MusicReplacer_WAVEFORMATEX *[1]")
	local size = ffi.new("uint32_t[1]")
	local hresult = mfplat.MusicReplacer_MFCreateWaveFormatExFromMFMediaType(actual, format_out, size, 0)
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

-- Asks the reader for 16-bit PCM from the first audio stream, then reads back the exact format it chose.
local function configure_pcm(reader)
	local out = ffi.new("void *[1]")

	call(reader, SET_STREAM_SELECTION, ALL_STREAMS, 0)
	call(reader, SET_STREAM_SELECTION, FIRST_AUDIO_STREAM, 1)

	if not NativeFfi.succeeded(mfplat.MusicReplacer_MFCreateMediaType(out)) then
		return nil, "creating a media type failed"
	end
	local wanted = out[0]
	call(wanted, SET_GUID, guids.major_type, guids.audio)
	call(wanted, SET_GUID, guids.subtype, guids.pcm)
	call(wanted, SET_UINT32, guids.bits_per_sample, 16)
	local hresult = call(reader, SET_CURRENT_MEDIA_TYPE, FIRST_AUDIO_STREAM, nil, wanted)
	NativeFfi.release(wanted)

	if not NativeFfi.succeeded(hresult) then
		return nil, "the file has no audio stream Windows can decode to PCM (" .. NativeFfi.hex(hresult) .. ")"
	end

	return read_format(reader)
end

local function read_duration(reader)
	local value = ffi.new("MusicReplacer_PROPVARIANT")
	if NativeFfi.succeeded(call(reader, GET_PRESENTATION_ATTRIBUTE, MEDIA_SOURCE, guids.duration, value)) then
		return tonumber(value.value) / HUNDRED_NANOSECONDS
	end
	return nil
end

-- Opens `path`, a UTF-8 file path, absolute or relative to the game's working directory. Returns a decoder, or nil and why.
function MediaDecoder.open(path)
	if not MediaDecoder.available() then
		return nil, init_error
	end

	local out = ffi.new("void *[1]")
	local hresult = mfreadwrite.MusicReplacer_MFCreateSourceReaderFromURL(NativeFfi.wide_full_path(path), nil, out)
	if not NativeFfi.succeeded(hresult) then
		return nil, "opening the file failed with " .. NativeFfi.hex(hresult)
	end
	local reader = out[0]

	local format, err = configure_pcm(reader)
	if not format then
		NativeFfi.release(reader)
		return nil, err
	end

	local decoder = setmetatable({
		reader = reader,
		-- Read many times a second, so it is fetched from the reader once.
		read_sample = NativeFfi.method(reader, READ_SAMPLE[1], READ_SAMPLE[2]),
		format = format,
		duration = read_duration(reader),
		source_ended = false,
		format_changed = false,
		empty_reads = 0,
		-- The part of a decoded chunk that did not fit the caller's buffer, on the Windows heap.
		carry = nil,
		carry_capacity = 0,
		carry_offset = 0,
		carry_bytes = 0,
		-- Out parameters, made once so reading allocates nothing on the Lua heap.
		stream_index = ffi.new("uint32_t[1]"),
		flags = ffi.new("uint32_t[1]"),
		timestamp = ffi.new("int64_t[1]"),
		out = ffi.new("void *[1]"),
		data = ffi.new("uint8_t *[1]"),
		length = ffi.new("uint32_t[1]"),
	}, Decoder)

	decoder:prime()
	return decoder
end

-- Keeps the bytes of a decoded chunk that did not fit, growing the carry buffer when a chunk is larger than any before.
local function keep_rest(self, source, bytes)
	if bytes > self.carry_capacity then
		NativeFfi.free(self.carry)
		self.carry = NativeFfi.alloc(bytes)
		self.carry_capacity = self.carry and bytes or 0
		if not self.carry then
			self.carry_bytes = 0
			return
		end
	end

	ffi.copy(self.carry, source, bytes)
	self.carry_offset = 0
	self.carry_bytes = bytes
end

local function has_flag(flags, flag)
	return bit.band(flags, flag) ~= 0
end

-- Whether to follow a format change the reader reports, which also updates the format before any audio has been handed out.
-- An AAC file at 24 kHz or less is first reported at twice its rate, and a mono one as stereo, in case it is HE-AAC.
-- Its real format comes with its first sample, so a change at that point is the file's true format.
-- Later, only a change that keeps the channels and the rate is followed, since a voice keeps the format it was created with.
local function follows_format_change(self)
	local format = read_format(self.reader)
	if not format then
		return false
	end

	if self.priming then
		self.format = format
		return true
	end

	return format.nChannels == self.format.nChannels and format.nSamplesPerSec == self.format.nSamplesPerSec
end

-- Reads the next sample and handles what the reader reports with it. Returns the sample, which the caller releases, or nil.
local function next_sample(self)
	self.out[0] = nil
	local hresult = self.read_sample(self.reader, FIRST_AUDIO_STREAM, 0, self.stream_index, self.flags, self.timestamp, self.out)
	local flags = self.flags[0]
	if not NativeFfi.succeeded(hresult) or has_flag(flags, END_OF_STREAM_FLAG) or has_flag(flags, ERROR_FLAG) then
		self.source_ended = true
	end

	-- A file whose format really changes partway, such as an mp3 that mixes sample rates, would play the rest at the wrong speed.
	-- So the file ends there instead, and the changed sample is dropped.
	local sample = self.out[0]
	if has_flag(flags, MEDIA_TYPE_CHANGED_FLAG) and not follows_format_change(self) then
		self.source_ended = true
		self.format_changed = true
		if sample ~= nil then
			NativeFfi.release(sample)
			sample = nil
		end
	end

	-- A reader that keeps answering with no sample and no end, as a broken file can, would otherwise spin the game's thread.
	if sample == nil then
		self.empty_reads = self.empty_reads + 1
		if self.empty_reads >= MAX_EMPTY_READS then
			self.source_ended = true
		end
	else
		self.empty_reads = 0
	end

	return sample
end

-- Copies up to `room` bytes of `sample` to `target`, keeps the rest for the next read, and releases the sample.
-- Returns how many bytes it copied.
local function take_sample(self, sample, target, room)
	local count = 0

	if NativeFfi.succeeded(call(sample, CONVERT_TO_CONTIGUOUS_BUFFER, self.out)) then
		local buffer = self.out[0]
		if NativeFfi.succeeded(call(buffer, LOCK, self.data, nil, self.length)) then
			local length = self.length[0]
			count = math.min(length, room)
			if count > 0 then
				ffi.copy(target, self.data[0], count)
			end

			if length > count then
				keep_rest(self, self.data[0] + count, length - count)
			end

			call(buffer, UNLOCK)
		end
		NativeFfi.release(buffer)
	end
	NativeFfi.release(sample)

	return count
end

-- Reads the first sample ahead and keeps it for the first read, so `format` is already the one the file plays in.
-- Called once by MediaDecoder.open.
function Decoder:prime()
	self.priming = true
	local sample = next_sample(self)
	self.priming = false

	if sample ~= nil then
		take_sample(self, sample, nil, 0)
	end
end

-- Fills `target`, a byte pointer with room for `capacity` bytes, and returns how many bytes it wrote.
-- It writes fewer only at the end of the file. Keep `capacity` a multiple of the format's block size.
function Decoder:read_into(target, capacity)
	local written = 0

	if self.carry_bytes > 0 then
		local count = math.min(self.carry_bytes, capacity)
		ffi.copy(target, self.carry + self.carry_offset, count)
		self.carry_offset = self.carry_offset + count
		self.carry_bytes = self.carry_bytes - count
		written = count
	end

	while written < capacity and not self.source_ended and self.reader ~= nil do
		local sample = next_sample(self)
		if sample ~= nil then
			written = written + take_sample(self, sample, target + written, capacity - written)
		end
	end

	return written
end

-- True once every decoded byte has been handed out.
function Decoder:at_end()
	return self.source_ended and self.carry_bytes == 0
end

-- Moves to `seconds` into the file. Returns true on success.
function Decoder:seek(seconds)
	local position = ffi.new("MusicReplacer_PROPVARIANT")
	position.vt = VT_I8
	position.value = math.floor(seconds * HUNDRED_NANOSECONDS)

	-- After a format change the file plays no further, not even from its start, since the voice cannot follow.
	-- A closed decoder has no reader left to call.
	if self.format_changed or self.reader == nil then
		return false
	end

	local ok = NativeFfi.succeeded(call(self.reader, SET_CURRENT_POSITION, guids.null, position))
	if ok then
		self.source_ended = false
		self.carry_bytes = 0
		self.empty_reads = 0
	end
	return ok
end

function Decoder:close()
	if self.reader ~= nil then
		NativeFfi.release(self.reader)
		self.reader = nil
	end

	NativeFfi.free(self.carry)
	self.carry = nil
	self.carry_capacity = 0
	self.carry_bytes = 0
end

return MediaDecoder
