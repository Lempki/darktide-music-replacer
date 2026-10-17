-- The constant UI element that draws the debug overlay's text over a dark backdrop, in a top corner of the screen.
-- debug_overlay.lua adds and removes it, and gives it its text.

require("scripts/ui/constant_elements/constant_element_base")

local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

local SIZE = { 600, 76 }
local MARGIN = 20
local PADDING = 10

-- Building the text makes strings, so it is refreshed a few times a second, not every frame.
local REFRESH_SECONDS = 0.25

local definitions = {
	scenegraph_definition = {
		screen = UIWorkspaceSettings.screen,
		overlay = {
			parent = "screen",
			vertical_alignment = "top",
			horizontal_alignment = "left",
			size = SIZE,
			position = { MARGIN, MARGIN, 1 },
		},
	},
	widget_definitions = {
		overlay = UIWidget.create_definition({
			{
				pass_type = "rect",
				style = {
					color = { 160, 0, 0, 0 },
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
					text_color = { 255, 230, 230, 230 },
					text_horizontal_alignment = "left",
					text_vertical_alignment = "top",
					size = { SIZE[1] - 2 * PADDING, SIZE[2] - 2 * PADDING },
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

	-- "top_left" or "top_right".
	function Element:set_corner(corner)
		local right = corner == "top_right"
		self:set_scenegraph_position("overlay", right and -MARGIN or MARGIN, MARGIN, nil, right and "right" or "left", "top")
		self._widgets_by_name.overlay.style.text.text_horizontal_alignment = right and "right" or "left"
	end

	function Element:update(dt, t, ui_renderer, render_settings, input_service)
		self._refresh_in = self._refresh_in - dt
		if self._refresh_in <= 0 then
			self._refresh_in = REFRESH_SECONDS
			self._widgets_by_name.overlay.content.text = DebugOverlay.current_text()
		end

		Element.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	end

	return Element
end
