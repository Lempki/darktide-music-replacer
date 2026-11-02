-- Pins key_message.lua: how a playback key's message fades in, holds, fades out, and gives way to a newer one.

local FakeEngine = require("tests.helpers.fake_engine")

local function load_key_message()
	local engine = FakeEngine.new()
	return engine:load("key_message")
end

-- The lines showing now, oldest first, each as its text and opacity.
local function lines_of(KeyMessage)
	local lines = {}
	for index = 1, KeyMessage.line_count() do
		local text, opacity = KeyMessage.line(index)
		lines[#lines + 1] = { text = text, opacity = opacity }
	end
	return lines
end

-- Checks the texts and opacities showing now, with opacities compared to within rounding.
local function assert_lines(KeyMessage, expected)
	local lines = lines_of(KeyMessage)
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
	end
end

describe("key_message.lua", function()
	it("shows nothing before a message", function()
		local KeyMessage = load_key_message()

		KeyMessage.advance(1)

		assert_equal(KeyMessage.line_count(), 0)
	end)

	it("fades a message in over 0.4 s", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Next")
		assert_lines(KeyMessage, { { "Next", 0 } })

		KeyMessage.advance(0.1)
		assert_lines(KeyMessage, { { "Next", 0.25 } })

		KeyMessage.advance(0.3)
		assert_lines(KeyMessage, { { "Next", 1 } })
	end)

	it("holds a message at full opacity until 3.4 s after it shows, then fades it out by 4.4 s", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Next")
		KeyMessage.advance(0.4)
		KeyMessage.advance(3)
		assert_lines(KeyMessage, { { "Next", 1 } })

		KeyMessage.advance(0.25)
		assert_lines(KeyMessage, { { "Next", 0.75 } })

		KeyMessage.advance(0.75)
		assert_equal(KeyMessage.line_count(), 0)
	end)

	it("crossfades to a different message over 0.3 s, the old line fading out over the new one", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Next")
		KeyMessage.advance(0.4)
		KeyMessage.show("Previous")
		assert_lines(KeyMessage, { { "Next", 1 }, { "Previous", 0 } })

		KeyMessage.advance(0.06)
		assert_lines(KeyMessage, { { "Next", 0.8 }, { "Previous", 0.2 } })

		KeyMessage.advance(0.25)
		assert_lines(KeyMessage, { { "Previous", 1 } })
	end)

	it("fades a replaced line out from the opacity it had, at the crossfade's rate", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Next")
		KeyMessage.advance(0.2)
		KeyMessage.show("Previous")
		KeyMessage.advance(0.06)

		assert_lines(KeyMessage, { { "Next", 0.3 }, { "Previous", 0.2 } })
	end)

	it("gives the new message its own full hold after the crossfade", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Next")
		KeyMessage.advance(2)
		KeyMessage.show("Previous")
		KeyMessage.advance(0.3)
		KeyMessage.advance(3)
		assert_lines(KeyMessage, { { "Previous", 1 } })

		KeyMessage.advance(1)
		assert_equal(KeyMessage.line_count(), 0)
	end)

	it("keeps the line of the same text shown again, and fades it back in from the opacity it has", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Paused")
		KeyMessage.advance(0.4)
		KeyMessage.advance(3)
		KeyMessage.advance(0.5)
		KeyMessage.show("Paused")
		assert_lines(KeyMessage, { { "Paused", 0.5 } })

		KeyMessage.advance(0.2)
		assert_lines(KeyMessage, { { "Paused", 1 } })
	end)

	it("starts the hold over when the same text shows again during it", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Paused")
		KeyMessage.advance(0.4)
		KeyMessage.advance(2)
		KeyMessage.show("Paused")
		KeyMessage.advance(3)
		assert_lines(KeyMessage, { { "Paused", 1 } })

		KeyMessage.advance(1)
		assert_equal(KeyMessage.line_count(), 0)
	end)

	it("keeps at most 3 lines fading out, dropping the faintest rather than the oldest", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("A")
		KeyMessage.advance(0.4)
		KeyMessage.show("B")
		KeyMessage.advance(0.09)
		KeyMessage.show("C")
		KeyMessage.advance(0.03)
		KeyMessage.show("D")
		assert_lines(KeyMessage, { { "A", 0.6 }, { "B", 0.2 }, { "C", 0.1 }, { "D", 0 } })

		KeyMessage.show("E")

		assert_lines(KeyMessage, { { "A", 0.6 }, { "B", 0.2 }, { "C", 0.1 }, { "E", 0 } })
	end)

	it("carries a long frame's time through the fade in and the hold into the fade out", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Next")
		KeyMessage.advance(4)

		assert_lines(KeyMessage, { { "Next", 0.4 } })
	end)

	it("carries a long frame past the crossfade into the new message's hold", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Next")
		KeyMessage.advance(0.4)
		KeyMessage.show("Previous")
		KeyMessage.advance(0.5)
		assert_lines(KeyMessage, { { "Previous", 1 } })

		KeyMessage.advance(2.8)
		assert_lines(KeyMessage, { { "Previous", 1 } })

		KeyMessage.advance(0.5)
		assert_lines(KeyMessage, { { "Previous", 0.5 } })
	end)

	it("shows nothing once a single frame outlasts the whole message", function()
		local KeyMessage = load_key_message()

		KeyMessage.show("Next")
		KeyMessage.advance(4.4)

		assert_equal(KeyMessage.line_count(), 0)
	end)
end)
