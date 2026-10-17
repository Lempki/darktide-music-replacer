-- The constant UI element that draws the debug overlay's text in a top corner of the screen.
-- debug_overlay.lua adds and removes it, and gives it its text.
-- The backdrop follows the text's size: solid behind the start of the text, then fading out past its end.

require("scripts/ui/constant_elements/constant_element_base")

local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

-- Large enough for any text the overlay shows. The backdrop and the text are sized and placed inside it.
local AREA_SIZE = { 1200, 400 }
local MARGIN = 20
local PADDING = 10

-- The share of the backdrop that is solid, and how far the fade reaches past the text.
local SOLID_SHARE = 0.55
local FADE_PAST_TEXT = 120

local BACKDROP_COLOR = { 170, 0, 0, 0 }

-- The game's horizontal gradient fades toward its left edge, so these uvs flip it to fade toward the right.
local FADE_RIGHT_UVS = { { 1, 0 }, { 0, 1 } }
local FADE_LEFT_UVS = { { 0, 0 }, { 1, 1 } }

-- Building the text makes strings, so it is refreshed a few times a second, not every frame.
local REFRESH_SECONDS = 0.25

local definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
		overlay = {
			parent = "screen",
			vertical_alignment = "top",
			horizontal_alignment = "left",
			size = AREA_SIZE,
			position = { MARGIN, MARGIN, 1 },
		},
	},
	widget_definitions = {
		overlay = UIWidget.create_definition({
			{
				pass_type = "rect",
				style_id = "solid",
				style = {
					color = BACKDROP_COLOR,
					horizontal_alignment = "left",
					vertical_alignment = "top",
					size = { 0, 0 },
					offset = { 0, 0, 0 },
				},
			},
			{
				pass_type = "texture_uv",
				style_id = "fade",
				value = "content/ui/materials/gradients/gradient_horizontal",
				style = {
					color = BACKDROP_COLOR,
					horizontal_alignment = "left",
					vertical_alignment = "top",
					size = { 0, 0 },
					offset = { 0, 0, 0 },
					uvs = FADE_RIGHT_UVS,
				},
			},
			{
				pass_type = "text",
				value_id = "text",
				value = "",
				style_id = "text",
				style = {
					font_type = "proxima_nova_bold",
					font_size = 16,
					line_spacing = 1.1,
					drop_shadow = true,
					text_color = { 255, 235, 235, 235 },
					text_horizontal_alignment = "left",
					text_vertical_alignment = "top",
					horizontal_alignment = "left",
					vertical_alignment = "top",
					size = { AREA_SIZE[1] - 2 * PADDING, AREA_SIZE[2] - 2 * PADDING },
					offset = { PADDING, PADDING, 1 },
				},
			},
		}, "overlay"),
	},
}

-- `DebugOverlay` is the loaded debug_overlay.lua. Returns the element class.
return function(DebugOverlay)
	local Element = class("ConstantElementMusicReplacerOverlay", "ConstantElementBase")

	function Element:init(parent, draw_layer, start_scale)
		Element.super.init(self, parent, draw_layer, start_scale, definitions)
		self._refresh_in = 0
		self:set_corner(DebugOverlay.corner())
	end

	-- "top_left" or "top_right". On the right, everything is mirrored, so the fade runs toward the screen's middle.
	function Element:set_corner(corner)
		local right = corner == "top_right"
		local side = right and "right" or "left"
		local style = self._widgets_by_name.overlay.style

		self._right = right
		self:set_scenegraph_position("overlay", right and -MARGIN or MARGIN, MARGIN, nil, side, "top")
		style.solid.horizontal_alignment = side
		style.fade.horizontal_alignment = side
		style.fade.uvs = right and FADE_LEFT_UVS or FADE_RIGHT_UVS
		style.text.horizontal_alignment = side
		style.text.text_horizontal_alignment = side
		style.text.offset[1] = right and -PADDING or PADDING
		self._refresh_in = 0
	end

	-- Sizes the backdrop to the text, which changes length with the song name and the lines shown.
	function Element:_fit_backdrop(ui_renderer)
		local style = self._widgets_by_name.overlay.style
		local text = self._widgets_by_name.overlay.content.text
		local text_width, text_height = UIRenderer.styled_text_size(ui_renderer, text, style.text, style.text.size)

		local height = text_height + 2 * PADDING
		local width = text_width + 2 * PADDING
		local solid_width = math.floor(width * SOLID_SHARE)
		local fade_width = width - solid_width + FADE_PAST_TEXT

		style.solid.size[1] = solid_width
		style.solid.size[2] = height
		style.fade.size[1] = fade_width
		style.fade.size[2] = height
		style.fade.offset[1] = self._right and -solid_width or solid_width
	end

	function Element:update(dt, t, ui_renderer, render_settings, input_service)
		self._refresh_in = self._refresh_in - dt
		if self._refresh_in <= 0 then
			self._refresh_in = REFRESH_SECONDS
			self._widgets_by_name.overlay.content.text = DebugOverlay.current_text()
			self:_fit_backdrop(ui_renderer)
		end

		Element.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	end

	return Element
end
