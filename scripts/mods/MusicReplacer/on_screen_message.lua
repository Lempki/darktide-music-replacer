-- The short on-screen message, such as a playback key's: a line that fades in, holds, and fades out.
-- A new message pushes the one showing away from the corner, where it shrinks to the previous line's size and keeps its own timer.
-- A message pushed out of the previous line's place fades out there, so the text never jumps or flickers.
-- It shows while For Key Presses, For Song Changes, For Notices, or For Errors is on, which all are by default.
--
-- The lines are drawn by an element in the game's constant UI, which constant_element_slot.lua keeps there.
-- The constant UI is drawn on every screen, so the message also shows on loading screens and the mission briefing.

local ConstantElementSlot = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/constant_element_slot")

local OnScreenMessage = {}

-- Above most constant elements, such as the subtitles, so the text stays readable.
local DRAW_LAYER = 900

local slot = ConstantElementSlot.new("ConstantElementMusicReplacerOnScreenMessage", DRAW_LAYER, { use_hud_scale = true })

-- The fade in stays short and fixed, so a key press always shows its message at once.
local FADE_IN_SECONDS = 0.4

-- The Message Duration and Message Fade Out settings, in seconds.
local hold_seconds = 4
local fade_out_seconds = 1

-- How long a push takes: the line showing slides into the previous line's place, and the new one fades in where it was.
-- A line pushed out of the previous line's place fades out over the same time.
local PUSH_SECONDS = 0.3

-- The previous line's size, as a share of the newest line's, so the newest stands out and both fit beside the game's HUD.
OnScreenMessage.PREVIOUS_SCALE = 0.75

-- The widest a line's text is drawn at the newest line's size, as a share of the screen's width.
-- A longer text, such as a long song name, is cut and ends with an ellipsis, so it stays clear of the HUD in the middle of the bottom row.
OnScreenMessage.MAX_TEXT_SHARE = 1 / 3

local ELLIPSIS = "…"

-- One character of UTF-8 text: a lead byte and its continuation bytes, so a cut never splits a character such as a Japanese one.
local CHARACTER_PATTERN = "[%z\1-\127\194-\244][\128-\191]*"

-- Keys pressed in quick succession leave several lines leaving at once. Past this many, the faintest goes.
local MAX_LEAVING = 2

-- The most lines that show at once, so the element knows how many to draw: those leaving, the previous, and the newest.
OnScreenMessage.MAX_LINES = MAX_LEAVING + 2

-- The Message Color setting's default, as ARGB: a muted grey at 85% opacity.
local DEFAULT_COLOR = { 217, 200, 200, 195 }

-- The Notice Color and Error Color settings' defaults, as ARGB at the same opacity: an amber and a red that read well on the dark backdrop.
local DEFAULT_NOTICE_COLOR = { 217, 235, 180, 80 }
local DEFAULT_ERROR_COLOR = { 217, 240, 100, 90 }

-- The kinds of message, each drawn in its own color.
-- A message is a song change or a key press, a notice is something the player needs to know, and an error is something that went wrong.
local KINDS = { message = true, notice = true, error = true }

-- The kinds that show, from For Notices and For Errors.
-- The caller checks For Key Presses and For Song Changes itself, since both of them show the message kind.
local shown_kinds = { message = true, notice = true, error = true }

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

-- The Message Backdrop Opacity setting's default, as a share, the same as the debug overlay's backdrop.
local DEFAULT_BACKDROP_OPACITY = 0.7

-- The Message Size setting's default, as a factor, small enough that both lines fit below the player portrait in the bottom left corner.
local DEFAULT_SCALE = 0.85

-- How the message looks, from its settings: its size as a factor, each kind's ARGB color, its corner, and its backdrop's opacity.
-- Its offsets are how far it moves inward from the corner, in the UI's pixels.
local look = {
	scale = DEFAULT_SCALE,
	color = DEFAULT_COLOR,
	notice_color = DEFAULT_NOTICE_COLOR,
	error_color = DEFAULT_ERROR_COLOR,
	corner = DEFAULT_CORNER,
	offset_x = 0,
	offset_y = 0,
	backdrop_opacity = DEFAULT_BACKDROP_OPACITY,
}

-- A message: its text, its kind, its opacity as a share, its phase, and the seconds left of its hold.
-- Its phase is "in", "hold", or "out".

-- The newest message, at the corner, or nil.
local current = nil

-- The message before it, or nil, with `push`, how far it has slid from the corner into the previous line's place, as a share.
local previous = nil

