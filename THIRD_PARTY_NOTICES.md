# Third-Party Notices

## TagLib

- **Project**: TagLib (audio metadata library)
- **Website**: https://taglib.org/
- **Usage in this repository**: AudioMator uses TagLib via the `AudioMator/TagLibBridge/` bridge for metadata reading/writing.

### Licensing

TagLib is third-party open-source software and is **not** public domain.

TagLib is provided under dual licensing (LGPL/MPL). For compliant use, choose and comply with at least one of these license paths:

- GNU Lesser General Public License (LGPL)
- Mozilla Public License (MPL)

### Commercial / Proprietary Usage Reminder

When using TagLib in commercial or closed-source applications, at minimum:

1. Note that the application uses TagLib.
2. Note TagLib's applicable license terms (LGPL or MPL path chosen).
3. If TagLib itself is modified, publish those TagLib modifications as required by the chosen license.

### Local Project Status

- This repository includes usage notice and licensing notice for TagLib in this file and in `README.md`.
- If future changes modify TagLib source itself, maintainers must publish those TagLib changes to remain compliant with the selected TagLib license path.

## iTunes Artwork Finder

- **Project**: iTunes Artwork Finder
- **Source used in this repository**: partial adaptation of the iTunes artwork lookup and result transformation logic from the package placed at `.tmp/iTunes-Artwork-Finder-master`
- **Upstream license**: The Unlicense / public domain dedication

### Licensing

The copied logic originates from software released under The Unlicense. That work is dedicated to the public domain where recognized, and otherwise provided for unrestricted use under the terms of The Unlicense.
