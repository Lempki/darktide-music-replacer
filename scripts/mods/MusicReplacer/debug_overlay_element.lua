-- The constant UI element that draws the debug overlay in the top left corner of the screen.
-- debug_overlay.lua adds and removes it, and gives it a view to draw.
-- The overlay is a stack of rows of fixed heights. Everything in a row is centered on the row's middle, so it all lines up.
-- The backdrop covers the rows and fades out to the right, past the widest row.

require("scripts/ui/constant_elements/constant_element_base")

local UIRenderer = require("scripts/managers/ui/ui_renderer")
local UIWidget = require("scripts/managers/ui/ui_widget")
local UIWorkspaceSettings = require("scripts/settings/ui/ui_workspace_settings")

-- Large enough for the overlay at its largest size. Every pass is sized and placed inside it.
local AREA_SIZE = { 2400, 800 }

-- The distance from the screen's corner stays the same at every size, so the overlay grows away from the corner.
local MARGIN = 20

-- These are the sizes at 100%, and they scale with the Overlay Size setting.
local PADDING = 12
local GAP = 10
local ROW_GAP = 4
local MIN_WIDTH = 380
local FADE_WIDTH = 120
-- Wide enough for the longest row label, Measuring, with room before the bar after it.
local LABEL_WIDTH = 78
local WAITING_BAR_WIDTH = 90

-- The game measures text a little narrower than it draws it, so measured widths get this much extra.
local MEASURE_SLACK = 6

-- Text is placed in a pass far wider than itself, so it never wraps.
local TEXT_ROOM = 2000

-- The meter shows the last METER_RANGE_DB below full scale, and falls back slowly, so it reads like a level meter.
local METER_SEGMENTS = 16
local METER_HOT_SEGMENTS = 3
local METER_RANGE_DB = 48
local METER_FALL_PER_SECOND = 1.5
local SEGMENT_WIDTH = 8
local SEGMENT_HEIGHT = 11
local SEGMENT_GAP = 3

-- The longest the song's time and level get, so the column they share keeps its width whatever they read.
local LONGEST_TIME = "00:00 / 00:00"
local LONGEST_LOUDNESS = "not measured"

-- Building the view makes strings, so it is refreshed a few times a second, and only the meter moves every frame.
local REFRESH_SECONDS = 0.25

local BACKDROP_RGB = { 12, 13, 11 }
local TITLE_COLOR = { 255, 217, 165, 74 }
local TEXT_COLOR = { 255, 235, 235, 235 }
local DIM_COLOR = { 255, 150, 150, 145 }
local SOFT_COLOR = { 255, 185, 185, 180 }
local TRACK_COLOR = { 255, 58, 60, 56 }
local METER_ON_COLOR = { 255, 169, 217, 140 }
local METER_HOT_COLOR = { 255, 217, 165, 74 }
local WAITING_TRACK_COLOR = { 255, 70, 56, 32 }

-- The markers beside the meter, greyed out until a menu is open or Even Out Loudness is on, when they light up.
local MARKER_OFF = { background = { 255, 40, 42, 38 }, text = { 255, 110, 110, 105 } }
local MARKER_ON = { background = { 255, 78, 64, 30 }, text = { 255, 230, 196, 120 } }

-- Each choice's tag: green for your songs, gold for the game's music, and red for silence.
local TAG_COLORS = {
	custom = { background = { 255, 47, 74, 42 }, text = { 255, 169, 217, 140 } },
	game = { background = { 255, 78, 64, 30 }, text = { 255, 230, 196, 120 } },
	silence = { background = { 255, 84, 36, 36 }, text = { 255, 235, 160, 160 } },
}

-- The game's horizontal gradient fades toward its left edge, so these uvs flip it to fade toward the right.
local FADE_RIGHT_UVS = { { 1, 0 }, { 0, 1 } }

local function text_pass(id, font_type, font_size, color, alignment)
	return {
		pass_type = "text",
		value_id = id,
		value = "",
		style_id = id,
		style = {
			font_type = font_type,
			font_size = font_size,
			drop_shadow = true,
			text_color = color,
			text_horizontal_alignment = alignment or "left",
			text_vertical_alignment = "center",
			horizontal_alignment = "left",
			vertical_alignment = "top",
			size = { 0, 0 },
			offset = { 0, 0, 3 },
		},
	}
end

