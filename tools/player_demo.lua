-- Standalone check of playback outside the game, through player.lua.
-- Timeline: A fades in, then the script freezes for 3 seconds like a stalled game thread, and A crossfades into B.
-- B starts 12 seconds before its end with looping on, so it wraps to its start with no gap added, and then B fades out.
-- Run it as `luajit tools/player_demo.lua <file A> <file B> [--silent]`.
-- --silent runs the same timeline at volume 0, to check decoding and feeding without making a sound.

local ffi = require("ffi")

local here = arg[0]:gsub("[^/\\]+$", "")
local modules = here .. "../scripts/mods/MusicReplacer/"
local NativeFfi = dofile(modules .. "native_ffi.lua")
local MediaDecoder = dofile(modules .. "media_decoder.lua")
local XAudio = dofile(modules .. "xaudio.lua")
local Player = dofile(modules .. "player.lua")

io.stdout:setvbuf("no")
assert(NativeFfi.load(), NativeFfi.error())

-- LuaJIT's arg holds the command line in the system code page, which garbles file names in other scripts.
-- The wide command line keeps every name intact. Its first two entries are luajit itself and this script.
NativeFfi.define([[
const uint16_t *MusicReplacer_DemoGetCommandLineW(void) __asm__("GetCommandLineW");
uint16_t **MusicReplacer_DemoCommandLineToArgvW(const uint16_t *line, int32_t *count) __asm__("CommandLineToArgvW");
void *MusicReplacer_DemoLocalFree(void *memory) __asm__("LocalFree");
]])
local shell32 = ffi.load("shell32")
local args = {}
do
	local count = ffi.new("int32_t[1]")
	local argv = shell32.MusicReplacer_DemoCommandLineToArgvW(NativeFfi.kernel32().MusicReplacer_DemoGetCommandLineW(), count)
	for index = 2, count[0] - 1 do
		args[#args + 1] = NativeFfi.utf8(argv[index])
	end
	NativeFfi.kernel32().MusicReplacer_DemoLocalFree(argv)
end

local file_a, file_b = args[1], args[2]
local silent = args[3] == "--silent"
assert(file_a and file_b, "usage: luajit tools/player_demo.lua <file A> <file B> [--silent]")

local GAIN = silent and 0 or 0.25
local FRAME_MS = 16
MediaDecoder.init(NativeFfi)
XAudio.init(NativeFfi)
Player.init(NativeFfi, MediaDecoder, XAudio)
assert(Player.available(), Player.error())

NativeFfi.define([[void MusicReplacer_DemoSleep(uint32_t milliseconds) __asm__("Sleep");]])
local kernel32 = NativeFfi.kernel32()

local function describe(name, stream)
	if not stream then
		return name .. " -"
	end
	return string.format("%s at %6.2f s, fade %.2f, underruns %d%s", name, stream:position(), stream.fade, stream.underruns,
		stream:failure() and (", FAILED: " .. stream:failure()) or "")
end

local a = assert(Player.open(file_a, { gain = GAIN, fade = 0 }))
a:fade_to(1, 2)
print(string.format("A: %s, %.1f s long", file_a:match("[^/\\]+$"), a.duration or -1))

local b = nil
local stalled = false
local started = os.clock()
local last = started
local next_report = 0

while true do
	local now = os.clock()
	local dt = now - last
	last = now
	local t = now - started

	if t >= 5 and not stalled then
		stalled = true
		print("  freezing the loop for 3 s, the music should carry on")
		kernel32.MusicReplacer_DemoSleep(3000)
	elseif t >= 10 and not b then
		local probe = assert(MediaDecoder.open(file_b))
		-- A file shorter than 12 seconds starts at its beginning instead.
		local start = math.max(0, (probe.duration or 60) - 12)
		probe:close()
		b = assert(Player.open(file_b, { gain = GAIN, fade = 0, start_position = start, loop = true }))
		print(string.format("B: %s from %.1f s, looping", file_b:match("[^/\\]+$"), start))
		a:fade_to(0, 4)
		b:fade_to(1, 4)
	elseif t >= 14 and a and not a:fading() then
		a:destroy()
		a = nil
	elseif t >= 26 and b and b.fade == 1 and not b:fading() then
		b:fade_to(0, 2)
	elseif t >= 28.5 then
		break
	end

	if a then a:update(dt) end
	if b then b:update(dt) end

	if t >= next_report then
		next_report = next_report + 1
		print(string.format("%5.1f s | %s | %s | slowest fill %.1f ms | pools %d KB | Lua heap %d KB",
			t, describe("A", a), describe("B", b), Player.slowest_fill_ms(), Player.pool_bytes() / 1024,
			collectgarbage("count")))
	end

	kernel32.MusicReplacer_DemoSleep(FRAME_MS)
end

b:destroy()
XAudio.shutdown()
MediaDecoder.shutdown()
print(string.format("done, pools %d KB", Player.pool_bytes() / 1024))
