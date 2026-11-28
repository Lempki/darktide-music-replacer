-- The parameters XAPOFX's echo takes for the Echo settings.
-- Its limits are those in Microsoft's xapofx.h.

local Echo = {}

-- The delay's range in milliseconds, FXECHO_MIN_DELAY to FXECHO_MAX_DELAY.
-- xaudio.lua makes the echo for the longest delay, so every delay in the range plays.
local MIN_DELAY = 1
local MAX_DELAY = 2000

local function clamp(value, low, high)
	return math.max(low, math.min(high, value))
end

-- The fields of FXECHO_PARAMETERS for `settings`.
-- * `mix` is the percent of the echo heard in place of the plain song.
-- * `feedback` is the percent of each repeat that comes back as the next one, so a higher one repeats longer.
-- * `delay` is the time between repeats, in milliseconds.
function Echo.native(settings)
	return {
		WetDryMix = clamp(settings.mix / 100, 0, 1),
		Feedback = clamp(settings.feedback / 100, 0, 1),
		Delay = clamp(settings.delay, MIN_DELAY, MAX_DELAY),
	}
end

return Echo
