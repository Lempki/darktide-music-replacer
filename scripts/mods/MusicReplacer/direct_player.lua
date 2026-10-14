-- Plays songs directly inside the game: each stream is a Media Foundation decoder feeding an XAudio2 voice.
-- A stream decodes into a fixed pool of buffers on the Windows heap, allocated once, so playing never grows the Lua heap.
-- The pool keeps several seconds queued, so the music plays on while the game's thread stalls, as it can during loading.
-- A stream's volume is its gain times its fade. The gain follows settings such as the sliders, and the fade shapes fades and crossfades.

local DirectPlayer = {}

local CHUNK_SECONDS = 0.25
local SLOT_COUNT = 16 -- 4 seconds queued.
local START_SLOTS = 2 -- Queued before a stream starts, so it never starts starved.
local FILLS_PER_UPDATE = 2 -- Spreads decoding over frames, so no single frame pays for a whole refill.

-- A stream whose voice has queued audio but plays nothing for this long has lost its audio device.
local STALL_SECONDS = 2

local _os = (Mods and Mods.lua and Mods.lua.os) or (not Mods and os) or nil

local NativeFfi = nil
local MediaDecoder = nil
local XAudio = nil
local pool_bytes = 0
local slowest_fill_ms = 0

local function clock()
	return _os and _os.clock and _os.clock() or 0
end

-- `native_ffi`, `media_decoder`, and `xaudio` are loaded and initialized modules.
function DirectPlayer.init(native_ffi, media_decoder, xaudio)
	NativeFfi = native_ffi
	MediaDecoder = media_decoder
	XAudio = xaudio
end

function DirectPlayer.available()
	return MediaDecoder ~= nil and MediaDecoder.available() and XAudio.available()
end

-- Why DirectPlayer.available() is false, or nil.
function DirectPlayer.error()
	if not MediaDecoder then
		return "direct_player.lua is not initialized"
	end
	return MediaDecoder.error() or XAudio.error()
end

-- Recreates the XAudio2 engine on next use, after a stream failed. Destroy every stream first.
function DirectPlayer.reset()
	XAudio.shutdown()
end

-- Bytes held by every open stream's pool, for logging.
function DirectPlayer.pool_bytes()
	return pool_bytes
end

-- The slowest refill so far in milliseconds, for logging.
function DirectPlayer.slowest_fill_ms()
	return slowest_fill_ms
end

local Stream = {}
Stream.__index = Stream

-- Equal power: a fade out and a fade in of the same length keep the combined loudness steady.
local function shaped(from, to, progress)
	if to > from then
		return from + (to - from) * math.sin(progress * math.pi / 2)
	end
	return from + (to - from) * (1 - math.cos(progress * math.pi / 2))
end

local function apply_volume(self)
	self.voice:set_volume(self.gain * self.fade)
end

-- Decodes up to `max_fills` buffers into free pool slots and queues them.
local function fill(self, max_fills)
	local started = clock()
	local fills = 0

	while fills < max_fills and not self.finishing and not self.failed do
		-- A slot is free once the buffer last written to it has played, which holds while the queue is not full.
		if self.voice:queued() >= SLOT_COUNT then
			break
		end

		local slot = self.pool + (self.submitted % SLOT_COUNT) * self.slot_bytes
		local bytes = self.decoder:read_into(slot, self.slot_bytes)

		if self.loop and self.decoder:at_end() then
			-- Gapless: the rest of this buffer continues from the file's start.
			self.decoder:seek(0)
			if bytes < self.slot_bytes then
				bytes = bytes + self.decoder:read_into(slot + bytes, self.slot_bytes - bytes)
			end
		end

		local last = not self.loop and self.decoder:at_end()

		if bytes > 0 then
			if not self.voice:submit(slot, bytes, last) then
				self.failed = XAudio.failure() or "XAudio2 refused a buffer"
				break
			end
			self.submitted = self.submitted + 1
		end

		if last then
			self.finishing = true
		elseif bytes == 0 then
			break
		end

		fills = fills + 1
	end

	slowest_fill_ms = math.max(slowest_fill_ms, (clock() - started) * 1000)
end

