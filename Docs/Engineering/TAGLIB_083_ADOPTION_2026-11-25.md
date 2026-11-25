# Published TagLibAudioMetadata 0.8.3 adoption

Recorded 2026-11-25. AudioMator commit `a4bbe67c3ecebedbfa84c0b10ef53e49e5b7a961` on `codex/adopt-taglib-083-store-ids` matches the source diff captured by the gate. The normal Xcode project resolved the published [0.8.3 tag](https://github.com/ChrisLloydME/TagLibAudioMetadata/tree/0.8.3) at `ebd21c7b1aa9be607133fc4a9de02d2c7890f42f`. The package retained mapping contract `AM-TLAM-MAPPING-2.2` and the checksum-pinned TagLib 2.3.1 revision 2 binary. The four dependency license texts matched after accounting for a trailing blank line and AudioMator's utfcpp attribution.

`bash scripts/validate-release.sh` passed with the published lock. It ran 33 policy and crash-recovery tests, 130 SwiftPM core tests and 1,096 serial app-hosted tests with zero failures, skips or expected failures in the app suite. The unsigned Release build and artifact validation passed. Artifact validation checked arm64 and x86_64 for the app and TagLib framework, the macOS 15.0 app minimum and five bundled licenses. Interactive UI acceptance, signing and distribution were outside this run.

- `MetadataBoundaryMatrixTests.testProviderBatchExecutesWithRealPipelineAndReloadsEveryFile` applied iTunes entries to FLAC and M4A fixtures. Album ID `6829122413` and Catalog ID `6829122414` read back from disk, and the refreshed application model retained the Album ID.
- `StoreIdentifierWriteTests` covered large Store ID set, replace and clear on generated AIFF and rejected an out-of-range M4A Artist ID with unchanged file bytes.
- `TagLibUpgradeContractTests.testExactDependencyPinMatchesProjectAndCurrentDisclosures` verified the project requirement, generated remote lock, mapping contract and acknowledgements.

Local run records are under `.deriveddata-codex/Validation/20261125-210759-88226/`. Current Store ID behavior is documented in [Dependency Limitations](../Reference/DEPENDENCY_LIMITATIONS.md#store-id-ranges).
