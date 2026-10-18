-- Loads MusicReplacer.lua, the main file, with its real context, suppression, and resume logic.
-- Everything underneath is a stand-in: the library, audio client, loudness, debug overlay, log, and Windows modules.
-- It borrows context_harness.lua's sequences, so the specs set the music states in the game's real order.
-- Time only passes through wait() and tick(), which call the mod's own update.

local FakeEngine = require("tests.helpers.fake_engine")
local Harness = require("tests.helpers.context_harness")

local MainHarness = setmetatable({}, { __index = Harness })
MainHarness.__index = MainHarness

-- The defaults of the mod's own settings.
local DEFAULT_SETTINGS = {
	resume_songs = true,
	custom_music_volume = 100,
	normalize_loudness = false,
	menu_volume = 50,
	captain_boss_music = false,
	daemonhost_boss_music = false,
	source_meat_grinder = "silence",
	combat_hold_seconds = 8,
	horde_hold_seconds = 3,
	event_hold_seconds = 5,
}

-- A stand-in for library.lua over `files`, which maps a folder key to a list of { name, duration }.
-- A folder key is a context, or an override folder inside it, such as "mission_boss/chaos_spawn".
-- Picks go through each folder in order, so the specs know which file comes next.
local function new_library(files)
	local library = { files = files, rescan_requested = false, listed_listeners = {} }
	local last_index = {}

	function library.init() end
	function library.shutdown() end
	function library.on_listed(listener) library.listed_listeners[#library.listed_listeners + 1] = listener end
	function library.request_rescan() library.rescan_requested = true end
	function library.has_files(folder_key) return library.files[folder_key] ~= nil and #library.files[folder_key] > 0 end
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

-- A stand-in for audio_client.lua that records every play and stop, and the volume levels it was given.
-- `available` turns playback off and on, and `position` is what AudioClient.position() reports.
local function new_audio_client()
	local client = { plays = {}, stops = 0, available = true, position = 0, elapsed = 0, current = nil, shut_down = false, volume = nil, menu_volume = nil }

	function client.init() end
	function client.error() return "no audio output" end
	function client.can_retry() return false end
	function client.update() end
	function client.shutdown() client.shut_down = true end
	function client.set_volume(scale) client.volume = scale end
	function client.set_menu_volume(target) client.menu_volume = target end
	function client.refresh_levels() client.levels_refreshed = (client.levels_refreshed or 0) + 1 end
	function client.try_again() client.tries_again = (client.tries_again or 0) + 1 end

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

	function module.duration()
		return client.current and client.current.opts.duration_seconds
	end

	function module.levels()
		return client.volume or 1, client.menu_volume or 1, 1
	end

	client.module = module
	return client
end

-- A stand-in for loudness.lua. `levels` maps a file path to the level it plays at once measured.
local function new_loudness()
	local loudness = { enabled = false, levels = {}, preferred_contexts = {}, shut_down = false }

	function loudness.init() end
	function loudness.set_enabled(on) loudness.enabled = on == true end
	function loudness.set_files() end
	function loudness.update(preferred_context) loudness.preferred_contexts[#loudness.preferred_contexts + 1] = tostring(preferred_context) end
	function loudness.shutdown() loudness.shut_down = true end

	function loudness.level(file_path)
		return loudness.enabled and loudness.levels[file_path] or 1
	end

	function loudness.describe(file_path)
		if not loudness.enabled then
			return nil
		end
		return loudness.levels[file_path] and string.format("level %.2f", loudness.levels[file_path]) or "loudness not measured yet"
	end

	return loudness
end

-- A stand-in for debug_overlay.lua that keeps what the main file gives it, so a spec can read the overlay's snapshot.
local function new_overlay()
	local overlay = { enabled = false, corner = nil, options = nil }

	function overlay.init(_, options) overlay.options = options end
	function overlay.set_enabled(on, corner, scale) overlay.enabled, overlay.corner, overlay.scale = on, corner, scale end
	function overlay.update() end
	function overlay.shutdown() end

	return overlay
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
	local loudness = new_loudness()
	local overlay = new_overlay()
	local lines = {}
	local noop = function() end

	local engine = FakeEngine.new({
		settings = settings,
		metadata = { version = "0.0.0" },
		modules = {
			library = library,
			audio_client = client.module,
			loudness = loudness,
			debug_overlay = overlay,
			loudness_meter = {},
			diagnostic_log = {
				init = noop,
				close = noop,
				write = function(line) lines[#lines + 1] = line end,
				detail = function(line) lines[#lines + 1] = line end,
				folder = function() return "C:/AppData/Fatshark/Darktide/MusicReplacer" end,
			},
			native_ffi = {},
			media_decoder = { init = noop, shutdown = noop },
			audio_folders = { init = noop },
			xaudio = { init = noop },
			player = { init = noop },
		},
	})

	local harness = setmetatable({ engine = engine, mod = engine.mod, library = library, client = client, loudness = loudness, overlay = overlay,
		lines = lines, settings = settings }, MainHarness)

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
