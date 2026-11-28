-- Pins what xaudio.lua does before XAudio2 itself is loaded, which tests can reach without Windows.

local XAUDIO_FILE = package.searchpath("scripts/mods/MusicReplacer/modules/windows/xaudio", package.path)

-- An xaudio.lua whose ffi fails any use, as LuaJIT does for a C structure that is not defined yet.
local function load_unloaded_xaudio()
	local XAudio = dofile(XAUDIO_FILE)
	local ffi = setmetatable({}, {
		__index = function(_, name)
			error("ffi." .. name .. " used before XAudio2 was loaded")
		end,
	})
	XAudio.init({ ffi = ffi })
	return XAudio
end

describe("xaudio.lua before XAudio2 is loaded", function()
	it("keeps the reverb, EQ, and echo it is given without touching the ffi, as the mod's startup does", function()
		local XAudio = load_unloaded_xaudio()

		assert_equal(XAudio.set_reverb(1, { WetDryMix = 30 }), true)
		assert_equal(XAudio.set_eq(2, { Gain0 = 1 }), true)
		assert_equal(XAudio.set_echo(3, { Delay = 500 }), true)
	end)
end)
