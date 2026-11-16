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
