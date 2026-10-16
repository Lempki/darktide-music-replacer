-- Pins audio_client.lua against a fake player.lua: crossfades, sliders, endings, failed files, and recovery.

local FakeEngine = require("tests.helpers.fake_engine")

-- A fake stream. A fade completes once updates have covered its length.
local function new_stream(path, opts)
	local stream = {
		path = path,
		opts = opts,
		fade = opts.fade or 1,
		gains = { opts.gain },
		fades = {},
		ramp_left = 0,
		current_position = opts.start_position or 0,
		is_ended = false,
		failed = nil,
		destroyed = false,
		paused = false,
		duration = 200,
	}

	function stream.pause(self) self.paused = true end
	function stream.resume(self) self.paused = false end
	function stream.is_paused(self) return self.paused end

	function stream.fade_to(self, target, seconds)
		self.fades[#self.fades + 1] = { target, seconds }
		self.fade = target
		self.ramp_left = seconds
	end
	function stream.fading(self) return self.ramp_left > 0 end
	function stream.set_gain(self, gain) self.gains[#self.gains + 1] = gain end
	function stream.update(self, dt) self.ramp_left = math.max(0, self.ramp_left - dt) end
	function stream.position(self) return self.current_position end
	function stream.ended(self) return self.is_ended end
	function stream.failure(self) return self.failed end
	function stream.file_failure(self) return self.file_failed end
	function stream.destroy(self) self.destroyed = true end

	return stream
end

-- Returns a loaded audio_client.lua, the fake player, the streams it opened, the fake sliders, and the logged lines.
local function load_client()
	local sliders = { option_master_slider = 80, options_music_slider = 50 }
	local engine = FakeEngine.new({ user_settings = sliders })
	local AudioClient = engine:load("audio_client")
	local streams = {}
	local lines = {}
	-- `output` is false while Windows has no audio output. Like XAudio2, a failed start stays failed until reset.
	-- `engine_failure_reason` is a failure left behind by a stream.
	-- `refuse` maps a path to why it cannot be opened, and `refuse_voice` maps a path to how many voices XAudio2 refuses it.
	local player = { resets = 0, refuse = {}, refuse_voice = {}, output = true, start_failed = false, engine_failure_reason = nil }

	function player.available()
		if not player.start_failed and not player.output then
			player.start_failed = true
		end
		return not player.start_failed
	end
	function player.can_retry() return player.start_failed end
	function player.error() return player.start_failed and "creating the output failed" or nil end
	function player.engine_failure() return player.engine_failure_reason end
	function player.open(path, opts)
		if player.refuse[path] then
			return nil, player.refuse[path]
		end
		if (player.refuse_voice[path] or 0) > 0 then
			player.refuse_voice[path] = player.refuse_voice[path] - 1
			return nil, "creating a voice failed", true
		end
		local stream = new_stream(path, opts)
		streams[#streams + 1] = stream
		return stream
	end
	function player.reset()
		player.resets = player.resets + 1
		player.start_failed = false
		player.engine_failure_reason = nil
	end
	function player.pool_bytes() return 0 end
	function player.last_open_ms() return player.open_ms or 0 end
	function player.slowest_fill_ms() return 0 end

	AudioClient.init(function(line) lines[#lines + 1] = line end, {
		player = player,
		disk_path = function(file_path) return "audio/" .. file_path end,
	})

	return AudioClient, player, streams, sliders, lines
end

describe("audio_client.lua", function()
	it("opens the file on disk at the sliders' gain and fades it in", function()
		local AudioClient, _, streams = load_client()

		AudioClient.play("hub/a.mp3", { fade_in = true, start_position = 30 })

		assert_equal(streams[1].path, "audio/hub/a.mp3")
		assert_equal(streams[1].opts.gain, 0.4)
		assert_equal(streams[1].opts.fade, 0)
		assert_equal(streams[1].opts.start_position, 30)
		assert_deep_equal(streams[1].fades, { { 1, 2 } })
		assert_equal(AudioClient.is_playing(), true)
	end)

	it("crossfades a real switch, parks the outgoing song once it has faded, and frees it after 60 seconds", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })

		AudioClient.play("mission_combat/b.mp3", { fade_in = true })

		assert_deep_equal(streams[1].fades[#streams[1].fades], { 0, 2 })
		assert_deep_equal(streams[2].fades, { { 1, 2 } })

		AudioClient.update(1)
		assert_equal(streams[1].paused, false)

		AudioClient.update(1.1)
		assert_equal(streams[1].paused, true)
		assert_equal(streams[1].destroyed, false)

		AudioClient.update(59)
		assert_equal(streams[1].destroyed, false)
		AudioClient.update(1.1)
		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].destroyed, false)
	end)

	it("continues a parked song where it faded out when the mod resumes it", function()
		local AudioClient, _, streams, _, lines = load_client()
		AudioClient.play("mission_explore/a.mp3", { fade_in = true })
		AudioClient.play("mission_combat/b.mp3", { fade_in = true })
		AudioClient.update(2.1)
		streams[1].current_position = 95

		AudioClient.play("mission_explore/a.mp3", { fade_in = true, start_position = 93 })

		assert_equal(#streams, 2)
		assert_equal(streams[1].paused, false)
		assert_deep_equal(streams[1].fades[#streams[1].fades], { 1, 2 })
		assert_deep_equal(streams[2].fades[#streams[2].fades], { 0, 2 })
		assert_equal(AudioClient.position(), 95)
		assert_equal(lines[#lines], "[player] continuing mission_explore/a.mp3 from 95.0s, where it faded out")
	end)

	it("does not take back a parked song whose loop setting differs, and opens it afresh instead", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("mission_explore/a.mp3", { fade_in = true, loop = true })
		AudioClient.play("mission_combat/b.mp3", { fade_in = true })
		AudioClient.update(2.1)

		AudioClient.play("mission_explore/a.mp3", { fade_in = true, start_position = 40, duration_seconds = 200 })

		assert_equal(#streams, 3)
		assert_equal(streams[3].opts.loop, false)
		assert_equal(streams[3].opts.start_position, 40)
	end)

	it("keeps at most 4 parked songs, freeing the oldest first", function()
		local AudioClient, _, streams = load_client()

		for index = 1, 7 do
			AudioClient.play("mission_explore/" .. index .. ".mp3", { fade_in = true })
			AudioClient.update(2.1)
		end

		local destroyed = {}
		for index, stream in ipairs(streams) do
			destroyed[index] = stream.destroyed
		end
		assert_deep_equal(destroyed, { true, true, false, false, false, false, false })
	end)

	it("treats a song that stops for its own reasons as a file that could not be played, without rebuilding", function()
		local AudioClient, player, streams, _, lines = load_client()
		local failed_after = nil
		AudioClient.play("hub/silent.mp3", { loop = true, on_finished = function(failed) failed_after = failed end })
		streams[1].file_failed = "it decodes to no audio"

		AudioClient.update(0.1)

		assert_equal(failed_after, true)
		assert_equal(player.resets, 0)
		assert_equal(streams[1].destroyed, true)
		assert_equal(lines[#lines], "[player] hub/silent.mp3 could not be played: it decodes to no audio")
	end)

	it("logs a slow file open, since it stalls the game's thread", function()
		local AudioClient, player, _, _, lines = load_client()
		player.open_ms = 250

		AudioClient.play("hub/a.mp3", { fade_in = true })

		assert_equal(lines[1], "[timing] opening hub/a.mp3 took 250 ms")
	end)

	it("takes back a song still fading out, fading it up from where it is", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("mission_explore/a.mp3", { fade_in = true })
		AudioClient.play("mission_combat/b.mp3", { fade_in = true })
		AudioClient.update(1)

		AudioClient.play("mission_explore/a.mp3", { fade_in = true, start_position = 10 })

		assert_equal(#streams, 2)
		assert_deep_equal(streams[1].fades[#streams[1].fades], { 1, 2 })
	end)

	it("starts a fresh pick of a parked file over, since only a resume continues it", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("mission_horde/a.mp3", { fade_in = true })
		AudioClient.play("mission_combat/b.mp3", { fade_in = true })
		AudioClient.update(2.1)

		AudioClient.play("mission_horde/a.mp3", { fade_in = true })

		assert_equal(#streams, 3)
		assert_equal(streams[3].path, "audio/mission_horde/a.mp3")
		assert_equal(streams[1].paused, true)
	end)

	it("starts a continuation at full level after freeing the track that ended", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })

		AudioClient.play("hub/b.mp3", { fade_in = false })

		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].opts.fade, 1)
		assert_deep_equal(streams[2].fades, {})
	end)

	it("follows the sliders up and down on every stream, with no reopening", function()
		local AudioClient, _, streams, sliders = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })
		AudioClient.play("hub/b.mp3", { fade_in = true })

		sliders.options_music_slider = 100
		AudioClient.update(0.1)
		sliders.options_music_slider = 25
		AudioClient.update(0.1)

		assert_equal(#streams, 2)
		assert_deep_equal(streams[2].gains, { 0.4, 0.8, 0.2 })
		assert_deep_equal(streams[1].gains, { 0.4, 0.8, 0.2 })
	end)

	it("calls on_finished once a track ends, after letting go of it, so the callback can play the next one", function()
		local AudioClient, _, streams = load_client()
		local calls = 0
		AudioClient.play("hub/a.mp3", {
			fade_in = true,
			on_finished = function()
				calls = calls + 1
				assert_equal(AudioClient.is_playing(), false)
				AudioClient.play("hub/b.mp3", { fade_in = false })
			end,
		})

		streams[1].is_ended = true
		AudioClient.update(0.1)
		AudioClient.update(0.1)

		assert_equal(calls, 1)
		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].path, "audio/hub/b.mp3")
	end)

	-- MusicReplacer.lua's quick-end guard reads elapsed() inside on_finished, so a song that played out must not look like a broken one.
	it("reports the finished track's elapsed time during on_finished", function()
		local AudioClient, _, streams = load_client()
		local finished_after, finished_failed = nil, nil
		AudioClient.play("hub/a.mp3", {
			fade_in = true,
			on_finished = function(failed)
				finished_after = AudioClient.elapsed()
				finished_failed = failed
			end,
		})

		for _ = 1, 50 do
			AudioClient.update(0.1)
		end
		streams[1].is_ended = true
		AudioClient.update(0.1)

		assert_equal(math.abs(finished_after - 5.1) < 1e-9, true, tostring(finished_after))
		assert_equal(finished_failed, false)
	end)

	it("fades out 2 seconds before the file's own end when given a duration", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = false, duration_seconds = 199 })

		streams[1].current_position = 197.5
		AudioClient.update(0.1)
		assert_deep_equal(streams[1].fades, {})

		streams[1].current_position = 198.2
		AudioClient.update(0.1)
		local fade = streams[1].fades[1]
		assert_equal(fade[1], 0)
		assert_equal(math.abs(fade[2] - 1.8) < 1e-9, true, tostring(fade[2]))
	end)

	it("stops a looping song at the end of its file when asked to play it to its end", function()
		local AudioClient, _, streams = load_client()
		local finished = nil
		AudioClient.play("hub/only.mp3", { fade_in = false, loop = true, on_finished = function(failed) finished = failed end })

		AudioClient.play_to_end()
		streams[1].current_position = 198.5
		AudioClient.update(0.1)
		assert_deep_equal(streams[1].fades, { { 0, 1.5 } })
		assert_equal(finished, nil)

		AudioClient.update(1.5)
		assert_equal(finished, false)
		assert_equal(streams[1].destroyed, true)
	end)

	it("does not fade out while looping", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("hub/b.mp3", { fade_in = false, duration_seconds = 199, loop = true })

		streams[1].current_position = 199
		AudioClient.update(0.1)

		assert_deep_equal(streams[1].fades, {})
		assert_equal(streams[1].opts.loop, true)
	end)

	-- Right after the folders are listed again, a song can start before the library has measured it.
	it("fades out at the decoder's own length when the library has not measured the file", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = false })

		streams[1].current_position = 197
		AudioClient.update(0.1)
		assert_deep_equal(streams[1].fades, {})

		streams[1].current_position = 198.5
		AudioClient.update(0.1)
		assert_deep_equal(streams[1].fades, { { 0, 1.5 } })
	end)

	it("treats a file it cannot open as a track that ended at once", function()
		local AudioClient, player, _, _, lines = load_client()
		player.refuse["audio/hub/broken.mp3"] = "unsupported format"
		local finished_after = nil
		AudioClient.play("hub/broken.mp3", {
			fade_in = true,
			on_finished = function(failed) finished_after = failed and AudioClient.elapsed() end,
		})

		AudioClient.update(0.1)

		assert_equal(finished_after, 0.1)
		assert_equal(lines[1], "[player] hub/broken.mp3 could not be played: unsupported format")
	end)

	it("fades out quickly on stop", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })

		AudioClient.stop()

		assert_equal(AudioClient.is_playing(), false)
		assert_deep_equal(streams[1].fades[#streams[1].fades], { 0, 0.5 })

		AudioClient.update(0.6)
		assert_equal(streams[1].paused, true)
	end)

	it("rebuilds the engine after a failure and resumes the song where it was", function()
		local AudioClient, player, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true, duration_seconds = 199 })
		streams[1].current_position = 42
		streams[1].failed = "the voice stopped playing with audio queued"

		AudioClient.update(0.1)

		assert_equal(player.resets, 1)
		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].path, "audio/hub/a.mp3")
		assert_equal(streams[2].opts.start_position, 42)
	end)

	it("gives up for the session after 3 recoveries in a row", function()
		local AudioClient, _, streams, _, lines = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })

		for _ = 1, 4 do
			streams[#streams].failed = "lost"
			AudioClient.update(0.1)
		end

		assert_equal(AudioClient.available(), false)
		assert_equal(AudioClient.is_playing(), false)
		assert_equal(lines[#lines]:find("gave up after 3 recoveries", 1, true) ~= nil, true, lines[#lines])
	end)

	it("tries for an audio output every 5 seconds, without counting it as a recovery, and plays once there is one", function()
		local AudioClient, player, streams, _, lines = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })
		streams[1].failed = "the voice stopped playing with audio queued"
		player.output = false

		AudioClient.update(0.1)

		assert_equal(player.resets, 1)
		assert_equal(AudioClient.available(), false)
		assert_equal(AudioClient.can_retry(), true)
		assert_equal(lines[#lines], "[player] no audio output (creating the output failed), trying again every 5s")

		for _ = 1, 10 do
			AudioClient.update(5)
		end

		assert_equal(player.resets, 11)
		assert_equal(AudioClient.can_retry(), true)

		player.output = true
		AudioClient.update(5)

		assert_equal(AudioClient.available(), true)
		assert_equal(lines[#lines], "[player] the audio output is back")

		AudioClient.update(5)
		assert_equal(player.resets, 12)
	end)

	it("rebuilds the engine before opening a song when a failure outlived its stream", function()
		local AudioClient, player, streams, _, lines = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })
		AudioClient.stop()
		AudioClient.update(1)
		player.engine_failure_reason = "submitting a buffer failed with 0x88960001"

		AudioClient.play("hub/b.mp3", { fade_in = true })

		assert_equal(player.resets, 1)
		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].path, "audio/hub/b.mp3")
		assert_equal(lines[1], "[player] the engine stopped working (submitting a buffer failed with 0x88960001), rebuilding it")
	end)

	it("rebuilds the engine and tries once more when a voice is refused with no song fading out", function()
		local AudioClient, player, streams = load_client()
		player.refuse_voice["audio/hub/a.mp3"] = 1

		AudioClient.play("hub/a.mp3", { fade_in = true })

		assert_equal(player.resets, 1)
		assert_equal(streams[1].path, "audio/hub/a.mp3")
		assert_equal(AudioClient.is_playing(), true)
	end)

	it("treats a file refused again after the rebuild as one that cannot be played, without counting a recovery", function()
		local AudioClient, player = load_client()
		local failures = 0
		player.refuse_voice["audio/hub/a.mp3"] = 100

		for _ = 1, 5 do
			AudioClient.play("hub/a.mp3", { on_finished = function(failed) failures = failures + (failed and 1 or 0) end })
			AudioClient.update(0.1)
		end

		assert_equal(failures, 5)
		assert_equal(AudioClient.available(), true)
	end)

	it("does not rebuild for a refused voice while another song fades out, since the engine plays", function()
		local AudioClient, player, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })
		player.refuse_voice["audio/hub/b.mp3"] = 1
		local failed_open = nil

		AudioClient.play("hub/b.mp3", { fade_in = true, on_finished = function(failed) failed_open = failed end })
		AudioClient.update(0.1)

		assert_equal(player.resets, 0)
		assert_equal(streams[1].destroyed, false)
		assert_equal(failed_open, true)
	end)

	it("starts counting recoveries afresh after 30 seconds of healthy playing", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })

		for _ = 1, 3 do
			streams[#streams].failed = "lost"
			AudioClient.update(0.1)
		end
		AudioClient.update(30)

		for _ = 1, 3 do
			streams[#streams].failed = "lost"
			AudioClient.update(0.1)
		end

		assert_equal(AudioClient.available(), true)
		assert_equal(AudioClient.is_playing(), true)
	end)

	it("frees a song that fails while fading out, without rebuilding the engine", function()
		local AudioClient, player, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })
		AudioClient.play("hub/b.mp3", { fade_in = true })

		streams[1].failed = "lost"
		AudioClient.update(0.1)

		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].destroyed, false)
		assert_equal(player.resets, 0)
	end)

	it("does not take back a parked song that has ended or failed", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("mission_explore/a.mp3", { fade_in = true })
		AudioClient.play("mission_combat/b.mp3", { fade_in = true })
		AudioClient.update(2.1)
		streams[1].failed = "lost"

		AudioClient.play("mission_explore/a.mp3", { fade_in = true, start_position = 93 })

		assert_equal(#streams, 3)
		assert_equal(streams[3].opts.start_position, 93)
	end)

	it("fades out at once when a song resumes within its last 2 seconds", function()
		local AudioClient, _, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true, start_position = 199, duration_seconds = 200 })

		AudioClient.update(0.1)

		assert_deep_equal(streams[1].fades[#streams[1].fades], { 0, 1 })
	end)

	it("plays nothing and says so while playback is unavailable", function()
		local AudioClient, player, streams = load_client()
		player.output = false

		assert_equal(AudioClient.play("hub/a.mp3", { fade_in = true }), false)
		assert_equal(#streams, 0)
		assert_equal(AudioClient.is_playing(), false)
	end)

	it("stops everything at once on shutdown", function()
		local AudioClient, player, streams = load_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })
		AudioClient.play("hub/b.mp3", { fade_in = true })

		AudioClient.shutdown()

		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].destroyed, true)
		assert_equal(player.resets, 1)
	end)
