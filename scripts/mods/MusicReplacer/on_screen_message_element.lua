-- The constant UI element that draws the on-screen message in a corner of the screen.
-- on_screen_message.lua adds and removes it, and times the lines it draws and where each one is.
-- The newest line sits at the corner, and the previous one beside it, away from the corner and smaller.
-- A line is drawn at its own opacity, size, and place every frame, so a pushed line slides and shrinks into the previous line's place.
-- Each line has a backdrop like the debug overlay's, which fits its text and fades out toward the middle of the screen.

require("scripts/ui/constant_elements/constant_element_base")

local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

-- These are the sizes at 100%, and they scale with the Message Size setting.
-- They are small enough that both lines fit below the player portrait in the bottom left corner at the game's default HUD Scale.
-- The padding is the space between the backdrop's edges and the text.
local FONT_SIZE = 13.6
local LINE_HEIGHT = 20.4
local BACKDROP_PADDING = 3.4
local FADE_WIDTH = 68

-- The space between the newest line's backdrop and the previous line's, none, so the two backdrops read as one block.
local LINE_GAP = 0
local FONT_TYPE = "proxima_nova_medium"

-- Text is placed in a pass far wider than itself, so it never wraps.
local TEXT_ROOM = 2000

-- The game measures text a little narrower than it draws it, so measured widths get this much extra.
local MEASURE_SLACK = 5.1

-- The same dark backdrop as the debug overlay's.
local BACKDROP_RGB = { 12, 13, 11 }

-- The game's horizontal gradient fades toward its left edge.
-- So in a left corner these uvs flip it to fade toward the right, the middle of the screen.
local FADE_RIGHT_UVS = { { 1, 0 }, { 0, 1 } }
local FADE_LEFT_UVS = { { 0, 0 }, { 1, 1 } }

local function line_id(index)
	return "line_" .. index
end

local function backdrop_id(index)
	return "backdrop_" .. index
end

local function backdrop_fade_id(index)
	return "backdrop_fade_" .. index
end

