-- Standalone check of native playback outside the game: decodes two files with media_decoder.lua and plays them with xaudio.lua.
-- Timeline: A fades in, dips and comes back, crossfades into B started 30 seconds in, and B fades out.
-- Usage: luajit tools/native_audio_demo.lua <file A> <file B> [--silent]
-- --silent runs the same timeline at volume 0, to check decoding and feeding without making a sound.

local ffi = require("ffi")

local here = arg[0]:gsub("[^/\\]+$", "")
local modules = here .. "../scripts/mods/MusicReplacer/"
local NativeFfi = dofile(modules .. "native_ffi.lua")
local MediaDecoder = dofile(modules .. "media_decoder.lua")
local XAudio = dofile(modules .. "xaudio.lua")

local file_a, file_b = arg[1], arg[2]
local silent = arg[3] == "--silent"
assert(file_a and file_b, "usage: luajit tools/native_audio_demo.lua <file A> <file B> [--silent]")

local BASE_VOLUME = silent and 0 or 0.25
local CHUNK_SECONDS = 0.5
local QUEUED_SECONDS = 4
local FRAME_MS = 16

assert(NativeFfi.load(), NativeFfi.error())
MediaDecoder.init(NativeFfi)
XAudio.init(NativeFfi)
assert(MediaDecoder.available(), MediaDecoder.error())
assert(XAudio.available(), XAudio.error())

if not pcall(ffi.typeof, "MusicReplacer_DemoSleep") then
	ffi.cdef([[void MusicReplacer_DemoSleep(uint32_t milliseconds) __asm__("Sleep");]])
end
local kernel32 = ffi.load("kernel32")

local slowest_pump_ms = 0

-- A decoder feeding a voice, kept QUEUED_SECONDS ahead.
local function new_stream(path, start_seconds)
	local decoder = assert(MediaDecoder.open(path))
	if start_seconds then
		assert(decoder:seek(start_seconds), "seek failed")
	end

	local voice = assert(XAudio.create_voice(decoder.format))
	voice:set_volume(0)

	local stream = { decoder = decoder, voice = voice, name = path:match("[^/\\]+$"), start_seconds = start_seconds or 0 }

	function stream.pump()
		local started = os.clock()
		while not decoder.ended and voice:queued() < QUEUED_SECONDS / CHUNK_SECONDS do
			local data, bytes = decoder:read(CHUNK_SECONDS)
			if not data then
				break
			end
			voice:submit(data, bytes, decoder.ended)
		end
		slowest_pump_ms = math.max(slowest_pump_ms, (os.clock() - started) * 1000)
	end

	function stream.position()
		return stream.start_seconds + voice:samples_played() / decoder.format.nSamplesPerSec
	end

	stream.pump()
	voice:start()
	return stream
end

local function ramp(from, to, progress)
	return from + (to - from) * math.max(0, math.min(1, progress))
end

print(string.format("A: %s", file_a))
print(string.format("B: %s, from 30 s", file_b))

local a = new_stream(file_a)
print(string.format("A format: %d Hz, %d channels, duration %.1f s", a.decoder.format.nSamplesPerSec, a.decoder.format.nChannels,
	a.decoder.duration or -1))

local b = nil
local started = os.clock()
local next_report = 0

while true do
	local t = os.clock() - started

	if t < 2 then
		a.voice:set_volume(BASE_VOLUME * ramp(0, 1, t / 2))
	elseif t < 6 then
		a.voice:set_volume(BASE_VOLUME)
	elseif t < 8 then
		a.voice:set_volume(BASE_VOLUME * ramp(1, 0.25, (t - 6) / 2))
	elseif t < 10 then
		a.voice:set_volume(BASE_VOLUME * ramp(0.25, 1, (t - 8) / 2))
	elseif t < 14 then
		b = b or new_stream(file_b, 30)
		-- Equal power: the two levels' squares always add up to 1, so the overall loudness holds steady.
		local progress = (t - 10) / 4
		a.voice:set_volume(BASE_VOLUME * math.cos(progress * math.pi / 2))
		b.voice:set_volume(BASE_VOLUME * math.sin(progress * math.pi / 2))
	elseif t < 20 then
		if a then
			a.voice:destroy()
			a.decoder:close()
			a = nil
		end
		b.voice:set_volume(BASE_VOLUME)
	elseif t < 22 then
		b.voice:set_volume(BASE_VOLUME * ramp(1, 0, (t - 20) / 2))
	else
		break
	end

	if a then a.pump() end
	if b then b.pump() end

	if t >= next_report then
		next_report = next_report + 1
		print(string.format("%5.1f s | A %s | B %s | slowest pump %.1f ms",
			t,
			a and string.format("at %6.2f s, vol %.3f, queued %d", a.position(), a.voice:volume(), a.voice:queued()) or "done",
			b and string.format("at %6.2f s, vol %.3f, queued %d", b.position(), b.voice:volume(), b.voice:queued()) or "-",
			slowest_pump_ms))
	end

	kernel32.MusicReplacer_DemoSleep(FRAME_MS)
end

b.voice:destroy()
b.decoder:close()
XAudio.shutdown()
print("done")
