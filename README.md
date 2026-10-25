# darktide-music-replacer

Music Replacer is a mod for Warhammer 40,000: Darktide that plays your own music in place of the game's, chosen by what is happening in the hub or a mission. You put audio files into folders, one folder per situation, and the mod picks the right one as you play. Wherever you add no songs, the game's music plays as usual.

## What it does

* Plays your songs by situation: the title screen, the hub, loading screens, exploring, combat, hordes, bosses, events, last stands, victory, defeat, Mortis Trials, and Expeditions.
* Picks a random song from a folder with several, never the one that just played.
* Loops a folder's only song seamlessly, with no gap added between its end and its start.
* Keeps a lone song playing when the next situation's folder holds that same song alone too, instead of starting it over.
* Crossfades when the situation changes, and fades a song out at its end.
* Continues a song where it stopped when its music comes back, such as explore music after a fight.
* Follows the game's master and music volume sliders at once, without restarting the song.
* Lets you choose Custom, Vanilla, or Silence for each situation.
* Can even out the loudness of your songs, without changing your files.
* Lowers your music while a menu is open.
* Has a debug overlay that shows which situation the mod sees and what it plays.
* Picks up added, removed, and replaced files while the game runs.

## What it does not do

* It does not change any game files.
* It does not install or run any extra program or DLL.
* It does not change sound effects or voice lines, only the music.
* It does not affect your squadmates. They hear their own game's music.
* It does not play your music during mission intros and cutscenes. The game's music plays there.
* It does not download or stream anything. It plays only the files in its own audio folders.
* It does not change your music files.

## Quickstart

