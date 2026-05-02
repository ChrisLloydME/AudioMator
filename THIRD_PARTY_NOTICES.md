# Third-Party Notices

This file summarizes third-party software and project influences used by AudioMator. It is not a substitute for the upstream license texts. Before distributing a release, review the applicable upstream licenses and make sure the final app bundle, website, and release notes include the notices required by the license path you choose.

## TagLib

- **Project**: TagLib audio metadata library
- **Website**: https://taglib.org/
- **Source**: https://github.com/taglib/taglib
- **Usage in this repository**: AudioMator uses TagLib through the `TagLibAudioMetadata` Swift package for audio metadata reading, metadata writing, format capability discovery, raw property-map inspection, and artwork operations.

### Licensing

TagLib is third-party open-source software and is not public domain.

TagLib is provided under dual licensing terms. For compliant use, choose and comply with at least one of these license paths:

- GNU Lesser General Public License (LGPL)
- Mozilla Public License (MPL)

### Commercial / Proprietary Usage Reminder

When using TagLib in commercial or closed-source applications, at minimum:

1. Note that the application uses TagLib.
2. Include or link to TagLib's applicable license terms.
3. If TagLib itself is modified, publish those TagLib modifications as required by the chosen license.
4. Preserve any upstream copyright and attribution notices required by the selected license path.

### Local Project Status

- This repository uses TagLib through a package dependency instead of checking a full TagLib source tree into the app repository.
- This repository includes usage and licensing notices for TagLib in `README.md`, `ACKNOWLEDGEMENTS_AND_PRIVACY.md`, and this file.
- If future changes vendor TagLib source or modify TagLib itself, maintainers must update these notices and publish required TagLib changes according to the selected license path.

## TagLibAudioMetadata

- **Project**: TagLibAudioMetadata
- **Source**: https://github.com/ChrisLloydME/TagLibAudioMetadata.git
- **Usage in this repository**: Swift Package Manager dependency that exposes the TagLib-backed APIs consumed by AudioMator's metadata pipeline.
- **Current resolution**: pinned by `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

Review that repository's license and its transitive TagLib obligations before redistribution.

## iTunes Artwork Finder

- **Project**: iTunes Artwork Finder
- **Source**: https://github.com/bendodson/itunes-artwork-finder
- **Usage in this repository**: inspiration for the album artwork lookup workflow and result transformation approach. AudioMator's current implementation is written in Swift in this repository.
- **Upstream license**: The Unlicense / public domain dedication

### Licensing

The referenced project is released under The Unlicense. Where recognized, the work is dedicated to the public domain; otherwise, it is provided for unrestricted use under the terms of The Unlicense.

## Sparkle

- **Project**: Sparkle
- **Website**: https://sparkle-project.org/
- **Source**: https://github.com/sparkle-project/Sparkle
- **Usage in this repository**: AudioMator keeps dormant macOS Sparkle update infrastructure available, but update checking is currently disabled and the app target does not link Sparkle by default.
- **Current resolution**: pinned by `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

### Licensing

Sparkle is third-party open-source software. Review Sparkle's upstream license before redistributing the app, and include any notices required by the Sparkle project in distributed builds.
