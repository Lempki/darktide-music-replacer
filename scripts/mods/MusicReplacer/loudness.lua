-- Measures every song's loudness in the background, so each can play at the level that brings it to TARGET_LUFS.
-- Measuring decodes a whole file, so it runs a little at a time, for at most MEASURE_MS per update, and frames stay smooth.
-- The results are kept in loudness.txt beside diagnostic.log, so a song is measured once and the music files are never changed.
-- A song is measured again once its file changes, which its size and write time show.
-- A song keeps the level it started with, so one measured while it plays changes level only at its next start.

local Loudness = {}

-- The level most streaming services play music at. Most released music is mastered at or above it.
local TARGET_LUFS = -14

local MEASURE_MS = 1

-- Decoded per read. A short chunk keeps each update close to MEASURE_MS.
local CHUNK_SECONDS = 0.05

local CACHE_FILE_NAME = "loudness.txt"

local _io = Mods and Mods.lua and Mods.lua.io
local _os = Mods and Mods.lua and Mods.lua.os

local log_fn = function() end
local detail_fn = function() end
local MediaDecoder = nil
local NativeFfi = nil
local LoudnessMeter = nil
local disk_path = function(file_path) return file_path end
local cache_path = nil

local enabled = false
local results = {} -- file_path -> { stamp, loudness, peak }. loudness is false for a song with no measurable loudness.
local stamps = {} -- file_path -> its stamp at the last listing.
local pending = {} -- Files still to measure, in listing order.
local active = nil -- The song being measured: file_path, stamp, decoder, meter, buffer, samples, capacity, block_align.
local measured_count = 0 -- Songs measured since the last summary line.
local measured_ms = 0

-- Wall time in seconds, or nil where there is no clock, which measures one chunk per update.
local function clock()
	return _os and _os.clock and _os.clock() or nil
end

local function load_cache()
	if not (_io and cache_path) then
		return
	end

	local file = _io.open(cache_path, "r")
	if not file then
		return
	end

	local text = file:read("*a") or ""
	file:close()

	for line in text:gmatch("[^\r\n]+") do
		local stamp, loudness, peak, file_path = line:match("^([^\t]*)\t([^\t]+)\t([^\t]+)\t(.+)$")
		if file_path then
			results[file_path] = { stamp = stamp, loudness = tonumber(loudness) or false, peak = tonumber(peak) or 0 }
		end
	end
end

