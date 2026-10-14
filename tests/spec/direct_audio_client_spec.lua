-- Pins direct_audio_client.lua against a fake direct_player.lua: crossfades, sliders, endings, failed files, and recovery.

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
		duration = 200,
	}

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
	function stream.destroy(self) self.destroyed = true end

	return stream
end

-- Returns a loaded direct_audio_client.lua, the fake player, the streams it opened, the fake sliders, and the logged lines.
local function load_client()
	local sliders = { option_master_slider = 80, options_music_slider = 50 }
	local engine = FakeEngine.new({ user_settings = sliders })
	local DirectAudioClient = engine:load("direct_audio_client")
	local streams = {}
	local lines = {}
	local player = { resets = 0, refuse = {} }

	function player.available() return true end
	function player.error() return nil end
	function player.open(path, opts)
		if player.refuse[path] then
			return nil, "unsupported format"
		end
		local stream = new_stream(path, opts)
		streams[#streams + 1] = stream
		return stream
	end
	function player.reset() player.resets = player.resets + 1 end
	function player.pool_bytes() return 0 end
	function player.slowest_fill_ms() return 0 end

	DirectAudioClient.init(function(line) lines[#lines + 1] = line end, {
		direct_player = player,
		disk_path = function(file_path) return "audio/" .. file_path end,
	})

	return DirectAudioClient, player, streams, sliders, lines
end

describe("direct_audio_client.lua", function()
	it("opens the file on disk at the sliders' gain and fades it in", function()
		local DirectAudioClient, _, streams = load_client()

		DirectAudioClient.play("hub/a.mp3", { fade_in = true, start_position = 30 })

		assert_equal(streams[1].path, "audio/hub/a.mp3")
		assert_equal(streams[1].opts.gain, 0.4)
		assert_equal(streams[1].opts.fade, 0)
		assert_equal(streams[1].opts.start_position, 30)
		assert_deep_equal(streams[1].fades, { { 1, 2 } })
		assert_equal(DirectAudioClient.is_playing(), true)
	end)

	it("crossfades a real switch, and frees the outgoing song once it has faded", function()
		local DirectAudioClient, _, streams = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = true })

		DirectAudioClient.play("mission_combat/b.mp3", { fade_in = true })

		assert_deep_equal(streams[1].fades[#streams[1].fades], { 0, 2 })
		assert_deep_equal(streams[2].fades, { { 1, 2 } })

		DirectAudioClient.update(1)
		assert_equal(streams[1].destroyed, false)

		DirectAudioClient.update(1.1)
		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].destroyed, false)
	end)

	it("starts a continuation at full level after freeing the track that ended", function()
		local DirectAudioClient, _, streams = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = true })

		DirectAudioClient.play("hub/b.mp3", { fade_in = false })

		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].opts.fade, 1)
		assert_deep_equal(streams[2].fades, {})
	end)

	it("follows the sliders up and down on every stream, with no reopening", function()
		local DirectAudioClient, _, streams, sliders = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = true })
		DirectAudioClient.play("hub/b.mp3", { fade_in = true })

		sliders.options_music_slider = 100
		DirectAudioClient.update(0.1)
		sliders.options_music_slider = 25
		DirectAudioClient.update(0.1)

		assert_equal(#streams, 2)
		assert_deep_equal(streams[2].gains, { 0.4, 0.8, 0.2 })
		assert_deep_equal(streams[1].gains, { 0.4, 0.8, 0.2 })
	end)

	it("calls on_finished once a track ends, after letting go of it, so the callback can play the next one", function()
		local DirectAudioClient, _, streams = load_client()
		local calls = 0
		DirectAudioClient.play("hub/a.mp3", {
			fade_in = true,
			on_finished = function()
				calls = calls + 1
				assert_equal(DirectAudioClient.is_playing(), false)
				DirectAudioClient.play("hub/b.mp3", { fade_in = false })
			end,
		})

		streams[1].is_ended = true
		DirectAudioClient.update(0.1)
		DirectAudioClient.update(0.1)

		assert_equal(calls, 1)
		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].path, "audio/hub/b.mp3")
	end)

	-- MusicReplacer.lua's quick-end guard reads elapsed() inside on_finished, so a song that played out must not look like a broken one.
	it("reports the finished track's elapsed time during on_finished", function()
		local DirectAudioClient, _, streams = load_client()
		local finished_after = nil
		DirectAudioClient.play("hub/a.mp3", {
			fade_in = true,
			on_finished = function() finished_after = DirectAudioClient.elapsed() end,
		})

		for _ = 1, 50 do
			DirectAudioClient.update(0.1)
		end
		streams[1].is_ended = true
		DirectAudioClient.update(0.1)

		assert_equal(math.abs(finished_after - 5.1) < 1e-9, true, tostring(finished_after))
	end)

	it("fades out 2 seconds before the file's own end when given a duration", function()
		local DirectAudioClient, _, streams = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = false, duration_seconds = 199 })

		streams[1].current_position = 197.5
		DirectAudioClient.update(0.1)
		assert_deep_equal(streams[1].fades, {})

		streams[1].current_position = 198.2
		DirectAudioClient.update(0.1)
		local fade = streams[1].fades[1]
		assert_equal(fade[1], 0)
		assert_equal(math.abs(fade[2] - 1.8) < 1e-9, true, tostring(fade[2]))
	end)

	it("does not fade out without a duration or while looping", function()
		local DirectAudioClient, _, streams = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = false })
		DirectAudioClient.play("hub/b.mp3", { fade_in = false, duration_seconds = 199, native_loop = true })

		streams[1].current_position = 199
		streams[2].current_position = 199
		DirectAudioClient.update(0.1)

		assert_deep_equal(streams[2].fades, {})
		assert_equal(streams[2].opts.loop, true)
	end)

	it("treats a file it cannot open as a track that ended at once", function()
		local DirectAudioClient, player, _, _, lines = load_client()
		player.refuse["audio/hub/a.ogg"] = true
		local finished_after = nil
		DirectAudioClient.play("hub/a.ogg", {
			fade_in = true,
			on_finished = function() finished_after = DirectAudioClient.elapsed() end,
		})

		DirectAudioClient.update(0.1)

		assert_equal(finished_after, 0.1)
		assert_equal(lines[1], "[direct] hub/a.ogg could not be played: unsupported format")
	end)

	it("fades out quickly on stop", function()
		local DirectAudioClient, _, streams = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = true })

		DirectAudioClient.stop()

		assert_equal(DirectAudioClient.is_playing(), false)
		assert_deep_equal(streams[1].fades[#streams[1].fades], { 0, 0.5 })

		DirectAudioClient.update(0.6)
		assert_equal(streams[1].destroyed, true)
	end)

	it("rebuilds the engine after a failure and resumes the song where it was", function()
		local DirectAudioClient, player, streams = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = true, duration_seconds = 199 })
		streams[1].current_position = 42
		streams[1].failed = "the voice stopped playing with audio queued"

		DirectAudioClient.update(0.1)

		assert_equal(player.resets, 1)
		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].path, "audio/hub/a.mp3")
		assert_equal(streams[2].opts.start_position, 42)
	end)

	it("gives up for the session after 3 recoveries in a row", function()
		local DirectAudioClient, _, streams, _, lines = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = true })

		for _ = 1, 4 do
			streams[#streams].failed = "lost"
			DirectAudioClient.update(0.1)
		end

		assert_equal(DirectAudioClient.available(), false)
		assert_equal(DirectAudioClient.is_playing(), false)
		assert_equal(lines[#lines]:find("gave up after 3 recoveries", 1, true) ~= nil, true, lines[#lines])
	end)

	it("stops everything at once on shutdown", function()
		local DirectAudioClient, player, streams = load_client()
		DirectAudioClient.play("hub/a.mp3", { fade_in = true })
		DirectAudioClient.play("hub/b.mp3", { fade_in = true })

		DirectAudioClient.shutdown()

		assert_equal(streams[1].destroyed, true)
		assert_equal(streams[2].destroyed, true)
		assert_equal(player.resets, 1)
	end)
end)
