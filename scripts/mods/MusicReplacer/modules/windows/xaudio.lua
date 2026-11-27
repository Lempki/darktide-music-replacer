-- Plays PCM audio through XAudio2, Windows' game audio engine, through LuaJIT's ffi.
-- XAudio2 mixes and plays on its own thread, so the game only needs to keep each voice's queue topped up.
-- No callback is ever registered, since LuaJIT cannot safely take calls from XAudio2's thread. Voice state is polled instead.
-- XAudio2 reads a submitted buffer's audio while it plays, so the caller keeps that memory alive until the queue has moved past it.
-- An error in XAudio2's own facility or in the Windows audio client's counts as a failed engine, so it and every voice must be made again.
-- Any other error fails only the voice it came from.
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

typedef struct {
	uint32_t Flags;
	void *pOutputVoice;
} MusicReplacer_XAUDIO2_SEND_DESCRIPTOR;

typedef struct {
	uint32_t SendCount;
	MusicReplacer_XAUDIO2_SEND_DESCRIPTOR *pSends;
} MusicReplacer_XAUDIO2_VOICE_SENDS;

typedef struct {
	void *pEffect;
	int32_t InitialState;
	uint32_t OutputChannels;
} MusicReplacer_XAUDIO2_EFFECT_DESCRIPTOR;

typedef struct {
	uint32_t EffectCount;
	MusicReplacer_XAUDIO2_EFFECT_DESCRIPTOR *pEffectDescriptors;
} MusicReplacer_XAUDIO2_EFFECT_CHAIN;

typedef struct {
	float WetDryMix;
	uint32_t ReflectionsDelay;
	uint8_t ReverbDelay;
	uint8_t RearDelay;
	uint8_t SideDelay;
	uint8_t PositionLeft;
	uint8_t PositionRight;
	uint8_t PositionMatrixLeft;
	uint8_t PositionMatrixRight;
	uint8_t EarlyDiffusion;
	uint8_t LateDiffusion;
	uint8_t LowEQGain;
	uint8_t LowEQCutoff;
	uint8_t HighEQGain;
	uint8_t HighEQCutoff;
	float RoomFilterFreq;
	float RoomFilterMain;
	float RoomFilterHF;
	float ReflectionsGain;
	float ReverbGain;
	float DecayTime;
	float Density;
	float RoomSize;
	int32_t DisableLateField;
} MusicReplacer_XAUDIO2FX_REVERB_PARAMETERS;

typedef struct {
	float FrequencyCenter0;
	float Gain0;
	float Bandwidth0;
	float FrequencyCenter1;
	float Gain1;
	float Bandwidth1;
	float FrequencyCenter2;
	float Gain2;
	float Bandwidth2;
	float FrequencyCenter3;
	float Gain3;
	float Bandwidth3;
} MusicReplacer_FXEQ_PARAMETERS;
#pragma pack(pop)

int32_t MusicReplacer_XAudio2Create(void **engine, uint32_t flags, uint32_t processor) __asm__("XAudio2Create");
int32_t MusicReplacer_CreateAudioReverb(void **effect) __asm__("CreateAudioReverb");
int32_t MusicReplacer_CreateFX(const MusicReplacer_GUID *clsid, void **effect, const void *init_data, uint32_t init_size) __asm__("CreateFX");
]]

-- The effects voice's format. XAudio2's reverb takes 20,000 to 48,000 Hz, XAPOFX's EQ 22,000 to 48,000 Hz, and both stereo.
-- Every song with effects on plays through this one voice, which converts its rate and channels.
local EFFECTS_CHANNELS = 2
local EFFECTS_SAMPLE_RATE = 48000

-- The effects' places in the effects voice's chain.
-- The EQ comes first, so the reverb echoes the song as the EQ shapes it.
local EQ_EFFECT = 0
local REVERB_EFFECT = 1
local EFFECT_COUNT = 2

-- CLSID_FXEQ in xapofx.h, the class CreateFX makes XAPOFX's EQ from.
local CLSID_FXEQ = { 0xF5E01117, 0xD6C4, 0x485A, { 0xA3, 0xF5, 0x69, 0x51, 0x96, 0xF3, 0xDB, 0xFA } }

