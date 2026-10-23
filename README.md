# darktide-music-replacer

Music Replacer is a mod for Warhammer 40,000: Darktide that plays your own music in place of the game's, chosen by what is happening in the hub or a mission.
You put audio files into folders, one folder per situation, and the mod picks the right one as you play.
Wherever you add no songs, the game's music plays as usual.

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
* It does not affect your squadmates.
  They hear their own game's music.
* It does not play your music during mission intros and cutscenes.
  The game's music plays there.
* It does not download or stream anything.
  It plays only the files in its own audio folders.
* It does not change your music files.

## Quick start

1. Install Music Replacer like any other Darktide mod, for example through Vortex.
   Check that `MusicReplacer` is listed below `dmf` in `mod_load_order.txt`, as described under Requirements.
2. Put your audio files into the folders inside the **installed** mod folder: `...\Warhammer 40,000 DARKTIDE\mods\MusicReplacer\audio\<folder>\`.
   For example, songs in `audio\hub\` play in the Mourningstar.
   Every folder is listed under Where your music plays.
3. Start the game and play.

The mod creates any missing folder when the game starts, so every folder is there after your first launch at the latest.
Put audio files directly inside the folders you want music for.
Folders inside them are override folders, which are optional.

The formats that work are `.mp3`, `.m4a`, `.aac`, `.wav`, `.flac`, and `.wma`.
Other files, such as `.ogg` and `.opus`, are ignored, so convert those to a supported format first.
File names in any language work.

## Requirements

* [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19).
* [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8) (DMF).
* `MusicReplacer` listed below `dmf` in `mod_load_order.txt`, in the game's `mods` folder.

On a Windows "N" edition, install Microsoft's free Media Feature Pack, which provides the audio decoder the mod uses.
Without it, the mod cannot play your songs, and the game's music plays as usual.

## Where your music plays

Each folder plays in one situation.
The music switches about half a second after the situation changes, or 3 seconds for a loading screen, so a moment that flickers does not restart the song.
The Music Holds settings also keep combat, horde, boss, and event music going for a few seconds, so a short lull does not switch the music at once.

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
| `boss` | While a monstrosity is near you, such as a Chaos Spawn, a Beast of Nurgle, a Plague Ogryn, or an Ogryn Houndmaster. This is when the game plays its own boss music. Captains and angered daemonhosts get boss music only with their settings on. A scripted boss such as Spillway's psyker gets no boss music, since the game does not report it as a boss. |
| `event` | While a mission event plays its music, such as a holdout, a hacking event, an escape, or a scripted boss fight like those in Spillway. It outranks boss, horde, combat, and explore music, as the game's event music does. In Operations, such as Rolling Steel and No Man's Land, it plays for the whole mission, since the game scripts their music from start to end. |
| `last_stand` | While only one player of the team is left alive. It outranks events, Mortis Trials waves and breaks, the Expedition extraction, bosses, hordes, combat, and explore. Victory and defeat still take over. |
| `victory` | From the moment a mission is won until the loading screen or a cutscene. |
| `defeat` | From the moment a mission is lost until the loading screen or a cutscene. |
| `mortis_trials_wave` | In Mortis Trials, during a wave or an objective round, through to the final win. Bosses, hordes, and fights do not interrupt it, since nearly every wave brings bosses. A last stand still takes over. |
| `mortis_trials_break` | In Mortis Trials, between waves. |
| `expedition_combat` | During a fight in an Expedition. Expeditions play this folder in place of `combat` and `horde`. |
| `expedition_safe_room` | In an Expedition's safe room. |
| `expedition_extraction` | While an Expedition's extraction runs, until the mission is won or lost. Only a last stand takes over. |

In Mortis Trials, the two Mortis Trials folders replace the mission folders from `explore` to `event`.
In an Expedition, quiet moments play `explore`.

Meat Grinder has no folder of its own.
It is a choice under Music per Situation, which starts at Silence.
Set it to Custom to hear your `explore` and `combat` songs there, which is a quick way to test them.

## Choosing what plays

The Music per Situation group has one dropdown per situation: Title Screen, Character Select, Hub, Loading, Mission Preparation, Mission Briefing, Explore, Combat, Horde, Boss, Event, Last Stand, Victory, Defeat, Mortis Trials Wave, Mortis Trials Break, Expedition Combat, Expedition Safe Room, Expedition Extraction, and Meat Grinder.
Each offers the same three choices:

| Choice | What plays |
|---|---|
| Custom | Your songs from the situation's folder. With an empty folder, the game's music plays. This is the default everywhere except Meat Grinder. |
| Vanilla | Always the game's music, even with songs in the folder, so you can turn one situation off without moving files. |
| Silence | Nothing. The game's music is silenced too. |

Meat Grinder starts at Silence.
There, Custom plays your `explore` and `combat` songs, and empty folders play the game's music.
Vanilla plays the game's music there, which is none, so it sounds the same as Silence.

A changed choice applies at once, also to the situation that is playing.

## Settings

The settings are in the in-game mod options under Music Replacer, in six groups, in the order the menu shows them.

### Playback

| Setting | Default | What it does |
|---|---|---|
| Rescan Audio Folders | (button) | Lists the audio folders again at once, and checks every song again. The mod notices added, removed, and replaced files by itself. It lists the folders again 3 seconds after files stop changing. Use this button on drives where Windows cannot report changes, such as some network drives, and to try a song again that would not play. It also lets the mod try playback again after it gave up. It does not measure loudness again. |
| Resume Songs | On | Explore, combat, Mortis Trials, and Expedition fight and safe room songs continue where they stopped when their music comes back. Horde, boss, and event songs continue too after music that outranks them interrupts them, such as a boss during a horde or a last stand during an event, while that horde, fight, or event lasts. A new horde, boss fight, or event gets a new pick. A song that stopped in its last 10 seconds is not continued. A new song is picked once one ends on its own. Every mission and hub visit starts with fresh songs. |

### Music per Situation

One dropdown per situation, with the choices Custom, Vanilla, and Silence.
See Choosing what plays above.

### Volume

| Setting | Default | What it does |
|---|---|---|
| Custom Music Volume | 100% | How loud your songs play, on top of the game's master and music volume sliders. At 100%, they play as loud as the files themselves. The game's music is not affected. |
| Even Out Loudness | Off | Plays every song at about the same loudness, without changing your files. Each song is measured once in the background and remembered, starting with the folder that plays. A song not measured yet plays at its own level, and a song measured while it plays changes level at its next start. Loud songs are turned down. A quiet song is only raised as far as it can go without distorting, and a very quiet one only partway, since raising it further mostly raises its hiss. |
| Menu Volume | 50% | How loud your songs play while a menu is open, as a share of the Custom Music Volume. The menus are the ones the game reports to its audio: the Esc menu and its settings, the inventory, the mission board, vendors, the store, and character appearance. The music fades down over half a second. It fades back up once no menu has been open for half a second, so moving between menus does not raise it. 100% keeps the music at full volume in menus. |

### Boss Music

| Setting | Default | What it does |
|---|---|---|
| Boss Music for Captains | Off | Plays your boss music while a captain is in the fight, from the moment it engages until it dies. Off leaves captains to the game's music. During an event, event music still plays. |
| Boss Music for Daemonhosts | Off | Plays your boss music while an angered daemonhost is alive. Off follows the game, which plays no music for daemonhosts. |

### Music Holds

Each hold goes from 0 to 30 seconds.
Set one to 0 to follow the game exactly.

| Setting | Default | What it does |
|---|---|---|
| Combat Music Hold | 8 seconds | How long combat music keeps playing after a fight quiets down, so a short lull does not switch to explore music. |
| Horde Music Hold | 3 seconds | How long horde music keeps playing after the game stops reporting a horde. The game drops that signal for a moment whenever few enemies are on you, so a short hold keeps the song from switching away and back. |
| Boss Music Hold | 3 seconds | How long boss music keeps playing after the game stops reporting a boss that is still alive. The game drops that signal for a moment now and then during a boss fight. Boss music still ends as soon as the boss dies. |
| Event Music Hold | 5 seconds | How long event music keeps playing after the game ends an event's music. Some events pause their music for a few seconds between stages, so a short hold keeps the event's song from starting over at every stage. |

### Debug

| Setting | Default | What it does |
|---|---|---|
| Detailed Logging | Off | Writes much more to `diagnostic.log`: every change in the game's music, each time the mod silences it, and the game's sound events. The important events are always logged, which is enough for most bug reports. The extra lines add up quickly, so turn this on only while tracking down a problem. |
| Debug Overlay | Off | Shows which situation the mod sees, the song playing, and its volume in a top corner of the screen. It shows on every screen, loading screens and the preparation screen included. It is useful for checking which music a moment counts as. |
| Overlay Corner | Top Left | Where the debug overlay sits, shown while the overlay is on. Top Left stays clear of the mission objectives, which sit at the top right. |
| Overlay Size | 100% | How big the debug overlay is, from 50% to 200%, shown while the overlay is on. It grows and shrinks away from its corner. |

The debug overlay has these lines:

* **Context** names the situation and what plays there, for example `explore (Custom)`, `hub (Vanilla)`, or `boss (Vanilla, no songs)`.
* **Folder** names the folder that plays, and the override names the moment looks for.
* **Waiting** shows a hold or a change that is still settling, with the seconds left.
* **Song** shows the file name, how far into it the song is, and its length.
* **Volume** shows the Custom Music Volume, the Menu Volume, and the song's own level from Even Out Loudness.

## Override folders

This section is optional and for advanced use.
Your music works without any of it.

A folder can hold folders of its own, named after what the game reports, which take over from it while they apply.
For example, songs in `boss\chaos_spawn\` play while a Chaos Spawn is the boss, and songs in `explore\expeditions\` play while you explore in an Expedition.
When several apply, the first one in this order that has songs wins:

1. In `event`, the kind of event, as the game names its event music: for example `escape_event`, `fortification_event`, `twins_event`, or an Operation's `operation_stage_1`. [docs/wwise-events.md](docs/wwise-events.md) lists the kinds.
2. In `boss`, the kind of boss: for example `chaos_spawn`, `chaos_beast_of_nurgle`, `chaos_plague_ogryn`, or `chaos_ogryn_houndmaster`, and with their settings on, `renegade_twin_captain` or `chaos_daemonhost`.
3. In any folder, the mission's code: for example `spillway` or `km_enforcer_twins`. [docs/game-internals.md](docs/game-internals.md) lists every mission's code with its in-game name.
4. In any folder, the game mode: `havoc`, `expeditions`, or `mortis_trials`.

On the way into a mission, the mission's code and its game mode apply during the preparation screen and the briefing.
So `mission_briefing\mortis_trials\` plays during the Mortis Trials briefing.
Havoc applies only once the mission has loaded, so a `havoc` folder does not apply on the preparation screen.

An override folder with no songs is skipped, so its parent folder, or the game's music, plays as before.
The mod does not create these folders, so make the ones you want.
Their names ignore case, and folders inside an override folder are not read.
The music switches within half a second once another override applies, for example when the game names a boss a few seconds after the boss music started, or when an event moves on to its escape.
With Debug Overlay on, its Folder line shows the folder that plays and the override names the moment looks for.

## Safe by design

* **No game files are changed.** The mod creates its own audio folders and writes files only to its own folder in `%APPDATA%`.
* **No extra programs or DLLs.** The mod uses the audio decoder and audio engine that come with Windows, and calls them from its Lua scripts.
* **The game's music is the fallback.** The game's music plays wherever the mod has no songs, cannot play them, or cannot start Windows audio at all.
  The game's music is only silenced once one of your songs is ready to play, or where you chose Silence.
* **Broken files are skipped.** A file Windows cannot decode is skipped once the mod has checked it, shortly after launch, and the log names it.
  If three songs in a row from one folder fail to play, that folder gives way to the game's music until the game restarts or the folders are listed again.
  An override folder gives way to its parent folder instead.
* **Easy to turn off.** You can turn the mod off in the mod options at any time, and the game's music comes back at once.
* **Your music files are never changed.** The mod only reads them.
* **It stops with the game.** The music plays inside the game itself, so it stops when the game closes, even after a crash.

The mod writes these files to `%APPDATA%\Fatshark\Darktide\MusicReplacer\`:

* `diagnostic.log`, the log of the current or last game session.
  Every launch starts a fresh one.
  A runaway log stops growing at 10 MB.
* `diagnostic-prev.log`, the log of the session before that.
* `loudness.txt`, the remembered results of Even Out Loudness, so each song is measured only once, and again after its file changes.
  Deleting it measures every song again.

If your audio device goes away, the mod handles it like this:

* While Windows has no audio output at all, for example right after you unplug your only headset, the game's music takes over.
  The mod tries again every 5 seconds, and your music comes back once an output does.
* If the audio device is lost in a way Windows cannot recover from by itself, the mod restarts its audio and continues the song where it was.
* If it still fails after three restarts in a row, the mod gives up and the game's music plays.
  Press Rescan Audio Folders, or turn the mod off and on, to let it try again.

## Updating and uninstalling

Update or reinstall the mod through Vortex as usual.
Your songs survive that.
Vortex only removes files it deployed itself, and the mod archive holds only the empty audio folders, never songs.
Your songs do not survive the mod folder being renamed, so move `audio\` across by hand if that ever happens.

Uninstalling the mod leaves its own files in `%APPDATA%\Fatshark\Darktide\MusicReplacer\` behind.
Delete that folder by hand if you want them gone.
Check `mods\MusicReplacer\audio\` in the game folder too, since your songs were never part of the mod archive.

## Compatibility

* Music Replacer only affects your own game.
  Squadmates hear their own game's music, with or without the mod.
* Running it alongside other music mods has not been tested.
  A mod that also changes the game's music states may conflict with it.
* Custom HUD cannot move the debug overlay, since the overlay is not part of the HUD.
* The mod has not been tested on Steam Deck or Linux.
  There the game runs through Proton, which brings its own stand-ins for the Windows audio decoder and audio engine the mod uses.
  If the mod cannot start them, the game's music plays as usual.
* If your Windows user name has letters outside the language Windows uses for older programs, such as Japanese letters on an English Windows, the mod cannot write `diagnostic.log` or `loudness.txt`.
  Your music still plays, and Even Out Loudness measures your songs again at every launch.

## Troubleshooting

* **No custom music anywhere.** Check that `MusicReplacer` is listed below `dmf` in `mod_load_order.txt`, that Music Replacer appears in the mod options and is turned on, and that your files sit directly inside the audio folders in a supported format.
* **The chat shows "Music Replacer could not start Windows audio playback".** The mod could not start Windows' audio decoder or audio engine, so the game's music plays as usual.
  The message ends with the reason.
  On a Windows "N" edition, install the Media Feature Pack.
  If Windows had no audio output at that moment, the mod keeps trying and starts once there is one.
* **One file never plays.** Windows cannot decode it.
  Convert it to another supported format.
  The mod picks up the new file by itself.
* **A situation plays the game's music although its folder has songs.** Turn on Debug Overlay and read its Context line.
  `Vanilla` means the situation is set to Vanilla.
  `Vanilla, no songs` means the mod found no playable file in that folder.
  `Vanilla, its songs would not play` means three songs in a row failed.
  `Vanilla, no audio output` means Windows audio is not available, or the mod gave up on it after repeated failures.
* **Changed files are not picked up.** The mod lists the folders again 3 seconds after files stop changing.
  On a drive where Windows cannot report changes, such as some network drives, press Rescan Audio Folders.

To report a problem, attach these two files:

* The mod's log from `%APPDATA%\Fatshark\Darktide\MusicReplacer\`.
  That is `diagnostic.log` if the problem happened in the current or last game session, or `diagnostic-prev.log` if it happened in the session before that.
* The newest file in `%APPDATA%\Fatshark\Darktide\console_logs\`.

The mod always logs the important events, such as which music plays and why, and any file it could not play.
If you are asked for more detail, turn on Detailed Logging in the Debug group of the mod options and play until the problem happens again.
What the detailed lines mean is explained in [docs/wwise-events.md](docs/wwise-events.md) and [docs/game-internals.md](docs/game-internals.md).

## Development

Building, testing, how playback works, the project structure, and the roadmap are covered in [docs/development.md](docs/development.md).
