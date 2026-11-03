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

-- The strings the code looks up itself rather than through the options, each with how many values it is formatted with.
-- A translation has to keep each placeholder, or the message shows the wrong value or none.
local MESSAGE_ARGUMENTS = {
	song_now_playing = 1,
	control_next_song = 1,
	control_previous_song = 1,
	control_restart_song = 1,
	control_paused = 1,
	control_resumed = 1,
	control_no_song = 0,
	control_only_song = 2,
	control_remove_confirm = 2,
	control_removed_song = 2,
	control_restored_song = 0,
	control_restored_songs = 1,
	control_nothing_removed = 0,
}

-- How many values `text` formats, leaving out the "%%" that shows a percent sign.
local function placeholder_count(text)
	local _, count = text:gsub("%%%%", ""):gsub("%%[%d%.%-]*%a", "")
	return count
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

		-- The key messages take up to two arguments, such as where a song plays and its name, which the format ignores for every other string.
		for text_id, translations in pairs(strings) do
			local ok, err = pcall(string.format, translations.en, "Hub", "song.mp3")
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

	it("has every message the code shows, each formatting as many values as the code gives it", function()
		local strings = load_strings()
		local wrong = {}

		for text_id, expected in pairs(MESSAGE_ARGUMENTS) do
			if not strings[text_id] then
				wrong[#wrong + 1] = text_id .. ": missing"
			elseif placeholder_count(strings[text_id].en) ~= expected then
				wrong[#wrong + 1] = string.format("%s: %d placeholder(s), expected %d", text_id, placeholder_count(strings[text_id].en), expected)
			end
		end
		table.sort(wrong)

		assert_deep_equal(wrong, {})
	end)

	it("names every situation, as the messages and the debug overlay do", function()
		local strings = load_strings()
		local Contexts = FakeEngine.new():load("contexts")
		local missing = {}

		for _, context in ipairs(Contexts.list) do
			if not strings["source_" .. context.id] then
				missing[#missing + 1] = "source_" .. context.id
			end
		end

		assert_deep_equal(missing, {})
	end)

	it("has no string that neither the options nor the code use", function()
		local strings, data = load_strings()
		local Contexts = FakeEngine.new():load("contexts")
		local used = {}
		for _, name in ipairs(collect_names(data.options.widgets, {})) do
			used[name] = true
		end
		for text_id in pairs(MESSAGE_ARGUMENTS) do
			used[text_id] = true
		end
		for _, context in ipairs(Contexts.list) do
			used["source_" .. context.id] = true
		end

		local unused = {}
		for text_id in pairs(strings) do
			if not used[text_id] then
				unused[#unused + 1] = text_id
			end
		end
		table.sort(unused)

		assert_deep_equal(unused, {})
	end)
end)
