# Development

How to build, test, and work on Music Replacer. How the game's music works is covered in [wwise-events.md](wwise-events.md), and how the game reports its missions and modes in [game-internals.md](game-internals.md).

## Building and testing

```powershell
tools\build.ps1           # Build dist\MusicReplacer.zip, for Vortex "Install from File".
tools\build.ps1 -Deploy   # Also copy the source straight into the installed mod folder.
tools\test.ps1            # Run the specs under tests\spec with LuaJIT.
luajit tools\player_demo.lua <file A> <file B> [--silent]   # Play two files through the mod's player outside the game.
luacheck .                # Static analysis with the settings in .luacheckrc.
uvx pre-commit run --all-files   # The shared dev-standards hooks: prose rules, synced config files, and file hygiene.
```

The specs need [LuaJIT 2.1](https://luajit.org/) on `PATH`, the same Lua runtime the game uses. `tools\test.ps1` exits non-zero when any spec fails. The Windows calls themselves need real audio hardware, so they are checked with `tools\player_demo.lua` rather than in the specs.

Static analysis needs [luacheck](https://github.com/lunarmodules/luacheck) on `PATH`. The standalone `luacheck.exe` from its releases page is enough.

## Deploying

`-Deploy` is the fast iteration path. It copies the staged files over the installed ones, including `MusicReplacer.mod` and the stamped `info.json`, and only adds missing folders to `audio\`, never touching their files. So a change can be tested by restarting the game rather than reinstalling through Vortex. It never deletes a file, so remove a module that was deleted from the source by hand. The ZIP stays the real artifact, and a Vortex purge discards anything deployed this way.

The build stamps the packaged `info.json` with the commit and build time, and the mod logs it at startup. A `-dirty` suffix means the packaged files had uncommitted changes.

`audio\` is not part of this repository. The ZIP carries its empty folders, and the mod creates any that are missing.

## Logs

* `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log`, with the previous launch's log beside it as `diagnostic-prev.log`. Detailed Logging adds the game's music state changes, the silencing, and the game's sound events.
* The game's console logs, in `%APPDATA%\Fatshark\Darktide\console_logs\`.

## Conventions and CI

The repository follows the shared conventions in [dev-standards](https://github.com/Lempki/dev-standards). Its hooks keep the managed blocks in `.editorconfig`, `.gitattributes`, and `.gitignore` in sync, and check comments and Markdown against the prose rules. They recognize this as a Lua repository by its `.luacheckrc`, so it needs no settings file. Install the hooks once per clone with `uvx pre-commit install`. CI runs dev-standards' Lua workflow on every push to `main` and every pull request: the hooks, luacheck, and the specs under LuaJIT.

## Contributing

Pull requests and [issues](https://github.com/Lempki/darktide-music-replacer/issues) are welcome. Before you open a pull request, run the checks under [Building and testing](#building-and-testing).

### Translations

All player-facing text is in `scripts/mods/MusicReplacer/MusicReplacer_localization.lua`. Each string is a table with one entry per language, keyed by the game's language ID, such as `en` for English and `de` for German. DMF shows a string in the game's language, and falls back to `en` when that language has none.

* To add a language, add an entry next to `en` in every string, for example `de = "..."`.
* The situation dropdowns build their English tooltips with `source_tooltip()`. A translation writes each tooltip as its own full text instead, since the sentence order differs between languages.
* `highlight()` colors the key words in a tooltip, such as the names of the choices, so keep it around the translated words.
* DMF formats every string, so `%%` shows as a single percent sign.

## Why the mod uses Windows' own audio

Early versions of the mod played the music through ffplay, FFmpeg's player program. The [Audio Plugin](https://www.nexusmods.com/warhammer40kdarktide/mods/196) and [Darktide Local Server](https://www.nexusmods.com/warhammer40kdarktide/mods/211) mods started it as a process of its own. That route had limits the mod could not work around:

* Each song ran in its own ffplay process, which took its volume when it started. Lowering a volume slider could follow at once through that process's Windows audio session. Raising it past the starting volume meant restarting the song, with a brief cut.
* Without volume control at run time, there could be no true crossfades and no lowering of the music in menus.
* Every request went through the local server, which added a slight delay.
* The process outlived the game, so a hard crash could leave a song playing until it ended.
* The Audio Plugin fixed the folder layout at one level deep, so a folder could not hold override folders.
* Players needed two more mods.

Playing through Media Foundation and XAudio2 inside the game's own process removes every one of these limits. The mod needs no other mod beyond the mod loader and DMF, and it ships no program or DLL, its own or anyone else's. Windows keeps the decoders up to date itself. The cost is Ogg and Opus, which Windows decodes only for Store apps, so the mod does not list them.

## How playback works

Music Replacer decodes the files with Media Foundation, Windows' own media framework, and plays them with XAudio2 2.9, the audio engine Windows provides for games. It calls both from Lua through LuaJIT's ffi, which the mod loader exposes as `Mods.lua.ffi`, so the mod ships no DLL or executable. Media Foundation starts in its lite mode, which leaves its network support uninitialized, since the mod only opens local files.

### Decoding and streaming

* `media_decoder.lua` asks Media Foundation for 16-bit PCM and reads it synchronously on the game's thread, a chunk at a time, so no Windows thread ever calls back into Lua.
* `player.lua` gives each stream a fixed pool of 16 slots of 0.25 seconds each, on the Windows heap and outside the game's Lua memory. That keeps 4 seconds queued, so the music plays on through a stalled frame or a busy loading screen. The pool is allocated once per stream, about 0.7 MB for 44.1 kHz stereo, and grows with the rate and the channels.
* A stream queues 2 slots before it starts, and each update refills at most 2, so no single frame pays for a whole refill.
* A looping stream reads on from the file's start in the same buffer, so the loop adds no gap. Silence in the file itself, such as an MP3's encoder padding, still plays.
* XAudio2 voice state is polled every update rather than reported through callbacks, since LuaJIT cannot safely take calls from XAudio2's thread.
* Each decoded buffer's peaks are measured in 50 ms blocks as it is queued, for the debug overlay's level meter. The meter reads the block at the voice's play position, times the stream's volume, so it shows the music as you hear it.

### Fades and parked songs

* A context change is a crossfade on an equal-power curve, as long as the Fade Length setting, 2 seconds by default. A song that does not loop fades out over its last stretch of that length. One shorter than two fades fades in over its first half and out over its second. A stop fades out over half a second.
* A song that fades out is paused and parked rather than freed. If the mod resumes it, the same stream fades back in from exactly where it stopped, with nothing reopened or sought.
* Each parked song keeps its buffer pool and its file open. It is freed after 60 seconds, and beyond 4 parked songs the oldest is freed first.
* The master and music sliders, Custom Music Volume, and the menu fade set every stream's gain directly, so no volume change restarts a song.

### Device recovery

* The mastering voice is created with no device ID, so XAudio2 uses Windows' virtual audio client and follows a change of the default audio device by itself.
* A voice that has audio queued but plays nothing for 2 seconds counts as a lost device, since XAudio2 does not report that stall itself.
* When the device is lost in a way XAudio2 cannot follow, the mod rebuilds the engine and resumes the song where it was.
* After 3 rebuilds in a row without 30 seconds of good playback in between, the next failure gives up, and the game's music plays. Rescan Audio Folders, or turning the mod off and on, lets it try again.
* While Windows has no audio output at all, creating the engine fails. The game's music plays, and the mod tries again every 5 seconds without counting it as a failure, so a headset that stays unplugged never makes it give up.

### Evening out loudness

* `loudness_meter.lua` measures each song's integrated loudness in LUFS following ITU-R BS.1770 and EBU R128: 400 ms blocks every 100 ms, an absolute gate at -70 LUFS, and a relative gate 10 LU below.
* Every song plays at the level that brings it to -14 LUFS, the level most streaming services play music at.
* A quiet song is only raised until its loudest sample reaches full scale, so it never clips, and by at most 12 dB, since raising a very quiet recording further mostly raises its hiss.
* `loudness.lua` decodes each whole song for this, in 50 ms chunks, for at most about a millisecond per update, starting with the folder of the context that plays. It only measures while Even Out Loudness is on.
* The log says how long measuring took once every song is measured.
* The results go to `loudness.txt` beside `diagnostic.log`, keyed by each file's size and write time, so a song is measured once and again only after its file changes. It is written every 10 songs, once measuring is done, and on unload. Deleting it measures every song again.
* A song keeps the level it started with, so one measured while it plays changes level at its next start.

### File checks

* `library.lua` measures every file's duration in the background, one file per update. A file Media Foundation cannot open is left out of the picks from then on.
* A track that ends within 3 seconds of starting, and before half its length, did not really play. After 3 in a row from one folder, that folder stops retrying until the folders are listed again. An override folder then gives way to the next folder, and a context's own folder to the game's music.

## Project structure

```
darktide-music-replacer/
├── .editorconfig                        # Its managed block is synced from dev-standards.
├── .gitattributes                       # Its managed block is synced from dev-standards.
├── .github/
│   ├── dependabot.yml                   # Weekly updates of the workflow and hook versions.
│   └── workflows/ci.yml                 # Calls dev-standards' Lua workflow.
├── .gitignore                           # Its managed block is synced from dev-standards.
├── .luacheckrc                          # luacheck settings: LuaJIT, and the globals the game and DMF provide.
├── .pre-commit-config.yaml              # The dev-standards hooks and file hygiene checks.
├── LICENSE                              # GPLv3. It stays in the repository and is not packaged into the ZIP.
├── MusicReplacer.mod
├── README.md                            # The player guide, with links to these docs.
├── info.json                            # Version and author metadata, read by DMF at mod init.
├── scripts/mods/MusicReplacer/
│   ├── MusicReplacer.lua                # Wires everything together and debounces context changes.
│   ├── contexts.lua                     # The catalog of contexts: their settings group, silencing, priorities, resume rules, and loading screens.
│   ├── context.lua                      # Tracks Wwise music state and boss encounters, resolves one context string.
│   ├── suppression.lua                  # Silences the game's music while a custom track plays.
│   ├── library.lua                      # Keeps each context's file list and picks a file for a context.
│   ├── audio_folders.lua                # Lists, checks, and creates the audio folders through Windows, and measures durations.
│   ├── resume_points.lua                # Remembers where interrupted songs stopped, until the next loading screen.
│   ├── audio_client.lua                 # Plays the music: crossfades, end fades, volumes, parked songs, and recovery.
│   ├── loudness.lua                     # Measures every song's loudness in the background and keeps the results in loudness.txt.
│   ├── loudness_meter.lua               # Measures loudness in LUFS following ITU-R BS.1770.
│   ├── player.lua                       # Streams one song through media_decoder.lua and xaudio.lua from a fixed buffer pool.
│   ├── media_decoder.lua                # Decodes audio files to PCM with Windows Media Foundation.
│   ├── xaudio.lua                       # Plays PCM through XAudio2 voices with live volume control.
│   ├── native_ffi.lua                   # Shared ffi plumbing for Windows APIs: GUIDs, COM calls and setup, UTF-16 strings, heap memory, files.
│   ├── diagnostic_log.lua               # Writes diagnostic.log, keeping the previous launch's, with detailed lines on request.
│   ├── debug_overlay.lua                # Builds the debug overlay's text and adds its element to the game's always-visible UI.
│   ├── debug_overlay_element.lua        # The debug overlay's on-screen element.
│   ├── event_probe.lua                  # Logs the game's Wwise event names, and changes nothing.
│   ├── mission_probe.lua                # Logs the current mission's name and type, and changes nothing.
│   ├── MusicReplacer_data.lua           # DMF mod-options widgets.
│   └── MusicReplacer_localization.lua   # Mod-options strings.
├── docs/
│   ├── development.md                   # This file.
│   ├── game-internals.md                # How the game reports its missions and modes, and the mission lines in the log.
│   ├── override-folders.md              # The optional override folders, for players.
│   ├── settings.md                      # Every setting and its default, and the debug overlay's lines, for players.
│   ├── troubleshooting.md               # Common problems, reporting one, the files the mod writes, and a lost audio device.
│   └── wwise-events.md                  # The game's music states and events, how the mod silences them, and tracing a sound.
├── tests/
│   ├── run.lua                          # Minimal spec runner, needs only LuaJIT.
│   ├── helpers/
│   │   ├── context_harness.lua          # Replays the game's real state sequences through context.lua.
│   │   ├── fake_engine.lua              # Fakes the game and DMF globals so the mod's modules run outside the game.
│   │   └── main_harness.lua             # Runs MusicReplacer.lua with stand-ins for the library, the audio client, and the loudness measurements.
│   └── spec/                            # Specs, one *_spec.lua file per subject.
└── tools/
    ├── build.ps1                        # Builds the ZIP and optionally deploys straight into the installed mod folder.
    ├── player_demo.lua                  # Plays two files through player.lua outside the game.
    └── test.ps1                         # Runs the specs and exits non-zero on failure.
```

## Roadmap

* [ ] Playback controls, in three layers. Manual control only steers the situation playing now, so a new situation still starts its own pick.
  * [ ] Keybinds to skip to the next song, go back to the previous one or restart the current one, and pause. A paused situation stays silent instead of handing back to the game's music, and a skipped song gets no resume point. A keybind that removes the playing song from its folder's rotation for good, kept in a small file beside `loudness.txt`. A short message for each keybind, so the controls work without the widget.
  * [ ] Settings for the order and repeat: shuffle on or off, where off plays a folder in name order, and repeating the folder or one song. An option to let a song finish before the next situation's music takes over belongs here too.
  * [ ] A now-playing widget that shows the song and the shuffle, repeat, and pause state. A song name too long for it scrolls, and its font covers every script a file name can use, such as Japanese, which the debug overlay's font does not. Its look is up to the players, with settings of its own for the hub and for missions, since the hub shows almost no HUD. A few presets set its position, size, and opacity at once, and offset settings move it anywhere on the screen. It can be hidden completely, and the keybinds still work then. In missions it can show for a few seconds when a song starts or a keybind is pressed, and then fade out.
* [ ] Translations of the mod options, the debug overlay, and the now-playing widget. The overlay's own texts, such as its idle reasons and markers, are in English in its code today, so they need to move into `MusicReplacer_localization.lua` first.
* [ ] More settings per situation, such as its own volume.
* [ ] User rules that refine which folder a situation plays, in three layers. A rule never creates a situation of its own, so each situation keeps its silencing, priority, resume rule, and fallback to the game's music.
  * [ ] Richer override folder names: combined conditions, such as `boss\chaos_spawn+havoc\`, and more of what the game reports. Examples are a mission's circumstance and event intensity.
  * [ ] A Vanilla marker, an empty file named `vanilla` that any folder can hold. Among other songs, the game's music becomes one more pick in the rotation, and it lasts until the situation changes. Alone in a folder, it keeps the game's music there, so `event\spillway\vanilla` keeps Spillway's own boss music while other events play your songs.
  * [ ] An optional rules file for what folder names cannot express, such as several conditions, weights, or a chance to play the game's music instead. A bad rule is skipped and named in the log, and the debug overlay shows which rule matched.
  * [ ] An in-game rule editor (low-priority).

  The priorities between situations stay fixed, offered at most as a few vetted settings.
* [ ] Any of the game's own tracks in any situation, after the Vanilla marker. The mod would force the game's music states into the combination that makes Wwise play a chosen track, the way it already forces them to silence the game. It needs a list of the tracks and their state combinations, built from the game's own source, and care with states that change other game audio, such as the mission intro's.