-- XAudio2's default processor, processor 1. Microsoft advises it over choosing processors, which can get in the scheduler's way.
-- Setting more than one processor bit would also start a worker thread for each.
local XAUDIO2_DEFAULT_PROCESSOR = 1

-- XAudio2's own default for the highest frequency ratio a voice allows.
-- The mod never changes a voice's pitch, so this only caps what SetFrequencyRatio could set.
local XAUDIO2_DEFAULT_FREQ_RATIO = 2

local XAUDIO2_END_OF_STREAM = 0x40
local XAUDIO2_VOICE_NOSAMPLESPLAYED = 0x100

-- AudioCategory_GameEffects, XAudio2's default category.
-- Microsoft gives game music AudioCategory_GameMedia.
-- Windows mutes that category while another application plays music in the background, and Windows Media Player faded it out in game.
local AUDIO_CATEGORY_GAME_EFFECTS = 6

-- The formats XAudio2 can play. A voice for anything else is always refused, whatever state the engine is in.
local MIN_SAMPLE_RATE = 1000
local MAX_SAMPLE_RATE = 200000
local MAX_CHANNELS = 64

-- XAudio2 takes volumes from -2^24 to 2^24, where a negative one inverts the phase.
-- A volume here is never negative, so Voice:set_volume() keeps it between 0 and this.
local MAX_VOLUME = 2 ^ 24

-- The top 16 bits of an error HRESULT in XAudio2's own facility, such as XAUDIO2_E_DEVICE_INVALIDATED, or the audio client's.
-- XAudio2's own codes stand for invalid calls, failed effects, and a lost device, while an invalid argument has no code.
-- So neither prefix points at one voice's arguments.
local XAUDIO2_ERROR_PREFIX = 0x8896
local AUDCLNT_ERROR_PREFIX = 0x8889

-- Signatures with the object pointer first. IXAudio2 starts with IUnknown's three slots, and its voices have no IUnknown.
local CREATE_SOURCE_VOICE = { 5, "int32_t (*)(void *, void **, const MusicReplacer_WAVEFORMATEX *, uint32_t, float, void *, " ..
	"const MusicReplacer_XAUDIO2_VOICE_SENDS *, void *)" }
local CREATE_SUBMIX_VOICE = { 6, "int32_t (*)(void *, void **, uint32_t, uint32_t, uint32_t, uint32_t, void *, " ..
	"const MusicReplacer_XAUDIO2_EFFECT_CHAIN *)" }
local CREATE_MASTERING_VOICE = { 7, "int32_t (*)(void *, void **, uint32_t, uint32_t, uint32_t, const uint16_t *, void *, int32_t)" }
local DESTROY_VOICE = { 18, "void (*)(void *)" } -- IXAudio2Voice's slot, also used on the mastering voice.
-- IXAudio2Voice's slots for one effect in a voice's chain.
local ENABLE_EFFECT = { 3, "int32_t (*)(void *, uint32_t, uint32_t)" }
local DISABLE_EFFECT = { 4, "int32_t (*)(void *, uint32_t, uint32_t)" }
local SET_EFFECT_PARAMETERS = { 6, "int32_t (*)(void *, uint32_t, const void *, uint32_t, uint32_t)" }

