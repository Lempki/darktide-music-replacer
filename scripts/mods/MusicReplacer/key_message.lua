-- The short message a playback key shows: one line that fades in, holds, and fades out.
-- A new message takes the place of the one showing, which fades out under it, so the text never jumps or flickers.
-- This file only keeps the timing. The element that draws the lines comes later.

local KeyMessage = {}

local FADE_IN_SECONDS = 0.4
local HOLD_SECONDS = 3
local FADE_OUT_SECONDS = 1

-- How long a new message takes to replace the one showing: the old one fades out and the new one in, at once.
local CROSSFADE_SECONDS = 0.3

-- Keys pressed in quick succession leave several messages fading out at once. Past this many, the faintest goes.
local MAX_FADING_OUT = 3

-- The message showing now, or nil: its text, its opacity as a share, its phase, and the seconds left of its hold.
-- Its phase is "in", "hold", or "out".
local current = nil

-- The messages a newer one replaced, oldest first, each with its text and opacity.
local fading_out = {}

-- The oldest line is not always the faintest: a message replaced while it was still fading in is fainter than the full one before it.
-- Dropping the faintest keeps a line that is still clearly visible from vanishing at once.
local function drop_faintest()
	local faintest = 1
	for index = 2, #fading_out do
		if fading_out[index].opacity < fading_out[faintest].opacity then
			faintest = index
		end
	end
	table.remove(fading_out, faintest)
end

-- Shows `text`, replacing the message showing now.
-- The same text again keeps its line and starts its hold over, since two copies of one text crossfading look brighter for a moment.
function KeyMessage.show(text)
	if current and current.text == text then
		current.phase = "in"
		current.fade_in_seconds = FADE_IN_SECONDS
		return
	end

	local fade_in_seconds = FADE_IN_SECONDS
	if current then
		fading_out[#fading_out + 1] = { text = current.text, opacity = current.opacity }
		if #fading_out > MAX_FADING_OUT then
			drop_faintest()
		end
		fade_in_seconds = CROSSFADE_SECONDS
	end

	current = { text = text, opacity = 0, phase = "in", fade_in_seconds = fade_in_seconds }
end

-- Moves the fades and the hold on by `dt` seconds. Call every frame the message is drawn.
function KeyMessage.advance(dt)
	for index = #fading_out, 1, -1 do
		local line = fading_out[index]
		line.opacity = line.opacity - dt / CROSSFADE_SECONDS
		if line.opacity <= 0 then
			table.remove(fading_out, index)
		end
	end

	-- A frame longer than a phase carries its rest into the next, so a slow frame does not stretch the message.
	local seconds = dt
	while current and seconds > 0 do
		if current.phase == "in" then
			local needed = (1 - current.opacity) * current.fade_in_seconds
			if seconds < needed then
				current.opacity = current.opacity + seconds / current.fade_in_seconds
				seconds = 0
			else
				current.opacity = 1
				current.phase = "hold"
				current.hold_left = HOLD_SECONDS
				seconds = seconds - needed
			end
		elseif current.phase == "hold" then
			if seconds < current.hold_left then
				current.hold_left = current.hold_left - seconds
				seconds = 0
			else
				current.phase = "out"
				seconds = seconds - current.hold_left
			end
		else
			current.opacity = current.opacity - seconds / FADE_OUT_SECONDS
			seconds = 0
			if current.opacity <= 0 then
				current = nil
			end
		end
	end
end

-- How many lines show now: the messages fading out under a newer one, and the newest.
function KeyMessage.line_count()
	return #fading_out + (current and 1 or 0)
end

-- The text and opacity of the line at `index`, oldest first, so the newest is drawn last, on top.
function KeyMessage.line(index)
	local line = fading_out[index] or current
	return line.text, line.opacity
end

return KeyMessage