end)

describe("audio_client.lua volume", function()
	-- Full sliders, so a stream's gain is the volume settings alone.
	local function load_full_client()
		local AudioClient, player, streams, sliders, lines = load_client()
		sliders.option_master_slider = 100
		sliders.options_music_slider = 100
		return AudioClient, player, streams, sliders, lines
	end

	it("opens a song at the Custom Music Volume, on top of the sliders", function()
		local AudioClient, _, streams = load_client()
		AudioClient.set_volume(0.5)

		AudioClient.play("hub/a.mp3", { fade_in = true })

		assert_equal(streams[1].opts.gain, 0.2)
	end)

	it("follows a changed Custom Music Volume on every stream at once", function()
		local AudioClient, _, streams = load_full_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })
		AudioClient.play("hub/b.mp3", { fade_in = true })

		AudioClient.set_volume(0.25)

		assert_deep_equal(streams[1].gains, { 1, 0.25 })
		assert_deep_equal(streams[2].gains, { 1, 0.25 })
	end)

	it("fades down to the menu volume over half a second while a menu is open, and back up once it closes", function()
		local AudioClient, _, streams = load_full_client()
		AudioClient.play("hub/a.mp3", { fade_in = true })

		AudioClient.set_menu_volume(0.5)
		AudioClient.update(0.25)
		AudioClient.update(0.25)
		AudioClient.update(0.25)
		AudioClient.set_menu_volume(1)
		AudioClient.update(0.25)
		AudioClient.update(0.25)
		AudioClient.update(0.25)

		assert_deep_equal(streams[1].gains, { 1, 0.75, 0.5, 0.75, 1 })
	end)

	it("opens a song during a menu at the menu volume", function()
		local AudioClient, _, streams = load_full_client()
		AudioClient.set_menu_volume(0.5)
		AudioClient.update(0.5)

		AudioClient.play("hub/a.mp3", { fade_in = true })

		assert_equal(streams[1].opts.gain, 0.5)
	end)
end)
