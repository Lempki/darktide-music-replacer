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

local FADE_IN_SECONDS = 0.4
local HOLD_SECONDS = 3
local FADE_OUT_SECONDS = 1

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

-- How the message looks, from its settings: its size as a factor, its ARGB color, and how far it moves right and up, in pixels.
local look = { scale = 1, color = DEFAULT_COLOR, offset_x = 0, offset_y = 0 }

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

-- Shows `text`, replacing the message showing now. Does nothing while the messages are turned off.
-- The same text again keeps its line and starts its hold over, since two copies of one text crossfading look brighter for a moment.
function OnScreenMessage.show(text)
	if not enabled then
		return
	end

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
-- `new_look.offset_x` and `new_look.offset_y` move it right and up from its spot, in pixels of the 1920x1080 UI.
function OnScreenMessage.set_enabled(on, new_look)
	enabled = on == true
	if new_look then
		look = {
			scale = new_look.scale or 1,
			color = checked_color(new_look.color),
			offset_x = new_look.offset_x or 0,
			offset_y = new_look.offset_y or 0,
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
