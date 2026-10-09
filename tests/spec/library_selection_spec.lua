-- Pins how library.lua picks a file for a context from its scanned folder.

local FakeEngine = require("tests.helpers.fake_engine")

local AUDIO_ROOT = "./../mods/MusicReplacer/audio/"

-- A fake Audio Plugin whose handlers list `files_by_context`, each entry a path relative to the audio folder.
-- A context listed as "pending" behaves like the plugin's handler before its listing resolves: count() returns nil.
local function new_audio_mod(files_by_context)
	local audio = {}

	function audio.new_files_handler(_, context_name)
		local files = files_by_context[context_name] or {}

		if files == "pending" then
			return {
				count = function() return nil end,
				lookup = function() error("the listing has not resolved yet") end,
			}
		end

		return {
			count = function() return #files end,
			lookup = function(_, index) return { file_path = files[index], duration = 100 + index } end,
		}
	end

	return audio
end

-- A fake io whose open() succeeds only for the paths in `existing`, relative to the audio folder.
local function new_fake_io(existing)
	local present = {}
	for _, file_path in ipairs(existing) do
		present[AUDIO_ROOT .. file_path] = true
	end

	return {
		open = function(path)
			if present[path] then
				return { close = function() end }
			end

			return nil, "No such file or directory"
		end,
	}
end

-- Returns a scanned library.lua, the lines it logged, and the fake engine.
-- `existing` lists the files on disk, and defaults to every listed file.
local function scanned_library(files_by_context, existing)
	if not existing then
		existing = {}
		for _, files in pairs(files_by_context) do
			if type(files) == "table" then
				for _, file_path in ipairs(files) do
					existing[#existing + 1] = file_path
				end
			end
		end
	end

	local engine = FakeEngine.new({
		mods = { Audio = new_audio_mod(files_by_context) },
		lua = { io = new_fake_io(existing) },
	})
	local Library = engine:load("library")
	local lines = {}
	Library.init(function(line) lines[#lines + 1] = line end)
	engine:initialize_backend()
	Library.update(0.1)

	return Library, lines, engine
end

describe("library.lua file selection", function()
	it("returns the file, its duration, and that it is the only one for a folder with one file", function()
		local Library = scanned_library({ hub = { "hub/a.ogg" } })

		assert_deep_equal({ Library.pick_file("hub") }, { "hub/a.ogg", 101, true })
	end)

	it("returns nil for an empty folder", function()
		local Library = scanned_library({ hub = {} })

		assert_equal(Library.pick_file("hub"), nil)
	end)

	it("returns nil while the folder's listing has not resolved", function()
		local Library = scanned_library({ hub = "pending" })

		assert_equal(Library.pick_file("hub"), nil)
	end)

	it("never picks the same file twice in a row when there is a choice", function()
		math.randomseed(1)
		local Library = scanned_library({ mission_combat = { "mission_combat/a.ogg", "mission_combat/b.ogg", "mission_combat/c.ogg" } })
		local previous = Library.pick_file("mission_combat")

		for _ = 1, 50 do
			local file_path, _, is_only_file = Library.pick_file("mission_combat")

			assert_equal(file_path ~= previous, true, "picked " .. file_path .. " twice in a row")
			assert_equal(is_only_file, false)
			previous = file_path
		end
	end)

	it("alternates between two files", function()
		local Library = scanned_library({ hub = { "hub/a.ogg", "hub/b.ogg" } })
		local picks = {}

		for index = 1, 4 do
			picks[index] = Library.pick_file("hub")
		end

		assert_equal(picks[1] ~= picks[2] and picks[1] == picks[3] and picks[2] == picks[4], true, table.concat(picks, ", "))
	end)

	-- The listing is a snapshot from the scan, so a file deleted afterward is still listed.
	it("skips a listed file that is missing on disk", function()
		local Library = scanned_library({ hub = { "hub/gone.ogg", "hub/kept.ogg" } }, { "hub/kept.ogg" })

		for _ = 1, 10 do
			assert_deep_equal({ Library.pick_file("hub") }, { "hub/kept.ogg", 102, true })
		end
	end)

	it("returns nil when every listed file is missing on disk", function()
		local Library = scanned_library({ hub = { "hub/gone.ogg" } }, {})

		assert_equal(Library.pick_file("hub"), nil)
	end)

	it("logs a missing file only once", function()
		local Library, lines = scanned_library({ hub = { "hub/gone.ogg", "hub/kept.ogg" } }, { "hub/kept.ogg" })

		Library.pick_file("hub")
		Library.pick_file("hub")

		local missing_lines = 0
		for _, line in ipairs(lines) do
			if line:find("hub/gone.ogg", 1, true) then
				missing_lines = missing_lines + 1
			end
		end

		assert_equal(missing_lines, 1)
	end)

	-- io.open reads a path in the system code page, so a UTF-8 name could look missing although it exists.
	it("skips the existence check for a name with non-ASCII characters", function()
		local Library = scanned_library({ hub = { "hub/Mötley.ogg" } }, {})

		assert_equal(Library.pick_file("hub"), "hub/Mötley.ogg")
	end)

	it("assumes every listed file exists when io is unavailable", function()
		local engine = FakeEngine.new({ mods = { Audio = new_audio_mod({ hub = { "hub/a.ogg" } }) } })
		local Library = engine:load("library")
		Library.init()
		engine:initialize_backend()
		Library.update(0.1)

		assert_equal(Library.pick_file("hub"), "hub/a.ogg")
	end)

	it("returns nil for a context it does not know", function()
		local Library = scanned_library({ hub = { "hub/a.ogg" } })

		assert_equal(Library.pick_file("mission_horde"), nil)
	end)
end)
