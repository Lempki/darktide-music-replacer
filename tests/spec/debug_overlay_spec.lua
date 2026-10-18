-- Pins debug_overlay.lua: the overlay's text, and adding and removing its element on the game's constant UI.
-- The constant UI is a stand-in with the fields and functions the game's own has.

local FakeEngine = require("tests.helpers.fake_engine")

local CLASS_NAME = "ConstantElementMusicReplacerOverlay"

-- A stand-in for the game's UIConstantElements, with two visibility groups.
local function new_constant_elements()
	local constant_elements = {
		_elements = {},
		_elements_array = { { __class_name = "ConstantElementChat" } },
		_visibility_groups = { { name = "in_loading" }, { name = "default" } },
		_visibility_group_parameters = {},
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

-- Returns a loaded debug_overlay.lua over `constant_elements`, the elements it made, and the logged lines.
local function load_overlay(constant_elements, failing)
	local engine = FakeEngine.new()
	local DebugOverlay = engine:load("debug_overlay")
	local made = {}
	local lines = {}
	local ui = { current = constant_elements }
	rawset(Managers, "ui", { ui_constant_elements = function() return ui.current end })

	DebugOverlay.init(function(line) lines[#lines + 1] = line end, {
		snapshot = function() return { context = "hub", status = "Custom" } end,
		create_element = function(parent, draw_layer)
			if failing then
				error("no renderer")
			end
			local element = { __class_name = CLASS_NAME, parent = parent, draw_layer = draw_layer, corners = {} }
			function element:destroy(renderer) self.destroyed_with = renderer end
			function element:set_layout(corner, scale) self.corners[#self.corners + 1] = corner .. "@" .. scale end
			made[#made + 1] = element
			return element
		end,
	})

	return DebugOverlay, made, lines, ui
end

local function full_snapshot()
	return {
		context = "mission_combat",
		status = "Custom",
		folder = "mission_combat",
		song = "Antagonist - Valfaris.mp3",
		position = 83.4,
		duration = 265.6,
		volume = 1,
		menu_level = 0.5,
		song_level = 10 ^ (-7.9 / 20),
		evening_out = true,
	}
end

describe("debug_overlay.lua text", function()
	it("shows the context and its choice, the song with its time, and the volume factors", function()
		local DebugOverlay = load_overlay(new_constant_elements())

		assert_equal(DebugOverlay.text(full_snapshot()),
			"Context: mission_combat (Custom)\n" ..
			"Folder: mission_combat\n" ..
			"Song: Antagonist - Valfaris.mp3  1:23 / 4:25\n" ..
			"Volume: custom 100%, menu 50%, song -7.9 dB")
	end)

	it("adds a line of its own for the hold, the pending change, and a song playing to its end", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		snapshot.hold = "combat"
		snapshot.hold_seconds = 6.24
		snapshot.pending = "mission_boss"
		snapshot.pending_seconds = 0.4
		snapshot.finishing = "mission_boss"

		local lines = DebugOverlay.lines(snapshot)

		assert_equal(#lines, 5)
		assert_deep_equal(lines[3], { "Waiting", "combat hold 6.2s, mission_boss in 0.4s, mission_boss song playing to its end", timing = true })
	end)

	it("dims the labels and colors the waiting line in the game's text markup", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		snapshot.hold = "horde"
		snapshot.hold_seconds = 2

		local rows = {}
		for row in DebugOverlay.text(snapshot, true):gmatch("[^\n]+") do
			rows[#rows + 1] = row
		end

		assert_equal(rows[1], "{#color(150,150,150)}Context: {#reset()}mission_combat (Custom){#reset()}")
		assert_equal(rows[3], "{#color(150,150,150)}Waiting: {#color(255,190,90)}horde hold 2.0s{#reset()}")
	end)

	it("shows no song while the game's music plays, songs as recorded while evening out is off, and long names cut short", function()
		local DebugOverlay = load_overlay(new_constant_elements())

		local game = DebugOverlay.text({ context = "mission_event", status = "game's music, no songs", evening_out = false })
		assert_equal(game, "Context: mission_event (game's music, no songs)\nFolder: none\nSong: none\nVolume: custom 100%, menu 100%, song as recorded")

		local snapshot = full_snapshot()
		snapshot.song = string.rep("a", 60) .. ".mp3"
		local song_line = DebugOverlay.text(snapshot):match("(Song: [^\n]+)")
		assert_equal(song_line, "Song: " .. string.rep("a", 45) .. "...  1:23 / 4:25")
	end)

	it("names the override folders the context looks for, after the folder it plays from", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		snapshot.context = "mission_boss"
		snapshot.folder = "mission_boss/chaos_spawn"
		snapshot.overrides = "chaos_spawn, fm_cargo, havoc"

		assert_deep_equal(DebugOverlay.lines(snapshot)[2], { "Folder", "mission_boss/chaos_spawn, overrides: chaos_spawn, fm_cargo, havoc" })
	end)

	it("says so while the mod is turned off", function()
		local DebugOverlay = load_overlay(new_constant_elements())

		assert_equal(DebugOverlay.text({ turned_off = true }), "Music Replacer: turned off")
	end)
end)

describe("debug_overlay.lua element", function()
	it("adds its element to every visibility group once turned on, and removes it all once turned off", function()
		local constant_elements = new_constant_elements()
		local DebugOverlay, made = load_overlay(constant_elements)

		DebugOverlay.update()
		assert_equal(#made, 0)

		DebugOverlay.set_enabled(true, "top_left")

		assert_equal(constant_elements._elements[CLASS_NAME], made[1])
		assert_equal(constant_elements._elements_array[2], made[1])
		assert_equal(made[1].draw_layer, 900)
		assert_equal(constant_elements._visibility_groups[1].visible_elements[CLASS_NAME], true)
		assert_equal(constant_elements._current_group_name, nil)

		DebugOverlay.set_enabled(false, "top_left")

		assert_equal(constant_elements._elements[CLASS_NAME], nil)
		assert_equal(#constant_elements._elements_array, 1)
		assert_equal(constant_elements._visibility_groups[2].visible_elements[CLASS_NAME], nil)
		assert_equal(made[1].destroyed_with, "renderer")
	end)

	it("moves and sizes its element without making a new one", function()
		local DebugOverlay, made = load_overlay(new_constant_elements())
		DebugOverlay.set_enabled(true, "top_left", 1)

		DebugOverlay.set_enabled(true, "top_right", 1.5)

		assert_equal(#made, 1)
		assert_deep_equal(made[1].corners, { "top_right@1.5" })
		assert_equal(DebugOverlay.corner(), "top_right")
		assert_equal(DebugOverlay.scale(), 1.5)
	end)

	it("adds its element again when the game builds a new UI", function()
		local first = new_constant_elements()
		local DebugOverlay, made, _, ui = load_overlay(first)
		DebugOverlay.set_enabled(true, "top_left")

		local second = new_constant_elements()
		ui.current = second
		DebugOverlay.update()

		assert_equal(first._elements[CLASS_NAME], nil)
		assert_equal(second._elements[CLASS_NAME], made[2])
	end)

	it("logs once and stops trying when its element cannot be made", function()
		local constant_elements = new_constant_elements()
		local DebugOverlay, _, lines = load_overlay(constant_elements, true)

		DebugOverlay.set_enabled(true, "top_left")
		DebugOverlay.update()
		DebugOverlay.update()

		assert_equal(#lines, 1)
		assert_equal(lines[1]:find("[overlay] could not be shown", 1, true) ~= nil, true)
		assert_equal(constant_elements._visibility_groups[1].visible_elements[CLASS_NAME], nil)
	end)
end)