-- Writes the results of the files listed now, which also drops removed and changed files from the cache.
local function save_cache()
	if not (_io and cache_path) then
		return
	end

	local file = _io.open(cache_path, "w")
	if not file then
		return
	end

	local file_paths = {}
	for file_path, result in pairs(results) do
		if stamps[file_path] == result.stamp then
			file_paths[#file_paths + 1] = file_path
		end
	end
	table.sort(file_paths)

	file:write("# Music Replacer's loudness measurements: file size and write time, LUFS, peak, file. Deleting it measures every song again.\n")
	for _, file_path in ipairs(file_paths) do
		local result = results[file_path]
		local loudness = result.loudness and string.format("%.2f", result.loudness) or "silent"
		file:write(string.format("%s\t%s\t%.5f\t%s\n", result.stamp, loudness, result.peak, file_path))
	end
	file:close()
end

local function decibels(scale)
	return scale > 0 and 20 * math.log10(scale) or -math.huge
end

local function stop_active()
	if active then
		active.decoder:close()
		NativeFfi.free(active.buffer)
		active = nil
	end
end

local function finish_active()
	local meter = active.meter
	local loudness = meter:loudness()
	local peak = meter:peak()
	results[active.file_path] = { stamp = active.stamp, loudness = loudness or false, peak = peak }

	detail_fn(string.format("[loudness] %s: %s, peak %.1f dBFS, %.0f ms",
		active.file_path, loudness and string.format("%.1f LUFS", loudness) or "no measurable loudness", decibels(peak), active.ms))

	measured_count = measured_count + 1
	measured_ms = measured_ms + active.ms
	stop_active()
	save_cache()

	if #pending == 0 then
		log_fn(string.format("[loudness] measured %d song(s), %.1f s of measuring spread over the updates", measured_count, measured_ms / 1000))
		measured_count = 0
		measured_ms = 0
	end
end

-- Takes the next file to measure out of `pending`, preferring the folder of `preferred_context`.
local function take_next(preferred_context)
	local chosen = 1
	if preferred_context then
		local prefix = preferred_context .. "/"
		for index, file_path in ipairs(pending) do
			if file_path:sub(1, #prefix) == prefix then
				chosen = index
				break
			end
		end
	end
	return table.remove(pending, chosen)
end

local function start(file_path)
	local decoder, err = MediaDecoder.open(disk_path(file_path))
	if not decoder then
		detail_fn(string.format("[loudness] %s could not be measured: %s", file_path, tostring(err)))
		return
	end

	local format = decoder.format
	local capacity = math.floor(format.nSamplesPerSec * CHUNK_SECONDS) * format.nBlockAlign
	local buffer = NativeFfi.alloc(capacity)
	if not buffer then
		decoder:close()
		return
	end

	active = {
		file_path = file_path,
		stamp = stamps[file_path],
		decoder = decoder,
		meter = LoudnessMeter.new(format.nSamplesPerSec, format.nChannels),
		buffer = buffer,
		samples = NativeFfi.ffi.cast("int16_t *", buffer),
		capacity = capacity,
		block_align = format.nBlockAlign,
		ms = 0,
	}
end

-- options: log, detail, media_decoder, native_ffi, and loudness_meter, which are loaded and initialized modules.
-- options.disk_path(file_path) turns a library path into a path on disk, and options.folder is where loudness.txt goes.
function Loudness.init(options)
	log_fn = options.log or log_fn
	detail_fn = options.detail or detail_fn
	MediaDecoder = options.media_decoder
	NativeFfi = options.native_ffi
	LoudnessMeter = options.loudness_meter
	disk_path = options.disk_path or disk_path
	cache_path = options.folder and (options.folder .. "/" .. CACHE_FILE_NAME)
	load_cache()
end

-- Turns evening out on or off. Measuring only runs while it is on.
function Loudness.set_enabled(on)
	enabled = on == true
	if not enabled and active then
		table.insert(pending, 1, active.file_path)
		stop_active()
	end
end

-- Takes a listing from Library.on_listed: every file as { file_path, stamp }.
-- Files with no result for their current stamp are measured, and a file that changed while it was measured starts over.
function Loudness.set_files(entries)
	stamps = {}
	pending = {}

	for _, entry in ipairs(entries) do
		stamps[entry.file_path] = entry.stamp
		local result = results[entry.file_path]
		local measuring = active and active.file_path == entry.file_path and active.stamp == entry.stamp
		if not measuring and not (result and result.stamp == entry.stamp) then
			pending[#pending + 1] = entry.file_path
		end
	end

	if active and stamps[active.file_path] ~= active.stamp then
		stop_active()
	end
end

-- Call every update. Measures for at most MEASURE_MS, starting with the files of `preferred_context`, the context playing now.
-- Opening a file takes an update of its own, since opening alone can take a few milliseconds.
function Loudness.update(preferred_context)
	if not enabled or not (MediaDecoder and MediaDecoder.available()) then
		return
	end

	local started = clock()

	if not active then
		if #pending > 0 then
			start(take_next(preferred_context))
			if active and started then
				active.ms = (clock() - started) * 1000
			end
		end
		return
	end

	repeat
		local bytes = active.decoder:read_into(active.buffer, active.capacity)
		if bytes > 0 then
			active.meter:add(active.samples, math.floor(bytes / active.block_align))
		end

		-- The decoder writes less than asked only at the end of the file.
		if bytes < active.capacity then
			if started then
				active.ms = active.ms + (clock() - started) * 1000
			end
			finish_active()
			return
		end
	until not started or (clock() - started) * 1000 >= MEASURE_MS

	if started then
		active.ms = active.ms + (clock() - started) * 1000
	end
end

-- The volume scale `file_path` plays at: 1 while evening out is off or the song is not measured yet.
function Loudness.level(file_path)
	if not enabled then
		return 1
	end

	local result = results[file_path]
	if not result or result.stamp ~= stamps[file_path] then
		return 1
	end

	return LoudnessMeter.level(result.loudness or nil, result.peak, TARGET_LUFS)
end

-- How `file_path`'s level was set, for the log, or nil while evening out is off.
function Loudness.describe(file_path)
	if not enabled then
		return nil
	end

	local result = results[file_path]
	if not result or result.stamp ~= stamps[file_path] then
		return "loudness not measured yet"
	end
	if not result.loudness then
		return "no measurable loudness"
	end

	return string.format("%.1f LUFS, %+.1f dB", result.loudness, decibels(Loudness.level(file_path)))
end

-- Call from the main mod file's mod.on_unload.
function Loudness.shutdown()
	stop_active()
end

return Loudness
