-- The rooms the Reverb Room setting offers, and the parameters XAudio2's reverb takes for each.
-- The rooms are the I3DL2 presets in Microsoft's xaudio2fx.h, all but its silent default.
-- Reverb.native() ports that header's ReverbConvertI3DL2ToNative, which turns a preset into the reverb's own parameters.

local Reverb = {}

-- Each preset's I3DL2 values, in xaudio2fx.h's order.
-- Room, RoomHF, Reflections, and Reverb are in hundredths of a decibel, the decay and delays in seconds.
-- RoomRolloffFactor is left out, since the conversion ignores it.
local function preset(room, room_hf, decay_time, decay_hf_ratio, reflections, reflections_delay, reverb, reverb_delay, diffusion, density)
	return {
		room = room,
		room_hf = room_hf,
		decay_time = decay_time,
		decay_hf_ratio = decay_hf_ratio,
		reflections = reflections,
		reflections_delay = reflections_delay,
		reverb = reverb,
		reverb_delay = reverb_delay,
		diffusion = diffusion,
		density = density,
		hf_reference = 5000,
	}
end

-- In the order the setting lists them, from small rooms to large halls and outdoor places.
Reverb.ROOMS = {
	{ id = "padded_cell", values = preset(-1000, -6000, 0.17, 0.10, -1204, 0.001, 207, 0.002, 100, 100) },
	{ id = "room", values = preset(-1000, -454, 0.40, 0.83, -1646, 0.002, 53, 0.003, 100, 100) },
	{ id = "bathroom", values = preset(-1000, -1200, 1.49, 0.54, -370, 0.007, 1030, 0.011, 100, 60) },
	{ id = "living_room", values = preset(-1000, -6000, 0.50, 0.10, -1376, 0.003, -1104, 0.004, 100, 100) },
	{ id = "small_room", values = preset(-1000, -600, 1.10, 0.83, -400, 0.005, 500, 0.010, 100, 100) },
	{ id = "medium_room", values = preset(-1000, -600, 1.30, 0.83, -1000, 0.010, -200, 0.020, 100, 100) },
	{ id = "large_room", values = preset(-1000, -600, 1.50, 0.83, -1600, 0.020, -1000, 0.040, 100, 100) },
	{ id = "stone_room", values = preset(-1000, -300, 2.31, 0.64, -711, 0.012, 83, 0.017, 100, 100) },
	{ id = "carpeted_hallway", values = preset(-1000, -4000, 0.30, 0.10, -1831, 0.002, -1630, 0.030, 100, 100) },
	{ id = "hallway", values = preset(-1000, -300, 1.49, 0.59, -1219, 0.007, 441, 0.011, 100, 100) },
	{ id = "stone_corridor", values = preset(-1000, -237, 2.70, 0.79, -1214, 0.013, 395, 0.020, 100, 100) },
	{ id = "medium_hall", values = preset(-1000, -600, 1.80, 0.70, -1300, 0.015, -800, 0.030, 100, 100) },
	{ id = "large_hall", values = preset(-1000, -600, 1.80, 0.70, -2000, 0.030, -1400, 0.060, 100, 100) },
	{ id = "auditorium", values = preset(-1000, -476, 4.32, 0.59, -789, 0.020, -289, 0.030, 100, 100) },
	{ id = "concert_hall", values = preset(-1000, -500, 3.92, 0.70, -1230, 0.020, -2, 0.029, 100, 100) },
	{ id = "arena", values = preset(-1000, -698, 7.24, 0.33, -1166, 0.020, 16, 0.030, 100, 100) },
	{ id = "hangar", values = preset(-1000, -1000, 10.05, 0.23, -602, 0.020, 198, 0.030, 100, 100) },
	{ id = "cave", values = preset(-1000, 0, 2.91, 1.30, -602, 0.015, -302, 0.022, 100, 100) },
	{ id = "sewer_pipe", values = preset(-1000, -1000, 2.81, 0.14, 429, 0.014, 648, 0.021, 80, 60) },
	{ id = "underwater", values = preset(-1000, -4000, 1.49, 0.10, -449, 0.007, 1700, 0.011, 100, 100) },
	{ id = "alley", values = preset(-1000, -270, 1.49, 0.86, -1204, 0.007, -4, 0.011, 100, 100) },
	{ id = "parking_lot", values = preset(-1000, 0, 1.65, 1.50, -1363, 0.008, -1153, 0.012, 100, 100) },
	{ id = "city", values = preset(-1000, -800, 1.49, 0.67, -2273, 0.007, -2217, 0.011, 50, 100) },
	{ id = "forest", values = preset(-1000, -3300, 1.49, 0.54, -2560, 0.162, -613, 0.088, 79, 100) },
	{ id = "mountains", values = preset(-1000, -2500, 1.49, 0.21, -2780, 0.300, -2014, 0.100, 27, 100) },
	{ id = "quarry", values = preset(-1000, -1000, 1.49, 0.83, -10000, 0.061, 500, 0.025, 100, 100) },
	{ id = "plain", values = preset(-1000, -2000, 1.49, 0.50, -2466, 0.179, -2514, 0.100, 21, 100) },
	{ id = "plate", values = preset(-1000, -200, 1.30, 0.90, 0, 0.002, 0, 0.010, 100, 75) },
	{ id = "generic", values = preset(-1000, -100, 1.49, 0.83, -2602, 0.007, 200, 0.011, 100, 100) },
}

