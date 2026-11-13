-- Pins on_screen_message.lua: how the on-screen message fades in, holds, fades out, and is pushed aside by a newer one.
-- It also pins adding and removing its element on the game's constant UI.
-- The constant UI is a stand-in with the fields and functions the game's own has.

local FakeEngine = require("tests.helpers.fake_engine")

local CLASS_NAME = "ConstantElementMusicReplacerOnScreenMessage"

-- A stand-in for the game's UIConstantElements, with two visibility groups.
local function new_constant_elements()
	local constant_elements = {
		_elements = {},
		_elements_array = { { __class_name = "ConstantElementChat" } },
		_visibility_groups = { { name = "in_loading" }, { name = "default" } },
		_visibility_group_parameters = {},
		_elements_hud_scale_lookup = {},
		_current_group_name = "default",
	}

	function constant_elements:_setup_visiblity_groups(definitions)
		for _, definition in ipairs(definitions) do
			for _, group in ipairs(self._visibility_groups) do
				group.visible_elements = group.visible_elements or {}
				group.visible_elements[definition.class_name] = true
			end
		end
	end

	function constant_elements:ui_renderer()
		return "renderer"
	end

	return constant_elements
end

-- Returns a loaded on_screen_message.lua, turned on, with no constant UI to add its element to.
local function load_on_screen_message()
	local engine = FakeEngine.new()
	local OnScreenMessage = engine:load("on_screen_message")
	OnScreenMessage.set_enabled(true)
	return OnScreenMessage
end

