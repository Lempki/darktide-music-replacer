-- Pins loudness.lua: measuring in the background within its time limit, the order, the cache file, and changed files.
-- The decoder, the clock, and the file system are stand-ins.
-- The meter is too, and it reports a file's frame count as its loudness, so a result shows that the whole file was read.

local FakeEngine = require("tests.helpers.fake_engine")

local FOLDER = "C:/AppData/Fatshark/Darktide/MusicReplacer"
local CACHE = FOLDER .. "/loudness.txt"

-- 100 frames per second, so a read of 0.05 seconds is 5 frames of 4 bytes.
local FORMAT = { nSamplesPerSec = 100, nChannels = 2, nBlockAlign = 4 }

-- Each read costs this much time, and opening a file costs OPEN_SECONDS.
local READ_SECONDS = 0.0004
local OPEN_SECONDS = 0.002

local function new_file_system(files)
	local fs = { files = files or {}, now = 0 }

	fs.io = {
		open = function(path, mode)
			if mode == "r" then
				if fs.files[path] == nil then
					return nil, "no such file"
				end
				return {
					read = function() return fs.files[path] end,
					close = function() end,
				}
			end

			fs.files[path] = ""
			return {
				write = function(_, ...) fs.files[path] = fs.files[path] .. table.concat({ ... }) end,
				close = function() end,
			}
		end,
	}

	fs.os = { clock = function() return fs.now end }

	return fs
end

-- Returns a loaded loudness.lua and a test context: `songs` maps a disk path to its length in frames, or to false when it cannot open.
-- loudness.txt's current first line, which every cache below gets unless it brings a first line of its own.
local CACHE_HEADER = "# Music Replacer's loudness measurements, format 2: file size and write time, LUFS, peak, file. "
	.. "Deleting it measures every song again.\n"

local function load_loudness(songs, cache_text)
	if cache_text and cache_text:sub(1, 1) ~= "#" then
		cache_text = CACHE_HEADER .. cache_text
	end
	local fs = new_file_system({ [CACHE] = cache_text })
	local engine = FakeEngine.new({ lua = { io = fs.io, os = fs.os } })
	local Loudness = engine:load("loudness")
	local RealMeter = engine:load("loudness_meter")
	local test = { fs = fs, lines = {}, details = {}, opened = {}, reads = 0 }

	local media_decoder = { available = function() return not test.decoder_unavailable end }
	function media_decoder.open(path)
		fs.now = fs.now + OPEN_SECONDS
		test.opened[#test.opened + 1] = path
		if not songs[path] then
			return nil, "opening the file failed"
		end

		local left = songs[path] * FORMAT.nBlockAlign
		return {
			format = FORMAT,
			read_into = function(_, _, capacity)
				fs.now = fs.now + READ_SECONDS
				test.reads = test.reads + 1
				local bytes = math.min(left, capacity)
				left = left - bytes
				return bytes
			end,
			close = function() test.closed = (test.closed or 0) + 1 end,
		}
	end

	local meter = { level = RealMeter.level }
	function meter.new()
		local frames = 0
		return {
			add = function(_, _, count) frames = frames + count end,
			loudness = function() return frames > 0 and -frames or nil end,
			peak = function() return 0.5 end,
		}
	end

	Loudness.init({
		log = function(line) test.lines[#test.lines + 1] = line end,
		detail = function(line) test.details[#test.details + 1] = line end,
		media_decoder = media_decoder,
		native_ffi = { alloc = function() return {} end, free = function() end, ffi = { cast = function(_, buffer) return buffer end } },
		loudness_meter = meter,
		disk_path = function(file_path) return "audio/" .. file_path end,
		folder = FOLDER,
	})

	return Loudness, test
end

local function entries(list)
	local result = {}
	for _, item in ipairs(list) do
		result[#result + 1] = { file_path = item[1], stamp = item[2] or "1" }
	end
	return result
end

-- Runs updates until nothing is left to measure, or `max` updates.
local function measure_all(Loudness, preferred_context, max)
	for _ = 1, max or 100 do
		Loudness.update(preferred_context)
	end
end

describe("loudness.lua measuring", function()
	it("measures every listed song, the playing context's first, and logs each and a summary", function()
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = 12, ["audio/combat/b.mp3"] = 30 })
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "combat/b.mp3" } }))

		measure_all(Loudness, "combat")

		assert_deep_equal(test.opened, { "audio/combat/b.mp3", "audio/hub/a.mp3" })
		assert_equal(test.details[1]:match("^%[loudness%] combat/b.mp3: %-30.0 LUFS, peak %-6.0 dBFS") ~= nil, true)
		assert_equal(test.details[2]:match("^%[loudness%] hub/a.mp3: %-12.0 LUFS") ~= nil, true)
		assert_equal(test.lines[1]:match("^%[loudness%] measured 2 song%(s%)") ~= nil, true)
		assert_equal(test.closed, 2)
	end)

	it("opens a song in an update of its own, then reads for about a millisecond per update", function()
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = 1000 })
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" } }))

		Loudness.update("hub")
		assert_equal(#test.opened, 1)
		assert_equal(test.reads, 0)

		Loudness.update("hub")
		assert_equal(test.reads, 3)
		Loudness.update("hub")
		assert_equal(test.reads, 6)
	end)

	it("measures nothing while evening out is off, and starts the interrupted song over once it is back on", function()
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = 100, ["audio/hub/b.mp3"] = 10 })
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" } }))

		measure_all(Loudness, "hub", 5)
		assert_equal(#test.opened, 0)

		Loudness.set_enabled(true)
		Loudness.update("hub")
		Loudness.update("hub")
		Loudness.set_enabled(false)
		assert_equal(test.closed, 1)

		Loudness.set_enabled(true)
		measure_all(Loudness, "hub")
		assert_deep_equal(test.opened, { "audio/hub/a.mp3", "audio/hub/a.mp3", "audio/hub/b.mp3" })
		assert_equal(Loudness.describe("hub/a.mp3"):match("^%-100.0 LUFS") ~= nil, true)
	end)

	it("logs a song it cannot open and moves on", function()
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = false, ["audio/hub/b.mp3"] = 10 })
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" } }))

		measure_all(Loudness, "hub")

		assert_equal(test.details[1], "[loudness] hub/a.mp3 could not be measured: opening the file failed")
		assert_equal(Loudness.describe("hub/a.mp3"), "loudness not measured yet")
		assert_equal(Loudness.describe("hub/b.mp3"):match("^%-10.0 LUFS") ~= nil, true)
	end)
