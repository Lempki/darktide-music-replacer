-- The short on-screen message, such as a playback key's: one line that fades in, holds, and fades out.
-- A new message takes the place of the one showing, which fades out under it, so the text never jumps or flickers.
-- It shows while For Key Presses or For Song Changes is on, which both are by default.
--
-- The lines are drawn by an element in the game's constant UI, which constant_element_slot.lua keeps there.
-- The constant UI is drawn on every screen, so the message also shows on loading screens and the mission briefing.

local ConstantElementSlot = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/constant_element_slot")

local OnScreenMessage = {}

-- Above most constant elements, such as the subtitles, so the text stays readable.
local DRAW_LAYER = 900

local slot = ConstantElementSlot.new("ConstantElementMusicReplacerOnScreenMessage", DRAW_LAYER)

-- The fade in stays short and fixed, so a key press always shows its message at once.
local FADE_IN_SECONDS = 0.4

-- The Message Duration and Message Fade Out settings, in seconds.
local hold_seconds = 3
local fade_out_seconds = 1

-- How long a new message takes to replace the one showing: the old one fades out and the new one in, at once.
local CROSSFADE_SECONDS = 0.3

-- Keys pressed in quick succession leave several messages fading out at once. Past this many, the faintest goes.
local MAX_FADING_OUT = 3

-- The most lines that show at once, so the element knows how many to draw: those fading out and the newest.
OnScreenMessage.MAX_LINES = MAX_FADING_OUT + 1

-- The Message Color setting's default, as ARGB: a muted grey at 85% opacity.
local DEFAULT_COLOR = { 217, 200, 200, 195 }

local create_element = nil
local log = function() end
local enabled = false

-- The Message Corner setting's choices: the side the message aligns to on each axis.
local CORNERS = {
	bottom_left = { horizontal = "left", vertical = "bottom" },
	bottom_right = { horizontal = "right", vertical = "bottom" },
	top_left = { horizontal = "left", vertical = "top" },
	top_right = { horizontal = "right", vertical = "top" },
}
local DEFAULT_CORNER = "bottom_left"

-- How far the message sits from its corner's edges at offsets of 0, in the UI's pixels, which the game scales to the screen's height.
local PADDING = 4

-- The Message Backdrop Opacity setting's default, as a share, the same as the debug overlay's backdrop.
local DEFAULT_BACKDROP_OPACITY = 0.7

-- How the message looks, from its settings: its size as a factor, its ARGB color, its corner, and its backdrop's opacity as a share.
-- Its offsets are how far it moves inward from the corner, in the UI's pixels.
local look = {
	scale = 1,
	color = DEFAULT_COLOR,
	corner = DEFAULT_CORNER,
	offset_x = 0,
	offset_y = 0,
	backdrop_opacity = DEFAULT_BACKDROP_OPACITY,
}

-- The message showing now, or nil: its text, its opacity as a share, its phase, and the seconds left of its hold.
-- Its phase is "in", "hold", or "out", and its min_hold_seconds, if set, is the shortest hold it gets.
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

-- Shows `text`, replacing the message showing now. Does nothing while the messages are turned off.
-- The same text again keeps its line and starts its hold over, since two copies of one text crossfading look brighter for a moment.
-- `min_hold_seconds`, if given, keeps the message held at least that long, whatever Message Duration says.
function OnScreenMessage.show(text, min_hold_seconds)
	if not enabled then
		return
	end

	if current and current.text == text then
		current.phase = "in"
		current.fade_in_seconds = FADE_IN_SECONDS
		current.min_hold_seconds = min_hold_seconds
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

	current = { text = text, opacity = 0, phase = "in", fade_in_seconds = fade_in_seconds, min_hold_seconds = min_hold_seconds }
end

-- Moves the fades and the hold on by `dt` seconds. Call every frame the message is drawn.
function OnScreenMessage.advance(dt)
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
				current.hold_left = math.max(hold_seconds, current.min_hold_seconds or 0)
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
		elseif fade_out_seconds <= 0 then
			current = nil
		else
			current.opacity = current.opacity - seconds / fade_out_seconds
			seconds = 0
			if current.opacity <= 0 then
				current = nil
			end
		end
	end
end

-- How many lines show now: the messages fading out under a newer one, and the newest.
function OnScreenMessage.line_count()
	return #fading_out + (current and 1 or 0)
