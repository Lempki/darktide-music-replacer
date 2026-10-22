-- Shows what the mod is doing in a corner of the screen: the context, the song, and its volume.
-- It is a debug aid behind the Debug Overlay setting, so it is off by default.
--
-- The text is drawn by an element added to the game's constant UI, which is drawn on every screen, loading screens included.
-- A HUD element would only exist in the hub and in missions, and miss the Loading and Preparation contexts.
-- The constant UI has no API for mods, so the element is added and removed the way the game sets up its own constant elements.

local DebugOverlay = {}

local CLASS_NAME = "ConstantElementMusicReplacerOverlay"

-- Above most constant elements, such as the subtitles, so the text stays readable.
local DRAW_LAYER = 900

-- Every group the game's own always-visible elements use, so the overlay shows on every screen but the disabled ones.
local VISIBILITY_GROUPS = {
	"tactical_overlay",
	"cutscene",
	"mission_lobby",
	"end_of_round",
	"in_view",
	"in_hub_view",
	"in_hub",
	"in_loading",
	"skippable_cinematic",
	"in_mission",
	"default",
}

-- Song names are cut to this many characters, so the overlay keeps its size.
local MAX_SONG_CHARACTERS = 48

-- The game's text markup. Labels are dimmed, so the values stand out, and the line about timing is amber, so it stands out from the rest.
local LABEL_COLOR = "{#color(150,150,150)}"
local TIMING_COLOR = "{#color(255,190,90)}"
local RESET = "{#reset()}"

local snapshot_fn = function() return nil end
local create_element = nil
local log = function() end
local enabled = false
local corner = "top_left"
local scale = 1 -- The Overlay Size setting, as a factor.
local installed_into = nil -- The constant UI the element was added to, or nil.
local install_failed = false

