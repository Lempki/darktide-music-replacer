-- The constant UI element that draws the on-screen message in a corner of the screen.
-- on_screen_message.lua adds and removes it, and times the lines it draws.
-- Every line is drawn at the same spot at its own opacity, so during a crossfade one text fades into the next.
-- A backdrop like the debug overlay's sits behind the text and fades out toward the middle of the screen.

require("scripts/ui/constant_elements/constant_element_base")

local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

-- These are the sizes at 100%, and they scale with the Message Size setting.
local FONT_SIZE = 16
local LINE_HEIGHT = 24
local BACKDROP_PADDING = 4
local FADE_WIDTH = 80

-- Text is placed in a pass far wider than itself, so it never wraps.
local TEXT_ROOM = 2000

-- The game measures text a little narrower than it draws it, so measured widths get this much extra.
local MEASURE_SLACK = 6

-- The same dark backdrop as the debug overlay's.
local BACKDROP_RGB = { 12, 13, 11 }

-- The game's horizontal gradient fades toward its left edge.
-- So in a left corner these uvs flip it to fade toward the right, the middle of the screen.
local FADE_RIGHT_UVS = { { 1, 0 }, { 0, 1 } }
local FADE_LEFT_UVS = { { 0, 0 }, { 1, 1 } }

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
			offset = { 0, 0, index + 1 },
		},
	}
end

local function backdrop_passes()
	return {
		{
			pass_type = "rect",
			style_id = "backdrop",
			style = {
				color = { 0, BACKDROP_RGB[1], BACKDROP_RGB[2], BACKDROP_RGB[3] },
				horizontal_alignment = "left",
				vertical_alignment = "bottom",
				size = { 0, 0 },
				offset = { 0, 0, 0 },
			},
		},
		{
			pass_type = "texture_uv",
			style_id = "backdrop_fade",
			value = "content/ui/materials/gradients/gradient_horizontal",
			style = {
				color = { 0, BACKDROP_RGB[1], BACKDROP_RGB[2], BACKDROP_RGB[3] },
				horizontal_alignment = "left",
				vertical_alignment = "bottom",
				size = { 0, 0 },
				offset = { 0, 0, 0 },
				uvs = FADE_RIGHT_UVS,
			},
		},
	}
end

-- `OnScreenMessage` is the loaded on_screen_message.lua. Returns the element class.
return function(OnScreenMessage)
	local passes = backdrop_passes()
	for index = 1, OnScreenMessage.MAX_LINES do
		passes[#passes + 1] = text_pass(index)
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

	-- `look` is OnScreenMessage.look(): the size, the ARGB color, the corner, the offsets inward from it, and the backdrop's opacity.
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
		for _, id in ipairs({ "backdrop", "backdrop_fade" }) do
			style[id].horizontal_alignment = placement.horizontal
			style[id].vertical_alignment = placement.vertical
		end
		style.backdrop_fade.uvs = placement.horizontal == "left" and FADE_RIGHT_UVS or FADE_LEFT_UVS

		self._alpha = look.color[1]
		self._backdrop_alpha = 255 * look.backdrop_opacity
		self._scale = look.scale
		self._placement = placement
		-- Widths depend on the font size, so they are measured again.
		self._widths = {}
	end

	-- The drawn width of `text`, measured once per text and size.
	function Element:_width(ui_renderer, text)
		local width = self._widths[text]
		if not width then
			local style = self._widgets_by_name.message.style.line_1
			width = UIRenderer.styled_text_size(ui_renderer, text, style, { TEXT_ROOM, LINE_HEIGHT }) + MEASURE_SLACK * self._scale
			self._widths[text] = width
		end
		return width
	end

	-- Sizes the backdrop around `width` of text at `opacity`, a share, and places its fade on the side away from the corner.
	-- toward_x and toward_y below are 1 or -1, the way the offsets move inward on each axis.
	function Element:_place_backdrop(width, opacity)
		local style = self._widgets_by_name.message.style
		local placement = self._placement
		local s = self._scale
		local padding = BACKDROP_PADDING * s
		local toward_x = placement.horizontal == "left" and 1 or -1
		local toward_y = placement.vertical == "top" and 1 or -1

		local box_width = math.ceil(width + 2 * padding)
		local box_height = math.ceil(LINE_HEIGHT * s + 2 * padding)
		local box_x = placement.x - toward_x * padding
		local box_y = placement.y - toward_y * padding

		local backdrop = style.backdrop
		backdrop.offset[1] = box_x
		backdrop.offset[2] = box_y
		backdrop.size[1] = box_width
		backdrop.size[2] = box_height

		local fade = style.backdrop_fade
		fade.offset[1] = box_x + toward_x * box_width
		fade.offset[2] = box_y
		fade.size[1] = FADE_WIDTH * s
		fade.size[2] = box_height

		local alpha = math.floor(self._backdrop_alpha * opacity + 0.5)
		backdrop.color[1] = alpha
		fade.color[1] = alpha
	end

	-- Moves the message on and gives each pass its line's text and opacity, or an empty text, and fits the backdrop to them.
	function Element:_draw_lines(dt, ui_renderer)
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

		-- Every song name gets measured once, so the widths are forgotten whenever nothing shows, and they never pile up.
		if line_count == 0 and next(self._widths) then
			self._widths = {}
		end

		local width, opacity = OnScreenMessage.backdrop(function(text) return self:_width(ui_renderer, text) end)
		self:_place_backdrop(width, opacity)
	end

	function Element:update(dt, t, ui_renderer, render_settings, input_service)
		-- This runs inside the game's own UI update, so a failure here only freezes the message.
		pcall(self._draw_lines, self, dt, ui_renderer)

		Element.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	end

	return Element
end
