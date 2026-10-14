# darktide-music-replacer

This is Music Replacer, a mod for Warhammer 40,000: Darktide that replaces the game's music with your own audio files, chosen by what is actually happening in the hub or a mission. It wraps the [Audio](https://www.nexusmods.com/warhammer40kdarktide/mods/196) and [DarktideLocalServer](https://www.nexusmods.com/warhammer40kdarktide/mods/211) plugins to play files through ffplay. Any context left without files keeps Darktide's own music, by construction rather than as a special case.

## Features

* Replaces hub, mission-explore, combat, horde, boss, event, last stand, victory, and defeat music with your own audio files.
* Several files in a folder are picked at random, never repeating the file that just played.
* Exactly one file in a folder loops natively and indefinitely, instead of restarting on every repeat.
* Explore and combat songs continue from where they stopped when the mission switches back to them, instead of restarting. Horde, boss, and event songs continue too after higher-priority music interrupts them, such as a boss during a horde or a last stand during an event, as long as that horde, fight, or event is still going.
* Fades in on a real context change, fades out at a track's own end when its folder holds several files, and overlaps briefly on a switch instead of cutting abruptly.
* Follows the in-game master and music volume sliders.
* Keeps the Meat Grinder training area silent unless you turn music on there, which doubles as a quick way to test your files.
* Native music is silenced only once a replacement track is confirmed playing, so a context with no files behaves exactly like an unmodified game.

## Prerequisites

