-- Pins the mod options' strings against how DMF uses them.
-- DMF's mod:localize runs every string through string.format, so a literal percent sign has to be written "%%".

local FakeEngine = require("tests.helpers.fake_engine")

local INPUT_UTILS = "scripts/managers/input/input_utils"

-- Loads the localization and the options, with the game's text coloring as a stand-in that leaves the text as it is.
local function load_strings()
	local engine = FakeEngine.new()
	package.loaded[INPUT_UTILS] = { apply_color_to_input_text = function(text) return text end }
	local saved_color = rawget(_G, "Color")
	rawset(_G, "Color", { terminal_text_warning_light = function() return {} end })

	local strings = engine:load("MusicReplacer_localization")
	local data = engine:load("MusicReplacer_data")

	rawset(_G, "Color", saved_color)
	package.loaded[INPUT_UTILS] = nil
	return strings, data
end

-- Every name the options look up in the localization, from every widget below `widgets`.
local function collect_names(widgets, names)
	for _, widget in ipairs(widgets) do
		names[#names + 1] = widget.title or widget.setting_id
		names[#names + 1] = widget.tooltip
		names[#names + 1] = widget.unit_text
		names[#names + 1] = widget.button_text
		for _, option in ipairs(widget.options or {}) do
			names[#names + 1] = option.text
		end
		collect_names(widget.sub_widgets or {}, names)
	end
	return names
end

describe("MusicReplacer_localization.lua", function()
	it("formats every string the way DMF does without an error", function()
		local strings = load_strings()
		local failures = {}

		for text_id, translations in pairs(strings) do
			local ok, err = pcall(string.format, translations.en)
			if not ok then
				failures[#failures + 1] = text_id .. ": " .. tostring(err)
			end
		end
		table.sort(failures)

		assert_deep_equal(failures, {})
	end)

	it("shows a percent sign as the volume sliders' unit", function()
		local strings = load_strings()

		assert_equal(string.format(strings.percent_unit.en), "%")
	end)

	it("has a string for every name the mod options use", function()
		local strings, data = load_strings()
		local missing = {}

		for _, name in ipairs(collect_names(data.options.widgets, {})) do
			if not strings[name] then
				missing[#missing + 1] = name
			end
		end

		assert_deep_equal(missing, {})
	end)
end)