Reverb.DEFAULT_ROOM = "large_hall"

local rooms_by_id = {}
for _, room in ipairs(Reverb.ROOMS) do
	rooms_by_id[room.id] = room.values
end

-- The parameters the reverb takes that I3DL2 has no equivalent for, as xaudio2fx.h sets them.
-- The rear delay is the one for anything but 7.1 output, since the mod's effects play in stereo.
local REAR_DELAY = 5
local SIDE_DELAY = 5
local POSITION = 6
local POSITION_MATRIX = 27
local ROOM_SIZE = 100
local LOW_EQ_CUTOFF = 4
local HIGH_EQ_CUTOFF = 6
local MAX_REFLECTIONS_DELAY = 300
local MAX_REVERB_DELAY = 85
-- The range XAudio2's reverb takes for the loudness of its reflections and of its tail, in decibels.
local MIN_GAIN = -100
local MAX_GAIN = 20

-- C's conversion of a float to an integer, which drops the fraction toward 0.
local function truncate(number)
	return number < 0 and math.ceil(number) or math.floor(number)
end

local function clamp_gain(decibels)
	return math.max(MIN_GAIN, math.min(MAX_GAIN, decibels))
end

-- The parameters for XAudio2's reverb in room `room_id`, with `mix` percent of the reverb heard in place of the dry music.
-- `strength` raises or lowers the room's reflections and tail by that many decibels, within the range the reverb takes.
-- An unknown room plays as Reverb.DEFAULT_ROOM, so a stored value the dropdown no longer offers still plays a room.
-- The fields are XAUDIO2FX_REVERB_PARAMETERS', for xaudio.lua to copy.
function Reverb.native(room_id, mix, strength)
	local i3dl2 = rooms_by_id[room_id] or rooms_by_id[Reverb.DEFAULT_ROOM]
	local native = {
		RearDelay = REAR_DELAY,
		SideDelay = SIDE_DELAY,
		PositionLeft = POSITION,
		PositionRight = POSITION,
		PositionMatrixLeft = POSITION_MATRIX,
		PositionMatrixRight = POSITION_MATRIX,
		RoomSize = ROOM_SIZE,
		LowEQCutoff = LOW_EQ_CUTOFF,
		HighEQCutoff = HIGH_EQ_CUTOFF,
		RoomFilterMain = i3dl2.room / 100,
		RoomFilterHF = i3dl2.room_hf / 100,
	}

	if i3dl2.decay_hf_ratio >= 1 then
		local index = math.max(-8, truncate(-4 * math.log10(i3dl2.decay_hf_ratio)))
		native.LowEQGain = index < 0 and index + 8 or 8
		native.HighEQGain = 8
		native.DecayTime = i3dl2.decay_time * i3dl2.decay_hf_ratio
	else
		local index = math.max(-8, truncate(4 * math.log10(i3dl2.decay_hf_ratio)))
		native.LowEQGain = 8
		native.HighEQGain = index < 0 and index + 8 or 8
		native.DecayTime = i3dl2.decay_time
	end

	local reflections_delay = i3dl2.reflections_delay * 1000
	if reflections_delay >= MAX_REFLECTIONS_DELAY then
		reflections_delay = MAX_REFLECTIONS_DELAY - 1
	elseif reflections_delay <= 1 then
		reflections_delay = 1
	end
	native.ReflectionsDelay = truncate(reflections_delay)

	local reverb_delay = i3dl2.reverb_delay * 1000
	if reverb_delay >= MAX_REVERB_DELAY then
		reverb_delay = MAX_REVERB_DELAY - 1
	end
	native.ReverbDelay = truncate(reverb_delay)

	native.ReflectionsGain = clamp_gain(i3dl2.reflections / 100 + strength)
	native.ReverbGain = clamp_gain(i3dl2.reverb / 100 + strength)
	native.EarlyDiffusion = truncate(15 * i3dl2.diffusion / 100)
	native.LateDiffusion = native.EarlyDiffusion
	native.Density = i3dl2.density
	native.RoomFilterFreq = i3dl2.hf_reference
	native.WetDryMix = math.max(0, math.min(100, mix))
	native.DisableLateField = 0

	return native
end

return Reverb