* You must install [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19) and [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8). This mod and the two below all run on this modding base.
* You must install [DarktideLocalServer](https://www.nexusmods.com/warhammer40kdarktide/mods/211).
* You must install [Audio](https://www.nexusmods.com/warhammer40kdarktide/mods/196), which depends on DarktideLocalServer above.

List all four in this order in `mod_load_order.txt`, followed by Music Replacer itself.

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
```

All nine folders already exist after install. Put audio files (`.mp3`, `.wav`, and so on) directly inside whichever ones you want music for. One level deep only, since this layout is fixed by the Audio Plugin, not by this mod.

| Folder | When it plays |
|---|---|
| `hub` | In the Mourningstar. |
| `mission_explore` | In a mission, no meaningful threat. |
| `mission_combat` | In a mission, while enemies are attacking you outside a horde or a boss fight. The game itself plays no music here. |
| `mission_horde` | In a mission, during a horde. With no files here, the game's own horde music plays, as it does without the mod. |
| `mission_boss` | In a mission, while a monstrosity is near you, such as a Chaos Spawn, a Beast of Nurgle, a Plague Ogryn, or an Ogryn Houndmaster. This is exactly when the game plays its own boss music. It does not play during an event, a last stand, or the mission's end, which take priority. It also does not play for an angered Daemonhost unless you turn on its setting. It does not play for captains unless you turn on their setting, or while a scripted boss such as Spillway's psyker is alive, since the game does not report those as bosses. |
| `mission_event` | In a mission, while an event plays its own music, such as a holdout, a hacking event, an escape, or a scripted boss fight like those in Spillway. It replaces boss, horde, combat, and explore music, as the game's own event music does. It does not play during a last stand or the mission's end, and it stops when the game ends the event's music. |
| `mission_last_stand` | In a mission, while only one player of the team is still alive. It replaces boss, combat, and explore music, as the game's own last stand music does. |
| `mission_victory` | From the moment a mission is won until the loading screen or a cutscene. |
| `mission_defeat` | From the moment a mission is lost until the loading screen or a cutscene. |

No custom music plays during cutscenes. The game's own music takes over there.

Your audio survives reinstalling or updating the mod through Vortex. Vortex only removes files it deployed itself, and `audio\` is never part of the mod archive. It does not survive the mod folder being renamed, so move `audio\` across by hand if that ever happens.

## Settings

These are in the in-game mod options under Music Replacer.

| Setting | Default | What it does |
|---|---|---|
| Combat music hold | 8 seconds | How long combat music keeps playing after a fight quiets down, so a short lull does not switch to explore music. Set it to 0 to switch immediately. |
| Horde music hold | 3 seconds | How long horde music keeps playing after the game stops reporting a horde. The game drops its horde signal for a second or two whenever few enemies are on you, so a short hold keeps the track from restarting. Set it to 0 to follow the game exactly. |
| Resume songs | On | When explore or combat music comes back, its song continues from where it stopped. A horde, boss, or event song also continues after higher-priority music interrupts it, such as a boss during a horde or a last stand during an event, as long as that horde, fight, or event did not end in between. A new horde, boss fight, or event gets a new pick. A new song is also picked once one ends on its own. Every mission and hub visit starts with fresh songs. |
| Music in Meat Grinder | Off | Off keeps custom music out of the Meat Grinder training area and also silences the game's own combat music there. On plays your explore and combat music there. |
| Boss music for captains | Off | On plays your boss music for a captain, including the Karnak Twins, from the moment it engages until it dies. Off leaves captains to the game's own music. Event music still plays during an event. |
| Boss music for daemonhosts | Off | Off follows the game, which plays no music for an angered daemonhost. On plays your boss music from the moment a daemonhost is angered until it dies. |
| Rescan audio folders | (button) | Picks up audio files added or removed since the game started, without a restart. A track that is playing keeps playing, and a context that had no files starts its new track right away. |
| Instant volume changes | On | Lowering the master or music volume slider changes a playing track's volume at once, without restarting it. Turn it off if music volume misbehaves, and every slider change restarts the track instead. |
| Diagnostic logging | Off | Writes `diagnostic.log` for troubleshooting. |
| Reset log on launch | On | Clears `diagnostic.log` at the start of each session. Only matters while diagnostic logging is on. |

## Limitations

* Raising the master or music volume slider above where the playing track started restarts that track. Music plays through a separate ffplay process, started by the Audio Plugin and DarktideLocalServer, which takes its volume when it starts. Music Replacer lowers a running track through that process's Windows audio session, the same per-app volume the Windows Volume Mixer shows, so lowering a slider is instant. A session cannot go above the volume the track started at, so raising past it stops the process and starts a new one at the same position. The request goes through the local server, so expect a slight delay and a brief pause or cut in the music. While you drag a slider this happens at most once per second, and the next track starts at the new volume anyway.
* The audio session calls go to Windows' Core Audio API directly from Lua, through the ffi the mod loader provides, so the mod ships no DLL or executable. Music Replacer only changes the sessions of the ffplay processes it started itself, and puts back the volume Windows remembers for ffplay once each one ends, so other mods' Audio Plugin sounds keep their own volume.
* Each audio folder is scanned when the game launches. After adding or removing files while the game runs, press Rescan Audio Folders in the mod settings, or restart the game. Until then, a file you removed is skipped and a file you added is not picked up.
* A hard crash can leave a track playing until it ends on its own. Quitting normally stops it. A crash runs no mod code at all, so nothing can intervene. If it happens, end `ffplay_dt.exe` in Task Manager.
* Music Replacer only affects your own game. Squadmates hear the game's own music regardless.
* Loading screens, the mission briefing, the mission intro, and cutscenes play the game's own music. Custom music starts once you are in the hub or the mission itself.

## Roadmap

* [x] Context-aware hub, explore, combat, boss, victory, and defeat switching.
* [x] Fallback to native music for any context without files.
* [x] Fade-in, natural-end fade-out, crossfade overlap.
* [x] Native looping for a single-file folder.
* [x] Native music suppressed while a custom track plays, only once a replacement is confirmed available.
* [x] All audio folders provisioned automatically, ready to use right after install.
* [x] Custom music following the in-game volume sliders.
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
* [x] Runtime volume control through the Windows audio session, so lowering a volume slider no longer restarts the track.
* [ ] A setting per context to choose custom music, the game's own music, or silence, without moving files around.
* [ ] More Meat Grinder options, such as choosing which contexts play there.
* [ ] An optional periodic rescan of the audio folders, on top of the rescan button.
* [ ] True crossfades between tracks, once runtime volume control works.
* [ ] Lowering custom music while the pause menu is open, as the game does with its own music, once runtime volume control works.
* [ ] Optional loudness normalization, so quiet and loud files play at a similar level without changing the files. It would have a setting to turn it on and a target level.
* [ ] "Let the current track finish" toggle, with a per-category override. For example, a boss track could play out even after the boss dies.
* [ ] Different music per mission type or game mode, such as Operations, Havoc, Mortis Trials, and Expeditions.
* [ ] Separate folders per kind of mission event, so for example a scripted boss fight and a holdout can have different music.
* [ ] Separate boss folders per kind of monstrosity, so each one can have its own boss music.
* [ ] Custom music for loading screens.

## Development

```powershell
tools\build.ps1           # Build dist\MusicReplacer.zip, for Vortex "Install from File".
tools\build.ps1 -Deploy   # Also copy the source straight into the installed mod folder.
tools\test.ps1            # Run the specs under tests\spec with LuaJIT.
luacheck .                # Static analysis with the settings in .luacheckrc.
```

`-Deploy` is the fast iteration path. It overwrites the `.lua` files in place, leaving `audio\` alone, so a change can be tested by restarting the game rather than reinstalling through Vortex. The zip stays the real artifact, and a Vortex purge discards anything deployed this way.

The build stamps the packaged `info.json` with the commit and build time, and the mod logs it at startup.
A `-dirty` suffix means the packaged files had uncommitted changes.

The specs need [LuaJIT 2.1](https://luajit.org/) on `PATH`, the same Lua runtime the game uses.
`tools\test.ps1` exits non-zero when any spec fails.
Static analysis needs [luacheck](https://github.com/lunarmodules/luacheck) on `PATH`.
The standalone `luacheck.exe` from its releases page is enough.

How native music reaches the player, how the mod silences it, and how to trace a sound to its Wwise event are covered in [docs/wwise-events.md](docs/wwise-events.md).

Logs to check when something misbehaves:

* `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log`, written only while Diagnostic Logging is on in the mod options.
* `%APPDATA%\Fatshark\Darktide\console_logs\`

## Project structure

```
darktide-music-replacer/
├── MusicReplacer.mod
├── info.json                            # Version and author metadata, read by DMF at mod init.
├── scripts/mods/MusicReplacer/
│   ├── MusicReplacer.lua                # Wires everything together and debounces context changes.
│   ├── context.lua                      # Tracks Wwise music state and boss encounters, resolves one context string.
│   ├── suppression.lua                  # Silences the game's own music while a custom track plays.
│   ├── library.lua                      # Picks a file for a context from its audio/ folder.
│   ├── resume_points.lua                # Remembers where interrupted songs stopped, until the next loading screen.
│   ├── audio_client.lua                 # Playback: fades, crossfade overlap, looping, and process cleanup.
│   ├── diagnostic_log.lua               # Writes diagnostic.log, opt-in, with a size cap and an optional reset on launch.
│   ├── event_probe.lua                  # Logging-only probe that records Wwise event names.
│   ├── mission_probe.lua                # Logging-only probe that records the current mission's name and type.
│   ├── session_volume.lua               # Reads and sets one process's Windows audio session volume through Core Audio.
│   ├── volume_sessions.lua              # Holds each ffplay's audio session to follow the sliders, and resets Windows' saved volume.
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
    └── test.ps1                         # Runs the specs and exits non-zero on failure.
```

`audio/` is not part of this repository. It is created inside the installed mod folder. See Setup above.
