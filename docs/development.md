# Development

How to build, test, and work on Music Replacer.
How the game's music works is covered in [wwise-events.md](wwise-events.md), and how the game reports its missions and modes in [game-internals.md](game-internals.md).

## Building and testing

```powershell
tools\build.ps1           # Build dist\MusicReplacer.zip, for Vortex "Install from File".
tools\build.ps1 -Deploy   # Also copy the source straight into the installed mod folder.
tools\test.ps1            # Run the specs under tests\spec with LuaJIT.
luajit tools\player_demo.lua <file A> <file B> [--silent]   # Play two files through the mod's player outside the game.
luacheck .                # Static analysis with the settings in .luacheckrc.
uvx pre-commit run --all-files   # The shared dev-standards hooks: prose rules, synced config files, and file hygiene.
```

The specs need [LuaJIT 2.1](https://luajit.org/) on `PATH`, the same Lua runtime the game uses.
`tools\test.ps1` exits non-zero when any spec fails.
The Windows calls themselves need real audio hardware, so they are checked with `tools\player_demo.lua` rather than in the specs.

Static analysis needs [luacheck](https://github.com/lunarmodules/luacheck) on `PATH`.
The standalone `luacheck.exe` from its releases page is enough.

## Deploying

`-Deploy` is the fast iteration path.
It copies the staged files over the installed ones, including `MusicReplacer.mod` and the stamped `info.json`, and leaves `audio\` alone.
So a change can be tested by restarting the game rather than reinstalling through Vortex.
It never deletes a file, so remove a module that was deleted from the source by hand.
The ZIP stays the real artifact, and a Vortex purge discards anything deployed this way.

The build stamps the packaged `info.json` with the commit and build time, and the mod logs it at startup.
A `-dirty` suffix means the packaged files had uncommitted changes.

`audio\` is not part of this repository.
The mod creates it inside the installed mod folder.

## Conventions and CI

The repository follows the shared conventions in [dev-standards](https://github.com/Lempki/dev-standards).
Its hooks keep the managed blocks in `.editorconfig`, `.gitattributes`, and `.gitignore` in sync, and check comments and Markdown against the prose rules.
They tell this is a Lua repository from `.luacheckrc`, so it needs no settings file.
Install the hooks once per clone with `uvx pre-commit install`.
CI runs dev-standards' Lua workflow on every push to `main` and every pull request: the hooks, luacheck, and the specs under LuaJIT.

## Logs

* `%APPDATA%\Fatshark\Darktide\MusicReplacer\diagnostic.log`, with the previous launch's log beside it as `diagnostic-prev.log`. Detailed Logging adds the game's music state changes, the silencing, and the game's sound events.
* The game's console logs, in `%APPDATA%\Fatshark\Darktide\console_logs\`.

## How playback works

Music Replacer decodes the files with Media Foundation, Windows' own media framework, and plays them with XAudio2 2.9, the audio engine Windows provides for games.
It calls both from Lua through LuaJIT's ffi, which the mod loader exposes as `Mods.lua.ffi`, so the mod ships no DLL or executable.
Media Foundation starts in its lite mode, which leaves its network support uninitialized, since the mod only opens local files.

### Decoding and streaming

* `media_decoder.lua` asks Media Foundation for 16-bit PCM and reads it synchronously on the game's thread, a chunk at a time, so no Windows thread ever calls back into Lua.
* `player.lua` gives each stream a fixed pool of 16 slots of 0.25 seconds each, on the Windows heap and outside the game's Lua memory.
  That keeps 4 seconds queued, so the music plays on through a stalled frame or a busy loading screen.
* Each pool is allocated once per stream, about 0.7 MB for 44.1 kHz stereo, and grows with the rate and the channels.
* A stream queues 2 slots before it starts, and each update refills at most 2, so no single frame pays for a whole refill.
* A looping stream reads on from the file's start in the same buffer, so the loop adds no gap.
  Silence the file carries itself, such as an MP3's encoder padding, still plays.
* XAudio2 voice state is polled every update rather than reported through callbacks, since LuaJIT cannot safely take calls from XAudio2's thread.

### Fades and parked songs

* A context change is a 2-second crossfade on an equal-power curve.
  A song that does not loop fades out over its last 2 seconds, and a stop fades out over half a second.
* A song that fades out is paused and parked rather than freed.
  If the mod resumes it, the same stream fades back in from exactly where it stopped, with nothing reopened or sought.
* Each parked song keeps its 4-second buffer pool, about 0.7 MB for 44.1 kHz stereo, and its file open.
  It is freed after 60 seconds, and beyond 4 parked songs the oldest is freed first.
* The master and music sliders, Custom Music Volume, and the menu fade set every stream's gain directly, so no volume change restarts a song.

### Device recovery

* The mastering voice is created with no device ID, so XAudio2 uses Windows' virtual audio client and follows a change of the default audio device by itself.
* A voice that has audio queued but plays nothing for 2 seconds counts as a lost device, since XAudio2 does not report that stall itself.
* When the device is lost in a way XAudio2 cannot follow, the mod rebuilds the engine and resumes the song where it was.
* After 3 rebuilds in a row without 30 seconds of good playback in between, the next failure gives up, and the game's music plays.
  Rescan Audio Folders, or turning the mod off and on, lets it try again.
* While Windows has no audio output at all, creating the engine fails.
  The game's music plays, and the mod tries again every 5 seconds without counting it as a failure, so a headset that stays unplugged never makes it give up.

### Evening out loudness

* `loudness_meter.lua` measures each song's integrated loudness in LUFS following ITU-R BS.1770 and EBU R128: 400 ms blocks every 100 ms, an absolute gate at -70 LUFS, and a relative gate 10 LU below.
* Every song plays at the level that brings it to -14 LUFS, the level most streaming services play music at.
* A quiet song is only raised until its loudest sample reaches full scale, so it never clips, and by at most 12 dB, since raising a very quiet recording further mostly raises its hiss.
* `loudness.lua` decodes each whole song for this, in 50 ms chunks, for at most about a millisecond per update, starting with the folder of the context that plays.
  It only measures while Even Out Loudness is on.
* The log says how long measuring took once every song is measured.
* The results go to `loudness.txt` beside `diagnostic.log`, keyed by each file's size and write time, so a song is measured once and again only after its file changes.
  It is written every 10 songs, once measuring is done, and on unload.
  Deleting it measures every song again.
* A song keeps the level it started with, so one measured while it plays changes level at its next start.

### File checks

* `library.lua` measures every file's duration in the background, one file per update.
  A file Media Foundation cannot open is left out of the picks from then on.
* A track that ends within 3 seconds of starting, and before half its length, did not really play.
  After 3 in a row from one folder, that folder stops retrying until the folders are listed again.
  An override folder then gives way to the next folder, and a context's own folder to the game's music.

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
├── MusicReplacer.mod
├── info.json                            # Version and author metadata, read by DMF at mod init.
├── scripts/mods/MusicReplacer/
│   ├── MusicReplacer.lua                # Wires everything together and debounces context changes.
│   ├── contexts.lua                     # The catalog of contexts: their folders, defaults, silencing, priorities, and resume rules.
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

* An option to let a song finish before the next situation's music takes over.
* Translations of the mod options.
* Contexts for new game modes and situations as the game adds them.
* Settings per situation, such as its own volume.
* Optional subfolders inside `expedition_combat` for each of an Expedition's fight levels, which follow how alert the enemy is, falling back to the main folder when empty.
