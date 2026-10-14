-- Plays PCM audio through XAudio2, Windows' game audio engine, through LuaJIT's ffi.
-- XAudio2 mixes and plays on its own thread, so the game only needs to keep each voice's queue topped up.
-- No callback is ever registered, since LuaJIT cannot take calls from XAudio2's thread. Voice state is polled instead.
-- XAudio2 reads a submitted buffer while it plays, so each voice keeps its buffers alive until XAudio2 reports them played.
-- Docs: https://learn.microsoft.com/en-us/windows/win32/xaudio2/xaudio2-introduction

local XAudio = {}

-- XAudio2's structures use tight packing.
local CDEF = [[
#pragma pack(push, 1)
typedef struct {
	uint32_t Flags;
	uint32_t AudioBytes;
	const uint8_t *pAudioData;
	uint32_t PlayBegin;
	uint32_t PlayLength;
	uint32_t LoopBegin;
	uint32_t LoopLength;
	uint32_t LoopCount;
	void *pContext;
} MusicReplacer_XAUDIO2_BUFFER;

typedef struct {
	void *pCurrentBufferContext;
	uint32_t BuffersQueued;
	uint64_t SamplesPlayed;
} MusicReplacer_XAUDIO2_VOICE_STATE;
#pragma pack(pop)

int32_t MusicReplacer_XAudio2Create(void **engine, uint32_t flags, uint32_t processor) __asm__("XAudio2Create");
]]

local XAUDIO2_DEFAULT_PROCESSOR = 1
local XAUDIO2_DEFAULT_FREQ_RATIO = 2
local XAUDIO2_END_OF_STREAM = 0x40
local AUDIO_CATEGORY_GAME_MEDIA = 7

-- XAudio2 holds at most 64 buffers per voice.
local MAX_QUEUED_BUFFERS = 64

-- Signatures with the object pointer first. IXAudio2 starts with IUnknown's three slots, and its voices have no IUnknown.
local CREATE_SOURCE_VOICE = { 5, "int32_t (*)(void *, void **, const MusicReplacer_WAVEFORMATEX *, uint32_t, float, void *, void *, void *)" }
local CREATE_MASTERING_VOICE = { 7, "int32_t (*)(void *, void **, uint32_t, uint32_t, uint32_t, const uint16_t *, void *, int32_t)" }
local SET_VOLUME = { 12, "int32_t (*)(void *, float, uint32_t)" } -- IXAudio2Voice
local GET_VOLUME = { 13, "void (*)(void *, float *)" }
local DESTROY_VOICE = { 18, "void (*)(void *)" }
local START = { 19, "int32_t (*)(void *, uint32_t, uint32_t)" } -- IXAudio2SourceVoice
local STOP = { 20, "int32_t (*)(void *, uint32_t, uint32_t)" }
local SUBMIT_SOURCE_BUFFER = { 21, "int32_t (*)(void *, const MusicReplacer_XAUDIO2_BUFFER *, void *)" }
local GET_STATE = { 25, "void (*)(void *, MusicReplacer_XAUDIO2_VOICE_STATE *, uint32_t)" }

local NativeFfi = nil
local ffi = nil
local library = nil -- Kept for the engine's lifetime, since a collected ffi library unloads its DLL.
local engine = nil
local mastering_voice = nil
local init_error = nil

local function call(object, method, ...)
	return NativeFfi.call(object, method[1], method[2], ...)
end

-- `native_ffi` is a loaded native_ffi.lua.
function XAudio.init(native_ffi)
	NativeFfi = native_ffi
	ffi = native_ffi and native_ffi.ffi
end

