# darktide-music-replacer

This is Music Replacer, a mod for Warhammer 40,000: Darktide that replaces the game's music with your own audio files, chosen by what is actually happening in the hub or a mission. It plays them inside the game through Windows' own audio decoder and game audio engine, so it needs no other mods and no extra programs. Any context left without files keeps Darktide's own music, by construction rather than as a special case.

## Features

* Replaces hub, mission-explore, combat, horde, boss, event, last stand, victory, and defeat music with your own audio files, and gives Mortis Trials its own wave and break music.
* Several files in a folder are picked at random, never repeating the file that just played.
* Exactly one file in a folder loops seamlessly and indefinitely.
* When the next situation's folder holds only the song that is already playing, such as the same song in `title_screen` and `character_select`, it keeps playing instead of starting over. A copy counts as the same song when it has the same file name and size.
* Switching between songs is a true crossfade: the outgoing song fades out while the incoming one fades in.
* Explore and combat songs, and Mortis Trials wave and break songs, continue from where they stopped when the music switches back to them, instead of restarting. Horde, boss, and event songs continue too after higher-priority music interrupts them, such as a boss during a horde or a last stand during an event, as long as that horde, fight, or event is still going.
* Follows the in-game master and music volume sliders at once, in both directions, without restarting the song.
* Lets you pick, per context, your songs, the game's own music, or silence.
* Keeps the Meat Grinder training area silent unless you pick music there, which doubles as a quick way to test your files.
* The game's music is silenced only once a replacement track is available, so a context with no files behaves exactly like an unmodified game.

## Prerequisites

* You must install [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19) and [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8). Add `MusicReplacer` below `dmf` in `mod_load_order.txt`.
* Windows 10 or later. On a Windows "N" edition, install Microsoft's free Media Feature Pack, which provides the audio decoder the mod uses.

## Setup

Install this mod like any other Darktide mod, then drop your own audio files into the **installed** mod's folder, not this repository:

```
...\Warhammer 40,000 DARKTIDE\mods\MusicReplacer\audio\
    title_screen\
    character_select\
    hub\
    loading\
    mission_preparation\
    mission_briefing\
    explore\
    combat\
    horde\
    boss\
    event\
    last_stand\
    victory\
    defeat\
    mortis_trials_wave\
    mortis_trials_break\
    expedition_combat\
    expedition_safe_room\
    expedition_extraction\
```

All nineteen folders already exist after install. Put audio files directly inside whichever ones you want music for. Folders inside them are override folders, described below.

Supported formats are `.mp3`, `.m4a`, `.aac`, `.wav`, `.flac`, and `.wma`. Other files, such as `.ogg` and `.opus`, are ignored, so convert those to a supported format first. File names in any language work.