-- The messages pushed out of the previous line's place, oldest first, each with its text, kind, and opacity, fading out where they were.
local leaving = {}

-- The oldest line is not always the faintest: a message pushed out while it was still fading in is fainter than the full one before it.
-- Dropping the faintest keeps a line that is still clearly visible from vanishing at once.
local function drop_faintest()
	local faintest = 1
	for index = 2, #leaving do
		if leaving[index].opacity < leaving[faintest].opacity then
			faintest = index
		end
	end
	table.remove(leaving, faintest)
end

-- Shows `text` at the corner, pushing the message there into the previous line's place.
-- `kind` sets the color it is drawn in, and is "message" unless told otherwise.
-- Every message is logged, even while its kind or all the messages are off, since a message is gone after a few seconds.
-- The same text of the same kind again keeps its line and starts its hold over, since a copy of it beside it would only repeat it.
function OnScreenMessage.show(text, kind)
	kind = KINDS[kind] and kind or "message"
	log("[on-screen message] " .. kind .. ": " .. text)
	if not enabled or not shown_kinds[kind] then
		return
	end

	if current and current.text == text and current.kind == kind then
		current.phase = "in"
		current.fade_in_seconds = FADE_IN_SECONDS
		return
	end

	local fade_in_seconds = FADE_IN_SECONDS
	if current then
		if previous then
			leaving[#leaving + 1] = { text = previous.text, kind = previous.kind, opacity = previous.opacity }
			if #leaving > MAX_LEAVING then
				drop_faintest()
			end
		end
		previous = current
		previous.push = 0
		fade_in_seconds = PUSH_SECONDS
	end

	current = { text = text, kind = kind, opacity = 0, phase = "in", fade_in_seconds = fade_in_seconds }
end

-- How long a message shown now stays on screen: its fade in, the Message Duration, and the Message Fade Out.
-- It holds while the messages are turned off too, for what a message would stand for.
function OnScreenMessage.seconds_shown()
	return FADE_IN_SECONDS + hold_seconds + fade_out_seconds
end

-- Moves `message` through its fade in, hold, and fade out by `dt` seconds.
-- Returns the message, or nil once it has faded out.
-- A frame longer than a phase carries its rest into the next, so a slow frame does not stretch the message.
local function advance_message(message, dt)
	local seconds = dt
	while seconds > 0 do
		if message.phase == "in" then
			local needed = (1 - message.opacity) * message.fade_in_seconds
			if seconds < needed then
				message.opacity = message.opacity + seconds / message.fade_in_seconds
				seconds = 0
			else
				message.opacity = 1
				message.phase = "hold"
				message.hold_left = hold_seconds
				seconds = seconds - needed
			end
		elseif message.phase == "hold" then
			if seconds < message.hold_left then
				message.hold_left = message.hold_left - seconds
				seconds = 0
			else
				message.phase = "out"
				seconds = seconds - message.hold_left
			end
		elseif fade_out_seconds <= 0 then
			return nil
		else
			message.opacity = message.opacity - seconds / fade_out_seconds
			seconds = 0
			if message.opacity <= 0 then
				return nil
			end
		end
	end
	return message
end

-- Moves the fades, the holds, and the push on by `dt` seconds. Call every frame the message is drawn.
function OnScreenMessage.advance(dt)
	for index = #leaving, 1, -1 do
		local line = leaving[index]
		line.opacity = line.opacity - dt / PUSH_SECONDS
		if line.opacity <= 0 then
			table.remove(leaving, index)
		end
	end

	if previous then
		previous.push = math.min(1, previous.push + dt / PUSH_SECONDS)
		previous = advance_message(previous, dt)
	end
	if current then
		current = advance_message(current, dt)
	end
end

-- How many lines show now: those leaving, the previous, and the newest.
function OnScreenMessage.line_count()
	return #leaving + (previous and 1 or 0) + (current and 1 or 0)
end

-- The line at `index`, oldest first, so the newest is drawn last, on top.
-- Returns its text, its opacity as a share, its place, and its kind.
-- Its place is 0 at the corner, 1 in the previous line's place, and the share of the way between while it slides.
function OnScreenMessage.line(index)
	if index <= #leaving then
		local line = leaving[index]
		return line.text, line.opacity, 1, line.kind
	end
	if previous and index == #leaving + 1 then
		return previous.text, previous.opacity, previous.push, previous.kind
	end
	return current.text, current.opacity, 0, current.kind
end

-- `text` as it fits in `max_width`, with `width_of(text)` its drawn width: whole when it fits, or cut with an ellipsis.
-- The cut keeps as many whole characters as fit beside the ellipsis, found by halving, so a long text is measured only a few times.
function OnScreenMessage.fit(text, max_width, width_of)
	if width_of(text) <= max_width then
		return text
	end

	local characters = {}
	for character in text:gmatch(CHARACTER_PATTERN) do
		characters[#characters + 1] = character
	end

	-- `kept` characters always fit beside the ellipsis, and more than `limit` never do.
	local kept = 0
	local limit = #characters
	while kept < limit do
		local middle = math.ceil((kept + limit) / 2)
		if width_of(table.concat(characters, "", 1, middle) .. ELLIPSIS) <= max_width then
			kept = middle
		else
			limit = middle - 1
		end
	end

	local cut = table.concat(characters, "", 1, kept):gsub("%s+$", "")
	return cut .. ELLIPSIS
end

function OnScreenMessage.look()
	return look
end

-- Where the message's backdrop sits for `new_look`: the side it aligns to on each axis, and the offset of its outer corner.
-- At offsets of 0 the backdrop touches the corner's two edges, and the text sits inside it.
-- toward_x and toward_y are 1 or -1, the sign that moves inward on each axis as the game's styles take offsets.
-- So a larger X moves it left from a right corner, and a larger Y moves it down from a top corner.
function OnScreenMessage.placement(new_look)
	local corner = CORNERS[new_look.corner]
	local toward_x = corner.horizontal == "left" and 1 or -1
	local toward_y = corner.vertical == "top" and 1 or -1
	return {
		horizontal = corner.horizontal,
		vertical = corner.vertical,
		toward_x = toward_x,
		toward_y = toward_y,
		x = toward_x * new_look.offset_x,
		y = toward_y * new_look.offset_y,
	}
end

-- Sets whether notices and errors show, from `kinds.notice` and `kinds.error`.
-- A kind turned off is still logged when shown.
function OnScreenMessage.set_shown_kinds(kinds)
	shown_kinds = { message = true, notice = kinds.notice == true, error = kinds.error == true }
end

-- Sets how long a message stays at full opacity, and how long it then takes to fade out, both in seconds.
-- A message showing now keeps the hold it started, and fades out at the new pace.
function OnScreenMessage.set_timing(new_hold_seconds, new_fade_out_seconds)
	hold_seconds = new_hold_seconds
	fade_out_seconds = new_fade_out_seconds
end

-- A color comes from the saved settings, so anything but four numbers keeps `default`.
local function checked_color(color, default)
	if type(color) ~= "table" then
		return default
	end
	for index = 1, 4 do
		if type(color[index]) ~= "number" then
			return default
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

local reported_draw_failures = {} -- error text -> true.

-- The element calls this when drawing fails. A failure repeats every frame, so each one is logged once.
function OnScreenMessage.report_draw_failure(err)
	local text = tostring(err)
	if reported_draw_failures[text] then
		return
	end
	reported_draw_failures[text] = true
	log("[on-screen message] drawing failed: " .. text)
end

-- Turns the messages on or off and sets how they look.
-- `new_look.scale` sizes the text as a factor, and `new_look.color` is its ARGB color, whose alpha also sets its opacity.
-- `new_look.notice_color` and `new_look.error_color` are the same for notices and errors.
-- `new_look.corner` is a Message Corner choice, such as "bottom_left".
-- `new_look.offset_x` and `new_look.offset_y` move it inward from that corner, in the UI's pixels.
-- `new_look.backdrop_opacity` is how opaque the backdrop behind it is, as a share.
function OnScreenMessage.set_enabled(on, new_look)
	enabled = on == true
	if new_look then
		look = {
			scale = new_look.scale or DEFAULT_SCALE,
			color = checked_color(new_look.color, DEFAULT_COLOR),
			notice_color = checked_color(new_look.notice_color, DEFAULT_NOTICE_COLOR),
			error_color = checked_color(new_look.error_color, DEFAULT_ERROR_COLOR),
			-- The corner comes from the saved settings too, so an unknown one keeps the default.
			corner = CORNERS[new_look.corner] and new_look.corner or DEFAULT_CORNER,
			-- Moving past the corner only pushes the message off the screen, so the offsets start at 0.
			offset_x = math.max(0, new_look.offset_x or 0),
			offset_y = math.max(0, new_look.offset_y or 0),
			backdrop_opacity = math.max(0, math.min(1, new_look.backdrop_opacity or DEFAULT_BACKDROP_OPACITY)),
		}
	end

	if not enabled then
		-- A message from before the messages were turned off would show again once they are back on.
		current = nil
		previous = nil
		leaving = {}
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
