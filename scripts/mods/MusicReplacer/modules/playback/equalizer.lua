-- The bands the EQ settings raise or lower, and the parameters XAPOFX's EQ takes for them.
-- The EQ has four bands, and each band's center frequency and bandwidth stay at the defaults in Microsoft's xapofx.h.
-- So each setting only sets its band's gain.

local Equalizer = {}

-- In the order the settings list them, from the lowest frequencies to the highest.
-- Each frequency is the band's center, in Hz.
Equalizer.BANDS = {
	{ id = "eq_bass", frequency = 100 },
	{ id = "eq_low_mids", frequency = 800 },
	{ id = "eq_high_mids", frequency = 2000 },
	{ id = "eq_treble", frequency = 10000 },
}

-- The gains the EQ takes, as amplitude ratios, which are about -18 and +18 dB.
local MIN_GAIN = 0.126
local MAX_GAIN = 7.94

-- xapofx.h's default bandwidth, which every band keeps.
local BANDWIDTH = 1

-- The fields of FXEQ_PARAMETERS for `gains`, which holds each band's gain in decibels under the band's id.
-- A band with no gain plays unchanged.
function Equalizer.native(gains)
	local native = {}
	for index, band in ipairs(Equalizer.BANDS) do
		local suffix = tostring(index - 1)
		local ratio = 10 ^ ((gains[band.id] or 0) / 20)
		native["FrequencyCenter" .. suffix] = band.frequency
		native["Gain" .. suffix] = math.max(MIN_GAIN, math.min(MAX_GAIN, ratio))
		native["Bandwidth" .. suffix] = BANDWIDTH
	end
	return native
end

return Equalizer
