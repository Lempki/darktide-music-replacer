-- Pins diagnostic_log.lua: which lines reach the file, the previous session's file, mod reloads, and the size cap.
-- The file system is an in-memory stand-in for Mods.lua.io and Mods.lua.os.

local FakeEngine = require("tests.helpers.fake_engine")

local LOG = "C:/AppData/Fatshark/Darktide/MusicReplacer/diagnostic.log"
local PREVIOUS = "C:/AppData/Fatshark/Darktide/MusicReplacer/diagnostic-prev.log"

-- An in-memory file system. `files` maps a path to its whole text.
local function new_file_system(files)
	local fs = { files = files or {} }

	fs.io = {
		open = function(path, mode)
			if mode == "w" or fs.files[path] == nil then
				fs.files[path] = ""
			end
			return {
				write = function(_, ...)
					fs.files[path] = fs.files[path] .. table.concat({ ... })
				end,
				flush = function() end,
				close = function() end,
			}
		end,
	}

	fs.os = {
		getenv = function(name) return name == "APPDATA" and "C:/AppData" or nil end,
		date = function() return "2000-01-01 00:00:00" end,
		execute = function() end,
		remove = function(path) fs.files[path] = nil end,
		rename = function(from, to)
			if fs.files[from] == nil then
				return nil, "no such file"
			end
			fs.files[to] = fs.files[from]
			fs.files[from] = nil
			return true
		end,
	}

	return fs
end

-- Returns a loaded diagnostic_log.lua over `fs`, with the detailed lines on or off, and its engine.
-- Passing the engine of an earlier load keeps its persistent tables, as a mod reload does.
local function load_log(fs, detailed, engine)
	engine = engine or FakeEngine.new({ lua = { io = fs.io, os = fs.os } })
	engine.settings.diagnostic_mode = detailed
	local DiagnosticLog = engine:load("diagnostic_log")
	DiagnosticLog.init(engine.mod)
	return DiagnosticLog, engine
end

describe("diagnostic_log.lua", function()
	it("always writes the important events, and the detailed lines only while Detailed Logging is on", function()
		local fs = new_file_system()
		local DiagnosticLog, engine = load_log(fs, false)

		DiagnosticLog.write("[context] nil -> hub")
		DiagnosticLog.detail("[raw] music_zone: None -> hub")
		engine.settings.diagnostic_mode = true
		DiagnosticLog.detail("[raw] music_game_state: loading -> mission")

		assert_equal(fs.files[LOG],
			"[2000-01-01 00:00:00] [context] nil -> hub\n" ..
			"[2000-01-01 00:00:00] [raw] music_game_state: loading -> mission\n")
	end)

	it("keeps the previous session's log beside a fresh one, replacing the one before", function()
		local fs = new_file_system({ [LOG] = "last session\n", [PREVIOUS] = "two sessions ago\n" })
		local DiagnosticLog = load_log(fs, false)

		DiagnosticLog.write("[startup] version 1")

		assert_equal(fs.files[PREVIOUS], "last session\n")
		assert_equal(fs.files[LOG], "[2000-01-01 00:00:00] [startup] version 1\n")
	end)

	it("starts a fresh log on the first launch, with no previous one to keep", function()
		local fs = new_file_system()
		local DiagnosticLog = load_log(fs, false)

		DiagnosticLog.write("[startup] version 1")

		assert_equal(fs.files[PREVIOUS], nil)
		assert_equal(fs.files[LOG], "[2000-01-01 00:00:00] [startup] version 1\n")
	end)

	it("continues the same file after a mod reload instead of starting a new session", function()
		local fs = new_file_system({ [LOG] = "last session\n" })
		local DiagnosticLog, engine = load_log(fs, false)
		DiagnosticLog.write("before the reload")
		DiagnosticLog.close()

		local Reloaded = load_log(fs, false, engine)
		Reloaded.write("after the reload")

		assert_equal(fs.files[PREVIOUS], "last session\n")
		assert_equal(fs.files[LOG],
			"[2000-01-01 00:00:00] before the reload\n" ..
			"[2000-01-01 00:00:00] after the reload\n")
	end)

	it("stops writing at 10 MB, and says so once", function()
		local fs = new_file_system()
		local DiagnosticLog = load_log(fs, true)
		local line = string.rep("x", 100 * 1024)

		for _ = 1, 110 do
			DiagnosticLog.detail(line)
		end

		local size = #fs.files[LOG]
		local _, stops = fs.files[LOG]:gsub("stopped writing, the file reached 10 MB", "")
		assert_equal(size <= 10 * 1024 * 1024, true)
		assert_equal(stops, 1)
	end)

	it("writes nothing when it cannot find the user's folder", function()
		local fs = new_file_system()
		fs.os.getenv = function() return nil end
		local DiagnosticLog = load_log(fs, true)

		DiagnosticLog.write("[startup] version 1")

		assert_equal(next(fs.files), nil)
	end)
end)
