# Published TagLibAudioMetadata 0.8.0 adoption — 2026-11-16

## Source and scope

AudioMator branch: `codex/taglib-080-integration`, based on `codex/diagnostic-date-contract-integration`. The normal Xcode project uses exact published `0.8.0`, revision `e91d822bf584c354f9d9b68803391731a9e7c9a8`, through committed `Package.resolved`. No local package override is used for acceptance. The package source remains untouched.

The adapter had already migrated to independent `.year` / `.standaloneDate`, typed native writes and current conflict/version APIs. This adoption updates the formal pin, runtime acknowledgements and exact published-dependency contract; no metadata coercion or raw-write workaround is added. Mapping contract remains `AM-TLAM-MAPPING-2.2`.

## Dependency and notices

The published revision's MIT license matches the bundled `TagLibAudioMetadata-MIT.txt` byte-for-byte. TagLib remains 2.3.1 revision 2, asset `TagLibAudioMetadataTagLib-2.3.1-apple-dynamic.xcframework.zip`, checksum `d7a36b2492266a17fcd97bd776cd841d9fc85275270bc0c3cb9621395b3178c7`. No network feature, endpoint, license terms or bundled license text changes. The acknowledgements view continues to read `LicenseDisclosure`.

## Verification

Resolution succeeded through `xcodebuild -resolvePackageDependencies -project AudioMator.xcodeproj -scheme AudioMator -derivedDataPath .deriveddata-codex`. The complete normal-project gate, `bash scripts/validate-release.sh`, and unsigned archive validation must pass before automated release readiness is claimed. Actual results are appended below.

## Distribution boundary

No interactive application launch, manual UI acceptance, live provider/network test, signed distribution, notarization, packaging, push, tag or publication is implied. Those manual distribution steps remain the maintainer's responsibility. All automated app-hosted tests run serially with the isolated test host.

## Final automated acceptance

**Ready for the maintainer's release workflow within the automated scope.** Final tested application source is `28997953`; subsequent commits record evidence/current guidance only. Published package identity is the exact 0.8.0 revision above. Neither the package checkout nor package cache was patched. No new functional metadata defect was reproduced, and no application write workaround was needed.

Normal-project evidence: `.deriveddata-codex/Validation/20261116-160318-32951/`.

| Check | Result |
| --- | --- |
| Policy | 13 tests passed |
| Core | 62/62 required tests; accepted |
| Serial app-hosted | 580/580 required tests; accepted; zero failures, skips or expected failures |
| Critical save contracts | Inspector dirty-state/workflows, Metadata Editor, native mapping boundary, provider/displayed-plan/date-state save journeys and exact published dependency contract passed |
| Unsigned Release | Build and artifact validation passed; app minimum macOS 15.0, embedded framework minimum macOS 13.0 |
| License/disclosure | Published MIT text matches bundled text; runtime version and current dependency notices match 0.8.0 |

The first in-flight run compiled the old 0.7.3 dependency-test constants before their update and was rejected on that single test (eight assertions); the other 579 tests passed. It is not accepted evidence for the final source. The final complete run above rebuilt the literal 0.8.0/revision contract and passed it without removing assertions or weakening the gate.

## Unsigned Archive

Archive creation passed using the normal project, stable Xcode, Release, generic macOS destination, `.deriveddata-codex`, `CODE_SIGNING_ALLOWED=NO`, `-disableAutomaticPackageResolution` and `-onlyUsePackageVersionsFromResolvedFile`. The archive is under the evidence directory at `AudioMator.xcarchive`.

The archive artifact validator passed. `archive-report.json` verifies arm64/x86_64 in both the application and embedded framework, Release bundle ID `com.LloydME.AudioMator`, all bundled license texts byte-identical to repository resources, the embedded framework's `@rpath` dependency, and absence of absolute developer-machine library paths. Build logs confirm compilation from the normally resolved remote checkout, not the ignored local-candidate workspace. The archive is unsigned validation output, not a signed/notarized distributable.