end)

describe("loudness.lua cache", function()
	-- Counts how often loudness.txt is written, which rewrites the whole file each time.
	local function count_writes(test)
		local open = test.fs.io.open
		test.writes = 0
		test.fs.io.open = function(path, mode)
			if mode == "w" then
				test.writes = test.writes + 1
			end
			return open(path, mode)
		end
	end

	local function hub_songs(count)
		local songs, listed = {}, {}
		for index = 1, count do
			songs["audio/hub/" .. index .. ".mp3"] = 10
			listed[#listed + 1] = { "hub/" .. index .. ".mp3" }
		end
		return songs, listed
	end

	it("writes loudness.txt every 10 songs and once measuring is done, instead of after every song", function()
		local songs, listed = hub_songs(12)
		local Loudness, test = load_loudness(songs)
		count_writes(test)
		Loudness.set_enabled(true)
		Loudness.set_files(entries(listed))

		measure_all(Loudness, "hub", 200)

		assert_equal(#test.details, 12)
		assert_equal(test.writes, 2)
	end)

	it("writes the songs measured since the last write when it unloads", function()
		local songs, listed = hub_songs(3)
		local Loudness, test = load_loudness(songs)
		count_writes(test)
		Loudness.set_enabled(true)
		Loudness.set_files(entries(listed))
		while #test.details < 1 do
			Loudness.update("hub")
		end
		assert_equal(test.writes, 0)

		Loudness.shutdown()

		assert_equal(test.writes, 1)
		assert_equal(test.fs.files[CACHE]:find("hub/1.mp3", 1, true) ~= nil, true)
	end)

	it("keeps the results in loudness.txt, so the next launch measures nothing again", function()
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = 12, ["audio/hub/b.mp3"] = 0 })
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3", "10:1:2" }, { "hub/b.mp3", "20:1:2" } }))
		measure_all(Loudness, "hub")

		local cache = test.fs.files[CACHE]
		assert_equal(cache:find("10:1:2\t-12.00\t0.50000\thub/a.mp3\n", 1, true) ~= nil, true)
		assert_equal(cache:find("20:1:2\tsilent\t0.50000\thub/b.mp3\n", 1, true) ~= nil, true)

		local Reloaded, retest = load_loudness({ ["audio/hub/a.mp3"] = 12, ["audio/hub/b.mp3"] = 0 }, cache)
		Reloaded.set_enabled(true)
		Reloaded.set_files(entries({ { "hub/a.mp3", "10:1:2" }, { "hub/b.mp3", "20:1:2" } }))
		measure_all(Reloaded, "hub")

		assert_deep_equal(retest.opened, {})
		assert_equal(Reloaded.describe("hub/a.mp3"), "-12.0 LUFS, -2.0 dB")
		assert_equal(Reloaded.describe("hub/b.mp3"), "no measurable loudness")
	end)

	it("measures a song again once its file changes, and drops removed songs from loudness.txt", function()
		local cache = "10:1:2\t-12.00\t0.50000\thub/a.mp3\n20:1:2\t-20.00\t0.50000\thub/b.mp3\n"
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = 16 }, cache)
		Loudness.set_enabled(true)

		Loudness.set_files(entries({ { "hub/a.mp3", "11:1:3" } }))
		assert_equal(Loudness.describe("hub/a.mp3"), "loudness not measured yet")
		measure_all(Loudness, "hub")

		assert_deep_equal(test.opened, { "audio/hub/a.mp3" })
		assert_equal(test.fs.files[CACHE]:find("11:1:3\t-16.00\t0.50000\thub/a.mp3\n", 1, true) ~= nil, true)
		assert_equal(test.fs.files[CACHE]:find("hub/b.mp3", 1, true), nil)
	end)

	it("measures a song again when its line in loudness.txt is broken or out of range", function()
		local cache = table.concat({
			"1\t-12.00\t0.50000\thub/good.mp3",
			"1\tsilent\t0.00000\thub/silent.mp3",
			"1\tinf\t0.50000\thub/infinite.mp3",
			"1\t1e999\t0.50000\thub/huge.mp3",
			"1\tnan\t0.50000\thub/nan.mp3",
			"1\t-300.00\t0.50000\thub/quiet.mp3",
			"1\t-12.00\t0.00000\thub/no_peak.mp3",
			"1\t-12.00\t2.00000\thub/over_peak.mp3",
			"1\tloud\t0.50000\thub/garbage.mp3",
			"1\t-12.00",
		}, "\n")
		local songs = {}
		local listed = {}
		for _, name in ipairs({ "good", "silent", "infinite", "huge", "nan", "quiet", "no_peak", "over_peak", "garbage" }) do
			songs["audio/hub/" .. name .. ".mp3"] = 10
			listed[#listed + 1] = { "hub/" .. name .. ".mp3" }
		end
		local Loudness, test = load_loudness(songs, cache)
		Loudness.set_enabled(true)
		Loudness.set_files(entries(listed))

		measure_all(Loudness, "hub")

		table.sort(test.opened)
		assert_deep_equal(test.opened, {
			"audio/hub/garbage.mp3", "audio/hub/huge.mp3", "audio/hub/infinite.mp3", "audio/hub/nan.mp3",
			"audio/hub/no_peak.mp3", "audio/hub/over_peak.mp3", "audio/hub/quiet.mp3",
		})
		assert_equal(Loudness.describe("hub/good.mp3"), "-12.0 LUFS, -2.0 dB")
		assert_equal(Loudness.describe("hub/silent.mp3"), "no measurable loudness")
	end)

	it("measures every song again when loudness.txt comes from an older way of measuring", function()
		local cache = "# Music Replacer's loudness measurements: file size and write time, LUFS, peak, file.\n"
			.. "1\t-12.00\t0.50000\thub/a.mp3\n"
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = 10 }, cache)
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" } }))

		measure_all(Loudness, "hub")

		assert_deep_equal(test.opened, { "audio/hub/a.mp3" })
		assert_equal(test.fs.files[CACHE]:sub(1, #CACHE_HEADER), CACHE_HEADER)
	end)

	it("tries a song it could not open again only once its file changes", function()
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = false })
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3", "1" } }))
		measure_all(Loudness, "hub")

		Loudness.set_files(entries({ { "hub/a.mp3", "1" } }))
		measure_all(Loudness, "hub")
		assert_equal(#test.opened, 1)

		Loudness.set_files(entries({ { "hub/a.mp3", "2" } }))
		measure_all(Loudness, "hub")
		assert_equal(#test.opened, 2)
	end)

	it("starts a song over when its file changes while it is measured", function()
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = 100 })
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3", "1" } }))
		Loudness.update("hub")
		Loudness.update("hub")

		Loudness.set_files(entries({ { "hub/a.mp3", "2" } }))
		measure_all(Loudness, "hub")

		assert_deep_equal(test.opened, { "audio/hub/a.mp3", "audio/hub/a.mp3" })
		assert_equal(test.details[1]:match("^%[loudness%] hub/a.mp3: %-100.0 LUFS") ~= nil, true)
		assert_equal(#test.details, 1)
	end)
