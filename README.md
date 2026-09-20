# Music Replacer

## Context-Aware Music Replacement for Warhammer 40,000: Darktide

- Replace hub, mission-explore, combat, boss, and victory/defeat music with your own audio files, chosen by what's actually happening.
- Provide files for only the situations you care about. Anything you leave empty keeps Darktide's own music.
- Several files in a folder are picked at random, never repeating the one that just played.
- Exactly one file in a folder loops natively and indefinitely instead of restarting on every repeat.
- Fades in on a real context change, fades out at a track's own end when its folder holds several files, and overlaps briefly on a switch instead of cutting abruptly.
- Follows the in-game master and music volume sliders.

## Quick Start

> Requires, listed in `mod_load_order.txt` in this order:
> [Darktide Mod Loader](https://www.nexusmods.com/warhammer40kdarktide/mods/19) and [Darktide Mod Framework](https://www.nexusmods.com/warhammer40kdarktide/mods/8) (the modding base both of these and Music Replacer itself run on), then [DarktideLocalServer](https://www.nexusmods.com/warhammer40kdarktide/mods/211), then [Audio](https://www.nexusmods.com/warhammer40kdarktide/mods/196), then Music Replacer.

Drop audio files into the **installed** mod's folder, not this repository:

```
...\Warhammer 40,000 DARKTIDE\mods\MusicReplacer\audio\
    hub\
    mission_explore\
    mission_combat\
    mission_boss\
    mission_victory\
    mission_defeat\
```

All six folders already exist after install. Put audio files (`.mp3`, `.wav`, ...) directly inside whichever ones you want music for. One level deep only. This layout is fixed by the Audio Plugin, not by this mod.

| Folder | When it plays |
|---|---|
| `hub` | In the Mourningstar. |
| `mission_explore` | In a mission, no meaningful threat. |
| `mission_combat` | In a mission, fighting, normal combat through to a heavy horde. |
| `mission_boss` | A monstrosity or an assassination target is active. |
| `mission_victory` | From the moment a mission is won until the loading screen. |
| `mission_defeat` | From the moment a mission is lost until the loading screen. |

Your audio survives reinstalling or updating the mod via Vortex: Vortex only removes files it deployed itself, and `audio\` is never part of the mod archive. It does **not** survive the mod folder being renamed. Move `audio\` across by hand if that ever happens.

## Limitations

- Changing the master or music volume slider restarts the playing track. Music plays through a separate ffplay process, started by the Audio Plugin and DarktideLocalServer. That process takes its volume when it starts and cannot be adjusted from outside once it is running. So on a slider change, Music Replacer stops the process and starts a new one at the same position with the new volume. The request goes through the local server, so expect a slight delay and a brief pause or cut in the music. While you drag a slider this happens at most once per second, and the final volume is applied once you stop.
- A hard crash can leave a track playing until it ends on its own. Quitting normally stops it. A crash runs no mod code at all, so nothing can intervene. If it happens, end `ffplay_dt.exe` in Task Manager.
- Music Replacer only affects your own game. Squadmates hear the game's own music regardless.

## Roadmap

- [x] Context-aware hub/explore/combat/boss/victory/defeat switching.
- [x] Fallback to native music for any context without files.
- [x] Fade-in, natural-end fade-out, crossfade overlap.
- [x] Native looping for a single-file folder.
- [x] Native music suppressed while a custom track plays, only once a replacement is confirmed available.
- [x] All audio folders provisioned automatically, ready to use right after install.
- [x] Custom music following the in-game volume sliders.
- [x] Adjustable combat music hold, so a lull in a fight does not drop back to explore music.
- [x] Opt-in diagnostic-mode setting, off by default.
- [ ] A setting for whether Meat Grinder plays music. It currently plays mission music.
- [ ] "Let the current track finish" toggle, with a per-category override. For example, a boss track could play out even after the boss dies.
- [ ] A `mission_horde` folder for the heaviest hordes, separate from `mission_combat`. With no files in it, hordes keep playing combat music exactly as they do now.
- [ ] Settings for horde music, such as how long it holds before falling back to combat music.
- [ ] Custom music for loading screens.

## Development

```powershell
tools\build.ps1           # Build dist\MusicReplacer.zip, for Vortex "Install from File".
tools\build.ps1 -Deploy   # Also copy the source straight into the installed mod folder.
```

`-Deploy` is the fast iteration path: it overwrites the `.lua` files in place, leaving `audio\` alone, so a change can be tested by restarting the game rather than reinstalling through Vortex. The zip stays the real artifact. A Vortex purge discards anything deployed this way.

Source layout:

| Path | Role |
|---|---|
| `scripts/mods/MusicReplacer/context.lua` | Tracks Wwise music state and boss encounters, resolves one context string. |
| `scripts/mods/MusicReplacer/suppression.lua` | Silences the game's own music while a custom track plays, by forcing Wwise states and dropping music events. |
| `scripts/mods/MusicReplacer/library.lua` | Picks a file for a context from its `audio/` folder. |
| `scripts/mods/MusicReplacer/audio_client.lua` | Playback: fades, crossfade overlap, looping, and process cleanup. |
| `scripts/mods/MusicReplacer/MusicReplacer.lua` | Wires those together, debounce and logging. |
| `scripts/mods/MusicReplacer/event_probe.lua` | Logging-only hook that records Wwise event names, for tracing where a sound comes from. |

How native music reaches the player, how the mod silences it, and how to trace a sound to its Wwise event are covered in [docs/wwise-events.md](docs/wwise-events.md).

Logs to check when something misbehaves:

- `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log`, written only while Diagnostic Logging is on in the mod options.
- `%APPDATA%\Fatshark\Darktide\console_logs\`
