-- Checks how audio_client.lua stops playback when the mod unloads.

local FakeEngine = require("tests.helpers.fake_engine")

local PID = 4242

-- A fake Audio Plugin whose stop_file sends its request through Managers.backend, like the real plugin does through DLS.
local function new_audio_mod()
	local audio = { stopped = {} }

	function audio.play_file()
		return "play-1"
	end

	function audio.file_pid()
		return PID
	end

	function audio.stop_file(play_file_id)
		audio.stopped[#audio.stopped + 1] = play_file_id
		Managers.backend:url_request("localhost:41012/stop_process?pid=" .. PID)
	end

	return audio
end

-- Returns a fake engine, the fake Audio Plugin, the commands passed to os.execute, and a loaded audio_client.lua playing a track.
local function play_a_track(with_os)
	local audio = new_audio_mod()
	local commands = {}
	local fake_os = { execute = function(command) commands[#commands + 1] = command end }

	local engine = FakeEngine.new({ mods = { Audio = audio }, lua = with_os and { os = fake_os } or nil })
	local AudioClient = engine:load("audio_client")
	AudioClient.init()
	AudioClient.play("hub/track.ogg", {})

	return engine, audio, commands, AudioClient
end

describe("audio_client.lua shutdown", function()
	it("kills the track and sends no stop request once the backend is gone at game exit", function()
		local engine, audio, commands, AudioClient = play_a_track(true)
		engine:tear_down_backend()

		AudioClient.shutdown()

		assert_deep_equal(commands, { "taskkill /PID 4242 /F /T >nul 2>nul" })
		assert_deep_equal(audio.stopped, {})
	end)

	it("also sends the stop request while the backend exists, as on a mod reload", function()
		local engine, audio, commands, AudioClient = play_a_track(true)

		AudioClient.shutdown()

		assert_deep_equal(commands, { "taskkill /PID 4242 /F /T >nul 2>nul" })
		assert_deep_equal(audio.stopped, { "play-1" })
		assert_deep_equal(engine.url_requests, { "localhost:41012/stop_process?pid=4242" })
	end)

	it("raises no error without os.execute and without the backend", function()
		local engine, audio, _, AudioClient = play_a_track(false)
		engine:tear_down_backend()

		AudioClient.shutdown()

		assert_deep_equal(audio.stopped, {})
	end)
end)