-- Returns a loaded on_screen_message.lua over `constant_elements`, still turned off, the elements it made, and the logged lines.
local function load_with_element(constant_elements, failing)
	local engine = FakeEngine.new()
	local OnScreenMessage = engine:load("on_screen_message")
	local made = {}
	local lines = {}
	rawset(Managers, "ui", { ui_constant_elements = function() return constant_elements end })

	OnScreenMessage.init(function(line) lines[#lines + 1] = line end, {
		create_element = function(parent, draw_layer)
			if failing then
				error("no renderer")
			end
			local element = { __class_name = CLASS_NAME, parent = parent, draw_layer = draw_layer, layouts = {} }
			function element:destroy(renderer) self.destroyed_with = renderer end
			function element:set_layout(look) self.layouts[#self.layouts + 1] = look end
			made[#made + 1] = element
			return element
		end,
	})

	return OnScreenMessage, made, lines
end

-- The lines showing now, oldest first, each as its text, opacity, and place.
local function lines_of(OnScreenMessage)
	local lines = {}
	for index = 1, OnScreenMessage.line_count() do
		local text, opacity, place = OnScreenMessage.line(index)
		lines[#lines + 1] = { text = text, opacity = opacity, place = place }
	end
	return lines
end

-- Checks the texts and opacities showing now, with opacities compared to within rounding.
-- An expected line's third value, when given, is its place: 0 at the corner and 1 in the previous line's place.
local function assert_lines(OnScreenMessage, expected)
	local lines = lines_of(OnScreenMessage)
	local texts = {}
	local expected_texts = {}
	for index, line in ipairs(lines) do
		texts[index] = line.text
	end
	for index, line in ipairs(expected) do
		expected_texts[index] = line[1]
	end
	assert_deep_equal(texts, expected_texts)

	for index, line in ipairs(expected) do
		local opacity = lines[index].opacity
		assert_equal(math.abs(opacity - line[2]) < 1e-9, true, line[1] .. "'s opacity " .. tostring(opacity))
		if line[3] then
			local place = lines[index].place
			assert_equal(math.abs(place - line[3]) < 1e-9, true, line[1] .. "'s place " .. tostring(place))
		end
	end
end

describe("on_screen_message.lua", function()
	it("shows nothing before a message", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.advance(1)

		assert_equal(OnScreenMessage.line_count(), 0)
	end)

	it("fades a message in over 0.4 s", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Next")
		assert_lines(OnScreenMessage, { { "Next", 0 } })

		OnScreenMessage.advance(0.1)
		assert_lines(OnScreenMessage, { { "Next", 0.25 } })

		OnScreenMessage.advance(0.3)
		assert_lines(OnScreenMessage, { { "Next", 1 } })
	end)

	it("holds a message at full opacity until 4.4 s after it shows, then fades it out by 5.4 s", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Next")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.advance(4)
		assert_lines(OnScreenMessage, { { "Next", 1 } })

		OnScreenMessage.advance(0.25)
		assert_lines(OnScreenMessage, { { "Next", 0.75 } })

		OnScreenMessage.advance(0.75)
		assert_equal(OnScreenMessage.line_count(), 0)
	end)

	it("pushes the message showing into the previous line's place over 0.3 s, as a different one fades in at the corner", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Next")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("Previous")
		assert_lines(OnScreenMessage, { { "Next", 1, 0 }, { "Previous", 0, 0 } })

		OnScreenMessage.advance(0.15)
		assert_lines(OnScreenMessage, { { "Next", 1, 0.5 }, { "Previous", 0.5, 0 } })

		OnScreenMessage.advance(0.15)
		assert_lines(OnScreenMessage, { { "Next", 1, 1 }, { "Previous", 1, 0 } })
	end)

	it("keeps a pushed message's own timer, so it fades out when it would have, before the newer one", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Next")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.advance(2)
		OnScreenMessage.show("Previous")
		OnScreenMessage.advance(2)
		assert_lines(OnScreenMessage, { { "Next", 1, 1 }, { "Previous", 1, 0 } })

		OnScreenMessage.advance(0.5)
		assert_lines(OnScreenMessage, { { "Next", 0.5, 1 }, { "Previous", 1, 0 } })

		OnScreenMessage.advance(0.5)
		assert_lines(OnScreenMessage, { { "Previous", 1, 0 } })

		OnScreenMessage.advance(1.3)
		assert_lines(OnScreenMessage, { { "Previous", 1, 0 } })

		OnScreenMessage.advance(1)
		assert_equal(OnScreenMessage.line_count(), 0)
	end)

	it("pushes the previous message out when a third shows, fading it out where it was over 0.3 s", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("A")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("B")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("C")
		assert_lines(OnScreenMessage, { { "A", 1, 1 }, { "B", 1, 0 }, { "C", 0, 0 } })

		OnScreenMessage.advance(0.15)
		assert_lines(OnScreenMessage, { { "A", 0.5, 1 }, { "B", 1, 0.5 }, { "C", 0.5, 0 } })

		OnScreenMessage.advance(0.15)
		assert_lines(OnScreenMessage, { { "B", 1, 1 }, { "C", 1, 0 } })
	end)

	it("shows a text again at the corner while its older copy leaves the previous line's place", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("A")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("B")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("A")

		assert_lines(OnScreenMessage, { { "A", 1, 1 }, { "B", 1, 0 }, { "A", 0, 0 } })
	end)

	it("keeps the line of the same text shown again, and fades it back in from the opacity it has", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Paused")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.advance(4)
		OnScreenMessage.advance(0.5)
		OnScreenMessage.show("Paused")
		assert_lines(OnScreenMessage, { { "Paused", 0.5 } })

		OnScreenMessage.advance(0.2)
		assert_lines(OnScreenMessage, { { "Paused", 1 } })
	end)

	it("starts the hold over when the same text shows again during it", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Paused")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.advance(2)
		OnScreenMessage.show("Paused")
		OnScreenMessage.advance(4)
		assert_lines(OnScreenMessage, { { "Paused", 1 } })

		OnScreenMessage.advance(1)
		assert_equal(OnScreenMessage.line_count(), 0)
	end)

	it("keeps at most 2 lines leaving, dropping the faintest rather than the oldest", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("A")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("B")
		OnScreenMessage.advance(0.09)
		OnScreenMessage.show("C")
		OnScreenMessage.advance(0.03)
		OnScreenMessage.show("D")
		assert_lines(OnScreenMessage, { { "A", 0.9, 1 }, { "B", 0.4, 1 }, { "C", 0.1, 0 }, { "D", 0, 0 } })

		OnScreenMessage.show("E")

		assert_lines(OnScreenMessage, { { "A", 0.9, 1 }, { "B", 0.4, 1 }, { "D", 0, 0 }, { "E", 0, 0 } })
	end)

	it("carries a long frame's time through the fade in and the hold into the fade out", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Next")
		OnScreenMessage.advance(5)

		assert_lines(OnScreenMessage, { { "Next", 0.4 } })
	end)

	it("carries a long frame past the push into the new message's hold", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Next")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("Previous")
		OnScreenMessage.advance(0.5)
		assert_lines(OnScreenMessage, { { "Next", 1, 1 }, { "Previous", 1, 0 } })

		OnScreenMessage.advance(3.8)
		assert_lines(OnScreenMessage, { { "Next", 0.7, 1 }, { "Previous", 1, 0 } })

		OnScreenMessage.advance(0.5)
		assert_lines(OnScreenMessage, { { "Next", 0.2, 1 }, { "Previous", 0.5, 0 } })
	end)

	it("holds and fades out for as long as its timing says", function()
		local OnScreenMessage = load_on_screen_message()
		OnScreenMessage.set_timing(5, 2)

		OnScreenMessage.show("Next")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.advance(5)
		assert_lines(OnScreenMessage, { { "Next", 1 } })

		OnScreenMessage.advance(1)
		assert_lines(OnScreenMessage, { { "Next", 0.5 } })

		OnScreenMessage.advance(1)
		assert_equal(OnScreenMessage.line_count(), 0)
	end)

	it("hides a message at once after its hold when its fade out is 0", function()
		local OnScreenMessage = load_on_screen_message()
		OnScreenMessage.set_timing(3, 0)

		OnScreenMessage.show("Next")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.advance(3)
		assert_lines(OnScreenMessage, { { "Next", 1 } })

		OnScreenMessage.advance(0.01)
		assert_equal(OnScreenMessage.line_count(), 0)
	end)

	it("says how long a new message stays on screen: its 0.4 s fade in, then the hold and the fade out its timing sets", function()
		local OnScreenMessage = load_on_screen_message()
		assert_equal(math.abs(OnScreenMessage.seconds_shown() - 5.4) < 1e-9, true)

		OnScreenMessage.set_timing(1, 2)
		assert_equal(math.abs(OnScreenMessage.seconds_shown() - 3.4) < 1e-9, true)

		OnScreenMessage.show("Press again")
		OnScreenMessage.advance(3.3)
		assert_equal(OnScreenMessage.line_count(), 1)
		OnScreenMessage.advance(0.2)
		assert_equal(OnScreenMessage.line_count(), 0)
	end)

	it("shows nothing once a single frame outlasts the whole message", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.show("Next")
		OnScreenMessage.advance(5.4)

		assert_equal(OnScreenMessage.line_count(), 0)
	end)

	it("shows nothing while turned off, and forgets the lines showing when turned off", function()
		local OnScreenMessage = load_on_screen_message()
		OnScreenMessage.show("Next")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("Restart")
		OnScreenMessage.advance(0.4)
		OnScreenMessage.show("Pause")

		OnScreenMessage.set_enabled(false)
		assert_equal(OnScreenMessage.line_count(), 0)

		OnScreenMessage.show("Previous")
		assert_equal(OnScreenMessage.line_count(), 0)

		OnScreenMessage.set_enabled(true)
		assert_equal(OnScreenMessage.line_count(), 0)
	end)
end)

describe("on_screen_message.lua look", function()
	it("starts at 85% size, in muted grey at 85% opacity, in the bottom left corner, on a 70% backdrop", function()
		local OnScreenMessage = load_on_screen_message()

		assert_deep_equal(OnScreenMessage.look(),
			{ scale = 0.85, color = { 217, 200, 200, 195 }, corner = "bottom_left", offset_x = 0, offset_y = 0, backdrop_opacity = 0.7 })
	end)

	it("takes the look it is given", function()
		local OnScreenMessage = load_on_screen_message()
		local look = { scale = 1.5, color = { 255, 10, 20, 30 }, corner = "top_right", offset_x = 300, offset_y = 40, backdrop_opacity = 0 }

		OnScreenMessage.set_enabled(true, look)

		assert_deep_equal(OnScreenMessage.look(), look)
	end)

	it("treats a saved negative offset as 0, so the message never moves past its corner", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.set_enabled(true, { scale = 1, color = { 217, 200, 200, 195 }, corner = "top_right", offset_x = -10, offset_y = -20 })

		assert_equal(OnScreenMessage.look().offset_x, 0)
		assert_equal(OnScreenMessage.look().offset_y, 0)
	end)

	it("keeps the bottom left corner when the saved corner is not one it knows", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.set_enabled(true, { scale = 1, color = { 217, 200, 200, 195 }, corner = "middle", offset_x = 0, offset_y = 0 })

		assert_equal(OnScreenMessage.look().corner, "bottom_left")
	end)

	it("keeps the default color when the saved color is not four numbers", function()
		local OnScreenMessage = load_on_screen_message()

		OnScreenMessage.set_enabled(true, { scale = 1, color = { 255, 10, 20 }, offset_x = 0, offset_y = 0 })
		assert_deep_equal(OnScreenMessage.look().color, { 217, 200, 200, 195 })

		OnScreenMessage.set_enabled(true, { scale = 1, color = "grey", offset_x = 0, offset_y = 0 })
		assert_deep_equal(OnScreenMessage.look().color, { 217, 200, 200, 195 })
	end)
end)

describe("on_screen_message.lua placement", function()
	local function placement(corner, offset_x, offset_y)
		local OnScreenMessage = load_on_screen_message()
		return OnScreenMessage.placement({ corner = corner, offset_x = offset_x, offset_y = offset_y })
	end

	it("puts the backdrop against its corner's edges at offsets of 0", function()
		assert_deep_equal(placement("bottom_left", 0, 0),
			{ horizontal = "left", vertical = "bottom", toward_x = 1, toward_y = -1, x = 0, y = 0 })
	end)

	it("aligns to the corner's side, and moves inward from every corner as the offsets grow", function()
		assert_deep_equal(placement("bottom_left", 10, 20),
			{ horizontal = "left", vertical = "bottom", toward_x = 1, toward_y = -1, x = 10, y = -20 })
		assert_deep_equal(placement("bottom_right", 10, 20),
			{ horizontal = "right", vertical = "bottom", toward_x = -1, toward_y = -1, x = -10, y = -20 })
		assert_deep_equal(placement("top_left", 10, 20),
			{ horizontal = "left", vertical = "top", toward_x = 1, toward_y = 1, x = 10, y = 20 })
		assert_deep_equal(placement("top_right", 10, 20),
			{ horizontal = "right", vertical = "top", toward_x = -1, toward_y = 1, x = -10, y = 20 })
	end)
end)

describe("on_screen_message.lua element", function()
	it("adds its element to every visibility group at the HUD Scale once turned on, and removes it all once turned off", function()
		local constant_elements = new_constant_elements()
		local OnScreenMessage, made = load_with_element(constant_elements)

		OnScreenMessage.update()
		assert_equal(#made, 0)

		OnScreenMessage.set_enabled(true)

		assert_equal(constant_elements._elements[CLASS_NAME], made[1])
		assert_equal(constant_elements._elements_array[2], made[1])
		assert_equal(made[1].draw_layer, 900)
		assert_equal(constant_elements._visibility_groups[1].visible_elements[CLASS_NAME], true)
		assert_equal(constant_elements._elements_hud_scale_lookup[CLASS_NAME], true)

		OnScreenMessage.set_enabled(false)

		assert_equal(constant_elements._elements[CLASS_NAME], nil)
		assert_equal(#constant_elements._elements_array, 1)
		assert_equal(constant_elements._visibility_groups[2].visible_elements[CLASS_NAME], nil)
		assert_equal(constant_elements._elements_hud_scale_lookup[CLASS_NAME], nil)
		assert_equal(made[1].destroyed_with, "renderer")
	end)

	it("gives its element a new look without making a new one", function()
		local OnScreenMessage, made = load_with_element(new_constant_elements())
		OnScreenMessage.set_enabled(true)

		local look = { scale = 2, color = { 255, 10, 20, 30 }, corner = "top_left", offset_x = 5, offset_y = 6, backdrop_opacity = 0.5 }

		OnScreenMessage.set_enabled(true, look)

		assert_equal(#made, 1)
		assert_deep_equal(made[1].layouts, { look })
	end)

	it("removes its element on shutdown", function()
		local constant_elements = new_constant_elements()
		local OnScreenMessage, made = load_with_element(constant_elements)
		OnScreenMessage.set_enabled(true)

		OnScreenMessage.shutdown()

		assert_equal(constant_elements._elements[CLASS_NAME], nil)
		assert_equal(made[1].destroyed_with, "renderer")
	end)

	it("logs once and stops trying when its element cannot be made", function()
		local constant_elements = new_constant_elements()
		local OnScreenMessage, _, lines = load_with_element(constant_elements, true)

		OnScreenMessage.set_enabled(true)
		OnScreenMessage.update()
		OnScreenMessage.update()

		assert_equal(#lines, 1)
		assert_equal(lines[1]:find("[on-screen message] could not be shown", 1, true) ~= nil, true)
		assert_equal(constant_elements._visibility_groups[1].visible_elements[CLASS_NAME], nil)
	end)

	it("logs each drawing failure once, however often it repeats", function()
		local OnScreenMessage, _, lines = load_with_element(new_constant_elements())

		OnScreenMessage.report_draw_failure("bad font")
		OnScreenMessage.report_draw_failure("bad font")
		OnScreenMessage.report_draw_failure("bad style")

		assert_deep_equal(lines, { "[on-screen message] drawing failed: bad font", "[on-screen message] drawing failed: bad style" })
	end)
end)
