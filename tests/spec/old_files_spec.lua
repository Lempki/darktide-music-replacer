-- Checks that old_files.lua moves the mod's song files from %APPDATA% into the audio folder once, and never overwrites one.

local FakeEngine = require("tests.helpers.fake_engine")

local FROM = "C:/AppData/Fatshark/Darktide/MusicReplacer"
local TO = "./../mods/MusicReplacer/audio"

-- A file system in memory over `files`, which maps a path to its text. A path in `read_only` cannot be written.
local function new_file_system(files, read_only)
	local fs = { files = files, removed = {} }
	fs.io = {
		open = function(path, mode)
			if mode:find("w") then
				if read_only and read_only[path] then
					return nil
				end
				fs.files[path] = ""
				return {
					write = function(_, text)
						fs.files[path] = fs.files[path] .. text
						return true
					end,
					close = function() end,
				}
			end
			if fs.files[path] == nil then
				return nil
			end
			return { read = function() return fs.files[path] end, close = function() end }
		end,
	}
	fs.os = {
		remove = function(path)
			fs.removed[#fs.removed + 1] = path
			fs.files[path] = nil
		end,
	}
	return fs
end

local function load_old_files(fs)
	local engine = FakeEngine.new({ lua = { io = fs.io, os = fs.os } })
	local OldFiles = engine:load("old_files")
	local lines = {}
	return OldFiles, lines, function(line) lines[#lines + 1] = line end
end

describe("old_files.lua", function()
	it("moves each file into the audio folder and removes the old one", function()
		local fs = new_file_system({ [FROM .. "/loudness.txt"] = "measurements", [FROM .. "/removed.txt"] = "hub/a.mp3\n" })
		local OldFiles, lines, log = load_old_files(fs)

		OldFiles.move({ "loudness.txt", "removed.txt" }, FROM, TO, log)

		assert_deep_equal(fs.files, { [TO .. "/loudness.txt"] = "measurements", [TO .. "/removed.txt"] = "hub/a.mp3\n" })
		assert_deep_equal(lines, {
			"[files] moved loudness.txt from %APPDATA% into the audio folder",
			"[files] moved removed.txt from %APPDATA% into the audio folder",
		})
	end)

	it("leaves both files alone when the audio folder already has one, so nothing is overwritten", function()
		local fs = new_file_system({ [FROM .. "/loudness.txt"] = "old", [TO .. "/loudness.txt"] = "new" })
		local OldFiles, lines, log = load_old_files(fs)

		OldFiles.move({ "loudness.txt" }, FROM, TO, log)

		assert_deep_equal(fs.files, { [FROM .. "/loudness.txt"] = "old", [TO .. "/loudness.txt"] = "new" })
		assert_deep_equal(lines, {})
	end)

	it("does nothing for a file there is no old copy of", function()
		local fs = new_file_system({})
		local OldFiles, lines, log = load_old_files(fs)

		OldFiles.move({ "removed.txt" }, FROM, TO, log)

		assert_deep_equal(fs.files, {})
		assert_deep_equal(lines, {})
	end)

	it("keeps the old file when the new one cannot be written, and says so", function()
		local fs = new_file_system({ [FROM .. "/removed.txt"] = "hub/a.mp3\n" }, { [TO .. "/removed.txt"] = true })
		local OldFiles, lines, log = load_old_files(fs)

		OldFiles.move({ "removed.txt" }, FROM, TO, log)

		assert_deep_equal(fs.removed, {})
		assert_deep_equal(lines, { "[files] could not move removed.txt into the audio folder, so it stays in %APPDATA% and is not used" })
	end)
end)
