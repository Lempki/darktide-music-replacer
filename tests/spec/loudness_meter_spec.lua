-- Pins loudness_meter.lua against the test signals of EBU Tech 3341, which any BS.1770 meter must measure to within 0.1 LU.

local ffi = require("ffi")
local FakeEngine = require("tests.helpers.fake_engine")

local function load_meter()
	return FakeEngine.new():load("loudness_meter")
end

-- Feeds a 1 kHz sine to `meter`, at `dbfs` peak level in every channel, for `seconds`, a second at a time as 16-bit samples.
local function add_sine(meter, sample_rate, channels, dbfs, seconds)
	local amplitude = 10 ^ (dbfs / 20)
	local chunk_frames = sample_rate
	local samples = ffi.new("int16_t[?]", chunk_frames * channels)
	local total_frames = math.floor(seconds * sample_rate + 0.5)
	local written = 0

	while written < total_frames do
		local frames = math.min(chunk_frames, total_frames - written)
		for frame = 0, frames - 1 do
			local value = math.floor(amplitude * math.sin(2 * math.pi * 1000 * (written + frame) / sample_rate) * 32767 + 0.5)
			for channel = 0, channels - 1 do
				samples[frame * channels + channel] = value
			end
		end
		meter:add(samples, frames)
		written = written + frames
	end
end

-- Measures a sequence of { dbfs, seconds } sine segments.
local function measure(segments, sample_rate, channels)
	local LoudnessMeter = load_meter()
	local meter = LoudnessMeter.new(sample_rate or 48000, channels or 2)
	for _, segment in ipairs(segments) do
		add_sine(meter, sample_rate or 48000, channels or 2, segment[1], segment[2])
	end
	return meter
end

local function assert_near(actual, expected, tolerance)
	assert_equal(actual ~= nil and math.abs(actual - expected) <= tolerance, true,
		string.format("expected %s within %s of %s", tostring(actual), tolerance, expected))
end

describe("loudness_meter.lua", function()
	it("uses BS.1770's own filter coefficients at 48 kHz", function()
		local LoudnessMeter = load_meter()
		local meter = LoudnessMeter.new(48000, 2)

		assert_near(meter.shelf.b0, 1.53512485958697, 1e-9)
		assert_near(meter.shelf.b1, -2.69169618940638, 1e-9)
		assert_near(meter.shelf.b2, 1.19839281085285, 1e-9)
		assert_near(meter.shelf.a1, -1.69065929318241, 1e-9)
		assert_near(meter.shelf.a2, 0.73248077421585, 1e-9)
		assert_near(meter.high_pass.a1, -1.99004745483398, 1e-9)
		assert_near(meter.high_pass.a2, 0.99007225036621, 1e-9)
	end)

	it("measures a stereo 1 kHz sine at -23 dBFS as -23 LUFS", function()
		assert_near(measure({ { -23, 20 } }):loudness(), -23, 0.1)
	end)

	it("measures a stereo 1 kHz sine at -33 dBFS as -33 LUFS", function()
		assert_near(measure({ { -33, 20 } }):loudness(), -33, 0.1)
	end)

	it("measures the same at 44.1 kHz as at 48 kHz", function()
		assert_near(measure({ { -23, 20 } }, 44100):loudness(), -23, 0.1)
	end)

	it("leaves quiet passages out through the relative gate", function()
		assert_near(measure({ { -36, 10 }, { -23, 60 }, { -36, 10 } }):loudness(), -23, 0.1)
	end)

	it("leaves near silence out through the absolute gate", function()
		assert_near(measure({ { -72, 10 }, { -36, 10 }, { -23, 60 }, { -36, 10 }, { -72, 10 } }):loudness(), -23, 0.1)
	end)

	it("averages the passages that pass both gates", function()
		assert_near(measure({ { -26, 20 }, { -20, 20.1 }, { -26, 20 } }):loudness(), -23, 0.1)
	end)

	it("measures a mono song as it plays, on both speakers at full level", function()
		assert_near(measure({ { -23, 20 } }, 48000, 1):loudness(), -23, 0.1)
	end)

	it("weighs quad and 7.1 by their speakers, with no weight on the LFE channel", function()
		-- The same sine in every channel adds each channel's weight to the stereo pair's 2.
		assert_near(measure({ { -23, 20 } }, 48000, 4):loudness(), -23 + 10 * math.log10(4.82 / 2), 0.1)
		assert_near(measure({ { -23, 20 } }, 48000, 8):loudness(), -23 + 10 * math.log10(7.82 / 2), 0.1)
	end)

	it("reports no loudness for silence or audio shorter than one block, and the highest sample as the peak", function()
		assert_equal(measure({ { -200, 5 } }):loudness(), nil)
		assert_equal(measure({ { -23, 0.3 } }):loudness(), nil)
		assert_near(measure({ { -6, 1 } }):peak(), 10 ^ (-6 / 20), 0.001)
	end)
end)

describe("loudness_meter.lua levels", function()
	it("lowers a loud song and raises a quiet one to the target", function()
		local LoudnessMeter = load_meter()

		assert_near(LoudnessMeter.level(-8, 1, -14), 10 ^ (-6 / 20), 1e-9)
		assert_near(LoudnessMeter.level(-20, 0.25, -14), 10 ^ (6 / 20), 1e-9)
	end)

	it("raises a quiet song only until its highest sample reaches full scale", function()
		local LoudnessMeter = load_meter()

		assert_near(LoudnessMeter.level(-26, 0.5, -14), 2, 1e-9)
	end)

	it("raises a quiet song by at most the given boost", function()
		local LoudnessMeter = load_meter()

		assert_near(LoudnessMeter.level(-40, 0.01, -14, 12), 10 ^ (12 / 20), 1e-9)
		assert_near(LoudnessMeter.level(-8, 1, -14, 12), 10 ^ (-6 / 20), 1e-9)
	end)

	it("keeps the level of a song with no measurable loudness", function()
		assert_equal(load_meter().level(nil, 0, -14), 1)
	end)
end)