end

-- The text and opacity of the line at `index`, oldest first, so the newest is drawn last, on top.
function OnScreenMessage.line(index)
	local line = fading_out[index] or current
	return line.text, line.opacity
end

function OnScreenMessage.look()
	return look
end

-- The backdrop behind the lines showing now: its width, from `width_of(text)` for each line, and its opacity as a share.
-- During a crossfade it blends from the old line's width to the new one's by their opacities, so it never jumps.
-- Returns 0, 0 while no line shows.
function OnScreenMessage.backdrop(width_of)
	local total_opacity = 0
	local weighted_width = 0
	for index = 1, OnScreenMessage.line_count() do
		local line_text, opacity = OnScreenMessage.line(index)
		total_opacity = total_opacity + opacity
		weighted_width = weighted_width + width_of(line_text) * opacity
	end

	if total_opacity <= 0 then
		return 0, 0
	end
	return weighted_width / total_opacity, math.min(1, total_opacity)
end

-- Where the message sits for `new_look`: the side it aligns to on each axis, and its offset as the game's styles take it.
-- The offsets move it inward, so a larger X moves it left from a right corner, and a larger Y moves it down from a top corner.
function OnScreenMessage.placement(new_look)
	local corner = CORNERS[new_look.corner]
	local x = PADDING + new_look.offset_x
	local y = PADDING + new_look.offset_y
	return {
		horizontal = corner.horizontal,
		vertical = corner.vertical,
		x = corner.horizontal == "left" and x or -x,
		y = corner.vertical == "top" and y or -y,
	}
end

-- Sets how long a message stays at full opacity, and how long it then takes to fade out, both in seconds.
-- A message showing now keeps the hold it started, and fades out at the new pace.
function OnScreenMessage.set_timing(new_hold_seconds, new_fade_out_seconds)
	hold_seconds = new_hold_seconds
	fade_out_seconds = new_fade_out_seconds
end

-- The color comes from the saved settings, so anything but four numbers keeps the default.
local function checked_color(color)
	if type(color) ~= "table" then
		return DEFAULT_COLOR
	end
	for index = 1, 4 do
		if type(color[index]) ~= "number" then
			return DEFAULT_COLOR
		end
	end
	return { color[1], color[2], color[3], color[4] }
end

-- `options.create_element(constant_elements, draw_layer)` makes the element.
function OnScreenMessage.init(logger, options)
	log = logger or log
	create_element = options.create_element
end

-- Call every update. Adds the element once the game's UI exists, and adds it again if the UI was rebuilt.
function OnScreenMessage.update()
	if not enabled or not create_element then
		return
	end

	local err = slot:update(create_element)
	if err then
		log("[on-screen message] could not be shown: " .. err)
	end
end

-- Turns the messages on or off and sets how they look.
-- `new_look.scale` sizes the text as a factor, and `new_look.color` is its ARGB color, whose alpha also sets its opacity.
-- `new_look.corner` is a Message Corner choice, such as "bottom_left".
-- `new_look.offset_x` and `new_look.offset_y` move it inward from that corner, in the UI's pixels.
-- `new_look.backdrop_opacity` is how opaque the backdrop behind it is, as a share.
function OnScreenMessage.set_enabled(on, new_look)
	enabled = on == true
	if new_look then
		look = {
			scale = new_look.scale or 1,
			color = checked_color(new_look.color),
			-- The corner comes from the saved settings too, so an unknown one keeps the default.
			corner = CORNERS[new_look.corner] and new_look.corner or DEFAULT_CORNER,
			offset_x = new_look.offset_x or 0,
			offset_y = new_look.offset_y or 0,
			backdrop_opacity = math.max(0, math.min(1, new_look.backdrop_opacity or DEFAULT_BACKDROP_OPACITY)),
		}
	end

	if not enabled then
		-- A message from before the messages were turned off would show again once they are back on.
		current = nil
		fading_out = {}
		slot:remove()
		return
	end

	local element = slot:element()
	if element and element.set_layout then
		element:set_layout(look)
	end

	OnScreenMessage.update()
end

-- Call from the main mod file's mod.on_unload.
function OnScreenMessage.shutdown()
	slot:remove()
end

return OnScreenMessage