| Folder | When it plays |
|---|---|
| `title_screen` | On the title screen, before character select. |
| `character_select` | On the character select screen, also while you create a character. |
| `hub` | In the Mourningstar. |
| `loading` | On loading screens that lead anywhere but into a mission: after starting the game, after a mission, and on the way to Meat Grinder. |
| `mission_preparation` | On the mission preparation screen, where the party stands together before a mission and can still change loadouts, in every game mode. Joining a mission already in progress skips it. |
| `mission_briefing` | On the loading screens and the briefing on the way into a mission, also when joining a mission already in progress. A song that the preparation screen interrupts continues in the briefing, unless Resume Songs is off. The mission's intro itself keeps the game's own music. For music that differs by game mode, as the game's own does, use override folders such as `mission_briefing\havoc\` or `mission_briefing\expeditions\`. |
| `explore` | In a mission, no meaningful threat. |
| `combat` | In a mission, while enemies are attacking you outside a horde or a boss fight. The game itself plays no music here. |
| `horde` | In a mission, during a horde. With no files here, the game's own horde music plays, as it does without the mod. |
| `boss` | In a mission, while a monstrosity is near you, such as a Chaos Spawn, a Beast of Nurgle, a Plague Ogryn, or an Ogryn Houndmaster. This is exactly when the game plays its own boss music, and the Boss Music Hold bridges the moments the game briefly stops reporting the boss. It does not play during an event, a last stand, or the mission's end, which take priority. It also does not play for an angered Daemonhost unless you turn on its setting. It does not play for captains unless you turn on their setting, or while a scripted boss such as Spillway's psyker is alive, since the game does not report those as bosses. |
| `event` | In a mission, while an event plays its own music, such as a holdout, a hacking event, an escape, or a scripted boss fight like those in Spillway. It replaces boss, horde, combat, and explore music, as the game's own event music does. It does not play during a last stand or the mission's end, and it stops a few seconds after the game ends the event's music, as set by Event Music Hold. In Operations, such as Rolling Steel and No Man's Land, it plays for the whole mission, since the game scripts their music from start to end. |
| `last_stand` | In a mission, while only one player of the team is still alive. It replaces boss, combat, and explore music, as the game's own last stand music does. |
| `victory` | From the moment a mission is won until the loading screen or a cutscene. |
| `defeat` | From the moment a mission is lost until the loading screen or a cutscene. |
| `mortis_trials_wave` | In Mortis Trials, during a wave or an objective round, through to the final win. Bosses, hordes, and fights do not interrupt it, since nearly every wave brings bosses. A last stand still takes over. In Mortis Trials, this and the break folder replace the mission folders above, apart from last stand, victory, and defeat. |
| `mortis_trials_break` | In Mortis Trials, between waves. |
| `expedition_combat` | In an Expedition, during a fight. Expeditions play this folder in place of Combat and Horde. |
| `expedition_safe_room` | In an Expedition's safe room. |
| `expedition_extraction` | While an Expedition's extraction runs, until the mission is won or lost. Only a last stand takes over. |

No custom music plays during cutscenes. The game's own music takes over there.

### Override folders

