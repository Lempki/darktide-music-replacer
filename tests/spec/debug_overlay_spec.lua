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
			local element = { __class_name = CLASS_NAME, parent = parent, draw_layer = draw_layer, layouts = {} }
			function element:destroy(renderer) self.destroyed_with = renderer end
			function element:set_layout(scale, opacity) self.layouts[#self.layouts + 1] = scale .. "@" .. opacity end
			made[#made + 1] = element
			return element
		end,
	})

	return DebugOverlay, made, lines, ui
end

local function full_snapshot()
	return {
		context = "combat",
		situation = "Combat",
		status = "Custom",
		folder = "combat",
		song = "Antagonist - Valfaris.mp3",
		position = 83.4,
		duration = 265.6,
		volume = 1,
		menu_volume = 0.5,
		menu_level = 1,
		song_level = 10 ^ (-7.9 / 20),
		evening_out = true,
	}
end

describe("debug_overlay.lua view", function()
	it("shows the situation by its dropdown name with its choice, the folder, the song with its time, and the song's level", function()
		local DebugOverlay = load_overlay(new_constant_elements())

		assert_equal(DebugOverlay.text(full_snapshot()),
			"Combat (Custom)\n" ..
			"Folder: combat\n" ..
			"Song: Antagonist - Valfaris.mp3  1:23 / 4:25\n" ..
			"Level: -7.9 dB")
	end)

	it("gives the song's progress as a share, and the choice's kind for the tag's color", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local view = DebugOverlay.view(full_snapshot())

		assert_equal(math.abs(view.progress - 83.4 / 265.6) < 1e-9, true)
		assert_equal(view.kind, "custom")
		assert_equal(DebugOverlay.view({ context = "event", status = "Vanilla, no songs" }).kind, "game")
		assert_equal(DebugOverlay.view({ context = "event", status = "Silence" }).kind, "silence")
	end)

	it("speaks about the volume only while something changes it", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		snapshot.evening_out = false
		assert_equal(DebugOverlay.view(snapshot).level, "")

		snapshot.menu_level = 0.72
		assert_equal(DebugOverlay.view(snapshot).level, "menu 72%")

		snapshot.menu_level = 0.5
		snapshot.evening_out = true
		assert_equal(DebugOverlay.view(snapshot).level, "menu lowered, -7.9 dB")
	end)

	it("lights the menu marker while a menu is open, not while the music fades back, and the loudness marker while evening out", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()

		local view = DebugOverlay.view(snapshot)
		assert_equal(view.menu, false)
		assert_equal(view.evening_out, true)
		assert_equal(view.loudness, "-7.9 dB")

		snapshot.menu_open = true
		assert_equal(DebugOverlay.view(snapshot).menu, true)

		snapshot.menu_open = false
		snapshot.menu_level = 0.8
		snapshot.evening_out = false
		view = DebugOverlay.view(snapshot)
		assert_equal(view.menu, false)
		assert_equal(view.evening_out, false)
		assert_equal(view.loudness, nil)
	end)

	it("adds a row for the hold and the pending change, with how much of the hold is left", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		snapshot.hold = "combat"
		snapshot.hold_seconds = 6
		snapshot.hold_length = 8
		snapshot.pending = "boss"
		snapshot.pending_seconds = 0.4
		snapshot.pending_length = 0.6

		local view = DebugOverlay.view(snapshot)

		assert_equal(view.waiting, "combat hold 6.0s, boss in 0.4s")
		assert_equal(view.waiting_share, 0.75)
		assert_equal(DebugOverlay.text(snapshot):match("Waiting: [^\n]+"), "Waiting: combat hold 6.0s, boss in 0.4s")
	end)

	it("says what plays while no song of yours does, with no folder or song level, and cuts long names short", function()
		local DebugOverlay = load_overlay(new_constant_elements())

		local game = DebugOverlay.view({ context = "event", situation = "Event", status = "Vanilla, no songs", evening_out = true })
		assert_equal(game.idle, "The game's music plays")
		assert_equal(game.folder, nil)
		assert_equal(game.level, "")
		assert_equal(DebugOverlay.view({ context = "event", status = "Silence" }).idle, "Nothing plays")

		local snapshot = full_snapshot()
		snapshot.song = string.rep("a", 60) .. ".mp3"
		assert_equal(DebugOverlay.view(snapshot).song, string.rep("a", 45) .. "...")
	end)

	it("cuts a long name in another script between its characters, not inside one", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		local kana = "\227\129\130" -- One Japanese character, three bytes in UTF-8.

		snapshot.song = string.rep(kana, 60) .. ".mp3"
		assert_equal(DebugOverlay.view(snapshot).song, string.rep(kana, 45) .. "...")

		snapshot.song = string.rep(kana, 48)
		assert_equal(DebugOverlay.view(snapshot).song, string.rep(kana, 48))
	end)

	it("shows markup in a song or folder name as plain text", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		snapshot.song = "red {#color(255,0,0)}.mp3"
		snapshot.folder = "combat/{#reset()}"

		local view = DebugOverlay.view(snapshot)

		assert_equal(view.song, "red { #color(255,0,0)}.mp3")
		assert_equal(view.folder, "combat/{ #reset()}")
	end)

	it("names the override folders the situation looks for, after the folder it plays from", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		snapshot.context = "boss"
		snapshot.folder = "boss/chaos_spawn"
		snapshot.overrides = "chaos_spawn, fm_cargo, havoc"

		assert_equal(DebugOverlay.view(snapshot).folder, "boss/chaos_spawn (looks for chaos_spawn, fm_cargo, havoc)")
	end)

	it("falls back to the context's own name when the dropdown has no text", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		local snapshot = full_snapshot()
		snapshot.situation = "<source_combat>"

		assert_equal(DebugOverlay.view(snapshot).situation, "combat")
	end)

	it("names a moment that resolves no situation by its reason", function()
		local DebugOverlay = load_overlay(new_constant_elements())

		assert_equal(DebugOverlay.view({ status = "Vanilla", idle = "cutscene" }).situation, "Cutscene")
		assert_equal(DebugOverlay.view({ status = "Vanilla", idle = "intro" }).situation, "Mission Intro")
		assert_equal(DebugOverlay.view({ status = "Vanilla", idle = "unknown_state" }).situation, "Unknown Music State")
		assert_equal(DebugOverlay.view({ status = "Vanilla" }).situation, "No situation")
	end)

	it("says so while the mod is turned off", function()
		local DebugOverlay = load_overlay(new_constant_elements())

		assert_equal(DebugOverlay.text({ turned_off = true }), "Music Replacer: turned off")
	end)

	it("reads the meter safely, as 0 when it fails", function()
		local DebugOverlay = load_overlay(new_constant_elements())
		assert_equal(DebugOverlay.meter(), 0)
	end)
end)

