-- Checks how library.lua rescans the audio folders on request.

local FakeEngine = require("tests.helpers.fake_engine")

-- A fake Audio Plugin whose listings answer only when the spec calls audio.resolve().
-- `disk` maps a context to the files currently on disk, and a listing captures it when it resolves.
local function new_audio_mod(disk)
	local audio = { listings = {}, created = 0 }

	function audio.new_files_handler(_, context_name)
		audio.created = audio.created + 1
		local listing = { context_name = context_name, files = nil }
		audio.listings[#audio.listings + 1] = listing

		return {
			count = function() return listing.files and #listing.files or nil end,
			lookup = function(_, index) return { file_path = listing.files[index], duration = 60 } end,
		}
	end

	-- Resolves every listing still waiting, except for the contexts in `skip`.
	function audio.resolve(skip)
		for _, listing in ipairs(audio.listings) do
			if not listing.files and not (skip and skip[listing.context_name]) then
				listing.files = disk[listing.context_name] or {}
			end
		end
	end

	return audio
end

-- Returns a fake engine, the fake Audio Plugin, the logged lines, and a library.lua whose first scan has resolved.
local function scanned_library(disk)
	local audio = new_audio_mod(disk)
	local engine = FakeEngine.new({ mods = { Audio = audio } })
	local Library = engine:load("library")
	local lines = {}
	Library.init(function(line) lines[#lines + 1] = line end)
	engine:initialize_backend()
	Library.update(0.1)
	audio.resolve()

	return engine, audio, lines, Library
end

describe("library.lua rescan", function()
	it("does nothing until a rescan is requested", function()
		local _, audio, _, Library = scanned_library({ hub = { "hub/a.ogg" } })
		local created = audio.created

		for _ = 1, 10 do
			assert_equal(Library.update(0.1), false)
		end

		assert_equal(audio.created, created)
	end)

	it("picks up a file added after the first scan", function()
		local disk = { hub = {} }
		local _, audio, _, Library = scanned_library(disk)
		assert_equal(Library.pick_file("hub"), nil)

		disk.hub = { "hub/new.ogg" }
		Library.request_rescan()
		Library.update(0.1)
		audio.resolve()

		assert_equal(Library.update(0.1), true)
		assert_equal(Library.pick_file("hub"), "hub/new.ogg")
	end)

	it("keeps serving the old list until the new listing has resolved", function()
		local disk = { hub = { "hub/old.ogg" } }
		local _, audio, _, Library = scanned_library(disk)

		disk.hub = { "hub/new.ogg" }
		Library.request_rescan()
		Library.update(0.1)

		assert_equal(Library.pick_file("hub"), "hub/old.ogg")

		audio.resolve()
		Library.update(0.1)

		assert_equal(Library.pick_file("hub"), "hub/new.ogg")
	end)

	it("keeps the old list for a folder that never answers, and finishes after the timeout", function()
		local disk = { hub = { "hub/old.ogg" }, mission_boss = {} }
		local _, audio, lines, Library = scanned_library(disk)

		disk.hub = { "hub/new.ogg" }
		disk.mission_boss = { "mission_boss/new.ogg" }
		Library.request_rescan()
		Library.update(0.1)
		audio.resolve({ hub = true })

		local finished = false
		for _ = 1, 200 do
			finished = Library.update(0.1)
			if finished then
				break
			end
		end

		assert_equal(finished, true)
		assert_equal(Library.pick_file("hub"), "hub/old.ogg")
		assert_equal(Library.pick_file("mission_boss"), "mission_boss/new.ogg")
		assert_equal(lines[#lines]:find("keeping the old list", 1, true) ~= nil, true, lines[#lines])
	end)

	it("folds a request made before the first scan into that scan", function()
		local audio = new_audio_mod({ hub = { "hub/a.ogg" } })
		local engine = FakeEngine.new({ mods = { Audio = audio } })
		local Library = engine:load("library")
		Library.init()

		Library.request_rescan()
		engine:initialize_backend()
		Library.update(0.1)
		local created = audio.created
		audio.resolve()

		for _ = 1, 10 do
			Library.update(0.1)
		end

		assert_equal(audio.created, created)
	end)

	it("ignores a request without the Audio Plugin", function()
		local engine = FakeEngine.new()
		local Library = engine:load("library")
		Library.init()
		engine:initialize_backend()

		Library.request_rescan()

		assert_equal(Library.update(0.1), false)
	end)
end)
