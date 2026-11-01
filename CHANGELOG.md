# Changelog

What changes for players in each release of Music Replacer. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version numbers follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Features

* A Next Song key, in the new Playback Controls group of the mod options, crossfades to another song from the folder playing now and shows the song's name. It starts unbound.
* Previous Song and Restart Song keys join Next Song. Within a song's first 3 seconds, Previous Song goes back to the song that played before it in the same situation, and later it starts the song over, as most music players do.
* A Pause / Resume key pauses your song while the game's music stays silent, and resumes it where it stopped.
* A Key Fade Length setting, 0.5 seconds by default, sets how long the playback keys crossfade, apart from the Fade Length that situation changes use. A key that starts the song playing now over jumps to its start instead of crossfading the song with itself.
* A Remove from Rotation key takes the song playing now out of its folder's rotation on a second press within 3 seconds, and moves on to another song. The file stays on disk, and the removed songs are listed in `removed.txt` beside `loudness.txt`. A Restore Removed Songs button puts them all back.
* The debug overlay shows a Measuring row while Even Out Loudness has songs left to measure, with a bar and a count such as `12 / 40`. It counts only the songs that need measuring, not those measured before.
* The debug overlay's Level row shows `not measured` instead of the song's level while Even Out Loudness is on and the song was not yet measured when it started. Such a song plays at its own level until its next start.

### Changes

* Even Out Loudness measures a song copied into several folders only once, so measuring a library with shared songs takes less time.
* The debug overlay's label column is a little wider, so the Level row's meter and markers sit further right.

### Fixes

* A song that resumes after it was started over, or picked again within a minute of fading out, continues from where it stopped, instead of from where its earlier play faded out.

## [1.0.0] - 2026-10-30

First public release.

[Unreleased]: https://github.com/Lempki/darktide-music-replacer/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Lempki/darktide-music-replacer/releases/tag/v1.0.0
