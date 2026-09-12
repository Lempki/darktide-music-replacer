# Music Replacer

## Context-Aware Music Replacement for Warhammer 40,000: Darktide

- Replace hub, mission-explore, combat and boss music with your own audio files, chosen by what's actually happening.
- Provide files for only the situations you care about. Anything you leave empty keeps Darktide's own music.
- Several files in a folder are picked at random, never repeating the one that just played.
- Exactly one file in a folder loops natively and indefinitely instead of restarting on every repeat.
- Fades in on a real context change, fades out at a track's own end, and overlaps briefly on a switch instead of cutting abruptly.

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
```

All four folders already exist after install. Put audio files (`.mp3`, `.wav`, ...) directly inside whichever ones you want music for. One level deep only. This layout is fixed by the Audio Plugin, not by this mod.

| Folder | When It Plays |
|---|---|
| `hub` | In the Mourningstar. |
| `mission_explore` | In a mission, no meaningful threat. |
| `mission_combat` | In a mission, fighting, normal combat through to a heavy horde. |
| `mission_boss` | A monstrosity or an assassination target is active. |

Your audio survives reinstalling or updating the mod via Vortex: Vortex only removes files it deployed itself, and `audio\` is never part of the mod archive. It does **not** survive the mod folder being renamed. Move `audio\` across by hand if that ever happens.

## Limitations

- Custom music does not follow the in-game volume sliders while a track is already playing. The volume is fixed when a track starts, and the player offers no way to change it afterwards. A slider change takes effect on the next track.
- A hard crash can leave a track playing until it ends on its own. Quitting normally stops it. A crash runs no mod code at all, so nothing can intervene. If it happens, end `ffplay_dt.exe` in Task Manager.
- Music Replacer only affects your own game. Squadmates hear the game's own music regardless.

## Roadmap

- [x] Context-aware hub/explore/combat/boss switching.
- [x] Fallback to native music for any context without files.
- [x] Fade-in, natural-end fade-out, crossfade overlap.
- [x] Native looping for a single-file folder.
- [x] Boss music suppression, only once a replacement is confirmed available.
- [x] All four audio folders provisioned automatically, ready to use right after install.
- [x] Opt-in diagnostic-mode setting, off by default.
- [ ] In-game settings UI for the rest below.
- [ ] Custom music responding to the in-game volume sliders.
- [ ] Meat Grinder silent by default, opt-in to override.
- [ ] "Let the current track finish" toggle, with a per-category override.

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
| `scripts/mods/MusicReplacer/library.lua` | Picks a file for a context from its `audio/` folder. |
| `scripts/mods/MusicReplacer/audio_client.lua` | Playback: fades, crossfade overlap, looping, and process cleanup. |
| `scripts/mods/MusicReplacer/MusicReplacer.lua` | Wires those together, debounce and logging. |

Logs to check when something misbehaves:

- `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log`
- `%APPDATA%\Fatshark\Darktide\console_logs\`
