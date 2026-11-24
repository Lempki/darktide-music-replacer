-- Gives the mod's own texts fonts that draw song and folder names in any alphabet, whatever language the game runs in.
-- The game gives each font a list of fonts to fall back on, character by character.
-- It adds its Japanese, Korean, and Chinese fonts to that list only in those languages, after loading their packages.
-- So the mod registers font types of its own, each the game's font with more fonts to fall back on.
-- It loads a font's package once a text needs that font.
-- The game's own fonts and texts stay as they are.

local FontDefinitions = require("scripts/managers/ui/ui_fonts_definitions")

local Fonts = {}

-- The mod's font types are the game's font names with this in front.
local PREFIX = "music_replacer_"

-- The game's Russian setup falls back on this font for Cyrillic letters, which the game's other Latin fonts lack.
local CYRILLIC_FONT = "proxima_nova_bold"

-- The game's languages whose fonts each script uses, from the game's own setup for those languages.
-- Han characters without kana are taken as Chinese, since a Japanese name with kanji nearly always has kana too.
-- Chinese gets both the simplified and the traditional setup, since a name can be in either.
-- Neither font has all of the other's characters.
local SCRIPT_LOCALES = { japanese = { "ja" }, korean = { "ko" }, chinese = { "zh-cn", "zh-tw" } }

local log = function() end -- It does nothing unless Fonts.init is given a real logger.

local registered = {} -- The game's font name -> true for every font the mod has a font type for.
local loading = {} -- The game's language -> true from asking for its font package until it has loaded.
local package_ids = {} -- The game's language -> the package manager's id for its font package, released at shutdown.
local added_fonts = {} -- The fonts loaded for scripts, in the order they loaded, as plain names.
-- Texts Fonts.prepare has looked at, so a text drawn every frame is scanned once.
-- It is cleared once it holds MAX_SCANNED texts, so it never grows past that.
local scanned = {}
local scanned_count = 0
local MAX_SCANNED = 256
local version = 0 -- Counts up whenever a font is added, so an element knows its measured widths are out of date.

-- ###########################################################################
-- Scripts in a text
-- ###########################################################################

-- The scripts a code point belongs to that need a font the game lacks in English, or nil.
local function script_of(code_point)
	if (code_point >= 0x3040 and code_point <= 0x30FF) or (code_point >= 0x31F0 and code_point <= 0x31FF)
		or (code_point >= 0xFF66 and code_point <= 0xFF9F) then
		return "japanese"
	elseif (code_point >= 0x1100 and code_point <= 0x11FF) or (code_point >= 0x3130 and code_point <= 0x318F)
		or (code_point >= 0xAC00 and code_point <= 0xD7AF) then
		return "korean"
	elseif (code_point >= 0x3400 and code_point <= 0x4DBF) or (code_point >= 0x4E00 and code_point <= 0x9FFF)
		or (code_point >= 0xF900 and code_point <= 0xFAFF) then
		return "han"
	end
	return nil
end

-- The scripts in `text` that need a font of their own, as a set: "japanese", "korean", or "chinese".
-- `text` is UTF-8, so each character is decoded from its lead byte and the continuation bytes after it.
function Fonts.scripts_in(text)
	local found = {}
	local has_han = false
	local index = 1
	local length = #text

	while index <= length do
		local byte = text:byte(index)
		local code_point, size
		if byte < 0x80 then
			code_point, size = byte, 1
		elseif byte >= 0xF0 then
			size = 4
			code_point = byte % 0x08
		elseif byte >= 0xE0 then
			size = 3
			code_point = byte % 0x10
		elseif byte >= 0xC0 then
			size = 2
			code_point = byte % 0x20
		else
			code_point, size = nil, 1 -- A stray continuation byte, which belongs to no character.
		end

		-- A character cut short, as in a name shortened mid-character, has too few continuation bytes, so it is left out.
		if code_point and size > 1 then
			for offset = 1, size - 1 do
				local continuation = text:byte(index + offset)
				if not continuation or continuation < 0x80 or continuation >= 0xC0 then
					code_point, size = nil, offset
					break
				end
				code_point = code_point * 0x40 + continuation % 0x40
			end
		end

		local script = code_point and script_of(code_point)
		if script == "han" then
			has_han = true
		elseif script then
			found[script] = true
		end

		index = index + size
	end

	if has_han and not found.japanese then
		found.chinese = true
	end
	return found
