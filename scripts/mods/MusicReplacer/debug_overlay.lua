-- Shows what the mod is doing in the top left corner of the screen: the situation, the song, and how loud it plays.
-- It is a debug aid behind the Debug Overlay setting, so it is off by default.
--
-- The text is drawn by an element in the game's constant UI, which constant_element_slot.lua keeps there.

local ConstantElementSlot = get_mod("MusicReplacer"):io_dofile("MusicReplacer/scripts/mods/MusicReplacer/constant_element_slot")

local DebugOverlay = {}

-- Above most constant elements, such as the subtitles, so the text stays readable.
local DRAW_LAYER = 900

local slot = ConstantElementSlot.new("ConstantElementMusicReplacerOverlay", DRAW_LAYER)

-- Song names are cut to this many characters, so the overlay keeps its size.
local MAX_SONG_CHARACTERS = 48

local snapshot_fn = function() return nil end
local meter_fn = function() return 0 end
local create_element = nil
local log = function() end
local enabled = false
local scale = 1 -- The Overlay Size setting, as a factor.
local opacity = 0.7 -- The Backdrop Opacity setting, as a share.

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

-- What the overlay names a moment that resolves no situation, by the reason context.lua gives.
local IDLE_NAMES = { cutscene = "Cutscene", intro = "Mission Intro", unknown_state = "Unknown Music State" }

-- The choice a status names, which colors its tag: "custom", "silence", or "game" for every reason the game's music plays.
local function kind_of(status)
	status = tostring(status)
	if status:find("^Custom") then
		return "custom"
	elseif status:find("^Silence") then
		return "silence"
	end
	return "game"
end

-- The song's own level while Even Out Loudness is on, or nil.
-- A song not measured when its level was set plays at its own level, and +0.0 dB would read as measured, so it says so instead.
local function song_loudness(snapshot)
	if not (snapshot.evening_out and snapshot.song) then
		return nil
	end
	if snapshot.song_measured == false then
		return "not measured"
	end
	return string.format("%+.1f dB", decibels(snapshot.song_level or 1))
end

