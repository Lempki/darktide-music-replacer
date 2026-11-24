-- Pins media_decoder.lua's own logic with a fake Media Foundation source reader: where reading starts after a seek.
-- The Windows calls underneath are checked outside the specs with tools/player_demo.lua.

local ffi = require("ffi")
local FakeEngine = require("tests.helpers.fake_engine")

local SAMPLE_RATE = 1000 -- Mono 16-bit, so a frame is 2 bytes and 1 ms.
local CHUNK_FRAMES = 100 -- Each sample the reader brings is 0.1 s.
local HUNDRED_NANOSECONDS = 10000000

-- The C declarations are made once per test run, since declaring a type twice is an error.
local declared = {}
local function declare(text)
	if not declared[text] then
		declared[text] = true
		ffi.cdef(text)
	end
end

-- The types media_decoder.lua expects native_ffi.lua to have declared.
local NATIVE_TYPES = [[
typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } MusicReplacer_GUID;
#pragma pack(push, 1)
typedef struct {
	uint16_t wFormatTag;
	uint16_t nChannels;
	uint32_t nSamplesPerSec;
	uint32_t nAvgBytesPerSec;
	uint16_t nBlockAlign;
	uint16_t wBitsPerSample;
	uint16_t cbSize;
} MusicReplacer_WAVEFORMATEX;
#pragma pack(pop)
]]

-- Returns media_decoder.lua initialized with a fake reader over a file of `seconds`, whose every frame holds its own index.
-- A seek lands at the start of the chunk before the one the asked position is in, as Media Foundation lands at or before it.
local function load_decoder(seconds)
	declare(NATIVE_TYPES)

	local anchors = {} -- Keeps the memory behind the fake objects alive.
	local objects = {} -- Each fake COM object's vtable slots, by its address.

	local function address(pointer)
		return tonumber(ffi.cast("uintptr_t", pointer))
	end
	local function new_object(slots)
		local memory = ffi.new("uint8_t[1]")
		anchors[#anchors + 1] = memory
		local pointer = ffi.cast("void *", memory)
		objects[address(pointer)] = slots
		return pointer
	end
	local function succeed()
		return 0
	end

	local total_frames = seconds * SAMPLE_RATE
	local next_frame = 0

	local format = ffi.new("MusicReplacer_WAVEFORMATEX")
	format.nChannels = 1
	format.nSamplesPerSec = SAMPLE_RATE

	local function new_sample(samples, frames)
		local buffer = new_object({
			[3] = function(data, _, length) -- IMFMediaBuffer::Lock
				data[0] = ffi.cast("uint8_t *", samples)
				length[0] = frames * 2
				return 0
			end,
			[4] = succeed,
		})
		return new_object({ [41] = function(out) out[0] = buffer return 0 end }) -- IMFSample::ConvertToContiguousBuffer
	end

	-- IMFSourceReader::ReadSample, which brings the chunk at `next_frame` with its time stamp.
	local function read_sample(_, _, _, _, flags, timestamp, sample_out)
		flags[0] = 0
		sample_out[0] = nil
		if next_frame >= total_frames then
			flags[0] = 0x2
			return 0
		end

		local frames = math.min(CHUNK_FRAMES, total_frames - next_frame)
		local samples = ffi.new("int16_t[?]", frames)
		for index = 0, frames - 1 do
			samples[index] = next_frame + index
		end
		anchors[#anchors + 1] = samples

		timestamp[0] = next_frame * HUNDRED_NANOSECONDS / SAMPLE_RATE
		sample_out[0] = new_sample(samples, frames)
		next_frame = next_frame + frames
		return 0
	end

	local reader = new_object({
		[4] = succeed, -- SetStreamSelection
		[6] = function(_, out) out[0] = new_object({}) return 0 end, -- GetCurrentMediaType
		[7] = succeed, -- SetCurrentMediaType
		[8] = function(_, position) -- SetCurrentPosition
			local asked_chunk = math.floor(tonumber(position.value) * SAMPLE_RATE / HUNDRED_NANOSECONDS / CHUNK_FRAMES)
			next_frame = math.max(0, asked_chunk - 1) * CHUNK_FRAMES
			return 0
		end,
		[12] = function(_, _, value) value.value = seconds * HUNDRED_NANOSECONDS return 0 end, -- GetPresentationAttribute
	})

	local fake_ffi = setmetatable({
		load = function(name)
			if name == "mfplat" then
				return {
					MusicReplacer_MFStartup = succeed,
					MusicReplacer_MFShutdown = succeed,
					MusicReplacer_MFCreateMediaType = function(out)
						out[0] = new_object({ [21] = succeed, [24] = succeed })
						return 0
					end,
					MusicReplacer_MFCreateWaveFormatExFromMFMediaType = function(_, format_out)
						format_out[0] = format
						return 0
					end,
				}
			end
			return { MusicReplacer_MFCreateSourceReaderFromURL = function(_, _, out) out[0] = reader return 0 end }
		end,
	}, { __index = ffi })

	local native_ffi = {
		ffi = fake_ffi,
		load = function() return true end,
		define = declare,
		ensure_com = function() end,
		succeeded = function(hresult) return hresult >= 0 end,
		hex = tostring,
		guid = function() return ffi.new("MusicReplacer_GUID") end,
		wide_full_path = function(path) return path end,
		ole32 = function() return { MusicReplacer_CoTaskMemFree = function() end } end,
		call = function(object, index, _, ...)
			if index == 2 then -- IUnknown::Release
				return 0
			end
			return objects[address(object)][index](...)
		end,
		method = function() return read_sample end,
		alloc = function(bytes)
			local memory = ffi.new("uint8_t[?]", bytes)
			anchors[#anchors + 1] = memory
			return memory
		end,
		free = function() end,
	}
	native_ffi.release = function(object) native_ffi.call(object, 2) end

	local MediaDecoder = FakeEngine.new():load("modules/windows/media_decoder")
	MediaDecoder.init(native_ffi)
	return MediaDecoder
end

-- Reads `frames` frames in one go, and returns the first frame's index and the bytes read.
local function read_frames(decoder, frames)
	local buffer = ffi.new("int16_t[?]", frames)
	local bytes = decoder:read_into(ffi.cast("uint8_t *", buffer), frames * 2)
	return buffer[0], bytes
end

describe("media_decoder.lua", function()
	it("reads from the file's start", function()
		local decoder = load_decoder(1).open("a.mp3")

		assert_deep_equal({ read_frames(decoder, 50) }, { 0, 100 })
	end)

	it("starts reading at the asked position when the seek lands before it", function()
		local decoder = load_decoder(1).open("a.mp3")

		assert_equal(decoder:seek(0.25), true)

		assert_deep_equal({ read_frames(decoder, 50) }, { 250, 100 })
	end)

	it("keeps every chunk whole once reading has reached the asked position", function()
		local decoder = load_decoder(1).open("a.mp3")
		decoder:seek(0.25)
		read_frames(decoder, 50)

		assert_deep_equal({ read_frames(decoder, 100) }, { 300, 200 })
	end)

	it("starts at the file's start again after a seek to 0", function()
		local decoder = load_decoder(1).open("a.mp3")
		read_frames(decoder, 300)

		assert_equal(decoder:seek(0), true)

		assert_deep_equal({ read_frames(decoder, 50) }, { 0, 100 })
	end)
end)
