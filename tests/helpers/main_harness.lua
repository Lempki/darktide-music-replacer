-- Loads MusicReplacer.lua, the main file, with its real context, suppression, and resume logic.
-- Everything underneath is a stand-in: the library, the audio client, the log, and the Windows modules.
-- It borrows context_harness.lua's sequences, so the specs set the music states in the game's real order.
-- Time only passes through wait() and tick(), which call the mod's own update.

local FakeEngine = require("tests.helpers.fake_engine")
local Harness = require("tests.helpers.context_harness")

local MainHarness = setmetatable({}, { __index = Harness })
MainHarness.__index = MainHarness

-- The defaults of the mod's own settings.
local DEFAULT_SETTINGS = {
	resume_songs = true,
	captain_boss_music = false,
	daemonhost_boss_music = false,
	meat_grinder_music = false,
	combat_hold_seconds = 8,
	horde_hold_seconds = 3,
	event_hold_seconds = 5,
}

-- A stand-in for library.lua over `files`, which maps a context to a list of { name, duration }.
-- Picks go through each folder in order, so the specs know which file comes next.
local function new_library(files)
	local library = { files = files, rescan_requested = false }
	local last_index = {}

	function library.init() end
	function library.request_rescan() library.rescan_requested = true end
	function library.disk_path(file_path) return file_path end

	function library.update()
		local rescanned = library.rescan_requested
		library.rescan_requested = false
		return rescanned
	end

	function library.pick_file(context_name)
		local list = library.files[context_name]
		if not list or #list == 0 then
			return nil
		end

		local index = (last_index[context_name] or 0) % #list + 1
		last_index[context_name] = index
		return context_name .. "/" .. list[index].name, list[index].duration, #list == 1
	end

	function library.find_file(context_name, file_path)
		local list = library.files[context_name] or {}
		for _, entry in ipairs(list) do
			if context_name .. "/" .. entry.name == file_path then
				return file_path, entry.duration, #list == 1
			end
		end
		return nil
	end

	return library
end

-- A stand-in for audio_client.lua that records every play and stop.
-- `available` turns playback off and on, and `position` is what AudioClient.position() reports.
local function new_audio_client()
	local client = { plays = {}, stops = 0, available = true, position = 0, elapsed = 0, current = nil, shut_down = false }

	function client.init() end
	function client.error() return "no audio output" end
	function client.can_retry() return false end
	function client.update() end
	function client.shutdown() client.shut_down = true end

	-- The real module reads these as functions, so they are looked up on the module table, not as fields.
	local module = setmetatable({}, { __index = client })

	function module.available() return client.available end
	function module.is_playing() return client.current ~= nil end
	function module.elapsed() return client.elapsed end
	function module.position() return client.position end

	function module.play(file_path, opts)
		if not client.available then
			return false
		end
		client.current = { file_path = file_path, opts = opts }
		client.plays[#client.plays + 1] = client.current
		client.elapsed = 0
		return true
	end

	function module.stop()
		client.current = nil
		client.stops = client.stops + 1
	end

	client.module = module
	return client
end

-- Options:
-- * `files`: each context's files for the library stand-in, as { name, duration } lists.
-- * `settings`: overrides of the mod's default settings.
-- * `turned_off`: the mod starts turned off in the mod options, as DMF reports with on_disabled(true).
function MainHarness.new(options)
	options = options or {}

	local settings = {}
	for key, value in pairs(DEFAULT_SETTINGS) do
		settings[key] = value
	end
	for key, value in pairs(options.settings or {}) do
		settings[key] = value
	end

	local library = new_library(options.files or {})
	local client = new_audio_client()
	local lines = {}
	local noop = function() end

	local engine = FakeEngine.new({
		settings = settings,
		metadata = { version = "0.0.0" },
		modules = {
			library = library,
			audio_client = client.module,
			diagnostic_log = { init = noop, close = noop, write = function(line) lines[#lines + 1] = line end },
			native_ffi = {},
			media_decoder = { init = noop, shutdown = noop },
			audio_folders = { init = noop },
			xaudio = { init = noop },
			player = { init = noop },
		},
	})

	local harness = setmetatable({ engine = engine, mod = engine.mod, library = library, client = client, lines = lines, settings = settings }, MainHarness)

	engine:load("MusicReplacer")
	if options.turned_off then
		harness.mod.on_disabled(true)
	else
		harness.mod.on_enabled(true)
	end
	harness.mod.on_all_mods_loaded()
	harness:tick(0)

	return harness
end

function MainHarness:tick(dt)
	self.mod.update(dt)
end

-- Changes a setting the way DMF does, which calls the mod's on_setting_changed.
function MainHarness:set_setting(setting_id, value)
	self.settings[setting_id] = value
	self.mod.on_setting_changed(setting_id)
end

-- The last play the mod asked for, or nil.
function MainHarness:last_play()
	return self.client.plays[#self.client.plays]
end

-- The file the mod is playing, or nil.
function MainHarness:playing()
	return self.client.current and self.client.current.file_path
end

-- Ends the current song the way audio_client.lua does, after `seconds` of playing, as a file that could not play when `failed`.
function MainHarness:finish_song(seconds, failed)
	local current = self.client.current
	self.client.current = nil
	self.client.elapsed = seconds
	current.opts.on_finished(failed == true)
end

-- The settled context: the debounce needs 0.6 seconds of quiet.
function MainHarness:settle()
	self:wait(0.7)
end

-- True when a logged line contains `text`.
function MainHarness:logged(text)
	for _, line in ipairs(self.lines) do
		if line:find(text, 1, true) then
			return true
		end
	end
	return false
end

return MainHarness