-- Slots 0 to 18 are IXAudio2Voice's, and 19 onward are IXAudio2SourceVoice's.
local VOICE_METHODS = {
	set_output_voices = { 1, "int32_t (*)(void *, const MusicReplacer_XAUDIO2_VOICE_SENDS *)" },
	set_volume = { 12, "int32_t (*)(void *, float, uint32_t)" },
	destroy_voice = DESTROY_VOICE,
	start = { 19, "int32_t (*)(void *, uint32_t, uint32_t)" },
	stop = { 20, "int32_t (*)(void *, uint32_t, uint32_t)" },
	submit_source_buffer = { 21, "int32_t (*)(void *, const MusicReplacer_XAUDIO2_BUFFER *, void *)" },
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

-- The voice that carries the effects, made the first time a song asks for them.
local effects_voice = nil
-- The send list that points source voices at it, as `sends`, with the descriptor it points to as `descriptor`.
-- The descriptor is kept here, since the garbage collector would free it while the send list still points to it.
local effects_route = nil
local effects_error = nil -- Why the effects voice could not be made, or nil. Songs then play without effects.
-- The effects' parameters, as Reverb.native() and Equalizer.native() give them, kept so a rebuilt engine's effects voice gets them again.
-- Nil turns that effect off, so the songs pass through it unchanged.
local reverb_parameters = nil
local eq_parameters = nil

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
	-- A nil device ID asks for Windows' default output.
	hresult = call(created, CREATE_MASTERING_VOICE, out, 0, 0, 0, nil, nil, AUDIO_CATEGORY_GAME_EFFECTS)
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

local function is_engine_error(hresult)
	local prefix = math.floor((hresult < 0 and hresult + 2 ^ 32 or hresult) / 65536)
	return prefix == XAUDIO2_ERROR_PREFIX or prefix == AUDCLNT_ERROR_PREFIX
end

-- Why XAudio2 can never play `format`, or nil when it can.
function XAudio.format_error(format)
	local channels, rate = format.nChannels, format.nSamplesPerSec
	if channels < 1 or channels > MAX_CHANNELS or rate < MIN_SAMPLE_RATE or rate > MAX_SAMPLE_RATE then
		return string.format("XAudio2 cannot play %d channel(s) at %d Hz", channels, rate)
	end
	return nil
end

-- Copies `parameters` into the effect at `index` in the effects voice's chain, as the C structure `type_name`, and turns it on.
-- Nil `parameters` turn the effect off instead, which XAudio2 then skips.
-- `what` names the effect in the failure. Returns false when XAudio2 refuses the change.
local function apply_effect(index, type_name, parameters, what)
	if effects_voice == nil then
		return true
	end

	local hresult
	if parameters then
		local native = ffi.new(type_name)
		for field, value in pairs(parameters) do
			native[field] = value
		end
		hresult = call(effects_voice, SET_EFFECT_PARAMETERS, index, native, ffi.sizeof(native), 0)
		if NativeFfi.succeeded(hresult) then
			hresult = call(effects_voice, ENABLE_EFFECT, index, 0)
		end
	else
		hresult = call(effects_voice, DISABLE_EFFECT, index, 0)
	end

	if NativeFfi.succeeded(hresult) then
		return true
	end
	if is_engine_error(hresult) then
		failure = failure or string.format("changing the %s failed with %s", what, NativeFfi.hex(hresult))
	end
	return false
end

local function apply_reverb()
	return apply_effect(REVERB_EFFECT, "MusicReplacer_XAUDIO2FX_REVERB_PARAMETERS", reverb_parameters, "reverb")
end

local function apply_eq()
	return apply_effect(EQ_EFFECT, "MusicReplacer_FXEQ_PARAMETERS", eq_parameters, "EQ")
end

-- Makes the effects voice the first time a song asks for effects. Returns false, with XAudio.effects_error() saying why, when it cannot.
-- It sends to the output, so a song sent to it plays with its effects.
local function ensure_effects_voice()
	if effects_voice ~= nil then
		return true
	end
	if effects_error then
		return false
	end

	local effects_out = ffi.new("void *[?]", EFFECT_COUNT)
	local clsid = NativeFfi.guid(CLSID_FXEQ[1], CLSID_FXEQ[2], CLSID_FXEQ[3], CLSID_FXEQ[4])
	local hresult = library.MusicReplacer_CreateFX(clsid, effects_out + EQ_EFFECT, nil, 0)
	if not NativeFfi.succeeded(hresult) then
		effects_error = "creating the EQ failed with " .. NativeFfi.hex(hresult)
		return false
	end
	hresult = library.MusicReplacer_CreateAudioReverb(effects_out + REVERB_EFFECT)
	if not NativeFfi.succeeded(hresult) then
		NativeFfi.release(effects_out[EQ_EFFECT])
		effects_error = "creating the reverb failed with " .. NativeFfi.hex(hresult)
		return false
	end

	local descriptors = ffi.new("MusicReplacer_XAUDIO2_EFFECT_DESCRIPTOR[?]", EFFECT_COUNT)
	for index = 0, EFFECT_COUNT - 1 do
		descriptors[index].pEffect = effects_out[index]
		descriptors[index].InitialState = 1
		descriptors[index].OutputChannels = EFFECTS_CHANNELS
	end
	local chain = ffi.new("MusicReplacer_XAUDIO2_EFFECT_CHAIN")
	chain.EffectCount = EFFECT_COUNT
	chain.pEffectDescriptors = descriptors

	local out = ffi.new("void *[1]")
	hresult = call(engine, CREATE_SUBMIX_VOICE, out, EFFECTS_CHANNELS, EFFECTS_SAMPLE_RATE, 0, 0, nil, chain)
	-- The voice holds its own reference to each effect, so these are let go either way.
	for index = 0, EFFECT_COUNT - 1 do
		NativeFfi.release(effects_out[index])
	end
	if not NativeFfi.succeeded(hresult) then
		effects_error = "creating the effects voice failed with " .. NativeFfi.hex(hresult)
		if is_engine_error(hresult) then
			failure = failure or effects_error
		end
		return false
	end

	effects_voice = out[0]
	-- One send list serves every source voice that sends to it.
	local descriptor_out = ffi.new("MusicReplacer_XAUDIO2_SEND_DESCRIPTOR[1]")
	descriptor_out[0].Flags = 0
	descriptor_out[0].pOutputVoice = effects_voice
	local sends = ffi.new("MusicReplacer_XAUDIO2_VOICE_SENDS")
	sends.SendCount = 1
	sends.pSends = descriptor_out
	effects_route = { sends = sends, descriptor = descriptor_out }

	apply_eq()
	apply_reverb()
	return true
end

-- Why the effects could not be made, such as on a Windows whose XAudio2 has no reverb or EQ, or nil.
-- Songs still play then, only without effects.
function XAudio.effects_error()
	return effects_error
end

-- Sets the reverb to `parameters`, the fields of XAUDIO2FX_REVERB_PARAMETERS as Reverb.native() gives them, or turns it off with nil.
-- The effects voice gets them at once if it exists, and when it is made otherwise.
function XAudio.set_reverb(parameters)
	reverb_parameters = parameters
	return apply_reverb()
end

-- Sets the EQ to `parameters`, the fields of FXEQ_PARAMETERS as Equalizer.native() gives them, or turns it off with nil.
-- The effects voice gets them at once if it exists, and when it is made otherwise.
function XAudio.set_eq(parameters)
	eq_parameters = parameters
	return apply_eq()
end

local Voice = {}
Voice.__index = Voice

-- Creates a stopped voice for PCM in `format`, a MusicReplacer_WAVEFORMATEX.
-- With `opts.effects`, it plays through the effects voice, or straight to the output when the effects could not be made.
-- Returns the voice, or nil, why, and true when XAudio2 itself refused the voice, which a failed engine also does.
-- A refusal counts as an engine failure only for an error in XAudio2's own facility or the audio client's, which no file's format causes.
function XAudio.create_voice(format, opts)
	if not XAudio.available() then
		return nil, init_error, false
	end

	local sends = nil
	if opts and opts.effects and ensure_effects_voice() then
		sends = effects_route.sends
	end

	local out = ffi.new("void *[1]")
	local hresult = call(engine, CREATE_SOURCE_VOICE, out, format, 0, XAUDIO2_DEFAULT_FREQ_RATIO, nil, sends, nil)
	if not NativeFfi.succeeded(hresult) then
		local reason = "creating a voice failed with " .. NativeFfi.hex(hresult)
		if is_engine_error(hresult) then
			failure = failure or reason
		end
		return nil, reason, true
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
		-- Both are made once, so submitting and polling allocate nothing on the Lua heap.
		-- XAudio2 lets the buffer descriptor be reused as soon as SubmitSourceBuffer returns. Only the audio it points to must stay alive.
		buffer = ffi.new("MusicReplacer_XAUDIO2_BUFFER"),
		state = ffi.new("MusicReplacer_XAUDIO2_VOICE_STATE"),
	}, Voice)
