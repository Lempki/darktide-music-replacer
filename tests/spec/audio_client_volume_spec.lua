-- Pins how audio_client.lua follows the volume sliders: through the session when it can, by a relaunch when it must.

local FakeEngine = require("tests.helpers.fake_engine")

-- A fake Audio Plugin that records every play_file call and stop.
local function new_audio_mod()
	local audio = { plays = {}, stopped = {} }

	function audio.play_file(file_path, options)
		audio.plays[#audio.plays + 1] = { file_path = file_path, options = options }
		return "play-" .. #audio.plays
	end

	function audio.file_pid() return nil end
	function audio.stop_file(play_file_id) audio.stopped[#audio.stopped + 1] = play_file_id end

	return audio
end

-- A fake volume_sessions.lua that accepts levels up to each track's launch percent while `accepting` is true.
local function new_volume_sessions()
	local fake = { tracked = {}, levels = {}, retired = {}, accepting = true }

	function fake.track(play_file_id, launch_percent) fake.tracked[play_file_id] = launch_percent end
	function fake.set_level(play_file_id, percent)
		local launch_percent = fake.tracked[play_file_id]
		if not fake.accepting or not launch_percent or math.floor(percent + 0.5) > launch_percent then
			return false
		end
		fake.levels[#fake.levels + 1] = { play_file_id, percent }
		return true
	end
	function fake.retire(play_file_id) fake.retired[#fake.retired + 1] = play_file_id end
	function fake.update() end
	function fake.shutdown() end

	return fake
end

-- Returns the fake Audio Plugin, the fake sliders, the fake volume_sessions.lua, and an audio_client.lua playing one track.
local function playing_track()
	local audio = new_audio_mod()
	local sliders = { option_master_slider = 80, options_music_slider = 50 }
	local engine = FakeEngine.new({ mods = { Audio = audio }, user_settings = sliders })
	local volume_sessions = new_volume_sessions()
	local AudioClient = engine:load("audio_client")
	AudioClient.init(nil, volume_sessions)
	AudioClient.play("hub/a.ogg", { duration_seconds = 200, fade_in = true })
	AudioClient.update(0.1)

	return audio, sliders, volume_sessions, AudioClient
end

describe("audio_client.lua volume", function()
	it("tracks each launch at the whole percent the Audio Plugin bakes in", function()
		local _, _, volume_sessions = playing_track()

		assert_equal(volume_sessions.tracked["play-1"], 40)
	end)

	it("lowers a running track through its session, with no relaunch", function()
		local audio, sliders, volume_sessions, AudioClient = playing_track()

		sliders.options_music_slider = 25
		AudioClient.update(0.1)

		assert_equal(#audio.plays, 1)
		assert_deep_equal(volume_sessions.levels, { { "play-1", 20 } })
	end)

	it("follows every step of a drag, with no cooldown", function()
		local audio, sliders, volume_sessions, AudioClient = playing_track()

		for music = 45, 30, -5 do
			sliders.options_music_slider = music
			AudioClient.update(0.016)
		end

		assert_equal(#audio.plays, 1)
		assert_equal(#volume_sessions.levels, 4)
	end)

	it("relaunches to raise a track above its launch level, and tracks the new launch", function()
		local audio, sliders, volume_sessions, AudioClient = playing_track()

		sliders.options_music_slider = 75
		AudioClient.update(0.1)

		assert_equal(#audio.plays, 2)
		assert_deep_equal(volume_sessions.retired, { "play-1" })
		assert_equal(volume_sessions.tracked["play-2"], 60)
	end)

	it("relaunches when the session cannot follow, at most once per second", function()
		local audio, sliders, volume_sessions, AudioClient = playing_track()
		volume_sessions.accepting = false

		sliders.options_music_slider = 25
		AudioClient.update(0.1)
		sliders.options_music_slider = 20
		AudioClient.update(0.1)

		assert_equal(#audio.plays, 2)

		AudioClient.update(1)

		assert_equal(#audio.plays, 3)
	end)

	it("also follows the sliders on a track fading out under the next one", function()
		local _, sliders, volume_sessions, AudioClient = playing_track()
		AudioClient.play("hub/b.ogg", { duration_seconds = 200, fade_in = true })

		sliders.options_music_slider = 25
		AudioClient.update(0.1)

		assert_deep_equal(volume_sessions.levels, { { "play-2", 20 }, { "play-1", 20 } })
	end)

	it("retires every stopped track's session", function()
		local _, _, volume_sessions, AudioClient = playing_track()
		AudioClient.play("hub/b.ogg", { duration_seconds = 200, fade_in = true })

		AudioClient.stop()

		assert_deep_equal(volume_sessions.retired, { "play-2", "play-1" })
	end)
end)
