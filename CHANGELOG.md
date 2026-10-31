# Changelog

What changes for players in each release of Music Replacer. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version numbers follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Features

* The debug overlay shows a Measuring row while Even Out Loudness has songs left to measure, with a bar and a count such as `12 / 40`. It counts only the songs that need measuring, not those measured before.
* The debug overlay's Level row shows `not measured` instead of the song's level while Even Out Loudness is on and the song was not yet measured when it started. Such a song plays at its own level until its next start.

### Changes

* The debug overlay's label column is a little wider, so the Level row's meter and markers sit further right.

## [1.0.0] - 2026-10-30

First public release.

[Unreleased]: https://github.com/Lempki/darktide-music-replacer/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Lempki/darktide-music-replacer/tree/v1.0.0
