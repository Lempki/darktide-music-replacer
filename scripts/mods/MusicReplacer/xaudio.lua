-- Plays PCM audio through XAudio2, Windows' game audio engine, through LuaJIT's ffi.
-- XAudio2 mixes and plays on its own thread, so the game only needs to keep each voice's queue topped up.
-- No callback is ever registered, since LuaJIT cannot take calls from XAudio2's thread. Voice state is polled instead.
-- XAudio2 reads a submitted buffer while it plays, so the caller keeps each buffer alive until the voice's queue has moved past it.
-- After a critical error, such as an audio device change it could not follow, every XAudio2 call fails until the engine is recreated.
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
	uint32_t SamplesPlayedLow;
	uint32_t SamplesPlayedHigh;
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
local DESTROY_VOICE = { 18, "void (*)(void *)" } -- IXAudio2Voice, also used on the mastering voice

-- Slots 12 to 18 are IXAudio2Voice's, and 19 onward are IXAudio2SourceVoice's.
local VOICE_METHODS = {
	set_volume = { 12, "int32_t (*)(void *, float, uint32_t)" },
	get_volume = { 13, "void (*)(void *, float *)" },
	destroy_voice = DESTROY_VOICE,
	start = { 19, "int32_t (*)(void *, uint32_t, uint32_t)" },
	stop = { 20, "int32_t (*)(void *, uint32_t, uint32_t)" },
	submit_source_buffer = { 21, "int32_t (*)(void *, const MusicReplacer_XAUDIO2_BUFFER *, void *)" },
	flush_source_buffers = { 22, "int32_t (*)(void *)" },
	get_state = { 25, "void (*)(void *, MusicReplacer_XAUDIO2_VOICE_STATE *, uint32_t)" },
}

local NativeFfi = nil
local ffi = nil
local library = nil -- Kept for the engine's lifetime, since a collected ffi library unloads its DLL.
local engine = nil
local mastering_voice = nil
local init_error = nil
local init_can_retry = false -- True when init_error came from creating the engine or its output, which an audio device coming back can fix.
local failure = nil -- Why the engine stopped working, or nil.

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
		NativeFfi.define(CDEF)
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
		init_can_retry = true
		return false
	end
	local created = out[0]

	-- This fails while Windows has no audio output at all, for example right after the only headset is unplugged.
	hresult = call(created, CREATE_MASTERING_VOICE, out, 0, 0, 0, nil, nil, AUDIO_CATEGORY_GAME_MEDIA)
	if not NativeFfi.succeeded(hresult) then
		NativeFfi.release(created)
		init_error = "creating the output failed with " .. NativeFfi.hex(hresult)
		init_can_retry = true
		return false
	end

	engine = created
	mastering_voice = out[0]
	return true
end

function XAudio.error()
	return init_error
end

-- True when the engine could not be created for a reason that can pass, such as having no audio output.
-- Calling XAudio.shutdown() clears the error, so the next XAudio.available() tries again.
function XAudio.can_retry()
	return init_error ~= nil and init_can_retry
end

-- Why the engine stopped working, or nil. Destroy every voice, call XAudio.shutdown(), and start again to recover.
function XAudio.failure()
	return failure
end

local Voice = {}
Voice.__index = Voice

-- Creates a stopped voice for PCM in `format`, a MusicReplacer_WAVEFORMATEX. Returns the voice, or nil and why.
-- A refused voice is not recorded as an engine failure, since one file's format, such as a sample rate above 200 kHz, can cause it.
function XAudio.create_voice(format)
	if not XAudio.available() then
		return nil, init_error
	end

	local out = ffi.new("void *[1]")
	local hresult = call(engine, CREATE_SOURCE_VOICE, out, format, 0, XAUDIO2_DEFAULT_FREQ_RATIO, nil, nil, nil)
	if not NativeFfi.succeeded(hresult) then
		return nil, "creating a voice failed with " .. NativeFfi.hex(hresult)
	end

	local pointer = out[0]

	-- The voice's methods run every frame, so they are bound once instead of cast on every call, which keeps the Lua heap quiet.
	local vtable = ffi.cast("MusicReplacer_ComObject *", pointer).lpVtbl
	local methods = {}
	for name, method in pairs(VOICE_METHODS) do
		methods[name] = ffi.cast(ffi.typeof(method[2]), vtable[method[1]])
	end

	return setmetatable({
		pointer = pointer,
		methods = methods,
		-- Made once and reused, since XAudio2 copies the descriptor when a buffer is submitted.
		buffer = ffi.new("MusicReplacer_XAUDIO2_BUFFER"),
		state = ffi.new("MusicReplacer_XAUDIO2_VOICE_STATE"),
		level = ffi.new("float[1]"),
	}, Voice)
end

local function read_state(self)
	self.methods.get_state(self.pointer, self.state, 0)
	return self.state
end

local function checked_voice(self, what, name, ...)
	local hresult = self.methods[name](self.pointer, ...)
	if NativeFfi.succeeded(hresult) then
		return true
	end

	failure = failure or string.format("%s failed with %s", what, NativeFfi.hex(hresult))
	return false
end

-- Buffers submitted and not yet played.
function Voice:queued()
	return read_state(self).BuffersQueued
end

-- Samples played since the voice was created, across every buffer.
-- Read as two halves, since a 64-bit field would come back as a new object on every read.
function Voice:samples_played()
	local state = read_state(self)
	return state.SamplesPlayedLow + state.SamplesPlayedHigh * 4294967296
end

-- Queues `bytes` at `data`. The caller keeps that memory alive until the queue has moved past it.
-- `last` marks the end of the stream. Returns false when the queue is full or XAudio2 refuses the buffer.
function Voice:submit(data, bytes, last)
	if self:queued() >= MAX_QUEUED_BUFFERS then
		return false
	end

	local buffer = self.buffer
	buffer.Flags = last and XAUDIO2_END_OF_STREAM or 0
	buffer.AudioBytes = bytes
	buffer.pAudioData = data

	return checked_voice(self, "submitting audio", "submit_source_buffer", buffer, nil)
end

-- Volume as a linear amplitude scale. 1 plays the audio as decoded, 0 is silent.
function Voice:set_volume(volume)
	checked_voice(self, "setting a volume", "set_volume", math.max(0, volume), 0)
end

function Voice:volume()
	self.methods.get_volume(self.pointer, self.level)
	return self.level[0]
end

function Voice:start()
	checked_voice(self, "starting a voice", "start", 0, 0)
end

function Voice:stop()
	checked_voice(self, "stopping a voice", "stop", 0, 0)
end

-- Drops every queued buffer that has not started playing.
function Voice:flush()
	checked_voice(self, "flushing a voice", "flush_source_buffers")
end

-- Stops and frees the voice. XAudio2 has finished with every buffer once this returns.
function Voice:destroy()
	if self.pointer ~= nil then
		self.methods.destroy_voice(self.pointer)
		self.pointer = nil
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

	failure = nil
	init_error = nil
	init_can_retry = false
end

return XAudio
