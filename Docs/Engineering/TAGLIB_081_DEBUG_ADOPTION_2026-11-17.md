# Published TagLibAudioMetadata 0.8.1 Debug adoption — 2026-11-17

Branch: `codex/adopt-taglib-081`, based on main `a0230a00`.

The normal Xcode project pins exact published `0.8.1`, revision `b8ed5475761cb50bacdd7dcd4f6e2f61142303d0`. Xcode generated the remote lock; no local workspace override is used. The package checkout is not modified. This adopts automatic edited-group numbering recovery and retirement after the earlier [local candidate](INTERNAL_NUMBERING_RECOVERY_2026-11-16.md).

The published MIT license matches the bundled text byte-for-byte. The TagLib 2.3.1 revision 2 binary URL and checksum remain unchanged (`d7a36b2492266a17fcd97bd776cd841d9fc85275270bc0c3cb9621395b3178c7`). Runtime acknowledgements, current notices and the literal dependency contract identify 0.8.1.

## Verification scope

Run `bash scripts/validate-release.sh --tests-only` against the normal project. Results will be recorded after completion. Release builds, artifacts, archives, signing, notarization, publication and interactive application launch are excluded by request. Debug automation does not establish distribution acceptance or visual UI acceptance.
