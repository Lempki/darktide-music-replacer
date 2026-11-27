-- Pins reverb.lua's port of ReverbConvertI3DL2ToNative from Microsoft's xaudio2fx.h, against values worked out by hand from that function.
-- The port leaves out the presets' room level, so RoomFilterMain is always 0 dB.

local FakeEngine = require("tests.helpers.fake_engine")

local function load_reverb()
	return FakeEngine.new():load("modules/playback/reverb")
end

-- The fields every room gets the same, since I3DL2 has no equivalent for them.
local FIXED = {
	RearDelay = 5,
	SideDelay = 5,
	PositionLeft = 6,
	PositionRight = 6,
	PositionMatrixLeft = 27,
	PositionMatrixRight = 27,
	RoomSize = 100,
	LowEQCutoff = 4,
	HighEQCutoff = 6,
	DisableLateField = 0,
}

local function with_fixed(fields)
	for field, value in pairs(FIXED) do
		fields[field] = value
	end
	return fields
end

local function assert_near(actual, expected, field)
	assert_equal(math.abs(actual - expected) < 1e-9, true, string.format("%s: %s, expected %s", field, tostring(actual), tostring(expected)))
end

local function assert_parameters(actual, expected)
	for field, value in pairs(expected) do
		assert_near(actual[field], value, field)
	end
	for field in pairs(actual) do
		assert_equal(expected[field] ~= nil, true, "unexpected field " .. field)
	end
end

