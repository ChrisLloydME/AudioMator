AudioMator test fixtures
========================

These files are intentionally committed for TagLib read/write integration tests.

- `Audio/` contains small audio samples used as immutable source fixtures.
- `Artwork/testCover.jpg` is a metadata-stripped JPEG generated from the local test cover with `jpegtran -copy none`.

Tests must copy audio files to a temporary directory before writing tags. Do not mutate these fixture files in place.
