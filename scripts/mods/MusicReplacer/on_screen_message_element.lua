-- The constant UI element that draws the on-screen message in a corner of the screen.
-- on_screen_message.lua adds and removes it, and times the lines it draws.
-- Every line is drawn at the same spot at its own opacity, so during a crossfade one text fades into the next.

require("scripts/ui/constant_elements/constant_element_base")

local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

-- These are the sizes at 100%, and they scale with the Message Size setting.
local FONT_SIZE = 16
local LINE_HEIGHT = 24

-- Text is placed in a pass far wider than itself, so it never wraps.
local TEXT_ROOM = 2000

local function line_id(index)
	return "line_" .. index
end

-- Each line is drawn one layer above the one before it, so the newest is on top.
local function text_pass(index)
	local id = line_id(index)
	return {
		pass_type = "text",
		value_id = id,
		value = "",
		style_id = id,
		style = {
			font_type = "proxima_nova_medium",
			font_size = FONT_SIZE,
			drop_shadow = true,
			text_color = { 0, 0, 0, 0 },
			text_horizontal_alignment = "left",
			text_vertical_alignment = "bottom",
			horizontal_alignment = "left",
			vertical_alignment = "bottom",
			size = { TEXT_ROOM, LINE_HEIGHT },
			offset = { 0, 0, index },
		},
	}
end

-- `OnScreenMessage` is the loaded on_screen_message.lua. Returns the element class.
return function(OnScreenMessage)
	local passes = {}
	for index = 1, OnScreenMessage.MAX_LINES do
		passes[index] = text_pass(index)
	end

	local definitions = {
		-- The passes sit straight on the screen node, which the game sizes to the whole screen at any aspect ratio, ultrawide included.
		-- So every corner of it is a corner of the screen.
		scenegraph_definition = {
			screen = UIWorkspaceSettings.screen,
		},
		widget_definitions = {
			message = UIWidget.create_definition(passes, "screen"),
		},
	}

	-- After a mod reload, class() hands back the class from the first load, and the methods below replace its old ones.
	local Element = class("ConstantElementMusicReplacerOnScreenMessage", "ConstantElementBase")

	function Element:init(parent, draw_layer, start_scale)
		Element.super.init(self, parent, draw_layer, start_scale, definitions)
		self:set_layout(OnScreenMessage.look())
	end

	-- `look` is OnScreenMessage.look(): the size, the ARGB color, the corner, and the offsets inward from it.
	-- The text aligns to the corner's side, so it grows away from the corner.
	function Element:set_layout(look)
		local style = self._widgets_by_name.message.style
		local placement = OnScreenMessage.placement(look)
		for index = 1, OnScreenMessage.MAX_LINES do
			local line_style = style[line_id(index)]
			line_style.font_size = FONT_SIZE * look.scale
			line_style.size[1] = TEXT_ROOM * look.scale
			line_style.size[2] = LINE_HEIGHT * look.scale
			line_style.horizontal_alignment = placement.horizontal
			line_style.text_horizontal_alignment = placement.horizontal
			line_style.vertical_alignment = placement.vertical
			line_style.text_vertical_alignment = placement.vertical
			line_style.offset[1] = placement.x
			line_style.offset[2] = placement.y
			line_style.text_color[2] = look.color[2]
			line_style.text_color[3] = look.color[3]
			line_style.text_color[4] = look.color[4]
		end
		self._alpha = look.color[1]
	end

	-- Moves the message on and gives each pass its line's text and opacity, or an empty text.
	function Element:_draw_lines(dt)
		OnScreenMessage.advance(dt)

		local widget = self._widgets_by_name.message
		local line_count = OnScreenMessage.line_count()
		for index = 1, OnScreenMessage.MAX_LINES do
			local id = line_id(index)
			if index <= line_count then
				local text, opacity = OnScreenMessage.line(index)
				widget.content[id] = text
				widget.style[id].text_color[1] = math.floor(self._alpha * math.max(0, math.min(1, opacity)) + 0.5)
			else
				widget.content[id] = ""
			end
		end
	end

	function Element:update(dt, t, ui_renderer, render_settings, input_service)
		-- This runs inside the game's own UI update, so a failure here only freezes the message.
		pcall(self._draw_lines, self, dt)

		Element.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	end

	return Element
end
