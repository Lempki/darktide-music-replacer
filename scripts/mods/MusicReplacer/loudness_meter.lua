-- Measures a song's loudness from 16-bit PCM the way ITU-R BS.1770 and EBU R128 define it, in LUFS.
-- Streaming services and broadcasters use the same measure, so a target level means the same here as there.
-- Its filter weighs frequencies roughly the way hearing does, and its gates leave silence and quiet passages out of the average.

local LoudnessMeter = {}
LoudnessMeter.__index = LoudnessMeter

-- The gating blocks are 400 ms long and start every 100 ms, so they are built from 100 ms parts.
local PART_SECONDS = 0.1
local PARTS_PER_BLOCK = 4

local ABSOLUTE_GATE_LUFS = -70
local RELATIVE_GATE_LU = -10

-- Channel weights in WAVE order: left, right, center, LFE, then the surrounds. The LFE channel does not count.
local CHANNEL_WEIGHTS = { 1, 1, 1, 0, 1.41, 1.41 }

local function lufs_of(power)
	return -0.691 + 10 * math.log10(power)
end

local function power_of(lufs)
	return 10 ^ ((lufs + 0.691) / 10)
end

-- The two filter stages for `sample_rate`, from the analog design behind BS.1770's 48 kHz coefficients, so every rate measures alike.
-- The first is a shelf of about +4 dB above 1.5 kHz, for the head's effect, and the second a high pass at about 38 Hz.
local function k_weighting(sample_rate)
	local k = math.tan(math.pi * 1681.974450955533 / sample_rate)
	local q = 0.7071752369554196
	local vh = 10 ^ (3.999843853973347 / 20)
	local vb = vh ^ 0.4996667741545416
	local a0 = 1 + k / q + k * k
	local shelf = {
		b0 = (vh + vb * k / q + k * k) / a0,
		b1 = 2 * (k * k - vh) / a0,
		b2 = (vh - vb * k / q + k * k) / a0,
		a1 = 2 * (k * k - 1) / a0,
		a2 = (1 - k / q + k * k) / a0,
	}

	k = math.tan(math.pi * 38.13547087602444 / sample_rate)
	q = 0.5003270373238773
	a0 = 1 + k / q + k * k
	local high_pass = { a1 = 2 * (k * k - 1) / a0, a2 = (1 - k / q + k * k) / a0 }

	return shelf, high_pass
end

function LoudnessMeter.new(sample_rate, channels)
	local shelf, high_pass = k_weighting(sample_rate)
	local self = setmetatable({
		channels = channels,
		shelf = shelf,
		high_pass = high_pass,
		weights = {},
		-- Each channel's filter memory: two values per stage.
		shelf_1 = {},
		shelf_2 = {},
		high_pass_1 = {},
		high_pass_2 = {},
		part_frames = math.floor(sample_rate * PART_SECONDS + 0.5),
		frames_in_part = 0,
		part_sum = 0,
		part_powers = {},
		peak_sample = 0,
	}, LoudnessMeter)

	for channel = 1, channels do
		self.weights[channel] = CHANNEL_WEIGHTS[channel] or 1
		self.shelf_1[channel] = 0
		self.shelf_2[channel] = 0
		self.high_pass_1[channel] = 0
		self.high_pass_2[channel] = 0
	end

	return self
end

-- Adds `frames` frames of interleaved 16-bit samples, read from `samples`, an int16_t pointer.
function LoudnessMeter:add(samples, frames)
	local channels = self.channels
	local weights = self.weights
	local shelf_1, shelf_2 = self.shelf_1, self.shelf_2
	local high_pass_1, high_pass_2 = self.high_pass_1, self.high_pass_2
	local sb0, sb1, sb2, sa1, sa2 = self.shelf.b0, self.shelf.b1, self.shelf.b2, self.shelf.a1, self.shelf.a2
	local ha1, ha2 = self.high_pass.a1, self.high_pass.a2
	local part_frames = self.part_frames
	local part_powers = self.part_powers
	local frames_in_part = self.frames_in_part
	local part_sum = self.part_sum
	local peak_sample = self.peak_sample

	local index = 0
	for _ = 1, frames do
		for channel = 1, channels do
			local sample = samples[index]
			index = index + 1

			if sample > peak_sample then
				peak_sample = sample
			elseif -sample > peak_sample then
				peak_sample = -sample
			end

			-- Both stages in transposed direct form II. The high pass's numerator is 1, -2, 1 at every rate.
			local x = sample / 32768
			local y = sb0 * x + shelf_1[channel]
			shelf_1[channel] = sb1 * x - sa1 * y + shelf_2[channel]
			shelf_2[channel] = sb2 * x - sa2 * y
			local z = y + high_pass_1[channel]
			high_pass_1[channel] = -2 * y - ha1 * z + high_pass_2[channel]
			high_pass_2[channel] = y - ha2 * z

			part_sum = part_sum + weights[channel] * z * z
		end

		frames_in_part = frames_in_part + 1
		if frames_in_part == part_frames then
			part_powers[#part_powers + 1] = part_sum / part_frames
			frames_in_part = 0
			part_sum = 0
		end
	end

	self.frames_in_part = frames_in_part
	self.part_sum = part_sum
	self.peak_sample = peak_sample
end

-- The integrated loudness in LUFS, or nil for audio that is silent or shorter than one 400 ms block.
function LoudnessMeter:loudness()
	local part_powers = self.part_powers
	local absolute_gate = power_of(ABSOLUTE_GATE_LUFS)
	local blocks = {}
	local total = 0

	for first = 1, #part_powers - PARTS_PER_BLOCK + 1 do
		local power = 0
		for part = first, first + PARTS_PER_BLOCK - 1 do
			power = power + part_powers[part]
		end
		power = power / PARTS_PER_BLOCK

		if power > absolute_gate then
			blocks[#blocks + 1] = power
			total = total + power
		end
	end

	if #blocks == 0 then
		return nil
	end

	local relative_gate = total / #blocks * 10 ^ (RELATIVE_GATE_LU / 10)
	local gated_total = 0
	local gated_count = 0

	for _, power in ipairs(blocks) do
		if power > relative_gate then
			gated_total = gated_total + power
			gated_count = gated_count + 1
		end
	end

	return lufs_of(gated_total / gated_count)
end

-- The highest sample, as a share of full scale from 0 to 1.
function LoudnessMeter:peak()
	return self.peak_sample / 32768
end

-- The volume scale that brings a song at `loudness` LUFS to `target` LUFS.
-- A quiet song is only raised until its highest sample reaches full scale, since anything above would clip.
-- A song with no measurable loudness keeps its own level.
function LoudnessMeter.level(loudness, peak, target)
	if not loudness then
		return 1
	end

	local level = 10 ^ ((target - loudness) / 20)
	if peak and peak > 0 and level * peak > 1 then
		level = 1 / peak
	end

	return level
end

return LoudnessMeter