end

-- ###########################################################################
-- Font types
-- ###########################################################################

local function font_manager()
	return Managers and Managers.font
end

local function path_of(font_name)
	return FontDefinitions.base_path .. font_name
end

-- Builds the mod's font type for `font_name` from the game's definition of that font, which already follows the game's language.
-- The added fonts go before the game's last fallback, its custom font, which only draws the game's own symbols.
local function build(manager, font_name)
	local game_definition = manager:data_by_type(font_name)
	if not game_definition then
		return false
	end

	local custom_path = path_of(FontDefinitions.custom_font)
	local paths = {}
	local listed = {}
	local function add(path)
		if not listed[path] then
			listed[path] = true
			paths[#paths + 1] = path
		end
	end

	for _, path in ipairs(game_definition.path) do
		if path ~= custom_path then
			add(path)
		end
	end
	add(path_of(CYRILLIC_FONT))
	for _, added in ipairs(added_fonts) do
		add(path_of(added))
	end
	add(custom_path)

	manager._font_definitions[PREFIX .. font_name] = { path = paths, render_flags = game_definition.render_flags }
	return true
end

local function rebuild_all()
	local manager = font_manager()
	if not manager then
		return
	end
	for font_name in pairs(registered) do
		build(manager, font_name)
	end
end

-- The mod's font type for the game's font `font_name`, such as "proxima_nova_medium".
-- Call it where the game's font manager exists, as when an element is created, since the type is registered there.
function Fonts.type(font_name)
	local manager = font_manager()
	if manager and not registered[font_name] and build(manager, font_name) then
		registered[font_name] = true
	end
	return registered[font_name] and PREFIX .. font_name or font_name
end

-- ###########################################################################
-- Loading the fonts a text needs
-- ###########################################################################

-- Loads the font package of the game's language `locale` and adds its sans serif fonts, which the game's own setup for it lists.
local function load_locale(locale, script)
	local locale_fonts = FontDefinitions.locale_specific_fonts[locale]
	local package_manager = Managers and Managers.package
	if not (locale_fonts and locale_fonts.package and package_manager) then
		return
	end

	local fonts = locale_fonts[FontDefinitions.FontTypes.sans_serif]
	if type(fonts) ~= "table" then
		fonts = { fonts }
	end

	loading[locale] = true
	package_ids[locale] = package_manager:load(locale_fonts.package, "MusicReplacer", function()
		loading[locale] = nil
		local names = {}
		for _, font in ipairs(fonts) do
			local known = false
			for _, added in ipairs(added_fonts) do
				known = known or added == font
			end
			if not known then
				added_fonts[#added_fonts + 1] = font
				names[#names + 1] = font
			end
		end
		version = version + 1
		rebuild_all()
		log(string.format("[fonts] loaded %s for %s song names", table.concat(names, " and "), script))
	end)
end

-- Loads the fonts `text` needs to draw, once each, so it draws in full from the next frame on.
-- Until a font has loaded, its characters draw as empty boxes, as before.
function Fonts.prepare(text)
	if type(text) ~= "string" or scanned[text] then
		return
	end
	if scanned_count >= MAX_SCANNED then
		scanned = {}
		scanned_count = 0
	end
	scanned[text] = true
	scanned_count = scanned_count + 1

	for script in pairs(Fonts.scripts_in(text)) do
		for _, locale in ipairs(SCRIPT_LOCALES[script]) do
			if not loading[locale] and not package_ids[locale] then
				local ok, err = pcall(load_locale, locale, script)
				if not ok then
					loading[locale] = nil
					log(string.format("[fonts] could not load the font for %s song names: %s", script, tostring(err)))
				end
			end
		end
	end
end

-- A number that changes whenever a font is added, after which text measures differently.
function Fonts.version()
	return version
end

-- Call once from the main mod file's top level.
function Fonts.init(logger)
	log = logger or log
end

-- Call from the main mod file's mod.on_unload. The mod's font types stay registered, so an element still drawing finds them.
function Fonts.shutdown()
	local package_manager = Managers and Managers.package
	for locale, id in pairs(package_ids) do
		if package_manager and not loading[locale] then
			pcall(package_manager.release, package_manager, id)
		end
	end
	package_ids = {}
end

return Fonts
