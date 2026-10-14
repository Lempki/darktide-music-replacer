-- Pins how audio_client.lua starts a song partway in, and keeps that position across a volume relaunch.

local FakeEngine = require("tests.helpers.fake_engine")

-- A fake Audio Plugin that records the options of every play_file call.
local function new_audio_mod()
	local audio = { plays = {} }

	function audio.play_file(file_path, options)
		audio.plays[#audio.plays + 1] = { file_path = file_path, options = options }
		return "play-" .. #audio.plays
	end

	function audio.file_pid() return nil end
	function audio.stop_file() end

	return audio
end

-- Returns the fake Audio Plugin, the fake slider values, and a loaded audio_client.lua.
local function load_audio_client()
	local audio = new_audio_mod()
	local sliders = { option_master_slider = 100, options_music_slider = 100 }
	local engine = FakeEngine.new({ mods = { Audio = audio }, user_settings = sliders })
	local AudioClient = engine:load("audio_client")
	AudioClient.init()

	return audio, sliders, AudioClient
end

describe("audio_client.lua resuming", function()
	it("seeks to the start position and fades in from there", function()
		local audio, _, AudioClient = load_audio_client()

		AudioClient.play("mission_explore/a.ogg", { duration_seconds = 200, fade_in = true, start_position = 63.25 })

		local options = audio.plays[1].options
		assert_equal(options.pos, 63.25)
		assert_equal(options.afade, "t=in:st=63.250:d=2,afade=t=out:st=198:d=2")
	end)

	it("plays from the start with the usual fade-in without a start position", function()
		local audio, _, AudioClient = load_audio_client()

		AudioClient.play("mission_explore/a.ogg", { duration_seconds = 200, fade_in = true })

		local options = audio.plays[1].options
		assert_equal(options.pos, nil)
		assert_equal(options.afade, "t=in:d=2,afade=t=out:st=198:d=2")
	end)

	it("reports the position in the file, counting from the start position", function()
		local _, _, AudioClient = load_audio_client()

		AudioClient.play("mission_explore/a.ogg", { duration_seconds = 200, fade_in = true, start_position = 60 })
		AudioClient.update(1.5)
		AudioClient.update(1.5)

		assert_equal(AudioClient.position(), 63)
		assert_equal(AudioClient.elapsed(), 3)
	end)

	it("relaunches a resumed song at its position in the file after a volume change", function()
		local audio, sliders, AudioClient = load_audio_client()
		AudioClient.play("mission_explore/a.ogg", { duration_seconds = 200, fade_in = true, start_position = 60 })
		AudioClient.update(2)

		sliders.options_music_slider = 50
		AudioClient.update(1)

		local relaunch = audio.plays[2]
		assert_equal(relaunch.file_path, "mission_explore/a.ogg")
		assert_equal(relaunch.options.pos, 63)
	end)

	it("reports position 0 after a stop", function()
		local _, _, AudioClient = load_audio_client()
		AudioClient.play("mission_explore/a.ogg", { start_position = 60 })
		AudioClient.update(1)

		AudioClient.stop()

		assert_equal(AudioClient.position(), 0)
	end)
end)