end

-- `flags` is XAUDIO2_VOICE_NOSAMPLESPLAYED when only the queue is needed, which spares XAudio2 working out the samples played.
local function read_state(self, flags)
	self.methods.get_state(self.pointer, self.state, flags)
	return self.state
end

-- Calls one of the voice's methods. A destroyed voice has no native object left, so it is not called at all.
local function checked_voice(self, what, name, ...)
	if self.pointer == nil then
		return false
	end

	local hresult = self.methods[name](self.pointer, ...)
	if NativeFfi.succeeded(hresult) then
		return true
	end

	local reason = string.format("%s failed with %s", what, NativeFfi.hex(hresult))
	if is_engine_error(hresult) then
		failure = failure or reason
	else
		self.error = self.error or reason
	end
	return false
end

-- Why one of this voice's calls failed while the engine works, or nil.
function Voice:failure()
	return self.error
end

-- Buffers submitted and not yet played.
function Voice:queued()
	if self.pointer == nil then
		return 0
	end
	return read_state(self, XAUDIO2_VOICE_NOSAMPLESPLAYED).BuffersQueued
end

-- Samples played since the voice was created, across every buffer.
-- Read as two halves, since a 64-bit field would come back as a new object on every read.
function Voice:samples_played()
	if self.pointer == nil then
		return 0
	end
	local state = read_state(self, 0)
	return state.SamplesPlayedLow + state.SamplesPlayedHigh * 4294967296