end)

describe("loudness.lua progress", function()
	-- Runs updates until `count` songs are measured or given up on, each of which logs a detail line.
	local function measure_songs(Loudness, test, count)
		for _ = 1, 100 do
			if #test.details >= count then
				return
			end
			Loudness.update("hub")
		end
	end

	local function progress(Loudness)
		return { Loudness.progress() }
	end

	local function ten_frames(names)
		local songs = {}
		for _, name in ipairs(names) do
			songs["audio/hub/" .. name .. ".mp3"] = 10
		end
		return songs
	end

	it("shows nothing while evening out is off", function()
		local Loudness = load_loudness(ten_frames({ "a", "b" }))
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" } }))

		assert_equal(Loudness.progress(), nil)
	end)

	it("shows nothing while the decoder is unavailable, since nothing is measured then", function()
		local Loudness, test = load_loudness(ten_frames({ "a" }))
		test.decoder_unavailable = true
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" } }))

		assert_equal(Loudness.progress(), nil)
	end)

	it("counts from 0 up to every listed song, and shows nothing once all are measured", function()
		local Loudness, test = load_loudness(ten_frames({ "a", "b", "c" }))
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" }, { "hub/c.mp3" } }))
		assert_deep_equal(progress(Loudness), { 0, 3 })

		Loudness.update("hub")
		assert_deep_equal(progress(Loudness), { 0, 3 })

		measure_songs(Loudness, test, 1)
		assert_deep_equal(progress(Loudness), { 1, 3 })
		measure_songs(Loudness, test, 2)
		assert_deep_equal(progress(Loudness), { 2, 3 })
		measure_songs(Loudness, test, 3)
		assert_equal(Loudness.progress(), nil)
	end)

	it("leaves out songs that loudness.txt already has", function()
		local Loudness = load_loudness(ten_frames({ "a", "b", "c" }), "1\t-12.00\t0.50000\thub/a.mp3\n")
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" }, { "hub/c.mp3" } }))

		assert_deep_equal(progress(Loudness), { 0, 2 })
	end)

	it("counts a song it cannot open as done", function()
		local Loudness = load_loudness({ ["audio/hub/a.mp3"] = false, ["audio/hub/b.mp3"] = 10 })
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" } }))

		Loudness.update("hub")

		assert_deep_equal(progress(Loudness), { 1, 2 })
	end)

	it("keeps the done count when a listing during measuring adds a song", function()
		local Loudness, test = load_loudness(ten_frames({ "a", "b", "c" }))
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" } }))
		measure_songs(Loudness, test, 1)
		Loudness.update("hub")

		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" }, { "hub/c.mp3" } }))

		assert_deep_equal(progress(Loudness), { 1, 3 })
	end)

	it("keeps the count when evening out is turned off and on during measuring", function()
		local Loudness, test = load_loudness({ ["audio/hub/a.mp3"] = 10, ["audio/hub/b.mp3"] = 100 })
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" } }))
		measure_songs(Loudness, test, 1)
		Loudness.update("hub")
		Loudness.update("hub")

		Loudness.set_enabled(false)
		Loudness.set_enabled(true)

		assert_deep_equal(progress(Loudness), { 1, 2 })
	end)

	it("starts again from 0 when a later listing brings new songs", function()
		local Loudness = load_loudness(ten_frames({ "a", "b", "c" }))
		Loudness.set_enabled(true)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" } }))
		measure_all(Loudness, "hub")
		assert_equal(Loudness.progress(), nil)

		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" }, { "hub/c.mp3" } }))

		assert_deep_equal(progress(Loudness), { 0, 1 })
	end)

	it("tells a measured song, one with no measurable loudness among them, from one not measured yet or changed since", function()
		local cache = "1\t-12.00\t0.50000\thub/a.mp3\n1\tsilent\t0.00000\thub/silent.mp3\n"
		local Loudness = load_loudness({}, cache)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/silent.mp3" }, { "hub/b.mp3" } }))

		assert_equal(Loudness.is_measured("hub/a.mp3"), true)
		assert_equal(Loudness.is_measured("hub/silent.mp3"), true)
		assert_equal(Loudness.is_measured("hub/b.mp3"), false)

		Loudness.set_files(entries({ { "hub/a.mp3", "2" } }))
		assert_equal(Loudness.is_measured("hub/a.mp3"), false)
	end)
end)

describe("loudness.lua levels", function()
	it("plays a song at its own level while evening out is off or it is not measured yet", function()
		local cache = "1\t-20.00\t0.10000\thub/a.mp3\n"
		local Loudness = load_loudness({}, cache)
		Loudness.set_files(entries({ { "hub/a.mp3" }, { "hub/b.mp3" } }))

		assert_equal(Loudness.level("hub/a.mp3"), 1)
		assert_equal(Loudness.describe("hub/a.mp3"), nil)

		Loudness.set_enabled(true)
		assert_equal(Loudness.level("hub/b.mp3"), 1)
		assert_equal(math.abs(Loudness.level("hub/a.mp3") - 10 ^ (6 / 20)) < 1e-9, true)
		assert_equal(Loudness.describe("hub/a.mp3"), "-20.0 LUFS, +6.0 dB")
	end)

	it("raises a very quiet song by at most 12 dB", function()
		local Loudness = load_loudness({}, "1\t-40.00\t0.01000\thub/a.mp3\n")
		Loudness.set_files(entries({ { "hub/a.mp3" } }))
		Loudness.set_enabled(true)

		assert_equal(Loudness.describe("hub/a.mp3"), "-40.0 LUFS, +12.0 dB")
	end)
end)
