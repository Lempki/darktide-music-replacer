# Changelog

What changes for players in each release of Music Replacer. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version numbers follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Features

* A Shuffle setting, on by default, in the Playback group. Turned off, each folder plays in the order File Explorer sorts it by name, and continues after the song it played last. Previous Song then goes to the song before in that order, and from the first song to the last.
* A Toggle Shuffle key turns Shuffle on or off, and the message says which. It starts unbound.
* A Repeat Song setting, off by default, in the Playback group. Turned on, the song playing now loops with no gap, and so does every song after it, until you turn it off. A Toggle Repeat Song key turns it on or off, and the message says which. It starts unbound.
* A Let Songs Finish setting, off by default, in the Playback group. Turned on, a song plays to its end before a situation that ranks the same or lower takes over, such as explore after a fight. A switch to a situation that ranks higher, to the game's music, or to silence still happens at once, and Next Song ends the wait.
* A Skip choice joins Custom, Vanilla, and Silence for the mission situations that rank above another, such as Combat, Boss, and Event. A skipped situation lets the one ranked below it play on, such as explore through fights with Combat skipped. The skipped situation's own game music stays silenced while your songs play, and the debug overlay's tag names it, such as `Custom, boss skipped`.
* The debug overlay has Fade in and Fade out rows, with each fade's level and seconds left while the music fades, and the name of the song fading out.
* With Detailed Logging on, the log names each boss in the level when it appears, picks or loses a target, and is gone, with its distance from you.

### Changes

* A folder plays each of its songs once before any song repeats, instead of only avoiding the song that just played.
* Next Song returns to the songs Previous Song went back past before it moves on to a new one, and so does a song that ends by itself.
* The debug overlay's Waiting and Measuring rows always show, so the overlay keeps its height. While nothing counts down or needs measuring, they are greyed out and say so, such as `none` or `all measured`.
* With several bosses in the fight, the boss override folder of the one that came first plays until that boss dies or despawns, so bosses that come back to back no longer change the music each time. Before, the boss that came last took over.
* Character select keeps its music while you pick a mission or wait for one from there, as some mods allow. Before, the game's music played.
* Every loading screen plays the Loading folder, wherever it leads, and Mission Briefing plays only in the briefing, also when you join a mission in progress. Before, the loading screen back to the hub after leaving the preparation screen played Mission Briefing, and so did a loading screen on the way into a mission that lasted over 3 seconds.

### Fixes

* Windows no longer fades your music out while Windows Media Player plays.
* Next Song keeps the song playing and says `No songs left in` the folder when you deleted the folder's songs while the game runs. Before, it said that no song of yours was playing.
* Restart Song and Previous Song keep a song playing whose file you deleted or moved while it played, and say so. Before, they tried to open the file again, and the music fell back to the game's or jumped to another song.
* Restart Song loops a song that became its folder's only one while it played, as such a song does when it starts by itself.
* Victory and defeat music no longer starts over when you leave character select after a mission, as with a mod that returns you there instead of to the Mourningstar.

## [1.1.0] - 2026-11-06

### Features

* A Next Song key, in the new Playback Controls group of the mod options, crossfades to another song from the folder playing now and shows the song's name. In a folder with only one song, it keeps that song playing, or resumes it while it is paused, and says so. It starts unbound.
* Previous Song and Restart Song keys join Next Song. Within a song's first 3 seconds, Previous Song goes back to the song that played before it in the same situation, and later it starts the song over, as most music players do.
* A Pause / Resume key pauses your song while the game's music stays silent, and resumes it where it stopped.
* A Key Fade Length setting, 0.5 seconds by default, sets how long the playback keys crossfade, apart from the Fade Length that situation changes use. A key that starts the song playing now over jumps to its start instead of crossfading the song with itself.
* A Remove from Rotation key takes the song playing now out of its folder's rotation on a second press while its question shows, and moves on to another song. The file stays on disk, and the removed songs are listed in `removed.txt` beside `loudness.txt`. A Restore Removed Songs button puts them all back.
* On-Screen Messages show what each playback key did, and the name of each song the mod starts by itself, as one calm line in a corner of the screen that fades out after a few seconds. They show on every screen, loading screens and the mission briefing included. Settings in the new On-Screen Messages group turn them off for key presses or song changes, and set how long they stay, how long they fade out, their size on top of the game's HUD Scale, their color, corner, and position, and the opacity of the dark backdrop behind them. The color setting needs DMF from August 2026 or newer.
* The debug overlay shows a Measuring row while Even Out Loudness has songs left to measure, with a bar and a count such as `12 / 40`. It counts only the songs that need measuring, not those measured before.
* The debug overlay's Level row shows `not measured` instead of the song's level while Even Out Loudness is on and the song was not yet measured when it started. Such a song plays at its own level until its next start.

### Changes

* The mod options have three new groups and a new order: Your Songs, Playback, Playback Controls, Volume, On-Screen Messages, Music per Situation, Meat Grinder, Boss Music, Music Holds, and Debug. Rescan Audio Folders moved from Playback to Your Songs. Every setting keeps its value.
* Rescan Audio Folders creates any situation's folder that went missing while the game runs, so it no longer takes a restart.
* A situation that switches back to an override folder it already played continues that folder's song where it stopped, with Resume Songs on. Rolling Steel goes back and forth between its first two stages, so stage folders no longer start their songs over each time.
* Even Out Loudness measures a song copied into several folders only once, so measuring a library with shared songs takes less time.
* Even Out Loudness measures the song playing now first, then the rest of the folder it plays from, such as an override folder, then the rest of the situation's songs. Before, it measured all of the situation's songs, override folders included, in the order they were listed.
* The debug overlay's label column is a little wider, so the Level row's meter and markers sit further right.
* The debug overlay follows the game's HUD Scale setting, with Overlay Size on top of it.
* The debug overlay's backdrop touches the top and left edges of the screen, as the on-screen messages' does, instead of sitting a little in from them.

### Fixes

* A song that resumes after it was started over, or picked again within a minute of fading out, continues from where it stopped, instead of from where its earlier play faded out.
* A song that Even Out Loudness could not get the memory to measure is tried again once its file changes, or on Rescan Audio Folders, instead of at every listing of the folders.
* When drawing the debug overlay fails, the log says why, once for each failure, instead of the overlay freezing with nothing in the log.
* Rescan Audio Folders lets Even Out Loudness measure a song again that it could not measure before, such as a file that was locked at the time. Before, it tried such a song again only once the file changed.
* Even Out Loudness keeps no level for a song whose reading fails partway, instead of the level of only its first part. Such a song is measured again once its file changes, or on Rescan Audio Folders.

## [1.0.0] - 2026-10-30

First public release.

[Unreleased]: https://github.com/Lempki/darktide-music-replacer/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Lempki/darktide-music-replacer/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/Lempki/darktide-music-replacer/releases/tag/v1.0.0