end

-- Queues `bytes` at `data`. The caller keeps that memory alive until the queue has moved past it.
-- `last` marks the end of the stream. Returns false when XAudio2 refuses the buffer.
-- player.lua never queues more than its 16 slots, far below XAudio2's 64, so the queue cannot be full here.
function Voice:submit(data, bytes, last)
	local buffer = self.buffer
	buffer.Flags = last and XAUDIO2_END_OF_STREAM or 0
	buffer.AudioBytes = bytes
	buffer.pAudioData = data

	return checked_voice(self, "submitting audio", "submit_source_buffer", buffer, nil)
end

-- Volume as a linear amplitude scale. 1 plays the audio as decoded, 0 is silent. Returns false when XAudio2 refuses it.
function Voice:set_volume(volume)
	-- NaN fails every comparison, so it falls to 0 here instead of reaching XAudio2.
	local safe = volume > 0 and math.min(volume, MAX_VOLUME) or 0
	return checked_voice(self, "setting a volume", "set_volume", safe, 0)
end

-- Sends the voice through the effects voice, or straight to the output, from its next processing pass.
-- Effects that could not be made leave it playing straight to the output. Returns false when XAudio2 refuses the change.
function Voice:set_effects(on)
	local sends = nil
	if on and ensure_effects_voice() then
		sends = effects_route.sends
	end
	return checked_voice(self, "changing a voice's output", "set_output_voices", sends)
end

-- Returns false when XAudio2 refuses it.
function Voice:start()
	return checked_voice(self, "starting a voice", "start", 0, 0)
end

-- Returns false when XAudio2 refuses it.
function Voice:stop()
	return checked_voice(self, "stopping a voice", "stop", 0, 0)
end

-- Stops and frees the voice. DestroyVoice waits for XAudio2's thread to be idle.
-- So XAudio2 has finished with every buffer once this returns.
function Voice:destroy()
	if self.pointer ~= nil then
		self.methods.destroy_voice(self.pointer)
		self.pointer = nil
	end
end

-- Frees the output and the engine. Destroy every voice first, since XAudio2 cannot destroy the output while a voice exists.
-- The effects voice goes first, since every song that sent to it is gone by then.
-- Its failure to be made is forgotten too, so a rebuilt engine tries again.
-- The effects' parameters are kept for the next effects voice.
function XAudio.shutdown()
	if effects_voice ~= nil then
		call(effects_voice, DESTROY_VOICE)
		effects_voice = nil
		effects_route = nil
	end
	effects_error = nil

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
