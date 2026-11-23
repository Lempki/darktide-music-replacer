# Troubleshooting

Fixes for common problems, how to report one, and what the mod writes where.

## Common problems

* **No custom music anywhere.** Check that `MusicReplacer` is listed below `dmf` in `mod_load_order.txt`, that Music Replacer appears in the mod options and is turned on, and that your files sit directly inside the audio folders in a supported format.
* **A notice says "No songs found" although you added songs.** The mod reads only the `audio` folder of the installed mod, `...\Warhammer 40,000 DARKTIDE\mods\MusicReplacer\audio\` in the game folder. Check that your songs are there, and not in a downloaded copy of the mod or in a mod manager's own folder.
* **A red message says "Windows audio playback could not start".** The mod could not start Windows' audio decoder or audio engine, so the game's music plays as usual. `diagnostic.log` gives the reason on its `[player] unavailable` line. On a Windows "N" edition, install the Media Feature Pack. If Windows had no audio output at that moment, the mod keeps trying and starts once there is one.
* **One file never plays, or a notice says files were skipped.** A file in a format the mod does not play, such as `.ogg` or `.opus`, or one Windows cannot decode, is skipped. `diagnostic.log` names each skipped file. Convert it to a supported format, and the mod picks up the new file by itself.
* **A situation plays the game's music although its folder has songs.** Turn on Debug Overlay and read the tag beside the situation. `Vanilla` means the situation is set to Vanilla. `Vanilla, no songs` means the mod found no playable file in that folder. `Vanilla, its songs would not play` means three songs in a row failed. `Vanilla, no audio output` means Windows audio is not available, or the mod gave up on it after repeated failures.
* **Cutscenes play the game's music.** Cutscene is set to Vanilla by default. Put songs into `cutscene` and set Cutscene to Custom under Music per Situation, or set it to Silence.
* **The same song plays every time.** A folder with only one song loops that song. Add more songs to the folder that plays, which the debug overlay's Folder line names.
* **Boss music starts before the boss shows up.** Boss Near plays once a boss is within Boss Distance, 80 m by default, and with its folder empty it plays your `boss` songs. Set Boss Near to Skip under Music per Situation to start boss music with the boss's HP bar, or lower Boss Distance in the Boss Music group.
* **A red message says "diagnostic.log could not be opened".** The mod could not write `diagnostic.log` in `%APPDATA%\Fatshark\Darktide\MusicReplacer\`, so this launch is not logged, and the reason is in the game's console log. Your music still plays.
* **Changed files are not picked up.** The mod lists the folders again 3 seconds after files stop changing. On a drive where Windows cannot report changes, such as some network drives, press Rescan Audio Folders. Press it too after deleting the whole `audio` folder and making it again while the game runs, since the mod notices no changes in the new folder until then.

## Reporting a problem

Open an [issue](https://github.com/Lempki/darktide-music-replacer/issues) on GitHub and attach these two files:

* `diagnostic.log` from `%APPDATA%\Fatshark\Darktide\MusicReplacer\` if the problem happened in the current or last game session, or `diagnostic-prev.log` from the same folder if it happened in the session before that.
* The newest file in `%APPDATA%\Fatshark\Darktide\console_logs\`.

A bug report on the mod's Nexus Mods page works too, but its form takes no files, so share them through a link instead.

The mod always logs the important events, such as which music plays and why, any file it could not play, and every error and notice, with the details its on-screen message leaves out. If you are asked for more detail, turn on Detailed Logging in the Debug group of the mod options and play until the problem happens again. What the detailed lines mean is explained in [wwise-events.md](wwise-events.md) and [game-internals.md](game-internals.md).

## Files the mod writes

The mod writes its logs to `%APPDATA%\Fatshark\Darktide\MusicReplacer\`:

* `diagnostic.log`, the log of the current or last game session. Every launch starts a fresh one. A runaway log stops growing at 10 MB.
* `diagnostic-prev.log`, the log of the session before that.

It writes the files that belong to your songs into the `audio` folder itself, so a copy of the folder brings them along:

* `loudness.txt`, the remembered results of Even Out Loudness, so each song is measured only once, and again after its file changes. Deleting it measures every song again.
* `removed.txt`, the songs Remove from Rotation took out of their folder's rotation, one per line, such as `hub/Song.mp3`. The song files themselves stay where they are. Deleting a line, or the whole file, and then pressing Rescan Audio Folders puts those songs back.

Versions before 1.3.0 kept `loudness.txt` and `removed.txt` in `%APPDATA%`. The first launch after updating moves them into the `audio` folder, unless the `audio` folder already has one.

## A lost audio device

* While Windows has no audio output at all, for example right after you unplug your only headset, the game's music takes over. The mod tries again every 5 seconds, and your music comes back once an output does.
* If the audio device is lost in a way Windows cannot recover from by itself, the mod restarts its audio and continues the song where it was.
* If it still fails after three restarts in a row, the mod gives up and the game's music plays. Press Rescan Audio Folders, or turn the mod off and on, to let it try again.
