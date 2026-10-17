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

local snapshot_fn = function() return nil end
local create_element = nil
local log_fn = function() end
local enabled = false
local corner = "top_left"
local installed_into = nil -- The constant UI the element was added to, or nil.
local install_failed = false

local function minutes(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function decibels(scale)
	return scale > 0 and 20 * math.log10(scale) or -math.huge
end

local function shorten(name)
	if #name <= MAX_SONG_CHARACTERS then
		return name
	end
	return name:sub(1, MAX_SONG_CHARACTERS - 3) .. "..."
end

-- The overlay's text for a snapshot from MusicReplacer.lua. Pure, so the specs can check it.
-- Its fields are turned_off, context, status, pending, pending_seconds, hold, hold_seconds, and finishing.
-- The song's are song, position, and duration, and the volume's are volume, menu_level, song_level, and evening_out.
function DebugOverlay.text(snapshot)
	if not snapshot then
		return "Music Replacer: starting"
	end

	if snapshot.turned_off then
		return "Music Replacer is turned off"
	end

	local context_line = "Context: " .. tostring(snapshot.context or "none") .. ", " .. tostring(snapshot.status)
	if snapshot.hold then
		context_line = context_line .. string.format(", %s hold %.1fs", snapshot.hold, snapshot.hold_seconds or 0)
	end
	if snapshot.pending then
		context_line = context_line .. string.format(", %s in %.1fs", snapshot.pending, snapshot.pending_seconds or 0)
	end

	local song_line
	if snapshot.song then
		song_line = "Song: " .. shorten(snapshot.song) .. "  " .. minutes(snapshot.position) .. " / " .. (snapshot.duration and minutes(snapshot.duration) or "?")
		if snapshot.finishing then
			song_line = song_line .. ", " .. snapshot.finishing .. " song playing to its end"
		end
	else
		song_line = "Song: none"
	end

	local volume_line = string.format("Volume: custom %d%%, menu %d%%, %s",
		math.floor((snapshot.volume or 1) * 100 + 0.5), math.floor((snapshot.menu_level or 1) * 100 + 0.5),
		snapshot.evening_out and string.format("song %+.1f dB", decibels(snapshot.song_level or 1)) or "song as recorded")

	return context_line .. "\n" .. song_line .. "\n" .. volume_line
end

-- The current text, for the element to draw.
function DebugOverlay.current_text()
	local ok, text = pcall(function() return DebugOverlay.text(snapshot_fn()) end)
	return ok and text or ("Music Replacer: " .. tostring(text))
end

function DebugOverlay.corner()
	return corner
end

-- `options.snapshot()` returns the state to show, and `options.create_element(constant_elements, draw_layer)` makes the element.
function DebugOverlay.init(log, options)
	log_fn = log or log_fn
	snapshot_fn = options.snapshot or snapshot_fn
	create_element = options.create_element
end

local function remove()
	local constant_elements = installed_into
	installed_into = nil
	if not constant_elements then
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
		log_fn("[overlay] could not be shown: " .. tostring(err))
	end
end

-- Turns the overlay on or off, and moves it to `new_corner`, "top_left" or "top_right".
function DebugOverlay.set_enabled(on, new_corner)
	enabled = on == true
	corner = new_corner or corner

	if not enabled then
		remove()
		return
	end

	local element = installed_into and installed_into._elements and installed_into._elements[CLASS_NAME]
	if element and element.set_corner then
		element:set_corner(corner)
	end

	DebugOverlay.update()
end

-- Call from the main mod file's mod.on_unload.
function DebugOverlay.shutdown()
	remove()
end

return DebugOverlay
