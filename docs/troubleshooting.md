# Troubleshooting

Fixes for common problems, how to report one, and what the mod writes where.

## Common problems

* **No custom music anywhere.** Check that `MusicReplacer` is listed below `dmf` in `mod_load_order.txt`, that Music Replacer appears in the mod options and is turned on, and that your files sit directly inside the audio folders in a supported format.
* **The chat shows "Music Replacer could not start Windows audio playback".** The mod could not start Windows' audio decoder or audio engine, so the game's music plays as usual. The message ends with the reason. On a Windows "N" edition, install the Media Feature Pack. If Windows had no audio output at that moment, the mod keeps trying and starts once there is one.
* **One file never plays.** Windows cannot decode it. Convert it to another supported format. The mod picks up the new file by itself.
* **A situation plays the game's music although its folder has songs.** Turn on Debug Overlay and read the tag beside the situation. `Vanilla` means the situation is set to Vanilla. `Vanilla, no songs` means the mod found no playable file in that folder. `Vanilla, its songs would not play` means three songs in a row failed. `Vanilla, no audio output` means Windows audio is not available, or the mod gave up on it after repeated failures.
* **Changed files are not picked up.** The mod lists the folders again 3 seconds after files stop changing. On a drive where Windows cannot report changes, such as some network drives, press Rescan Audio Folders.

## Reporting a problem

Open an [issue](https://github.com/Lempki/darktide-music-replacer/issues) on GitHub and attach these two files:

* The mod's log from `%APPDATA%\Fatshark\Darktide\MusicReplacer\`. That is `diagnostic.log` if the problem happened in the current or last game session, or `diagnostic-prev.log` if it happened in the session before that.
* The newest file in `%APPDATA%\Fatshark\Darktide\console_logs\`.

A bug report on the mod's Nexus Mods page works too, but its form takes no files, so share them through a link instead.

The mod always logs the important events, such as which music plays and why, and any file it could not play. If you are asked for more detail, turn on Detailed Logging in the Debug group of the mod options and play until the problem happens again. What the detailed lines mean is explained in [wwise-events.md](wwise-events.md) and [game-internals.md](game-internals.md).

## Files the mod writes

The mod writes these files to `%APPDATA%\Fatshark\Darktide\MusicReplacer\`:

* `diagnostic.log`, the log of the current or last game session. Every launch starts a fresh one. A runaway log stops growing at 10 MB.
* `diagnostic-prev.log`, the log of the session before that.
* `loudness.txt`, the remembered results of Even Out Loudness, so each song is measured only once, and again after its file changes. Deleting it measures every song again.

## A lost audio device

If your audio device goes away, the mod handles it like this:

* While Windows has no audio output at all, for example right after you unplug your only headset, the game's music takes over. The mod tries again every 5 seconds, and your music comes back once an output does.
* If the audio device is lost in a way Windows cannot recover from by itself, the mod restarts its audio and continues the song where it was.
* If it still fails after three restarts in a row, the mod gives up and the game's music plays. Press Rescan Audio Folders, or turn the mod off and on, to let it try again.