local function rect_pass(id, color, layer)
	return {
		pass_type = "rect",
		style_id = id,
		style = {
			color = color,
			horizontal_alignment = "left",
			vertical_alignment = "top",
			size = { 0, 0 },
			offset = { 0, 0, layer },
		},
	}
end

local passes = {
	rect_pass("solid", { 0, BACKDROP_RGB[1], BACKDROP_RGB[2], BACKDROP_RGB[3] }, 0),
	{
		pass_type = "texture_uv",
		style_id = "fade",
		value = "content/ui/materials/gradients/gradient_horizontal",
		style = {
			color = { 0, BACKDROP_RGB[1], BACKDROP_RGB[2], BACKDROP_RGB[3] },
			horizontal_alignment = "left",
			vertical_alignment = "top",
			size = { 0, 0 },
			offset = { 0, 0, 0 },
			uvs = FADE_RIGHT_UVS,
		},
	},
	text_pass("title", "machine_medium", 12, TITLE_COLOR),
	text_pass("situation", "machine_medium", 22, TEXT_COLOR),
	rect_pass("tag_background", TAG_COLORS.custom.background, 1),
	text_pass("tag", "proxima_nova_bold", 12, TAG_COLORS.custom.text, "center"),
	text_pass("folder", "proxima_nova_medium", 13, DIM_COLOR),
	text_pass("song", "proxima_nova_bold", 15, TEXT_COLOR),
	rect_pass("progress_track", TRACK_COLOR, 1),
	rect_pass("progress", TEXT_COLOR, 2),
	text_pass("time", "proxima_nova_medium", 13, SOFT_COLOR),
	text_pass("level_label", "proxima_nova_medium", 13, DIM_COLOR),
	rect_pass("menu_background", MARKER_OFF.background, 1),
	text_pass("menu", "proxima_nova_bold", 11, MARKER_OFF.text, "center"),
	rect_pass("evening_background", MARKER_OFF.background, 1),
	text_pass("evening", "proxima_nova_bold", 11, MARKER_OFF.text, "center"),
	text_pass("loudness", "proxima_nova_medium", 13, SOFT_COLOR),
	text_pass("waiting_label", "proxima_nova_medium", 13, TITLE_COLOR),
	rect_pass("waiting_track", WAITING_TRACK_COLOR, 1),
	rect_pass("waiting_bar", TITLE_COLOR, 2),
	text_pass("waiting", "proxima_nova_medium", 13, TITLE_COLOR),
	text_pass("measuring_label", "proxima_nova_medium", 13, TITLE_COLOR),
	rect_pass("measuring_track", WAITING_TRACK_COLOR, 1),
	rect_pass("measuring_bar", TITLE_COLOR, 2),
	text_pass("measuring", "proxima_nova_medium", 13, TITLE_COLOR),
}
for index = 1, METER_SEGMENTS do
	passes[#passes + 1] = rect_pass("segment_" .. index, TRACK_COLOR, 1)
end

local FONT_SIZES = {}
local PASS_IDS = {}
for _, pass in ipairs(passes) do
	PASS_IDS[#PASS_IDS + 1] = pass.style_id
	if pass.pass_type == "text" then
		FONT_SIZES[pass.style_id] = pass.style.font_size
	end
end

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
		overlay = UIWidget.create_definition(passes, "overlay"),
	},
}