describe("reverb.lua", function()
	it("converts Large Hall as Microsoft's ReverbConvertI3DL2ToNative does, but without its room level", function()
		local Reverb = load_reverb()

		assert_parameters(Reverb.native("large_hall", { mix = 30, strength = 0 }), with_fixed({
			WetDryMix = 30,
			RoomFilterMain = 0,
			RoomFilterHF = -6,
			LowEQGain = 8,
			HighEQGain = 8,
			DecayTime = 1.8,
			ReflectionsDelay = 30,
			ReverbDelay = 60,
			ReflectionsGain = -20,
			ReverbGain = -14,
			EarlyDiffusion = 15,
			LateDiffusion = 15,
			Density = 100,
			RoomFilterFreq = 5000,
		}))
	end)

	it("lowers the high EQ for a room whose highs die out early, as Padded Cell's do", function()
		local native = load_reverb().native("padded_cell", { mix = 50, strength = 0 })

		assert_equal(native.HighEQGain, 4)
		assert_equal(native.LowEQGain, 8)
		assert_equal(native.ReflectionsDelay, 1)
		assert_equal(native.ReverbDelay, 2)
		assert_near(native.DecayTime, 0.17, "DecayTime")
	end)

	it("stretches the decay of a room whose highs last longer than its lows, as Cave's do", function()
		local native = load_reverb().native("cave", { mix = 50, strength = 0 })

		assert_equal(native.LowEQGain, 8)
		assert_equal(native.HighEQGain, 8)
		assert_near(native.DecayTime, 2.91 * 1.3, "DecayTime")
	end)

	it("cuts the high EQ in steps, as Hangar's and Sewer Pipe's ratios give", function()
		local Reverb = load_reverb()

		assert_equal(Reverb.native("hangar", { mix = 50, strength = 0 }).HighEQGain, 6)
		assert_equal(Reverb.native("sewer_pipe", { mix = 50, strength = 0 }).HighEQGain, 5)
	end)

	it("keeps the delays below their limits and the diffusion whole, as Mountains needs", function()
		local native = load_reverb().native("mountains", { mix = 50, strength = 0 })

		assert_equal(native.ReflectionsDelay, 299)
		assert_equal(native.ReverbDelay, 84)
		assert_equal(native.EarlyDiffusion, 4)
	end)

	it("plays an unknown room as Large Hall, and keeps the mix between 0 and 100", function()
		local Reverb = load_reverb()

		assert_parameters(Reverb.native("ballroom", { mix = 30, strength = 0 }), Reverb.native("large_hall", { mix = 30, strength = 0 }))
		assert_equal(Reverb.native("cave", { mix = 150, strength = 0 }).WetDryMix, 100)
		assert_equal(Reverb.native("cave", { mix = -5, strength = 0 }).WetDryMix, 0)
	end)

	it("raises or lowers the reflections and the tail by the strength, and leaves the rest of the room as it is", function()
		local Reverb = load_reverb()
		local plain = Reverb.native("large_hall", { mix = 30, strength = 0 })
		local stronger = Reverb.native("large_hall", { mix = 30, strength = 10 })

		assert_near(stronger.ReflectionsGain, -10, "ReflectionsGain")
		assert_near(stronger.ReverbGain, -4, "ReverbGain")
		stronger.ReflectionsGain, stronger.ReverbGain = plain.ReflectionsGain, plain.ReverbGain
		assert_parameters(stronger, plain)
	end)

	it("gives every room its whole reverb at 0 dB, since Reverb Mix sets how much of it plays", function()
		for _, room in ipairs(load_reverb().ROOMS) do
			assert_equal(load_reverb().native(room.id, { mix = 30 }).RoomFilterMain, 0, room.id)
		end
	end)

	it("stretches or shortens the room's decay by the decay percent, and plays it as it is by default", function()
		local Reverb = load_reverb()

		assert_near(Reverb.native("concert_hall", { mix = 30 }).DecayTime, 3.92, "DecayTime")
		assert_near(Reverb.native("concert_hall", { mix = 30, decay = 200 }).DecayTime, 7.84, "DecayTime")
		assert_near(Reverb.native("concert_hall", { mix = 30, decay = 25 }).DecayTime, 0.98, "DecayTime")
	end)

	it("keeps a shortened decay at the reverb's shortest, 0.1 seconds", function()
		assert_equal(load_reverb().native("padded_cell", { mix = 30, decay = 25 }).DecayTime, 0.1)
	end)

	it("adds the pre-delay to the room's own delay before the first reflection, within the 300 ms the reverb takes", function()
		local Reverb = load_reverb()

		assert_equal(Reverb.native("large_hall", { mix = 30, pre_delay = 50 }).ReflectionsDelay, 80)
		assert_equal(Reverb.native("arena", { mix = 30, pre_delay = 200 }).ReflectionsDelay, 220)
		assert_equal(Reverb.native("plain", { mix = 30, pre_delay = 200 }).ReflectionsDelay, 299)
	end)

	it("fades the tail's highs faster by the damping, or more slowly with a negative one, from the room's own", function()
		local Reverb = load_reverb()

		assert_equal(Reverb.native("hangar", { mix = 30 }).HighEQGain, 6)
		assert_equal(Reverb.native("hangar", { mix = 30, damping = 2 }).HighEQGain, 4)
		assert_equal(Reverb.native("hangar", { mix = 30, damping = -1 }).HighEQGain, 7)
		assert_equal(Reverb.native("large_hall", { mix = 30, damping = 3 }).HighEQGain, 5)
	end)

	it("keeps a damped room within the steps the reverb takes, from 0 to 8", function()
		local Reverb = load_reverb()

		assert_equal(Reverb.native("hangar", { mix = 30, damping = -8 }).HighEQGain, 8)
		assert_equal(Reverb.native("sewer_pipe", { mix = 30, damping = 8 }).HighEQGain, 0)
	end)

	it("keeps a strengthened or weakened room within the loudness the reverb takes", function()
		local Reverb = load_reverb()

		assert_equal(Reverb.native("underwater", { mix = 30, strength = 20 }).ReverbGain, 20)
		assert_equal(Reverb.native("quarry", { mix = 30, strength = -20 }).ReflectionsGain, -100)
	end)

	it("gives every room parameters within the ranges XAudio2's reverb takes, at any strength", function()
		local Reverb = load_reverb()

		for _, room in ipairs(Reverb.ROOMS) do
			for _, strength in ipairs({ -20, 0, 20 }) do
				local native = Reverb.native(room.id, { mix = 100, strength = strength, decay = 25, pre_delay = 200, damping = strength * 0.4 })
				local function within(field, low, high)
					assert_equal(native[field] >= low and native[field] <= high, true,
						string.format("%s at %d dB, %s: %s", room.id, strength, field, tostring(native[field])))
				end
				within("ReflectionsDelay", 0, 300)
				within("ReverbDelay", 0, 85)
				within("EarlyDiffusion", 0, 15)
				within("LateDiffusion", 0, 15)
				within("LowEQGain", 0, 12)
				within("HighEQGain", 0, 8)
				within("RoomFilterMain", -100, 0)
				within("RoomFilterHF", -100, 0)
				within("ReflectionsGain", -100, 20)
				within("ReverbGain", -100, 20)
				within("Density", 0, 100)
				assert_equal(native.DecayTime >= 0.1, true, room.id .. " DecayTime")
			end
		end
	end)

	it("offers Large Hall by default, and every room once", function()
		local Reverb = load_reverb()
		local seen = {}

		for _, room in ipairs(Reverb.ROOMS) do
			assert_equal(seen[room.id], nil, room.id)
			seen[room.id] = true
		end

		assert_equal(seen[Reverb.DEFAULT_ROOM], true)
		assert_equal(#Reverb.ROOMS, 29)
	end)
end)
