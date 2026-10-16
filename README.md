# darktide-music-replacer

This is Music Replacer, a mod for Warhammer 40,000: Darktide that replaces the game's music with your own audio files, chosen by what is actually happening in the hub or a mission. It plays them inside the game through Windows' own audio decoder and game audio engine, so it needs no other mods and no extra programs. Any context left without files keeps Darktide's own music, by construction rather than as a special case.

## Features

* Replaces hub, mission-explore, combat, horde, boss, event, last stand, victory, and defeat music with your own audio files, and gives Mortis Trials its own wave and break music.
* Several files in a folder are picked at random, never repeating the file that just played.
* Exactly one file in a folder loops seamlessly and indefinitely.
* Switching between songs is a true crossfade: the outgoing song fades out while the incoming one fades in.
* Explore and combat songs, and Mortis Trials wave and break songs, continue from where they stopped when the music switches back to them, instead of restarting. Horde, boss, and event songs continue too after higher-priority music interrupts them, such as a boss during a horde or a last stand during an event, as long as that horde, fight, or event is still going.
* Follows the in-game master and music volume sliders at once, in both directions, without restarting the song.
* Keeps the Meat Grinder training area silent unless you turn music on there, which doubles as a quick way to test your files.
* Native music is silenced only once a replacement track is available, so a context with no files behaves exactly like an unmodified game.

## Prerequisites

* You must install [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19) and [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8). Add `MusicReplacer` below `dmf` in `mod_load_order.txt`.
* Windows 10 or later. On a Windows "N" edition, install Microsoft's free Media Feature Pack, which provides the audio decoder the mod uses.

## Setup

Install this mod like any other Darktide mod, then drop your own audio files into the **installed** mod's folder, not this repository:

```
...\Warhammer 40,000 DARKTIDE\mods\MusicReplacer\audio\
    hub\
    mission_explore\
    mission_combat\
    mission_horde\
    mission_boss\
    mission_event\
    mission_last_stand\
    mission_victory\
    mission_defeat\
    mortis_trials_wave\
    mortis_trials_break\
```

All eleven folders already exist after install. Put audio files directly inside whichever ones you want music for. Files in subfolders inside them are not read.

Supported formats are `.mp3`, `.m4a`, `.aac`, `.wav`, `.flac`, and `.wma`. Other files, such as `.ogg` and `.opus`, are ignored, so convert those to a supported format first. File names in any language work.

| Folder | When it plays |
|---|---|
| `hub` | In the Mourningstar. |
| `mission_explore` | In a mission, no meaningful threat. |
| `mission_combat` | In a mission, while enemies are attacking you outside a horde or a boss fight. The game itself plays no music here. |
| `mission_horde` | In a mission, during a horde. With no files here, the game's own horde music plays, as it does without the mod. |
| `mission_boss` | In a mission, while a monstrosity is near you, such as a Chaos Spawn, a Beast of Nurgle, a Plague Ogryn, or an Ogryn Houndmaster. This is exactly when the game plays its own boss music. It does not play during an event, a last stand, or the mission's end, which take priority. It also does not play for an angered Daemonhost unless you turn on its setting. It does not play for captains unless you turn on their setting, or while a scripted boss such as Spillway's psyker is alive, since the game does not report those as bosses. |
| `mission_event` | In a mission, while an event plays its own music, such as a holdout, a hacking event, an escape, or a scripted boss fight like those in Spillway. It replaces boss, horde, combat, and explore music, as the game's own event music does. It does not play during a last stand or the mission's end, and it stops a few seconds after the game ends the event's music, as set by Event Music Hold. In Operations, such as Rolling Steel and No Man's Land, it plays for the whole mission, since the game scripts their music from start to end. |
| `mission_last_stand` | In a mission, while only one player of the team is still alive. It replaces boss, combat, and explore music, as the game's own last stand music does. |
| `mission_victory` | From the moment a mission is won until the loading screen or a cutscene. |
| `mission_defeat` | From the moment a mission is lost until the loading screen or a cutscene. |
| `mortis_trials_wave` | In Mortis Trials, during a wave or an objective round, through to the final win. Bosses, hordes, and fights do not interrupt it, since nearly every wave brings bosses. A last stand still takes over. In Mortis Trials, this and the break folder replace the mission folders above, apart from last stand, victory, and defeat. |
| `mortis_trials_break` | In Mortis Trials, between waves. |