-- `DebugOverlay` is the loaded debug_overlay.lua. Returns the element class.
return function(DebugOverlay)
	-- After a mod reload, class() hands back the class from the first load, and the methods below replace its old ones.
	local Element = class("ConstantElementMusicReplacerOverlay", "ConstantElementBase")

	function Element:init(parent, draw_layer, start_scale)
		Element.super.init(self, parent, draw_layer, start_scale, definitions)
		self._refresh_in = 0
		self._meter_fill = 0
		self:set_layout(DebugOverlay.scale(), DebugOverlay.opacity())
	end

	-- `scale` sizes everything, the fonts included, and `opacity` is the backdrop's, as a share.
	function Element:set_layout(scale, opacity)
		local style = self._widgets_by_name.overlay.style
		self._scale = scale
		for id, size in pairs(FONT_SIZES) do
			style[id].font_size = size * scale
		end
		local alpha = math.floor(255 * math.max(0, math.min(1, opacity)) + 0.5)
		style.solid.color[1] = alpha
		style.fade.color[1] = alpha
		self._refresh_in = 0
	end

	function Element:_text_width(ui_renderer, id, text)
		local style = self._widgets_by_name.overlay.style[id]
		local width = UIRenderer.styled_text_size(ui_renderer, text, style, AREA_SIZE)
		return width + MEASURE_SLACK * self._scale
	end

	-- Places text at `x` on the row starting at `y`, centered on the row.
	function Element:_text(id, x, y, row_height, width)
		local style = self._widgets_by_name.overlay.style[id]
		style.offset[1] = x
		style.offset[2] = y
		style.size[1] = width or TEXT_ROOM * self._scale
		style.size[2] = row_height
	end

	-- Places a box `width` by `height` at `x`, centered on the row starting at `y`.
	function Element:_box(id, x, y, row_height, width, height)
		local style = self._widgets_by_name.overlay.style[id]
		style.offset[1] = x
		style.offset[2] = y + (row_height - height) / 2
		style.size[1] = width
		style.size[2] = height
	end

	-- Fills in the view's text and stacks the rows the view shows.
	function Element:_lay_out(ui_renderer, view)
		local widget = self._widgets_by_name.overlay
		local content = widget.content
		local style = widget.style
		local s = self._scale
		local padding = PADDING * s
		local gap = GAP * s

		-- Every pass starts hidden, and each shown row places its own.
		for _, id in ipairs(PASS_IDS) do
			style[id].size[1] = 0
			style[id].size[2] = 0
		end

		content.title = view.title or ""
		content.situation = view.situation or ""
		content.tag = view.tag or ""
		content.folder = view.folder or ""
		content.song = view.song or view.idle or ""
		content.time = view.time or ""
		content.level_label = "Level"
		content.menu = "Menu"
		content.evening = "Loudness"
		content.loudness = view.loudness or ""
		content.waiting_label = "Waiting"
		content.waiting = view.waiting or ""
		content.measuring_label = "Measuring"
		content.measuring = view.measuring or ""

		local tag_colors = TAG_COLORS[view.kind] or TAG_COLORS.game
		style.tag_background.color = tag_colors.background
		style.tag.text_color = tag_colors.text
		style.song.text_color = view.song and TEXT_COLOR or DIM_COLOR
		local menu_colors = view.menu and MARKER_ON or MARKER_OFF
		style.menu_background.color = menu_colors.background
		style.menu.text_color = menu_colors.text
		local evening_colors = view.evening_out and MARKER_ON or MARKER_OFF
		style.evening_background.color = evening_colors.background
		style.evening.text_color = evening_colors.text

		local label_width = LABEL_WIDTH * s
		local meter_width = METER_SEGMENTS * (SEGMENT_WIDTH + SEGMENT_GAP) * s - SEGMENT_GAP * s
		local waiting_bar_width = WAITING_BAR_WIDTH * s
		local situation_width = self:_text_width(ui_renderer, "situation", content.situation)
		local tag_width = view.tag and self:_text_width(ui_renderer, "tag", content.tag) + 12 * s or 0
		local menu_width = self:_text_width(ui_renderer, "menu", content.menu) + 10 * s
		local evening_width = self:_text_width(ui_renderer, "evening", content.evening) + 10 * s
		local marker_gap = 4 * s

		-- The progress bar ends where the Loudness marker ends, and the time and the level share the column after both.
		local markers_end = label_width + meter_width + gap + menu_width + marker_gap + evening_width
		local column_width = math.max(
			self:_text_width(ui_renderer, "time", LONGEST_TIME), self:_text_width(ui_renderer, "loudness", LONGEST_LOUDNESS))

		local inner = math.max(
			MIN_WIDTH * s - 2 * padding,
			self:_text_width(ui_renderer, "title", content.title),
			situation_width + (view.tag and gap + tag_width or 0),
			view.folder and self:_text_width(ui_renderer, "folder", content.folder) or 0,
			self:_text_width(ui_renderer, "song", content.song),
			view.song and markers_end + gap + column_width or 0,
			view.waiting and label_width + waiting_bar_width + gap + self:_text_width(ui_renderer, "waiting", content.waiting) or 0,
			view.measuring and label_width + waiting_bar_width + gap + self:_text_width(ui_renderer, "measuring", content.measuring) or 0)
		local width = math.ceil(inner + 2 * padding)

		local x = padding
		local y = padding
		local function next_row(height)
			y = y + height + ROW_GAP * s
		end

		local row = 14 * s
		self:_text("title", x, y, row)
		next_row(row)

		row = 26 * s
		self:_text("situation", x, y, row)
		if view.tag then
			local tag_x = x + situation_width + gap
			self:_box("tag_background", tag_x, y, row, tag_width, 20 * s)
			self:_text("tag", tag_x, y, row, tag_width)
		end
		next_row(row)

		row = 16 * s
		if view.folder then
			self:_text("folder", x, y, row)
			next_row(row)
		end

		if view.tag then
			y = y + 4 * s
			row = 18 * s
			self:_text("song", x, y, row)
			next_row(row)
		end

		row = 16 * s
		if view.progress then
			self:_box("progress_track", x, y, row, markers_end, 4 * s)
			self:_box("progress", x, y, row, math.floor(markers_end * view.progress + 0.5), 4 * s)
			self:_text("time", x + markers_end + gap, y, row)
			next_row(row)
		end

		-- The meter only measures your songs, so its row is left out while none plays.
		if view.song then
			self:_text("level_label", x, y, row)
			for index = 1, METER_SEGMENTS do
				local segment_x = x + label_width + (index - 1) * (SEGMENT_WIDTH + SEGMENT_GAP) * s
				self:_box("segment_" .. index, segment_x, y, row, SEGMENT_WIDTH * s, SEGMENT_HEIGHT * s)
			end
			local menu_x = x + label_width + meter_width + gap
			self:_box("menu_background", menu_x, y, row, menu_width, 15 * s)
			self:_text("menu", menu_x, y, row, menu_width)
			local evening_x = menu_x + menu_width + marker_gap
			self:_box("evening_background", evening_x, y, row, evening_width, 15 * s)
			self:_text("evening", evening_x, y, row, evening_width)
			self:_text("loudness", x + markers_end + gap, y, row)
			next_row(row)
		end

		if view.waiting then
			self:_text("waiting_label", x, y, row)
			self:_box("waiting_track", x + label_width, y, row, waiting_bar_width, 3 * s)
			self:_box("waiting_bar", x + label_width, y, row, math.floor(waiting_bar_width * view.waiting_share + 0.5), 3 * s)
			self:_text("waiting", x + label_width + waiting_bar_width + gap, y, row)
			next_row(row)
		end

		if view.measuring then
			self:_text("measuring_label", x, y, row)
			self:_box("measuring_track", x + label_width, y, row, waiting_bar_width, 3 * s)
			self:_box("measuring_bar", x + label_width, y, row, math.floor(waiting_bar_width * view.measuring_share + 0.5), 3 * s)
			self:_text("measuring", x + label_width + waiting_bar_width + gap, y, row)
			next_row(row)
		end

		-- The last row added a gap below itself, which the padding replaces.
		local height = math.ceil(y - ROW_GAP * s + padding)
		self:_box("solid", 0, 0, height, width, height)
		self:_box("fade", width, 0, height, FADE_WIDTH * s, height)
	end

	-- Lights the meter's segments, falling back slowly after a peak.
	function Element:_update_meter(dt)
		local level = DebugOverlay.meter()
		local fill = 0
		if level > 0 then
			fill = math.max(0, math.min(1, 1 + 20 * math.log10(level) / METER_RANGE_DB))
		end
		self._meter_fill = math.max(fill, self._meter_fill - METER_FALL_PER_SECOND * dt)

		local style = self._widgets_by_name.overlay.style
		local lit = math.floor(self._meter_fill * METER_SEGMENTS + 0.5)
		for index = 1, METER_SEGMENTS do
			local color = TRACK_COLOR
			if index <= lit then
				color = index > METER_SEGMENTS - METER_HOT_SEGMENTS and METER_HOT_COLOR or METER_ON_COLOR
			end
			style["segment_" .. index].color = color
		end
	end

	function Element:update(dt, t, ui_renderer, render_settings, input_service)
		self._refresh_in = self._refresh_in - dt
		if self._refresh_in <= 0 then
			self._refresh_in = REFRESH_SECONDS
			-- This runs inside the game's own UI update, so a failure here only leaves the overlay as it was.
			pcall(self._lay_out, self, ui_renderer, DebugOverlay.current_view())
		end

		pcall(self._update_meter, self, dt)

		Element.super.update(self, dt, t, ui_renderer, render_settings, input_service)
	end

	return Element
end