describe("debug_overlay.lua element", function()
	it("adds its element to every visibility group once turned on, and removes it all once turned off", function()
		local constant_elements = new_constant_elements()
		local DebugOverlay, made = load_overlay(constant_elements)

		DebugOverlay.update()
		assert_equal(#made, 0)

		DebugOverlay.set_enabled(true)

		assert_equal(constant_elements._elements[CLASS_NAME], made[1])
		assert_equal(constant_elements._elements_array[2], made[1])
		assert_equal(made[1].draw_layer, 900)
		assert_equal(constant_elements._visibility_groups[1].visible_elements[CLASS_NAME], true)
		assert_equal(constant_elements._current_group_name, nil)

		DebugOverlay.set_enabled(false)

		assert_equal(constant_elements._elements[CLASS_NAME], nil)
		assert_equal(#constant_elements._elements_array, 1)
		assert_equal(constant_elements._visibility_groups[2].visible_elements[CLASS_NAME], nil)
		assert_equal(made[1].destroyed_with, "renderer")
	end)

	it("sizes its element and sets its backdrop without making a new one", function()
		local DebugOverlay, made = load_overlay(new_constant_elements())
		DebugOverlay.set_enabled(true, 1, 0.7)

		DebugOverlay.set_enabled(true, 1.5, 0.4)

		assert_equal(#made, 1)
		assert_deep_equal(made[1].layouts, { "1.5@0.4" })
		assert_equal(DebugOverlay.scale(), 1.5)
		assert_equal(DebugOverlay.opacity(), 0.4)
	end)

	it("adds its element again when the game builds a new UI", function()
		local first = new_constant_elements()
		local DebugOverlay, made, _, ui = load_overlay(first)
		DebugOverlay.set_enabled(true)

		local second = new_constant_elements()
		ui.current = second
		DebugOverlay.update()

		assert_equal(first._elements[CLASS_NAME], nil)
		assert_equal(second._elements[CLASS_NAME], made[2])
	end)

	it("adds its element to a new UI without touching the one the game tore down", function()
		local first = new_constant_elements()
		local DebugOverlay, made, _, ui = load_overlay(first)
		DebugOverlay.set_enabled(true)

		-- The game's teardown destroys every element, then drops its element list.
		made[1]:destroy("renderer")
		made[1].destroyed_with = nil
		first._elements_array = nil

		local second = new_constant_elements()
		ui.current = second
		DebugOverlay.update()

		assert_equal(made[1].destroyed_with, nil)
		assert_equal(second._elements[CLASS_NAME], made[2])
	end)

	it("logs once and stops trying when its element cannot be made", function()
		local constant_elements = new_constant_elements()
		local DebugOverlay, _, lines = load_overlay(constant_elements, true)

		DebugOverlay.set_enabled(true)
		DebugOverlay.update()
		DebugOverlay.update()

		assert_equal(#lines, 1)
		assert_equal(lines[1]:find("[overlay] could not be shown", 1, true) ~= nil, true)
		assert_equal(constant_elements._visibility_groups[1].visible_elements[CLASS_NAME], nil)
	end)
end)
