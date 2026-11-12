# Published 0.7.3 release readiness — 2026-11-12

Branch: `codex/taglib-0.7.3-release-readiness`. Clean starting baseline: `53abe559` on main. This adoption uses `AudioMator.xcodeproj`, without the historical local override workspace. Package publication is already complete; this task prepares AudioMator for maintainer distribution.

## Dependency identity and review

- Exact remote version: `0.7.3`, revision `7ca1b75326388a5902815f70145b600299944ae0`, independently matched to `git ls-remote` for the published tag.
- Xcode-generated lock: `AudioMator.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- [Release changelog](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.7.3/CHANGELOG.md): native MP4 Comment/Lyrics routing, independent date owners across replay and low-level reads, unchanged arrays/text preservation, Artist/ARTISTS independence and ASF custom-field/verification repairs.
- [Package manifest](https://github.com/ChrisLloydME/TagLibAudioMetadata/blob/0.7.3/Package.swift): TagLib 2.3.1 revision 2 binary asset and SHA-256 `d7a36b2492266a17fcd97bd776cd841d9fc85275270bc0c3cb9621395b3178c7` are unchanged from 0.7.2.
- Bundled MIT text matches the published 0.7.3 LICENSE after file-end whitespace normalization; no license resource replacement is needed. In-app Acknowledgements and current legal/build/dependency documentation identify 0.7.3.
- The pin/disclosure test has literal reviewed version/revision expectations. Original mapping and save regressions remain ordinary mandatory tests.

The existing app release identity remains version 2.7, build 2697. The remote `V2.7B2697` tag was absent during this inspection; the highest matching remote release-format tag observed was `V2.6B2691`. Choosing a different release identity remains a maintainer release decision.

## Acceptance

**Automated release-candidate acceptance passed.** No new functional blocker was reproduced. This result uses the published remote tag, not the historical local candidate.

```bash
bash scripts/validate-release.sh
```

Evidence root: `.deriveddata-codex/Validation/20261112-100337-3720/`.

| Check | Result | Evidence |
| --- | --- | --- |
| Gate policy | 13 Python tests passed | `policy.log` |
| Core | 62 passed; complete named execution accepted | `core.log`, `core-gate.json` |
| Full serial Debug app suite | 579 passed, zero failures/skips/expected failures; exact inventory accepted | `app.log`, `AppTests.xcresult`, `test-summary.json`, `test-tree.json`, `test-gate.json` |
| Exact dependency/disclosure contract | passed for 0.7.3 and the reviewed remote revision | Named execution in `app.log` |
| MP4 Comment/Lyrics with absent Year and present Date | both retained regressions passed normally | `MappingPackageConformanceTests` in the full run |
| Provider, Inspector, Editor, CSV and date-state matrices | passed as part of the full suite | `MetadataSaveJourneyTests` and `MetadataBoundaryMatrixTests` |
| Unsigned generic Release build | passed | `release.log` |
| macOS artifact validation | passed; app minOS 15.0, embedded TagLib minOS 13.0, both architectures | `artifact.log` |
| Candidate source/pin identity | recorded | `source.txt` |

Compiler source paths in `app.log` reference the normal project's `SourcePackages/checkouts/TagLibAudioMetadata`; no sibling package source path was referenced. The completed gate reports `published Package.resolved`.

## Unsigned Archive

An additional archive was built with stable Xcode, the normal project, Release, generic macOS destination, `.deriveddata-codex`, `CODE_SIGNING_ALLOWED=NO`, `-disableAutomaticPackageResolution` and `-onlyUsePackageVersionsFromResolvedFile`:

```bash
xcodebuild -project AudioMator.xcodeproj -scheme AudioMator \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath .deriveddata-codex \
  -archivePath .deriveddata-codex/Validation/20261112-100337-3720/AudioMator.xcarchive \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO archive
```

Archive creation and artifact validation passed. `archive-report.json`, `archive.log`, `archive-artifact.log` and `archive-dependencies.log` record:

- Release bundle ID `com.LloydME.AudioMator`, version 2.7, build 2697.
- Both app and embedded framework contain `arm64` and `x86_64` slices.
- Embedded TagLib framework reports 2.3.1.
- All five license texts are present and byte-identical to the reviewed repository resources.
- The app loads TagLib via the embedded `@rpath` location, includes `@executable_path/../Frameworks`, and has no absolute user-directory dependency path.

The archive is an unsigned validation artifact, not a signed/notarized distribution. Build outputs remain ignored and are not committed.

## Distribution boundary

No interactive app launch, UI automation, live-provider network, distribution signing, notarization, installer packaging or publication is performed by the automated gate. Maintainer UI acceptance and the manual distribution steps in [Release Engineering](../Development/RELEASE.md) remain necessary before distributing the app.

Hosted CI, runtime testing on macOS 15 and interactive UI acceptance were not executed. Source changes are limited to the dependency pin/lock, current version disclosure, literal upgrade contract and matching documentation; no application metadata workaround was added.