-- Opens `path` and starts it playing. Returns the stream, or nil and why.
-- opts.start_position starts partway in, in seconds. opts.loop repeats the file without a gap.
-- opts.gain and opts.fade set the starting levels, 1 by default.
function DirectPlayer.open(path, opts)
	opts = opts or {}

	local decoder, err = MediaDecoder.open(path)
	if not decoder then
		return nil, err
	end

	local start_position = opts.start_position or 0
	if start_position > 0 and not decoder:seek(start_position) then
		decoder:close()
		return nil, "seeking to " .. start_position .. "s failed"
	end

	local format = decoder.format
	local slot_bytes = math.floor(CHUNK_SECONDS * format.nAvgBytesPerSec / format.nBlockAlign) * format.nBlockAlign
	local pool = NativeFfi.alloc(slot_bytes * SLOT_COUNT)
	if not pool then
		decoder:close()
		return nil, "allocating the buffer pool failed"
	end

	local voice
	voice, err = XAudio.create_voice(format)
	if not voice then
		NativeFfi.free(pool)
		decoder:close()
		return nil, err
	end

	pool_bytes = pool_bytes + slot_bytes * SLOT_COUNT

	local self = setmetatable({
		decoder = decoder,
		voice = voice,
		pool = pool,
		slot_bytes = slot_bytes,
		sample_rate = format.nSamplesPerSec,
		duration = decoder.duration,
		start_position = start_position,
		loop = opts.loop == true,
		submitted = 0,
		finishing = false,
		failed = nil,
		gain = opts.gain or 1,
		fade = opts.fade or 1,
		ramp = nil,
		underruns = 0,
		last_samples_played = 0,
		stalled_seconds = 0,
	}, Stream)

	apply_volume(self)
	fill(self, START_SLOTS)
	voice:start()

	return self
end

-- Sets the gain at once, for slider changes and ducking.
function Stream:set_gain(gain)
	self.gain = gain
	apply_volume(self)
end

-- Fades to `target` over `seconds` on an equal-power curve. Zero seconds sets it at once.
function Stream:fade_to(target, seconds)
	if not seconds or seconds <= 0 then
		self.ramp = nil
		self.fade = target
		apply_volume(self)
		return
	end

	self.ramp = { from = self.fade, to = target, seconds = seconds, elapsed = 0 }
end

-- True while a fade is still moving.
function Stream:fading()
	return self.ramp ~= nil
end

-- Seconds into the file. A looping stream wraps back at the file's end.
function Stream:position()
	local position = self.start_position + self.voice:samples_played() / self.sample_rate
	if self.loop and self.duration and self.duration > 0 then
		position = position % self.duration
	end
	return position
end

-- True once a stream that does not loop has played its last sample.
function Stream:ended()
	return self.finishing and self.voice:queued() == 0
end

-- Why the stream stopped working, or nil.
function Stream:failure()
	return self.failed
end

-- Call every tick: moves the fade, refills the queue, and watches for a lost device.
function Stream:update(dt)
	if self.failed then
		return
	end

	local ramp = self.ramp
	if ramp then
		ramp.elapsed = ramp.elapsed + dt
		local progress = math.min(1, ramp.elapsed / ramp.seconds)
		self.fade = shaped(ramp.from, ramp.to, progress)
		apply_volume(self)
		if progress >= 1 then
			self.ramp = nil
		end
	end

	local queued = self.voice:queued()
	if queued == 0 and not self.finishing then
		self.underruns = self.underruns + 1
	end

	fill(self, FILLS_PER_UPDATE)

	local played = self.voice:samples_played()
	if queued > 0 and played == self.last_samples_played then
		self.stalled_seconds = self.stalled_seconds + dt
		if self.stalled_seconds >= STALL_SECONDS then
			self.failed = XAudio.failure() or "the voice stopped playing with audio queued"
		end
	else
		self.stalled_seconds = 0
	end
	self.last_samples_played = played

	if not self.failed and XAudio.failure() then
		self.failed = XAudio.failure()
	end
end

-- Stops the stream at once and frees everything it holds.
function Stream:destroy()
	if not self.voice then
		return
	end

	self.voice:destroy()
	self.voice = nil
	self.decoder:close()
	NativeFfi.free(self.pool)
	self.pool = nil
	pool_bytes = pool_bytes - self.slot_bytes * SLOT_COUNT
end

return DirectPlayer