-- Each line is drawn one layer above the one before it, so the newest is on top.
-- Every backdrop sits below every text, so a line leaving over the previous one never hides its text.
local function line_passes(index)
	return {
		{
			pass_type = "rect",
			style_id = backdrop_id(index),
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
			style_id = backdrop_fade_id(index),
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
		{
			pass_type = "text",
			value_id = line_id(index),
			value = "",
			style_id = line_id(index),
			style = {
				font_type = FONT_TYPE,
				font_size = FONT_SIZE,
				drop_shadow = true,
				text_color = { 0, 0, 0, 0 },
				text_horizontal_alignment = "left",
				text_vertical_alignment = "center",
				horizontal_alignment = "left",
				vertical_alignment = "bottom",
				size = { TEXT_ROOM, LINE_HEIGHT },
				offset = { 0, 0, index + 1 },
			},
		},
	}
end

-- `OnScreenMessage` is the loaded on_screen_message.lua. Returns the element class.
return function(OnScreenMessage)
	local passes = {}
	for index = 1, OnScreenMessage.MAX_LINES do
		for _, pass in ipairs(line_passes(index)) do
			passes[#passes + 1] = pass
		end
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
		-- A new scenegraph keeps the screen node at 1920 by 1080 until it is updated at the scale the element draws at.
		-- That scale is the HUD Scale, so the first update sizes the node to the whole screen at it.
		self._update_scenegraph = true
		self:set_layout(OnScreenMessage.look())
	end

	-- `look` is OnScreenMessage.look(): the size, the ARGB color, the corner, the offsets inward from it, and the backdrop's opacity.
	-- Each backdrop sits toward the corner, and its text inside it by the padding, aligned to the corner's side to grow away from it.
	-- The sizes and places change as lines slide, so _draw_lines sets them every frame.
	function Element:set_layout(look)
		local style = self._widgets_by_name.message.style
		local placement = OnScreenMessage.placement(look)
		for index = 1, OnScreenMessage.MAX_LINES do
			local line_style = style[line_id(index)]
			line_style.horizontal_alignment = placement.horizontal
			line_style.text_horizontal_alignment = placement.horizontal
			line_style.vertical_alignment = placement.vertical
			for _, id in ipairs({ backdrop_id(index), backdrop_fade_id(index) }) do
				style[id].horizontal_alignment = placement.horizontal
				style[id].vertical_alignment = placement.vertical
			end
			style[backdrop_fade_id(index)].uvs = placement.horizontal == "left" and FADE_RIGHT_UVS or FADE_LEFT_UVS
		end

		self._colors = { message = look.color, notice = look.notice_color, error = look.error_color }
		self._backdrop_alpha = 255 * look.backdrop_opacity
		self._scale = look.scale
		self._placement = placement
		-- Widths depend on the font size, so they are measured and fitted again.
		self._widths = {}
		self._fitted = {}
	end

	-- `text` as drawn: whole, or cut with an ellipsis where it would grow past `max_width`. Fitted once per text, size, and width.
	function Element:_fit(ui_renderer, text, max_width)
		local fitted = self._fitted[text]
		if not fitted then
			fitted = OnScreenMessage.fit(text, max_width, function(candidate) return self:_width(ui_renderer, candidate) end)
			self._fitted[text] = fitted
		end
		return fitted
	end

	-- The widest a text is drawn, as OnScreenMessage.MAX_TEXT_SHARE of the screen's width in this element's units.
	-- The screen node fits the whole screen, which the game measures as its width in pixels over the draw scale, as here.
	-- So the share holds on an ultrawide screen and at any HUD Scale.
	-- A new width forgets the texts fitted to the old one.
	function Element:_max_text_width()
		local screen_width = RESOLUTION_LOOKUP.width / (self._draw_scale or RESOLUTION_LOOKUP.scale)
		local max_width = screen_width * OnScreenMessage.MAX_TEXT_SHARE
		if max_width ~= self._fitted_max_width then
			self._fitted_max_width = max_width
			self._fitted = {}
		end
		return max_width
	end

	-- The drawn width of `text` at the newest line's size, measured once per text and size.
	-- A smaller line's width is this one scaled, so a line that shrinks is not measured at every size it passes through.
	-- It is measured without the text's alignment, since an aligned measure can span the whole box the text sits in.
	function Element:_width(ui_renderer, text)
		local width = self._widths[text]
		if not width then
			width = UIRenderer.text_size(ui_renderer, text, FONT_TYPE, FONT_SIZE * self._scale) + MEASURE_SLACK * self._scale
			self._widths[text] = width
		end
		return width
	end

	-- Sizes and places the line at `index`, with `text` at `opacity`, a share, at `place`, 0 at the corner and 1 in the previous line's place.
	-- It is drawn in the color of its `kind`, whose alpha the opacity scales.
	-- A line in the previous line's place sits right beyond the newest line's backdrop, so the two never overlap.
	function Element:_place_line(ui_renderer, index, text, opacity, place, kind)
		local style = self._widgets_by_name.message.style
		local placement = self._placement
		local line_scale = 1 + (OnScreenMessage.PREVIOUS_SCALE - 1) * place
		local s = self._scale * line_scale
		local padding = BACKDROP_PADDING * s

		local newest_box_height = math.ceil(LINE_HEIGHT * self._scale + 2 * BACKDROP_PADDING * self._scale)
		local away = place * (newest_box_height + LINE_GAP * self._scale)
		local x = placement.x
		local y = placement.y + placement.toward_y * away

		local box_width = math.ceil(self:_width(ui_renderer, text) * line_scale + 2 * padding)
		local box_height = math.ceil(LINE_HEIGHT * s + 2 * padding)

		local line_style = style[line_id(index)]
		line_style.font_size = FONT_SIZE * s
		line_style.size[1] = TEXT_ROOM * s
		line_style.size[2] = LINE_HEIGHT * s
		line_style.offset[1] = x + placement.toward_x * padding
		line_style.offset[2] = y + placement.toward_y * padding
		local color = self._colors[kind] or self._colors.message
		line_style.text_color[1] = math.floor(color[1] * opacity + 0.5)
		line_style.text_color[2] = color[2]
		line_style.text_color[3] = color[3]
		line_style.text_color[4] = color[4]

		local backdrop = style[backdrop_id(index)]
		backdrop.offset[1] = x
		backdrop.offset[2] = y
		backdrop.size[1] = box_width
		backdrop.size[2] = box_height

		local fade = style[backdrop_fade_id(index)]
		fade.offset[1] = x + placement.toward_x * box_width
		fade.offset[2] = y
		fade.size[1] = FADE_WIDTH * s
		fade.size[2] = box_height

		local backdrop_alpha = math.floor(self._backdrop_alpha * opacity + 0.5)
		backdrop.color[1] = backdrop_alpha
		fade.color[1] = backdrop_alpha
	end

	-- Moves the message on and gives each line its text, size, place, and opacity, and hides the passes no line uses.
	function Element:_draw_lines(dt, ui_renderer)
		OnScreenMessage.advance(dt)

		local widget = self._widgets_by_name.message
		local line_count = OnScreenMessage.line_count()
		local max_width = self:_max_text_width()
		for index = 1, OnScreenMessage.MAX_LINES do
			if index <= line_count then
				local full_text, opacity, place, kind = OnScreenMessage.line(index)
				local text = self:_fit(ui_renderer, full_text, max_width)
				widget.content[line_id(index)] = text
				self:_place_line(ui_renderer, index, text, math.max(0, math.min(1, opacity)), place, kind)
			else
				widget.content[line_id(index)] = ""
				widget.style[backdrop_id(index)].color[1] = 0
				widget.style[backdrop_fade_id(index)].color[1] = 0
			end
		end

		-- Every song name gets measured once, so the widths are forgotten whenever nothing shows, and they never pile up.
		if line_count == 0 and next(self._widths) then
			self._widths = {}
			self._fitted = {}
		end
	end

	function Element:update(dt, t, ui_renderer, render_settings, input_service)
		-- The game sets the draw scale to the HUD Scale for this element just before calling it, so it is current after the player changes it.
		self._draw_scale = render_settings and render_settings.scale

		-- This runs inside the game's own UI update, so a failure here only freezes the message.
		local ok, err = pcall(self._draw_lines, self, dt, ui_renderer)
		if not ok then
			OnScreenMessage.report_draw_failure(err)
		end

		Element.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	end

	return Element
end
