-- Builds the mod's on-screen messages from its localized texts, and hands them to on_screen_message.lua to show.
-- Song and folder names are the player's own text, and "{#" starts a tag in the game's markup, so every message breaks it up.
-- A message that names a song also says where the name sits, so on_screen_message.lua can draw its own words dimmer than the name.

local Messages = {}

local localize = nil
local on_screen_message = nil

-- The messages whose last value is a song's name.
local NAMED_MESSAGES = {
	song_now_playing = true,
	control_next_song = true,
	control_previous_song = true,
	control_restart_song = true,
	control_paused = true,
	control_resumed = true,
	control_removed_song = true,
	control_remove_confirm = true,
	control_only_song = true,
	control_song_gone = true,
}

-- Stands in for the song's name while the message is localized once more, to find where the name lands.
-- A translation can put the name anywhere, so its place comes from the localized text itself.
local NAME_MARK = "\1"

-- `options.localize(text_id, ...)` returns the text `text_id` in the game's language, formatted with `...`, as DMF's mod:localize does.
-- `options.on_screen_message` is on_screen_message.lua, or a stand-in with its show().
function Messages.init(options)
	localize = options.localize
	on_screen_message = options.on_screen_message
end

local function without_markup(text)
	return (text:gsub("{#", "{ #"))
end

local function message_text(text_id, ...)
	return without_markup(localize(text_id, ...))
end

-- The message `text_id` formatted with `...`, as message_text() makes it.
-- For a message that names a song, it also returns where the name sits in the text, as { first, last } byte positions.
local function message_parts(text_id, ...)
	local text = message_text(text_id, ...)
	if not NAMED_MESSAGES[text_id] then
		return text, nil
	end

	local count = select("#", ...)
	local values = { ... }
	local name = without_markup(values[count])
	values[count] = NAME_MARK
	local first = message_text(text_id, unpack(values, 1, count)):find(NAME_MARK, 1, true)
	if not first or text:sub(first, first + #name - 1) ~= name then
		return text, nil
	end
	return text, { first, first + #name - 1 }
end

-- Shows the message `text_id`, formatted with `...`, in Message Color.
function Messages.show(text_id, ...)
	local text, name = message_parts(text_id, ...)
	on_screen_message.show(text, "message", name)
end

-- Shows the error message `text_id` in Error Color.
-- Its details are logged by the caller, so the message itself stays short and points to diagnostic.log.
function Messages.show_error(text_id)
	on_screen_message.show(message_text(text_id), "error")
end

-- Shows the notice `text_id`, formatted with `...`, in Notice Color.
function Messages.show_notice(text_id, ...)
	on_screen_message.show(message_text(text_id, ...), "notice")
end

-- Says how many songs the mod found once a listing has been checked, so a new player sees it works, or where songs go when there are none.
local function show_songs_found(counts)
	if counts.songs == 0 then
		Messages.show_notice("notice_no_songs")
	elseif counts.songs == 1 then
		Messages.show_notice("notice_found_song")
	elseif counts.folders == 1 then
		Messages.show_notice("notice_found_songs_in_folder", counts.songs)
	else
		Messages.show_notice("notice_found_songs", counts.songs, counts.folders)
	end
end

-- Says how many files were skipped and why, after the count, so a player knows to convert a file or look at the log.
local function show_files_skipped(counts)
	local other_formats, unopenable = counts.other_formats, counts.unopenable
	if other_formats > 0 and unopenable > 0 then
		Messages.show_notice("notice_skipped_files", other_formats + unopenable, other_formats, unopenable)
	elseif other_formats == 1 then
		Messages.show_notice("notice_skipped_format_file")
	elseif other_formats > 1 then
		Messages.show_notice("notice_skipped_format_files", other_formats)
	elseif unopenable == 1 then
		Messages.show_notice("notice_skipped_unopenable_file")
	elseif unopenable > 1 then
		Messages.show_notice("notice_skipped_unopenable_files", unopenable)
	end
end

-- Says what a checked listing found, from the counts library.lua passes its on_checked listeners.
-- A listing after a restore shows nothing, since the restore's own message already says how many songs came back.
function Messages.show_listing_checked(counts)
	if counts.after_restore then
		return
	end
	show_songs_found(counts)
	show_files_skipped(counts)
end

-- Says how many songs Even Out Loudness measured, so a player knows it has finished and every song now plays evened out.
function Messages.show_songs_measured(count)
	if count == 1 then
		Messages.show_notice("notice_measured_song")
	else
		Messages.show_notice("notice_measured_songs", count)
	end
end

return Messages
