# darktide-music-replacer

This is Music Replacer, a mod for Warhammer 40,000: Darktide that replaces the game's music with your own audio files, chosen by what is actually happening in the hub or a mission. It wraps the [Audio](https://www.nexusmods.com/warhammer40kdarktide/mods/196) and [DarktideLocalServer](https://www.nexusmods.com/warhammer40kdarktide/mods/211) plugins to play files through ffplay. Any context left without files keeps Darktide's own music, by construction rather than as a special case.

## Features

* Replaces hub, mission-explore, combat, boss, victory, and defeat music with your own audio files.
* Several files in a folder are picked at random, never repeating the file that just played.
* Exactly one file in a folder loops natively and indefinitely, instead of restarting on every repeat.
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
    mission_boss\
    mission_victory\
    mission_defeat\
```

All six folders already exist after install. Put audio files (`.mp3`, `.wav`, and so on) directly inside whichever ones you want music for. One level deep only, since this layout is fixed by the Audio Plugin, not by this mod.

| Folder | When it plays |
|---|---|
| `hub` | In the Mourningstar. |
| `mission_explore` | In a mission, no meaningful threat. |
| `mission_combat` | In a mission, fighting, normal combat through to a heavy horde. |
| `mission_boss` | A monstrosity or an assassination target is active. |
| `mission_victory` | From the moment a mission is won until the loading screen or a cutscene. |
| `mission_defeat` | From the moment a mission is lost until the loading screen or a cutscene. |

No custom music plays during cutscenes. The game's own music takes over there.

Your audio survives reinstalling or updating the mod through Vortex. Vortex only removes files it deployed itself, and `audio\` is never part of the mod archive. It does not survive the mod folder being renamed, so move `audio\` across by hand if that ever happens.

## Settings

These are in the in-game mod options under Music Replacer.

| Setting | Default | What it does |
|---|---|---|
| Combat music hold | 8 seconds | How long combat music keeps playing after a fight quiets down before it switches back to explore music. Set it to 0 to switch back immediately. |
| Music in Meat Grinder | Off | Off keeps custom music out of the Meat Grinder training area and also silences the game's own combat music there. On plays your explore and combat music there. |
| Diagnostic logging | Off | Writes `diagnostic.log` for troubleshooting. |
| Reset log on launch | On | Clears `diagnostic.log` at the start of each session. Only matters while diagnostic logging is on. |

## Limitations

* Changing the master or music volume slider restarts the playing track. Music plays through a separate ffplay process, started by the Audio Plugin and DarktideLocalServer. That process takes its volume when it starts and cannot be adjusted from outside once it is running. On a slider change, Music Replacer stops the process and starts a new one at the same position with the new volume. The request goes through the local server, so expect a slight delay and a brief pause or cut in the music. While you drag a slider this happens at most once per second, and the final volume is applied once you stop.
* Each audio folder is scanned once, when the game launches. Restart the game after adding or removing files. A file you remove while the game runs is skipped, and a file you add is not picked up until the next launch.
* A hard crash can leave a track playing until it ends on its own. Quitting normally stops it. A crash runs no mod code at all, so nothing can intervene. If it happens, end `ffplay_dt.exe` in Task Manager.
* Music Replacer only affects your own game. Squadmates hear the game's own music regardless.

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
* [ ] A setting per context to choose custom music, the game's own music, or silence, without moving files around.
* [ ] More Meat Grinder options, such as choosing which contexts play there.
* [ ] Detecting music files added or removed during a session, with a rescan button in the mod settings and an optional periodic rescan.
* [ ] Runtime volume control through the Windows audio session, replacing the relaunch on a slider change.
* [ ] True crossfades between tracks, once runtime volume control works.
* [ ] Resuming the combat track when combat returns right after it faded out, instead of restarting it from the beginning.
* [ ] Optional loudness normalization, so quiet and loud files play at a similar level without changing the files. It would have a setting to turn it on and a target level.
* [ ] "Let the current track finish" toggle, with a per-category override. For example, a boss track could play out even after the boss dies.
* [ ] A `mission_horde` folder for the heaviest hordes, separate from `mission_combat`. With no files in it, hordes keep playing combat music exactly as they do now.
* [ ] Settings for horde music, such as how long it holds before falling back to combat music.
* [ ] Different music per mission type or game mode, such as Operations, Havoc, Mortis Trials, and Expeditions.
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
│   ├── audio_client.lua                 # Playback: fades, crossfade overlap, looping, and process cleanup.
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
    └── test.ps1                         # Runs the specs and exits non-zero on failure.
```

`audio/` is not part of this repository. It is created inside the installed mod folder. See Setup above.