1. Install Music Replacer like any other Darktide mod, for example through Vortex. Check that `MusicReplacer` is listed below `dmf` in `mod_load_order.txt`, as described under Requirements.
2. Put your audio files into the folders inside the **installed** mod folder: `...\Warhammer 40,000 DARKTIDE\mods\MusicReplacer\audio\<folder>\`. For example, songs in `audio\hub\` play in the Mourningstar. Every folder is listed under Where your music plays.
3. Start the game and play.

The mod creates any missing folder when the game starts, so every folder is there after your first launch at the latest. You can add, remove, or replace files while the game runs, and the mod picks them up by itself 3 seconds after files stop changing. A song that is playing finishes, even if you remove its file. Put audio files directly inside the folders you want music for. Folders inside them are [override folders](docs/override-folders.md), which are optional.

The formats that work are `.mp3`, `.m4a`, `.aac`, `.wav`, `.flac`, and `.wma`. Other files, such as `.ogg` and `.opus`, are ignored, so convert those to a supported format first. File names in any language work.

## Requirements

* [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19).
* [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8) (DMF).
* `MusicReplacer` listed below `dmf` in `mod_load_order.txt`, in the game's `mods` folder.

On a Windows "N" edition, install Microsoft's free Media Feature Pack, which provides the audio decoder the mod uses. Without it, the mod cannot play your songs, and the game's music plays as usual.

## Where your music plays

Each folder plays in one situation. The music switches about half a second after the situation changes, or 3 seconds for a loading screen, so a moment that flickers does not restart the song. The Music Holds settings also keep combat, horde, boss, and event music going for a few seconds, so a short lull does not switch the music at once.

| Folder | When it plays |
|---|---|
| `title_screen` | On the title screen, before character select. |
| `character_select` | On the character select screen, also while you create a character. |
| `hub` | In the Mourningstar. |
| `loading` | On loading screens that lead anywhere but into a mission: after starting the game, after a mission, and on the way to Meat Grinder. |
| `mission_preparation` | On the mission preparation screen, where the party stands together before a mission and can still change loadouts, in every game mode. |
| `mission_briefing` | On the loading screens and the briefing on the way into a mission, also when you join a mission in progress. A song that the preparation screen interrupts continues in the briefing, unless Resume Songs is off. The mission's intro keeps the game's music. |
| `explore` | In a mission while nothing threatens you. |
| `combat` | In a mission while enemies attack you, outside a horde or a boss fight. |
| `horde` | During a horde. With no songs here, the game's horde music plays, as it does without the mod. |
| `boss` | While a monstrosity is near you, such as a Chaos Spawn, a Beast of Nurgle, a Plague Ogryn, or an Ogryn Houndmaster. This is when the game plays its own boss music. Captains and angered daemonhosts get boss music only with their settings on. A scripted boss, such as Rodin Karnak in Spillway, gets no boss music, since the game does not report it as a boss. |
| `event` | While a mission event plays its music, such as a holdout, a hacking event, an escape, or a scripted boss fight like those in Spillway. It outranks boss, horde, combat, and explore music, as the game's event music does. In Operations, such as Rolling Steel and No Man's Land, it plays for the whole mission, since the game scripts their music from start to end. |
| `last_stand` | While only one player of the team is left alive. It outranks events, Mortis Trials waves and breaks, the Expedition extraction, bosses, hordes, combat, and explore. Victory and defeat still take over. |
| `victory` | From the moment a mission is won until the loading screen or a cutscene. |
| `defeat` | From the moment a mission is lost until the loading screen or a cutscene. |
| `mortis_trials_wave` | In Mortis Trials, during a wave or an objective round, through to the final win. Bosses, hordes, and fights do not interrupt it, since nearly every wave brings bosses. A last stand still takes over. |
| `mortis_trials_break` | In Mortis Trials, between waves. |
| `expedition_combat` | During a fight in an Expedition. Expeditions play this folder in place of `combat` and `horde`. |
| `expedition_safe_room` | In an Expedition's safe room. |
| `expedition_extraction` | While an Expedition's extraction runs, until the mission is won or lost. Only a last stand takes over. |

In Mortis Trials, the two Mortis Trials folders replace the mission folders from `explore` to `event`. In an Expedition, quiet moments play `explore`.

Meat Grinder has no folder of its own. It is a choice under Music per Situation, which starts at Silence. Set it to Custom to hear your `explore` and `combat` songs there, which is a quick way to test them.

## Choosing what plays

The Music per Situation group has one dropdown per situation: Title Screen, Character Select, Hub, Loading, Mission Preparation, Mission Briefing, Explore, Combat, Horde, Boss, Event, Last Stand, Victory, Defeat, Mortis Trials Wave, Mortis Trials Break, Expedition Combat, Expedition Safe Room, Expedition Extraction, and Meat Grinder. Each offers the same three choices:

| Choice | What plays |
|---|---|
| Custom | Your songs from the situation's folder. With an empty folder, the game's music plays. This is the default everywhere except Meat Grinder. |
| Vanilla | Always the game's music, even with songs in the folder, so you can turn one situation off without moving files. |
| Silence | Nothing. The game's music is silenced too. |

Meat Grinder starts at Silence. There, Custom plays your `explore` and `combat` songs, and empty folders play the game's music. Vanilla plays the game's music there, which is none, so it sounds the same as Silence.

A changed choice applies at once, also to the situation that is playing.

## Settings

The settings are in the in-game mod options under Music Replacer, in six groups: Playback, Music per Situation, Volume, Boss Music, Music Holds, and Debug. Every setting and its default is explained in [docs/settings.md](docs/settings.md).

## Override folders

Override folders are optional and for advanced use. A folder can hold folders of its own, which play for a kind of event, a kind of boss, a mission, or a game mode. They are explained in [docs/override-folders.md](docs/override-folders.md).

## Safe by design

* **No game files are changed.** The mod creates its own audio folders and writes files only to its own folder in `%APPDATA%`.
* **No extra programs or DLLs.** The mod uses the audio decoder and audio engine that come with Windows, and calls them from its Lua scripts.
* **The game's music is the fallback.** The game's music plays wherever the mod has no songs, cannot play them, or cannot start Windows audio at all. The game's music is only silenced once one of your songs is ready to play, or where you chose Silence.
* **Broken files are skipped.** A file Windows cannot decode is skipped once the mod has checked it, shortly after launch, and the log names it. If three songs in a row from one folder fail to play, that folder gives way to the game's music until the game restarts or the folders are listed again. An override folder gives way to its parent folder instead.
* **Easy to turn off.** You can turn the mod off in the mod options at any time, and the game's music comes back at once.
* **Your music files are never changed.** The mod only reads them.
* **It stops with the game.** The music plays inside the game itself, so it stops when the game closes, even after a crash.

What the mod writes where, and how it handles a lost audio device, are covered in [docs/troubleshooting.md](docs/troubleshooting.md).

## Updating and uninstalling

Update or reinstall the mod through Vortex as usual. Your songs survive that. Vortex only removes files it deployed itself, and the mod archive holds only the empty audio folders, never songs. Your songs do not survive the mod folder being renamed, so move `audio\` across by hand if that ever happens.

Uninstalling the mod leaves its own files in `%APPDATA%\Fatshark\Darktide\MusicReplacer\` behind. Delete that folder by hand if you want them gone. Check `mods\MusicReplacer\audio\` in the game folder too, since your songs were never part of the mod archive.

## Compatibility

* Music Replacer only affects your own game. Squadmates hear their own game's music, with or without the mod.
* Running it alongside other music mods has not been tested. A mod that also changes the game's music states may conflict with it.
* The mod has not been tested on Steam Deck or Linux. There the game runs through Proton, which brings its own stand-ins for the Windows audio decoder and audio engine the mod uses. If the mod cannot start them, the game's music plays as usual.
* If your Windows user name has letters outside the language Windows uses for older programs, such as Japanese letters on an English Windows, the mod cannot write `diagnostic.log` or `loudness.txt`. Your music still plays, and Even Out Loudness measures your songs again at every launch.

## Troubleshooting

Fixes for common problems are in [docs/troubleshooting.md](docs/troubleshooting.md).

To report a problem, attach these two files:

* The mod's log from `%APPDATA%\Fatshark\Darktide\MusicReplacer\`. That is `diagnostic.log` if the problem happened in the current or last game session, or `diagnostic-prev.log` if it happened in the session before that.
* The newest file in `%APPDATA%\Fatshark\Darktide\console_logs\`.

## Languages and contributing

* The mod options and their tooltips are in English. With the game set to another language, they show in English too.
* Translations are welcome as pull requests on [GitHub](https://github.com/Lempki/darktide-music-replacer). [docs/development.md](docs/development.md) explains where the texts live and how to add a language.
* Fixes, ideas, and bug reports are welcome there too, as pull requests or issues. For a bug, attach the files listed under Troubleshooting.

## Credits

* [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19) and [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8), which this mod builds on.
* [Audio Plugin](https://www.nexusmods.com/warhammer40kdarktide/mods/196) and [Darktide Local Server](https://www.nexusmods.com/warhammer40kdarktide/mods/211), which early versions of this mod played their music through.
* [Simple Audio](https://www.nexusmods.com/warhammer40kdarktide/mods/929) and [Darktide DJ - Music Picker and Shuffler](https://www.nexusmods.com/warhammer40kdarktide/mods/1118), whose takes on custom and situational music inspired this mod.

## More documentation

* For players:
  * [Settings](docs/settings.md): every setting, its default, and the debug overlay's lines.
  * [Override folders](docs/override-folders.md): songs for a kind of event, a kind of boss, a mission, or a game mode.
  * [Troubleshooting](docs/troubleshooting.md): fixes, reporting a problem, the files the mod writes, and a lost audio device.
* For reading the log:
  * [Wwise music states and events](docs/wwise-events.md): the game's music states, how the mod silences them, and tracing a sound.
  * [Game missions and modes](docs/game-internals.md): how the game reports its missions and modes.
* For developers:
  * [Development](docs/development.md): building, testing, how playback works, the project structure, and the roadmap.