local function minutes(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function decibels(level)
	return level > 0 and 20 * math.log10(level) or -math.huge
end

local function percent(share)
	return math.floor(share * 100 + 0.5)
end

-- The Menu Volume setting, and while the music is lowered for a menu, or fading there or back, how far it is now.
local function menu_text(setting, level)
	local text = string.format("menu %d%%", percent(setting))
	if level >= 1 then
		return text
	end
	if percent(level) == percent(setting) then
		return text .. " (lowered)"
	end
	return text .. string.format(" (now %d%%)", percent(level))
end

-- Cuts on a character boundary, since a name in another script uses several bytes per character and half a character garbles the text.
local function shorten(name)
	local characters = 0
	local cut = nil
	for index = 1, #name do
		-- Each UTF-8 character starts with a byte outside 0x80 to 0xBF.
		local byte = name:byte(index)
		if byte < 0x80 or byte >= 0xC0 then
			characters = characters + 1
			if characters == MAX_SONG_CHARACTERS - 2 then
				cut = index - 1
			elseif characters > MAX_SONG_CHARACTERS then
				return name:sub(1, cut) .. "..."
			end
		end
	end
	return name
end

-- File and folder names are the player's own text, and "{#" starts a tag in the game's markup, so it is broken up.
local function plain(text)
	return (text:gsub("{#", "{ #"))
end

-- The overlay's lines for a snapshot from MusicReplacer.lua, each { label, value }, and timing = true on the line about timing.
-- Its fields are turned_off, context, status, folder, overrides, pending, pending_seconds, hold, and hold_seconds.
-- The song's are song, position, and duration, and the volume's are volume, menu_volume, menu_level, song_level, and evening_out.
-- menu_volume is the Menu Volume setting, and menu_level how far the music is lowered for a menu now, both as scales.
function DebugOverlay.lines(snapshot)
	if not snapshot then
		return { { "Music Replacer", "starting" } }
	end

	if snapshot.turned_off then
		return { { "Music Replacer", "turned off" } }
	end

	local lines = { { "Context", tostring(snapshot.context or "none") .. " (" .. tostring(snapshot.status) .. ")" } }

	-- The override names the context looks for, so a player can see which folder to make.
	if snapshot.context then
		local folder = snapshot.folder or "none"
		if snapshot.overrides and snapshot.overrides ~= "" then
			folder = folder .. ", overrides: " .. snapshot.overrides
		end
		lines[#lines + 1] = { "Folder", folder }
	end

	-- Holds and changes that are still settling explain why the music has not changed yet.
	local timing = {}
	if snapshot.hold then
		timing[#timing + 1] = string.format("%s hold %.1fs", snapshot.hold, snapshot.hold_seconds or 0)
	end
	if snapshot.pending then
		timing[#timing + 1] = string.format("%s in %.1fs", snapshot.pending, snapshot.pending_seconds or 0)
	end
	if #timing > 0 then
		lines[#lines + 1] = { "Waiting", table.concat(timing, ", "), timing = true }
	end

	if snapshot.song then
		lines[#lines + 1] = { "Song", shorten(snapshot.song) .. "  " .. minutes(snapshot.position) .. " / " .. (snapshot.duration and minutes(snapshot.duration) or "?") }
	else
		lines[#lines + 1] = { "Song", "none" }
	end

	lines[#lines + 1] = { "Volume", string.format("custom %d%%, %s, %s",
		percent(snapshot.volume or 1), menu_text(snapshot.menu_volume or 1, snapshot.menu_level or 1),
		snapshot.evening_out and string.format("song %+.1f dB", decibels(snapshot.song_level or 1)) or "song as recorded") }

	return lines
end

-- The overlay's text, one line per row. With `colored`, in the game's text markup.
function DebugOverlay.text(snapshot, colored)
	local rows = {}
	for index, line in ipairs(DebugOverlay.lines(snapshot)) do
		if colored then
			local value_color = line.timing and TIMING_COLOR or RESET
			rows[index] = LABEL_COLOR .. line[1] .. ": " .. value_color .. plain(line[2]) .. RESET
		else
			rows[index] = line[1] .. ": " .. line[2]
		end
	end
	return table.concat(rows, "\n")
end

-- The current text, colored, for the element to draw.
function DebugOverlay.current_text()
	local ok, text = pcall(DebugOverlay.text, snapshot_fn(), true)
	return ok and text or ("Music Replacer: " .. tostring(text))
end

function DebugOverlay.corner()
	return corner
end

function DebugOverlay.scale()
	return scale
end

-- `options.snapshot()` returns the state to show, and `options.create_element(constant_elements, draw_layer)` makes the element.
function DebugOverlay.init(logger, options)
	log = logger or log
	snapshot_fn = options.snapshot or snapshot_fn
	create_element = options.create_element
end

local function remove()
	local constant_elements = installed_into
	installed_into = nil

	-- The game destroys every element of a constant UI it tears down, ours included, and then drops its element list.
	-- So a torn-down UI has nothing left to remove, and destroying the element again would act on a dead object.
	if not constant_elements or not constant_elements._elements_array then
		return
	end

	local elements = constant_elements._elements
	local element = elements and elements[CLASS_NAME]
	if element then
		elements[CLASS_NAME] = nil

		local elements_array = constant_elements._elements_array
		for index = #elements_array, 1, -1 do
			if elements_array[index] == element then
				table.remove(elements_array, index)
			end
		end

		if element.destroy then
			element:destroy(constant_elements:ui_renderer())
		end
	end

	for _, group in ipairs(constant_elements._visibility_groups or {}) do
		if group.visible_elements then
			group.visible_elements[CLASS_NAME] = nil
		end
	end
	for _, parameters in pairs(constant_elements._visibility_group_parameters or {}) do
		parameters[CLASS_NAME] = nil
	end
end

local function install(constant_elements)
	-- Set first, so a failure below still has its partial setup removed.
	installed_into = constant_elements

	-- Fills in the visibility groups the same way the game does for its own elements.
	constant_elements:_setup_visiblity_groups({ { class_name = CLASS_NAME, visibility_groups = VISIBILITY_GROUPS } })

	local element = create_element(constant_elements, DRAW_LAYER)
	constant_elements._elements[CLASS_NAME] = element
	constant_elements._elements_array[#constant_elements._elements_array + 1] = element

	-- The next update works out the element's visibility again, as after the game adds an element.
	constant_elements._current_group_name = nil
end

local function constant_elements_now()
	local ui = Managers and Managers.ui
	return ui and ui.ui_constant_elements and ui:ui_constant_elements()
end

-- Call every update. Adds the element once the game's UI exists, and adds it again if the UI was rebuilt.
function DebugOverlay.update()
	if not enabled or install_failed or not create_element then
		return
	end

	local constant_elements = constant_elements_now()
	if not constant_elements or constant_elements == installed_into then
		return
	end

	remove()

	local ok, err = pcall(install, constant_elements)
	if not ok then
		install_failed = true
		remove()
		log("[overlay] could not be shown: " .. tostring(err))
	end
end

-- Turns the overlay on or off, moves it to `new_corner`, "top_left" or "top_right", and sizes it by `new_scale`, 1 by default.
function DebugOverlay.set_enabled(on, new_corner, new_scale)
	enabled = on == true
	corner = new_corner or corner
	scale = new_scale or scale

	if not enabled then
		remove()
		return
	end

	local element = installed_into and installed_into._elements and installed_into._elements[CLASS_NAME]
	if element and element.set_layout then
		element:set_layout(corner, scale)
	end

	DebugOverlay.update()
end

-- Call from the main mod file's mod.on_unload.
function DebugOverlay.shutdown()
	remove()
end

return DebugOverlay