No custom music plays during cutscenes. The game's own music takes over there.

Your audio survives reinstalling or updating the mod through Vortex. Vortex only removes files it deployed itself, and `audio\` is never part of the mod archive. It does not survive the mod folder being renamed, so move `audio\` across by hand if that ever happens.

## Settings

These are in the in-game mod options under Music Replacer, in four groups, in the order the menu shows them.

### Songs

| Setting | Default | What it does |
|---|---|---|
| Rescan Audio Folders | (button) | Picks up audio files added or removed since the game started, without a restart. A track that is playing keeps playing, and a context that had no files starts its new track right away. |
| Resume Songs | On | When explore or combat music, or a Mortis Trials wave or break, comes back, its song continues from where it stopped. A horde, boss, or event song also continues after higher-priority music interrupts it, such as a boss during a horde or a last stand during an event, as long as that horde, fight, or event did not end in between. A new horde, boss fight, or event gets a new pick. A new song is also picked once one ends on its own. Every mission and hub visit starts with fresh songs. |

### Where Music Plays

| Setting | Default | What it does |
|---|---|---|
| Boss Music for Captains | Off | On plays your boss music for a captain, including the Karnak Twins, from the moment it engages until it dies. Off leaves captains to the game's own music. Event music still plays during an event. |
| Boss Music for Daemonhosts | Off | Off follows the game, which plays no music for an angered daemonhost. On plays your boss music from the moment a daemonhost is angered until it dies. |
| Music in Meat Grinder | Off | Off keeps custom music out of the Meat Grinder training area and also silences the game's own combat music there. On plays your explore and combat music there. |

### Timing

| Setting | Default | What it does |
|---|---|---|
| Combat Music Hold | 8 seconds | How long combat music keeps playing after a fight quiets down, so a short lull does not switch to explore music. Set it to 0 to switch immediately. |
| Horde Music Hold | 3 seconds | How long horde music keeps playing after the game stops reporting a horde. The game drops its horde signal for a second or two whenever few enemies are on you, so a short hold keeps the track from restarting. Set it to 0 to follow the game exactly. |
| Event Music Hold | 5 seconds | How long event music keeps playing after the game ends an event's music. Some events pause their music for a few seconds between stages, so a short hold keeps the event's song from starting over at every stage. Set it to 0 to follow the game exactly. |

### Debug

| Setting | Default | What it does |
|---|---|---|
| Diagnostic Logging | Off | Writes `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log` for troubleshooting. See Troubleshooting below. |
| Reset Log on Launch | On | Shown while Diagnostic Logging is on. Clears `diagnostic.log` every time the game launches. Off keeps adding to it, trimmed to its last 2,000 lines. |

## How it plays

Music Replacer decodes your files with Media Foundation, Windows' own audio decoder, and plays them with XAudio2, the audio engine Windows provides for games. It calls both from Lua through the ffi the mod loader provides, so the mod ships no DLL or executable.

* Each playing song holds a fixed buffer of about 0.7 MB, allocated once and outside the game's Lua memory. A song that fades out keeps it for up to a minute, so a song that comes back soon continues without reopening its file, and then frees it.
* About four seconds of music are always queued ahead, so the music plays on through a stalled frame or a busy loading moment.
* XAudio2 follows a change of the default audio device by itself. If the device is lost in a way it cannot follow, the mod rebuilds the engine and continues the song where it was. After three rebuilds in a row fail, it gives up for the session and the game's own music plays.
* While Windows has no audio output at all, for example right after the only headset is unplugged, the game's own music takes over and the mod tries again every five seconds. Custom music comes back once the output does.
* The music plays inside the game's own process, so it stops with the game, including after a crash.

## Limitations

* Each audio folder is listed when the game launches. After adding or removing files while the game runs, press Rescan Audio Folders in the mod settings, or restart the game. Until then, a file you removed is skipped and a file you added is not picked up.
* A file Windows cannot decode is skipped once the mod has measured it, shortly after launch, and Diagnostic Logging names it. If one is picked before then and fails three times in a row, that context uses the game's own music until the game restarts or you press Rescan Audio Folders.
* Music Replacer only affects your own game. Squadmates hear the game's own music regardless.
* Loading screens, the mission briefing, the mission intro, and cutscenes play the game's own music. Custom music starts once you are in the hub or the mission itself.

## Troubleshooting

* **No custom music anywhere.** Check that `MusicReplacer` is listed below `dmf` in `mod_load_order.txt`, that Music Replacer appears in the mod options and is turned on, and that your files sit directly inside the audio folders in a supported format.
* **The chat shows "Windows audio playback could not start".** The mod could not start Windows' audio decoder or audio engine, so the game's own music plays as usual. The message ends with the reason. On a Windows "N" edition, install the Media Feature Pack. If Windows had no audio output at that moment, the mod keeps trying and starts once there is one.
* **One file never plays.** Windows cannot decode it. Convert it to another supported format, then press Rescan Audio Folders.

To report a problem, turn on Diagnostic Logging in the Debug group of the mod options, play until the problem happens, and attach these two files:

* `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log`
* The newest file in `%APPDATA%\Fatshark\Darktide\console_logs\`

Reset Log on Launch clears `diagnostic.log` every time the game starts, so copy the log before launching the game again, or turn that setting off first.

## Roadmap

* [x] Context-aware hub, explore, combat, boss, victory, and defeat switching.
* [x] Fallback to native music for any context without files.
* [x] Fade-in, natural-end fade-out, and true crossfades between songs.
* [x] Seamless looping for a single-file folder.
* [x] Native music suppressed while a custom track plays, only once a replacement is confirmed available.
* [x] All audio folders provisioned automatically, ready to use right after install.
* [x] Custom music following the in-game volume sliders at once, in both directions.
* [x] Adjustable combat music hold, so a lull in a fight does not drop back to explore music.
* [x] Opt-in diagnostic-mode setting, off by default.
* [x] A setting for whether Meat Grinder plays music, off by default.
* [x] Custom music for the last stand, when only one player of the team is still alive.
* [x] Custom music for mission events, such as holdouts, escapes, and scripted boss fights.
* [x] A setting for whether angered daemonhosts play boss music, off by default.
* [x] A setting for whether captains, including the Karnak Twins, play boss music, off by default.
* [x] A button in the mod settings that rescans the audio folders without a restart.
* [x] Custom music for hordes, with the game's own horde music when the folder is empty, and its own hold setting.
* [x] Songs continuing from where they left off: explore and combat whenever they come back, and a horde, boss fight, or event after an interruption while it is still going.
* [x] Playback inside the game through Windows' own decoder and audio engine, with no other mods or programs needed.
* [x] Custom music for Mortis Trials, with separate folders for its waves and the breaks between them.
* [ ] A setting per context to choose custom music, the game's own music, or silence, without moving files around.
* [ ] More Meat Grinder options, such as choosing which contexts play there.
* [ ] An optional periodic rescan of the audio folders, on top of the rescan button.
* [ ] Lowering custom music while the pause menu is open, as the game does with its own music.
* [ ] Optional loudness normalization, so quiet and loud files play at a similar level without changing the files. It would have a setting to turn it on and a target level.
* [ ] "Let the current track finish" toggle, with a per-category override. For example, a boss track could play out even after the boss dies.
* [ ] Different music per mission type or game mode, such as Operations, Havoc, and Expeditions.
* [ ] Separate folders per kind of mission event, so for example a scripted boss fight and a holdout can have different music.
* [ ] Separate boss folders per kind of monstrosity, so each one can have its own boss music.
* [ ] Custom music for loading screens.
* [ ] A short log of the important events written by default, with the previous session's log kept beside it as `diagnostic-prev.log`, so either can be attached to a bug report. Diagnostic Logging would add the detailed lines on top, as it does now.

## Development

```powershell
tools\build.ps1           # Build dist\MusicReplacer.zip, for Vortex "Install from File".
tools\build.ps1 -Deploy   # Also copy the source straight into the installed mod folder.
tools\test.ps1            # Run the specs under tests\spec with LuaJIT.
luajit tools\player_demo.lua <file A> <file B> [--silent]   # Play two files through the mod's player outside the game.
luacheck .                # Static analysis with the settings in .luacheckrc.
```

`-Deploy` is the fast iteration path. It copies the staged files over the installed ones, including `MusicReplacer.mod` and the stamped `info.json`, leaving `audio\` alone, so a change can be tested by restarting the game rather than reinstalling through Vortex. It never deletes a file, so remove a module that was deleted from the source by hand. The zip stays the real artifact, and a Vortex purge discards anything deployed this way.

The build stamps the packaged `info.json` with the commit and build time, and the mod logs it at startup. A `-dirty` suffix means the packaged files had uncommitted changes.

The specs need [LuaJIT 2.1](https://luajit.org/) on `PATH`, the same Lua runtime the game uses. `tools\test.ps1` exits non-zero when any spec fails. The Windows calls themselves need real audio hardware, so they are checked with `tools\player_demo.lua` rather than in the specs.

Static analysis needs [luacheck](https://github.com/lunarmodules/luacheck) on `PATH`. The standalone `luacheck.exe` from its releases page is enough.

How native music reaches the player, how the mod silences it, and how to trace a sound to its Wwise event are covered in [docs/wwise-events.md](docs/wwise-events.md).

Logs to check when something misbehaves:

* `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log`, written only while Diagnostic Logging is on in the mod options.
* `%APPDATA%\Fatshark\Darktide\console_logs\`

## Project structure

```
darktide-music-replacer/
├── .gitignore
├── .luacheckrc                          # luacheck settings: LuaJIT, and the globals the game and DMF provide.
├── MusicReplacer.mod
├── info.json                            # Version and author metadata, read by DMF at mod init.
├── scripts/mods/MusicReplacer/
│   ├── MusicReplacer.lua                # Wires everything together and debounces context changes.
│   ├── context.lua                      # Tracks Wwise music state and boss encounters, resolves one context string.
│   ├── suppression.lua                  # Silences the game's own music while a custom track plays.
│   ├── library.lua                      # Keeps each context's file list and picks a file for a context.
│   ├── audio_folders.lua                # Lists, checks, and creates the audio folders through Windows, and measures durations.
│   ├── resume_points.lua                # Remembers where interrupted songs stopped, until the next loading screen.
│   ├── audio_client.lua                 # Plays the music: crossfades, end fades, sliders, parked songs, and recovery.
│   ├── player.lua                       # Streams one song through media_decoder.lua and xaudio.lua from a fixed buffer pool.
│   ├── media_decoder.lua                # Decodes audio files to PCM with Windows Media Foundation.
│   ├── xaudio.lua                       # Plays PCM through XAudio2 voices with live volume control.
│   ├── native_ffi.lua                   # Shared ffi plumbing for Windows APIs: GUIDs, COM calls and setup, UTF-16 strings, heap memory, files.
│   ├── diagnostic_log.lua               # Writes diagnostic.log, opt-in, with a size cap and an optional reset on launch.
│   ├── event_probe.lua                  # Logging-only probe that records Wwise event names.
│   ├── mission_probe.lua                # Logging-only probe that records the current mission's name and type.
│   ├── MusicReplacer_data.lua           # DMF mod-options widgets.
│   └── MusicReplacer_localization.lua   # Mod-options strings.
├── docs/
│   └── wwise-events.md                  # Native music sources, suppression, and the event and mission probes.
├── tests/
│   ├── run.lua                          # Minimal spec runner, needs only LuaJIT.
│   ├── helpers/
│   │   ├── context_harness.lua          # Replays the game's real state sequences through context.lua.
│   │   └── fake_engine.lua              # Fakes the game and DMF globals so the mod's modules run outside the game.
│   └── spec/                            # Specs, one *_spec.lua file per subject.
└── tools/
    ├── build.ps1                        # Builds the zip and optionally deploys straight into the installed mod folder.
    ├── player_demo.lua                  # Plays two files through player.lua outside the game.
    └── test.ps1                         # Runs the specs and exits non-zero on failure.
```

`audio/` is not part of this repository. It is created inside the installed mod folder. See Setup above.
