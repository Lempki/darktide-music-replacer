-- Pins player.lua's own logic with fake decoders and voices: the buffer pool, refills, ends, loops, fades, and stalls.
-- The Windows calls underneath are checked outside the specs with tools/player_demo.lua.

local FakeEngine = require("tests.helpers.fake_engine")

local BYTES_PER_SECOND = 4000 -- A tiny format, so a quarter-second buffer is 1000 bytes.
local SLOT_BYTES = 1000
local POOL = 100000 -- The fake pool's address.

-- A fake decoder holding `seconds` of audio.
local function new_decoder(seconds)
	local decoder = {
		format = { nAvgBytesPerSec = BYTES_PER_SECOND, nBlockAlign = 4, nSamplesPerSec = 1000 },
		duration = seconds,
		remaining = seconds * BYTES_PER_SECOND,
		seeks = {},
		closed = false,
	}

	function decoder.read_into(self, _, capacity)
		local bytes = math.min(capacity, self.remaining)
		self.remaining = self.remaining - bytes
		return bytes
	end
	function decoder.at_end(self) return self.remaining == 0 end
	function decoder.seek(self, position)
		self.seeks[#self.seeks + 1] = position
		if self.refuse_seek then
			return false
		end
		self.remaining = (self.duration - position) * BYTES_PER_SECOND
		return true
	end
	function decoder.close(self) self.closed = true end

	return decoder
end

-- A fake voice whose queue only drains when the spec calls voice:play(buffers).
local function new_voice()
	local voice = { submitted = {}, volumes = {}, queue = 0, played = 0, started = false, destroyed = false }

	function voice.queued(self) return self.queue end
	function voice.samples_played(self) return self.played end
	function voice.submit(self, data, bytes, last)
		if self.refuse_submit then
			return false
		end
		self.submitted[#self.submitted + 1] = { data = data, bytes = bytes, last = last }
		self.queue = self.queue + 1
		return true
	end
	function voice.set_volume(self, volume) self.volumes[#self.volumes + 1] = volume end
	function voice.start(self) self.started = true end
	function voice.destroy(self) self.destroyed = true end
	function voice.play(self, buffers)
		self.queue = math.max(0, self.queue - buffers)
		self.played = self.played + buffers * 250
	end

	return voice
end

-- Returns player.lua initialized with fakes, and the fakes: the decoder `seconds` long, the voice, and freed pools.
-- `voice_error`, if given, makes XAudio2 refuse the voice with that error.
local function load_player(seconds, voice_error)
	local engine = FakeEngine.new()
	local Player = engine:load("player")
	local decoder = new_decoder(seconds)
	local voice = new_voice()
	local freed = {}

	Player.init(
		{ alloc = function() return POOL end, free = function(memory) freed[#freed + 1] = memory end },
		{ open = function() return decoder end, available = function() return true end, error = function() return nil end },
		{
			create_voice = function()
				if voice_error then
					return nil, voice_error
				end
				return voice
			end,
			failure = function() return nil end,
			available = function() return true end,
		}
	)

	return Player, decoder, voice, freed
end

describe("player.lua", function()
	it("queues two buffers and starts at once, and holds a 16-buffer pool until destroyed", function()
		local Player, decoder, voice, freed = load_player(60)

		local stream = Player.open("a.mp3")

		assert_equal(#voice.submitted, 2)
		assert_equal(voice.started, true)
		assert_equal(Player.pool_bytes(), 16 * SLOT_BYTES)

		stream:destroy()

		assert_equal(voice.destroyed, true)
		assert_equal(decoder.closed, true)
		assert_deep_equal(freed, { POOL })
		assert_equal(Player.pool_bytes(), 0)
	end)

	it("says when XAudio2 refused the voice, and frees what it had opened", function()
		local Player, decoder, _, freed = load_player(60, "creating a voice failed with 0x88960001")

		assert_deep_equal({ Player.open("a.mp3") }, { nil, "creating a voice failed with 0x88960001", true })
		assert_equal(decoder.closed, true)
		assert_deep_equal(freed, { POOL })
		assert_equal(Player.pool_bytes(), 0)
	end)

	it("refills at most two buffers per update, and never queues more than the pool holds", function()
		local Player, _, voice = load_player(60)
		local stream = Player.open("a.mp3")

		stream:update(0.016)
		assert_equal(voice.queue, 4)

		for _ = 1, 20 do
			stream:update(0.016)
		end
		assert_equal(voice.queue, 16)
	end)

	it("writes each buffer to the next slot of the pool, wrapping around", function()
		local Player, _, voice = load_player(60)
		local stream = Player.open("a.mp3")
		for _ = 1, 7 do
			stream:update(0.016)
		end

		voice:play(1)
		stream:update(0.016)

		assert_equal(voice.submitted[16].data, POOL + 15 * SLOT_BYTES)
		assert_equal(voice.submitted[17].data, POOL)
	end)

	it("stops a looping file that decodes to no audio, as the file's own failure, instead of seeking forever", function()
		local Player, decoder, voice = load_player(0)
		local stream = Player.open("silent.mp3", { loop = true })

		assert_equal(stream:file_failure(), "it decodes to no audio")
		assert_equal(stream:failure(), nil)
		assert_equal(#voice.submitted, 0)

		stream:update(0.016)
		assert_equal(#decoder.seeks, 1)
	end)

	it("stops a looping file that cannot go back to its start, as the file's own failure", function()
		local Player, decoder = load_player(0.5)
		decoder.refuse_seek = true
		local stream = Player.open("a.mp3", { loop = true })

		stream:update(0.016)

		assert_equal(stream:file_failure(), "it could not go back to its start to loop")
		assert_equal(stream:failure(), nil)
	end)

	it("keeps looping a file shorter than one buffer", function()
		local Player, decoder, voice = load_player(0.1)
		local stream = Player.open("short.mp3", { loop = true })

		for _ = 1, 10 do
			voice:play(2)
			stream:update(0.016)
		end

		assert_equal(stream:file_failure(), nil)
		assert_equal(#decoder.seeks > 5, true)
	end)

	it("marks the file's last buffer, and ends once it has played", function()
		local Player, _, voice = load_player(1)
		local stream = Player.open("a.mp3")
		stream:update(0.016)

		assert_equal(#voice.submitted, 4)
		assert_equal(voice.submitted[4].last, true)
		assert_equal(stream:ended(), false)

		voice:play(4)

		assert_equal(stream:ended(), true)
	end)

	it("loops back to the file's start without ever marking a last buffer", function()
		local Player, decoder, voice = load_player(1)
		local stream = Player.open("a.mp3", { loop = true })

		for _ = 1, 4 do
			voice:play(2)
			stream:update(0.016)
		end

		assert_deep_equal(decoder.seeks, { 0, 0 })
		for _, buffer in ipairs(voice.submitted) do
			assert_equal(buffer.last, false)
		end
		assert_equal(stream:ended(), false)
	end)

	it("starts partway in, and reports positions from there", function()
		local Player, decoder, voice = load_player(60)
		local stream = Player.open("a.mp3", { start_position = 30 })

		voice:play(2)

		assert_deep_equal(decoder.seeks, { 30 })
		assert_equal(stream:position(), 30.5)
	end)

	it("sets the voice to gain times fade, and fades on an equal-power curve", function()
		local Player, _, voice = load_player(60)
		local stream = Player.open("a.mp3", { gain = 0.5, fade = 0 })

		stream:fade_to(1, 2)
		stream:update(1)

		assert_equal(math.abs(voice.volumes[#voice.volumes] - 0.5 * math.sqrt(0.5)) < 1e-9, true, tostring(voice.volumes[#voice.volumes]))

		stream:update(1)
		stream:set_gain(0.25)

		assert_equal(voice.volumes[#voice.volumes], 0.25)
		assert_equal(stream:fading(), false)
	end)

	it("counts an underrun when the queue ran dry before the file's end", function()
		local Player, _, voice = load_player(60)
		local stream = Player.open("a.mp3")

		voice:play(2)
		stream:update(0.016)

		assert_equal(stream.underruns, 1)
	end)

	it("neither refills nor counts a stall while paused, and plays on after resuming", function()
		local Player, _, voice = load_player(60)
		local stream = Player.open("a.mp3")
		local stops = 0
		function voice.stop() stops = stops + 1 end

		stream:pause()
		for _ = 1, 30 do
			stream:update(0.1)
		end

		assert_equal(stops, 1)
		assert_equal(#voice.submitted, 2)
		assert_equal(stream:failure(), nil)

		stream:resume()
		stream:update(0.1)

		assert_equal(stream:is_paused(), false)
		assert_equal(#voice.submitted, 4)
	end)

	it("reports a failure when queued audio stops playing for 2 seconds", function()
		local Player, _, voice = load_player(60)
		local stream = Player.open("a.mp3")

		for _ = 1, 10 do
			voice:play(1)
			stream:update(0.1)
		end
		assert_equal(stream:failure(), nil)

		for _ = 1, 21 do
			stream:update(0.1)
		end

		assert_equal(stream:failure(), "the voice stopped playing with audio queued")
	end)

	it("reports a failure when XAudio2 refuses a buffer", function()
		local Player, _, voice = load_player(60)
		local stream = Player.open("a.mp3")

		voice.refuse_submit = true
		stream:update(0.016)

		assert_equal(stream:failure(), "XAudio2 refused a buffer")
	end)

	it("wraps a looping stream's position back into the file", function()
		local Player, _, voice = load_player(1)
		local stream = Player.open("a.mp3", { loop = true })

		voice:play(6)

		assert_equal(stream:position(), 0.5)
	end)

	it("finishes a fade at once after a frame gap longer than the fade", function()
		local Player = load_player(60)
		local stream = Player.open("a.mp3", { fade = 1 })

		stream:fade_to(0, 2)
		stream:update(1000)

		assert_equal(stream.fade, 0)
		assert_equal(stream:fading(), false)
	end)

	it("frees everything once when destroyed twice", function()
		local Player, _, _, freed = load_player(60)
		local stream = Player.open("a.mp3")

		stream:destroy()
		stream:destroy()

		assert_deep_equal(freed, { POOL })
		assert_equal(Player.pool_bytes(), 0)
	end)
end)
