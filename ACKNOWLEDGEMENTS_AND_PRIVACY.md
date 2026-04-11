# Acknowledgements & Privacy Notes

## TagLib

- Project: https://github.com/taglib/taglib
- Website: https://taglib.org/
- AudioMator uses TagLib through the local bridge for metadata reading and writing.

TagLib is distributed under the GNU Lesser General Public License (LGPL) and Mozilla Public License (MPL). Essentially that means that it may be used in proprietary applications, but if changes are made to TagLib they must be contributed back to the project. Please review the licenses if you are considering using TagLib in your project.

## iTunes-Artwork-Finder by bendodson

- Project: https://github.com/bendodson/itunes-artwork-finder
- AudioMator's current implementation is fully rewritten in Swift, but the artwork lookup method and approach are based on the ideas from this project.

## Privacy & Network Activity

AudioMator's local metadata reading/writing runs on your Mac.  
**Your music files themselves are not uploaded.**

Network activity only happens when optional online features are used:

1. **iTunes artwork lookup**
   - Target hosts: `itunes.apple.com`, `is5-ssl.mzstatic.com`, `a5.mzstatic.com`
   - Sent data: lookup/search query parameters derived from metadata fields (for example: iTunes Album ID, album name, or track title)
   - Purpose: searching and downloading album artwork

2. **MusicBrainz browser/search**
   - Target host: `musicbrainz.org` (`/ws/2` API and selected MusicBrainz pages)
   - Sent data: query terms generated from entered/selected metadata fields, including possible fields such as title, artist, album artist, album, track number, total tracks, duration bucket, release date/year, ISRC, barcode, MusicBrainz album ID, and MusicBrainz track ID (or IDs parsed from a pasted MusicBrainz link)
   - Purpose: searching and referencing MusicBrainz metadata

3. **Release Notes**
   - Target host: `api.github.com`
   - Sent data: request headers and release list request only (no audio file content)
   - Purpose: load published release notes for AudioMator