-- The menu lowering while it is under way or done, and the song's own level while Even Out Loudness is on.
-- The settings that stay the same are left out, so the line only speaks when something changes what you hear.
local function level_words(snapshot)
	local words = {}
	local menu_level = snapshot.menu_level or 1
	if menu_level < 1 then
		if percent(menu_level) == percent(snapshot.menu_volume or 1) then
			words[#words + 1] = "menu lowered"
		else
			words[#words + 1] = string.format("menu %d%%", percent(menu_level))
		end
	end
	local loudness = song_loudness(snapshot)
	if loudness then
		words[#words + 1] = loudness
	end
	return table.concat(words, ", ")
end

-- What the overlay shows for a snapshot from MusicReplacer.lua, as plain fields for the element to draw.
-- A field of the view is only set when it is shown, and idle says what plays while no song of yours does.
-- The meter itself shows the menu lowering's fade, so the Menu marker follows the menu, not the fade.
function DebugOverlay.view(snapshot)
	local view = { title = "Music Replacer" }

	if not snapshot then
		view.situation = "Starting"
		return view
	end

	if snapshot.turned_off then
		view.situation = "Turned off"
		return view
	end

	-- DMF marks a string it has no text for as "<id>", so the context's own name stands in.
	local situation = snapshot.situation
	if not situation or situation:find("^<") then
		situation = snapshot.context
	end
	view.situation = situation or IDLE_NAMES[snapshot.idle] or "No situation"
	view.tag = tostring(snapshot.status)
	view.kind = kind_of(snapshot.status)

	-- The override names the context looks for, so a player can see which folder to make.
	-- With no folder and nothing to look for, as while the game's music plays, the row says nothing and is left out.
	local overrides = snapshot.overrides ~= "" and snapshot.overrides or nil
	if snapshot.context and (snapshot.folder or overrides) then
		local folder = plain(snapshot.folder or "none")
		if overrides then
			folder = folder .. " (looks for " .. plain(overrides) .. ")"
		end
		view.folder = folder
	end

	-- Holds and changes that are still settling explain why the music has not changed yet.
	local timing = {}
	local share = nil
	if snapshot.hold then
		timing[#timing + 1] = string.format("%s hold %.1fs", snapshot.hold, snapshot.hold_seconds or 0)
		share = (snapshot.hold_length or 0) > 0 and (snapshot.hold_seconds or 0) / snapshot.hold_length or nil
	end
	if snapshot.pending then
		timing[#timing + 1] = string.format("%s in %.1fs", snapshot.pending, snapshot.pending_seconds or 0)
		if not share and (snapshot.pending_length or 0) > 0 then
			share = (snapshot.pending_seconds or 0) / snapshot.pending_length
		end
	end
	if #timing > 0 then
		view.waiting = table.concat(timing, ", ")
		view.waiting_share = share and math.max(0, math.min(1, share)) or 1
	end

	-- Even Out Loudness measures songs whatever plays, so this row shows with or without a song.
	if snapshot.measuring_done and snapshot.measuring_total then
		view.measuring = string.format("%d / %d", snapshot.measuring_done, snapshot.measuring_total)
		local measuring_share = snapshot.measuring_total > 0 and snapshot.measuring_done / snapshot.measuring_total or 0
		view.measuring_share = math.max(0, math.min(1, measuring_share))
	end

	if not snapshot.song then
		view.idle = view.kind == "silence" and "Nothing plays" or view.kind == "game" and "The game's music plays" or "No song playing"
	else
		view.song = plain(shorten(snapshot.song))
		view.time = minutes(snapshot.position) .. " / " .. (snapshot.duration and minutes(snapshot.duration) or "?")
		if snapshot.duration and snapshot.duration > 0 then
			view.progress = math.max(0, math.min(1, (snapshot.position or 0) / snapshot.duration))
		end
	end

	view.level = level_words(snapshot)
	view.menu = snapshot.menu_open == true
	view.evening_out = snapshot.evening_out == true
	view.loudness = song_loudness(snapshot)

	return view
end

-- The overlay as plain text, one row per line, for the log and the specs.
function DebugOverlay.text(snapshot)
	local view = DebugOverlay.view(snapshot)
	if not view.tag then
		return view.title .. ": " .. view.situation:lower()
	end

	local rows = { view.situation .. " (" .. view.tag .. ")" }
	if view.folder then
		rows[#rows + 1] = "Folder: " .. view.folder
	end
	if view.waiting then
		rows[#rows + 1] = "Waiting: " .. view.waiting
	end
	if view.measuring then
		rows[#rows + 1] = "Measuring: " .. view.measuring
	end
	rows[#rows + 1] = "Song: " .. (view.song and (view.song .. "  " .. view.time) or "none")
	if view.level ~= "" then
		rows[#rows + 1] = "Level: " .. view.level
	end
	return table.concat(rows, "\n")
end

-- The current view, for the element to draw. A failure shows as the situation, so the overlay still says something.
function DebugOverlay.current_view()
	local ok, view = pcall(DebugOverlay.view, snapshot_fn())
	return ok and view or { title = "Music Replacer", situation = "error: " .. tostring(view) }
end

-- How loud the music sounds now, as a share of full scale, for the meter. Cheap enough to read every frame.
function DebugOverlay.meter()
	local ok, level = pcall(meter_fn)
	return ok and tonumber(level) or 0
end

function DebugOverlay.opacity()
	return opacity
end

function DebugOverlay.scale()
	return scale
end

-- `options.snapshot()` returns the state to show, and `options.meter()` how loud the music sounds now.
-- `options.create_element(constant_elements, draw_layer)` makes the element.
function DebugOverlay.init(logger, options)
	log = logger or log
	snapshot_fn = options.snapshot or snapshot_fn
	meter_fn = options.meter or meter_fn
	create_element = options.create_element
end

-- Call every update. Adds the element once the game's UI exists, and adds it again if the UI was rebuilt.
function DebugOverlay.update()
	if not enabled or not create_element then
		return
	end

	local err = slot:update(create_element)
	if err then
		log("[overlay] could not be shown: " .. err)
	end
end

-- Turns the overlay on or off, sizes it by `new_scale`, and sets its backdrop's opacity to `new_opacity`, both as factors.
function DebugOverlay.set_enabled(on, new_scale, new_opacity)
	enabled = on == true
	scale = new_scale or scale
	opacity = new_opacity or opacity

	if not enabled then
		slot:remove()
		return
	end

	local element = slot:element()
	if element and element.set_layout then
		element:set_layout(scale, opacity)
	end

	DebugOverlay.update()
end

-- Call from the main mod file's mod.on_unload.
function DebugOverlay.shutdown()
	slot:remove()
end

return DebugOverlay