A context folder can hold folders of its own, named after what the game reports, which take over from it while they apply. For example, songs in `boss\chaos_spawn\` play while a Chaos Spawn is the boss, and songs in `explore\havoc\` play while exploring in Havoc. When several apply, the first one in this order that has songs wins:

1. In `event`, the kind of event, as the game names its event music: for example `escape_event`, `fortification_event`, `twins_event`, or an Operation's `operation_stage_1`. [docs/wwise-events.md](docs/wwise-events.md) lists the kinds seen so far.
2. In `boss`, the kind of boss: for example `chaos_spawn`, `chaos_beast_of_nurgle`, `chaos_plague_ogryn`, or `chaos_ogryn_houndmaster`, and with their settings on, `renegade_twin_captain` or `chaos_daemonhost`.
3. In any context, the mission's code: for example `spillway` or `km_enforcer_twins`. [docs/game-internals.md](docs/game-internals.md) lists every mission's code with its in-game name.
4. In any context, the game mode: `havoc`, `expeditions`, or `mortis_trials`.

On the way into a mission, the mission's code and its game mode apply from the moment the game knows the mission, so `mission_briefing\mortis_trials\` plays during the Mortis Trials briefing. Havoc only applies once the mission has loaded.

An override folder with no songs is skipped, so the context's own folder, or the game's music, plays as before. The mod does not create these folders, so make the ones you want. Their names ignore case, and folders inside an override folder are not read. The music switches as soon as another override applies, for example when the game names a boss a few seconds after the boss music started, or when an event moves on to its escape. With Debug Overlay on, its Folder line shows the folder playing now and the override names the moment looks for.

Your audio survives reinstalling or updating the mod through Vortex. Vortex only removes files it deployed itself, and `audio\` is never part of the mod archive. It does not survive the mod folder being renamed, so move `audio\` across by hand if that ever happens.

## Settings

These are in the in-game mod options under Music Replacer, in six groups, in the order the menu shows them.

### Playback

| Setting | Default | What it does |
|---|---|---|
| Rescan Audio Folders | (button) | Lists the audio folders again at once, and measures every song again. The mod already notices added, removed, and replaced files by itself a few seconds after they change, so this is for drives where Windows cannot report changes, such as some network drives, and for trying a song again that would not play. |
| Resume Songs | On | When explore or combat music, or a Mortis Trials wave or break, comes back, its song continues from where it stopped. A horde, boss, or event song also continues after higher-priority music interrupts it, such as a boss during a horde or a last stand during an event, as long as that horde, fight, or event did not end in between. A new horde, boss fight, or event gets a new pick. A new song is also picked once one ends on its own. Every mission and hub visit starts with fresh songs. A mission loading song that the mission preparation screen interrupts continues in the briefing after it. |

### Music per Situation

One dropdown per context: Title Screen, Character Select, Hub, Loading, Mission Preparation, Mission Briefing, Explore, Combat, Horde, Boss, Event, Last Stand, Victory, Defeat, Mortis Trials Wave, Mortis Trials Break, Expedition Combat, Expedition Safe Room, Expedition Extraction, and Meat Grinder. Each picks what plays there:

| Choice | What plays |
|---|---|
| Custom | Your songs from the context's folder, or the game's own music while the folder is empty. This is the default for every context except Meat Grinder. |
| Vanilla | The game's own music, even with songs in the folder, so you can turn one context off without moving files. |
| Silence | Nothing. The game's own music is silenced too. |

Meat Grinder defaults to Silence. There, Custom plays your explore and combat songs, which is a quick way to test them, and Vanilla plays the game's music there, which is none, so it sounds the same as Silence. A changed choice applies at once, also to the context playing now.

### Volume

| Setting | Default | What it does |
|---|---|---|
| Custom Music Volume | 100% | How loud your songs play, on top of the game's master and music volume sliders. At 100% they play as loud as the files themselves. The game's own music is not affected. |
| Even Out Loudness | Off | Plays every song at about the same loudness, without changing your files. The mod measures each song once in the background and remembers it, see How it plays below. A song not measured yet plays at its own level, and a song that starts playing keeps its level until it starts again. |
| Menu Volume | 50% | How loud your songs play while a menu is open, as a share of the Custom Music Volume. The menus are the ones the game itself reports to its audio: the Esc menu and its settings, the inventory, the mission board, vendors, the store, and character appearance. The music fades down over half a second, and back up half a second after the last menu closes, so moving between menus does not raise it. Set it to 100% to keep full volume in menus. |

### Boss Music

| Setting | Default | What it does |
|---|---|---|
| Boss Music for Captains | Off | On plays your boss music for a captain from the moment it engages until it dies. Off leaves captains to the game's own music. Event music still plays during an event. |
| Boss Music for Daemonhosts | Off | Off follows the game, which plays no music for an angered daemonhost. On plays your boss music from the moment a daemonhost is angered until it dies. |

### Music Holds

| Setting | Default | What it does |
|---|---|---|
| Combat Music Hold | 8 seconds | How long combat music keeps playing after a fight quiets down, so a short lull does not switch to explore music. Set it to 0 to follow the game exactly. |
| Horde Music Hold | 3 seconds | How long horde music keeps playing after the game stops reporting a horde. The game drops its horde signal for a second or two whenever few enemies are on you, so a short hold keeps the track from restarting. Set it to 0 to follow the game exactly. |
| Boss Music Hold | 3 seconds | How long boss music keeps playing after the game stops reporting a boss that is still alive. The game drops its boss signal for a second or two now and then during a boss fight, so a short hold keeps the track from switching away and back. Boss music still ends as soon as the boss dies. Set it to 0 to follow the game exactly. |
| Event Music Hold | 5 seconds | How long event music keeps playing after the game ends an event's music. Some events pause their music for a few seconds between stages, so a short hold keeps the event's song from starting over at every stage. Set it to 0 to follow the game exactly. |

### Debug

| Setting | Default | What it does |
|---|---|---|
| Detailed Logging | Off | Adds the game's raw music states, the silencing of its music, and its sound events to `diagnostic.log`. The important events are always logged. See Troubleshooting below. |
| Debug Overlay | Off | Shows the current context and what it plays, the song with its time, and the volume factors in a top corner of the screen. It shows on every screen, loading screens and the preparation screen included, and shows holds and changes that are still settling, which helps when checking which music a moment counts as. Its Folder line names the override folders the moment looks for. Overlay Corner and Overlay Size, shown while it is on, pick the top left or the top right and scale it from 50% to 200% away from its corner. Custom HUD cannot move it, since it is not part of the HUD. |

## How it plays

Music Replacer decodes your files with Media Foundation, Windows' own audio decoder, and plays them with XAudio2, the audio engine Windows provides for games. It calls both from Lua through the ffi the mod loader provides, so the mod ships no DLL or executable.

* Each playing song holds a fixed buffer of about 0.7 MB, allocated once and outside the game's Lua memory. A song that fades out keeps it for up to a minute, so a song that comes back soon continues without reopening its file, and then frees it.
* About four seconds of music are always queued ahead, so the music plays on through a stalled frame or a busy loading moment.
* XAudio2 follows a change of the default audio device by itself. If the device is lost in a way it cannot follow, the mod rebuilds the engine and continues the song where it was. After three rebuilds in a row fail, it gives up for the session and the game's own music plays.
* While Windows has no audio output at all, for example right after the only headset is unplugged, the game's own music takes over and the mod tries again every five seconds. Custom music comes back once the output does.
* The music plays inside the game's own process, so it stops with the game, including after a crash.
* With Even Out Loudness on, the mod measures each song's loudness the way streaming services do, in LUFS, following ITU-R BS.1770. Every song then plays at -14 LUFS, the level most of them use. A quiet song is only raised until its loudest sample reaches full scale, so it never distorts, and by at most 12 dB, since raising a very quiet recording further mostly raises its hiss.
* Measuring decodes the whole song, about a millisecond of work per frame, starting with the folder of the music playing now. The log says how long it took once every song is measured. The results go to `loudness.txt` beside `diagnostic.log`, so each song is measured once, and again only after its file changes. Deleting `loudness.txt` measures every song again.

## Limitations

* The mod notices audio files added, removed, or replaced while the game runs, and lists the folders again 3 seconds after the changes stop. A song that is playing keeps playing, and a context that had no files starts its new song right away. On a drive where Windows cannot report changes, such as some network drives, press Rescan Audio Folders instead.
* A file Windows cannot decode is skipped once the mod has measured it, shortly after launch, and the log names it. If one is picked before then and fails three times in a row, that context uses the game's own music until the game restarts or the audio folders are listed again.
* Music Replacer only affects your own game. Squadmates hear the game's own music regardless.
* If your Windows user name has letters outside the language Windows uses for older programs, such as Japanese letters on an English Windows, the mod cannot write `diagnostic.log` or `loudness.txt`. Your music still plays, and Even Out Loudness measures your songs again at every launch.
* The mission intro and cutscenes play the game's own music.

## Troubleshooting

* **No custom music anywhere.** Check that `MusicReplacer` is listed below `dmf` in `mod_load_order.txt`, that Music Replacer appears in the mod options and is turned on, and that your files sit directly inside the audio folders in a supported format.
* **The chat shows "Music Replacer could not start Windows audio playback".** The mod could not start Windows' audio decoder or audio engine, so the game's own music plays as usual. The message ends with the reason. On a Windows "N" edition, install the Media Feature Pack. If Windows had no audio output at that moment, the mod keeps trying and starts once there is one.
* **One file never plays.** Windows cannot decode it. Convert it to another supported format. The mod picks up the new file by itself.

To report a problem, attach these two files:

* The mod's log from `%APPDATA%\Fatshark\Darktide\MusicReplacer\`. That is `diagnostic.log` if the problem happened in the current or last game session, or `diagnostic-prev.log` if it happened in the session before that.
* The newest file in `%APPDATA%\Fatshark\Darktide\console_logs\`.

The mod always logs the important events, such as which music plays and why, and any file it could not play. Every game launch starts a fresh `diagnostic.log` and keeps the previous one as `diagnostic-prev.log`. If you are asked for more detail, turn on Detailed Logging in the Debug group of the mod options and play until the problem happens again. What the detailed lines mean is explained in [docs/wwise-events.md](docs/wwise-events.md) and [docs/game-internals.md](docs/game-internals.md).

## Development

Building, testing, the project structure, and the roadmap are covered in [docs/development.md](docs/development.md).
