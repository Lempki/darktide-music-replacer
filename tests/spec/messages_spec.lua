-- Pins how messages.lua builds a message's text, and where it says a song's name sits in it.

local MESSAGES_FILE = package.searchpath("scripts/mods/MusicReplacer/modules/interface/messages", package.path)

-- A messages.lua whose texts come from `texts`, format strings by text ID, and whose shown messages land in the returned list.
-- Its module state lives in the file, so each spec loads a fresh copy.
local function new_messages(texts)
	local Messages = dofile(MESSAGES_FILE)
	local shown = {}

	Messages.init({
		localize = function(text_id, ...)
			return string.format(texts[text_id], ...)
		end,
		on_screen_message = {
			show = function(text, kind, name)
				shown[#shown + 1] = { text = text, kind = kind, name = name }
			end,
		},
	})

	return Messages, shown
end

describe("messages.lua names", function()
	it("says where the song's name sits in a message that names one", function()
		local Messages, shown = new_messages({ song_now_playing = "Now playing: %s" })

		Messages.show("song_now_playing", "Song.mp3")

		assert_equal(shown[1].text, "Now playing: Song.mp3")
		assert_equal(shown[1].kind, "message")
		assert_equal(shown[1].text:sub(shown[1].name[1], shown[1].name[2]), "Song.mp3")
	end)

	it("finds the name where a translation puts it, even first", function()
		local Messages, shown = new_messages({ control_next_song = "%s plays next" })

		Messages.show("control_next_song", "Song.mp3")

		assert_deep_equal(shown[1].name, { 1, 8 })
	end)

	it("takes the last value as the name, after the folder a message names first", function()
		local Messages, shown = new_messages({ control_remove_confirm = "Remove from %s: %s?" })

		Messages.show("control_remove_confirm", "Boss", "Boss.mp3")

		assert_equal(shown[1].text:sub(shown[1].name[1], shown[1].name[2]), "Boss.mp3")
	end)

	it("says nothing of a name in a message that names no song", function()
		local Messages, shown = new_messages({ control_shuffle_on_for = "Shuffle on for %s" })

		Messages.show("control_shuffle_on_for", "Hub")

		assert_equal(shown[1].text, "Shuffle on for Hub")
		assert_equal(shown[1].name, nil)
	end)

	it("breaks up the game's markup in a name, and the name's place covers the broken-up name", function()
		local Messages, shown = new_messages({ song_now_playing = "Now playing: %s" })

		Messages.show("song_now_playing", "{#color(255,0,0)}.mp3")

		assert_equal(shown[1].text, "Now playing: { #color(255,0,0)}.mp3")
		assert_equal(shown[1].text:sub(shown[1].name[1], shown[1].name[2]), "{ #color(255,0,0)}.mp3")
	end)
end)

describe("messages.lua kinds", function()
	it("shows a notice in its own kind, formatted with its values", function()
		local Messages, shown = new_messages({ notice_found_songs = "Found %d songs in %d folders" })

		Messages.show_notice("notice_found_songs", 12, 3)

		assert_equal(shown[1].text, "Found 12 songs in 3 folders")
		assert_equal(shown[1].kind, "notice")
	end)

	it("shows an error in its own kind", function()
		local Messages, shown = new_messages({ error_game_change = "See diagnostic.log" })

		Messages.show_error("error_game_change")

		assert_equal(shown[1].text, "See diagnostic.log")
		assert_equal(shown[1].kind, "error")
	end)
end)