-- Creates the engine and its output once. Returns false, with XAudio.error() saying why, when it cannot.
function XAudio.available()
	if engine ~= nil then
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
		if not pcall(ffi.typeof, "MusicReplacer_XAUDIO2_BUFFER") then
			ffi.cdef(CDEF)
		end
		library = ffi.load("xaudio2_9")
	end)

	if not ok then
		init_error = "loading XAudio2 failed: " .. tostring(err)
		return false
	end

	NativeFfi.ensure_com()

	local out = ffi.new("void *[1]")
	local hresult = library.MusicReplacer_XAudio2Create(out, 0, XAUDIO2_DEFAULT_PROCESSOR)
	if not NativeFfi.succeeded(hresult) then
		init_error = "XAudio2Create failed with " .. NativeFfi.hex(hresult)
		return false
	end
	local created = out[0]

	hresult = call(created, CREATE_MASTERING_VOICE, out, 0, 0, 0, nil, nil, AUDIO_CATEGORY_GAME_MEDIA)
	if not NativeFfi.succeeded(hresult) then
		NativeFfi.release(created)
		init_error = "creating the output failed with " .. NativeFfi.hex(hresult)
		return false
	end

	engine = created
	mastering_voice = out[0]
	return true
end

function XAudio.error()
	return init_error
end

local Voice = {}
Voice.__index = Voice

-- Creates a stopped voice for PCM in `format`, a MusicReplacer_WAVEFORMATEX. Returns the voice, or nil and why.
function XAudio.create_voice(format)
	if not XAudio.available() then
		return nil, init_error
	end

	local out = ffi.new("void *[1]")
	local hresult = call(engine, CREATE_SOURCE_VOICE, out, format, 0, XAUDIO2_DEFAULT_FREQ_RATIO, nil, nil, nil)
	if not NativeFfi.succeeded(hresult) then
		return nil, "creating a voice failed with " .. NativeFfi.hex(hresult)
	end

	return setmetatable({
		pointer = out[0],
		pending = {}, -- Submitted buffers XAudio2 may still read, oldest first.
		state = ffi.new("MusicReplacer_XAUDIO2_VOICE_STATE"),
	}, Voice)
end

-- Drops the buffers XAudio2 has finished with, and returns how many are still queued.
function Voice:queued()
	call(self.pointer, GET_STATE, self.state, 0)
	local queued = self.state.BuffersQueued

	while #self.pending > queued do
		table.remove(self.pending, 1)
	end

	return queued
end

-- Samples played since the voice was created, across every buffer.
function Voice:samples_played()
	call(self.pointer, GET_STATE, self.state, 0)
	return tonumber(self.state.SamplesPlayed)
end

-- Queues `bytes` of `data`, a Lua-owned buffer this voice keeps alive until it is played.
-- `last` marks the end of the stream. Returns false when the queue is full or XAudio2 refuses the buffer.
function Voice:submit(data, bytes, last)
	if self:queued() >= MAX_QUEUED_BUFFERS then
		return false
	end

	local buffer = ffi.new("MusicReplacer_XAUDIO2_BUFFER")
	buffer.Flags = last and XAUDIO2_END_OF_STREAM or 0
	buffer.AudioBytes = bytes
	buffer.pAudioData = data

	if not NativeFfi.succeeded(call(self.pointer, SUBMIT_SOURCE_BUFFER, buffer, nil)) then
		return false
	end

	self.pending[#self.pending + 1] = data
	return true
end

-- Volume as a linear amplitude scale. 1 plays the audio as decoded, 0 is silent.
function Voice:set_volume(volume)
	call(self.pointer, SET_VOLUME, math.max(0, volume), 0)
end

function Voice:volume()
	local level = ffi.new("float[1]")
	call(self.pointer, GET_VOLUME, level)
	return level[0]
end

function Voice:start()
	call(self.pointer, START, 0, 0)
end

function Voice:stop()
	call(self.pointer, STOP, 0, 0)
end

-- Stops and frees the voice. XAudio2 has finished with every buffer once this returns, so they are freed too.
function Voice:destroy()
	if self.pointer ~= nil then
		call(self.pointer, DESTROY_VOICE)
		self.pointer = nil
		self.pending = {}
	end
end

-- Frees the output and the engine. Destroy every voice first.
function XAudio.shutdown()
	if mastering_voice ~= nil then
		call(mastering_voice, DESTROY_VOICE)
		mastering_voice = nil
	end

	if engine ~= nil then
		NativeFfi.release(engine)
		engine = nil
	end
end

return XAudio
