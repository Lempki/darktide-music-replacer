-- Checks that fonts.lua finds the alphabets a song name needs, gives the mod's texts fonts that fall back on them, and loads each once.

local FakeEngine = require("tests.helpers.fake_engine")

local BASE = "content/ui/fonts/"

-- A font manager as the game's, with `proxima_nova_medium` as English has it, and a package manager that loads on request.
local function new_fonts()
	local engine = FakeEngine.new()
	local definitions = {
		proxima_nova_medium = { path = { BASE .. "proxima_nova_medium", BASE .. "darktide_custom_regular" }, render_flags = 7 },
	}
	local font_manager = {
		_font_definitions = definitions,
		data_by_type = function(_, font_type) return definitions[font_type] end,
	}
	local packages = { loads = {}, released = {} }
	function packages.load(_, package_name, reference, callback)
		packages.loads[#packages.loads + 1] = { name = package_name, reference = reference, callback = callback }
		return #packages.loads
	end
	function packages.release(_, id)
		packages.released[#packages.released + 1] = id
	end
	rawset(Managers, "font", font_manager)
	rawset(Managers, "package", packages)

	local Fonts = engine:load("modules/interface/fonts")
	local lines = {}
	Fonts.init(function(line) lines[#lines + 1] = line end)
	return Fonts, definitions, packages, lines
end

local function set_of(scripts)
	local list = {}
	for script in pairs(scripts) do
		list[#list + 1] = script
	end
	table.sort(list)
	return list
end

describe("fonts.lua alphabets", function()
	it("finds the scripts that need a font of their own", function()
		local Fonts = new_fonts()

		assert_deep_equal(set_of(Fonts.scripts_in("Song.mp3")), {})
		assert_deep_equal(set_of(Fonts.scripts_in("Кино - Группа крови.mp3")), {})
		assert_deep_equal(set_of(Fonts.scripts_in("夜に駆ける.mp3")), { "japanese" })
		assert_deep_equal(set_of(Fonts.scripts_in("아리랑.mp3")), { "korean" })
		assert_deep_equal(set_of(Fonts.scripts_in("月亮代表我的心.mp3")), { "chinese" })
		assert_deep_equal(set_of(Fonts.scripts_in("アリラン 아리랑")), { "japanese", "korean" })
	end)

	it("reads a name cut in the middle of a character without failing", function()
		local Fonts = new_fonts()

		assert_deep_equal(set_of(Fonts.scripts_in("夜" .. string.char(0xE3, 0x81))), { "chinese" })
		assert_deep_equal(set_of(Fonts.scripts_in(string.char(0x80, 0x41))), {})
	end)
end)

describe("fonts.lua font types", function()
	it("registers the game's font with Cyrillic before the game's last fallback", function()
		local Fonts, definitions = new_fonts()

		local font_type = Fonts.type("proxima_nova_medium")

		assert_equal(font_type, "music_replacer_proxima_nova_medium")
		assert_deep_equal(definitions[font_type], {
			path = { BASE .. "proxima_nova_medium", BASE .. "proxima_nova_bold", BASE .. "darktide_custom_regular" },
			render_flags = 7,
		})
	end)

	it("keeps the game's own font for a font the game does not know", function()
		local Fonts = new_fonts()

		assert_equal(Fonts.type("not_a_font"), "not_a_font")
	end)

	it("loads a script's font once a text needs it, and adds it to every font type", function()
		local Fonts, definitions, packages, lines = new_fonts()
		local font_type = Fonts.type("proxima_nova_medium")
		local version = Fonts.version()

		Fonts.prepare("Now playing: 夜に駆ける.mp3")
		Fonts.prepare("Next song: アイドル.mp3")
		assert_equal(#packages.loads, 1)
		assert_equal(packages.loads[1].name, "packages/ui/fonts/slug_ja")

		packages.loads[1].callback()

		assert_deep_equal(definitions[font_type].path, {
			BASE .. "proxima_nova_medium", BASE .. "proxima_nova_bold", BASE .. "noto_sans_jp_bold", BASE .. "darktide_custom_regular",
		})
		assert_equal(Fonts.version(), version + 1)
		assert_deep_equal(lines, { "[fonts] loaded noto_sans_jp_bold for japanese song names" })
	end)

	it("loads both Chinese fonts for a Chinese name, each font once", function()
		local Fonts, definitions, packages, lines = new_fonts()
		local font_type = Fonts.type("proxima_nova_medium")

		Fonts.prepare("后来 - 刘若英.mp3")
		assert_deep_equal({ packages.loads[1].name, packages.loads[2].name }, { "packages/ui/fonts/slug_zh_cn", "packages/ui/fonts/slug_zh_tw" })
		packages.loads[1].callback()
		packages.loads[2].callback()

		assert_deep_equal(definitions[font_type].path, {
			BASE .. "proxima_nova_medium", BASE .. "proxima_nova_bold", BASE .. "noto_sans_sc_bold", BASE .. "noto_sans_tc_bold",
			BASE .. "darktide_custom_regular",
		})
		assert_deep_equal(lines, {
			"[fonts] loaded noto_sans_sc_bold for chinese song names",
			"[fonts] loaded noto_sans_tc_bold for chinese song names",
		})
	end)

	it("loads nothing for Latin or Cyrillic names", function()
		local Fonts, _, packages = new_fonts()

		Fonts.prepare("Now playing: Кино - Группа крови.mp3")

		assert_equal(#packages.loads, 0)
	end)

	it("releases the loaded packages at shutdown", function()
		local Fonts, _, packages = new_fonts()
		Fonts.prepare("아리랑.mp3")
		packages.loads[1].callback()

		Fonts.shutdown()

		assert_deep_equal(packages.released, { 1 })
	end)

	it("logs a package that could not load, and tries again for the next text", function()
		local Fonts, _, packages, lines = new_fonts()
		packages.load = function() error("no such package", 0) end

		Fonts.prepare("아리랑.mp3")
		Fonts.prepare("한국.mp3")

		assert_deep_equal(lines, {
			"[fonts] could not load the font for korean song names: no such package",
			"[fonts] could not load the font for korean song names: no such package",
		})
	end)
end)
