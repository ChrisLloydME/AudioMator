# Security and Data Integrity

This document describes the security-relevant behavior that exists in AudioMator, separates protections from recommended improvements, and states what has not been verified. It does not claim that AudioMator is secure against any particular threat. Values were verified by source inspection on 2026-11-18; malformed-file robustness, signed-build bookmark behavior, and WebKit runtime behavior were not tested.

## Scope and Trust Model

AudioMator is a sandboxed macOS app that edits files the user selects. Its main trust boundaries are:

1. **User-selected files** — untrusted input parsed by TagLib; modified in place after explicit user action.
2. **The external metadata package** — trusted to parse and write containers, but not audited by this repository.
3. **Online services** — untrusted HTTP responses consumed by provider clients.
4. **Embedded web content** — Apple/MusicBrainz pages loaded in WebKit.
5. **Local persisted state** — preferences, bookmarks, and the save issue log.

There is no server component, account system, or telemetry. External web pages can load their own scripts inside WebKit; that content is bounded by the embedded-page policy described below.

## Sandbox and Entitlements

`Config/AudioMator.entitlements` enables:

- App Sandbox,
- user-selected file read/write,
- outgoing network client.

The app does not request:

- incoming network connections,
- camera/microphone/contacts/etc.,
- Keychain access,
- app-scoped bookmark entitlement.

Both Debug and Release builds enable App Sandbox and Hardened Runtime. Debug and Release use different bundle identifiers, so their sandbox containers are separate.

### Security-scoped file access

- Watched folders and authorized save folders are stored as security-scoped bookmark data in `UserDefaults`.
- The app starts access when a folder is restored or added, and stops it when the folder is removed or the view model is deinitialized.
- Quick Import keeps security scope for loaded files and their parent directories until the files are removed.
- A mutation outside authorized roots computes the missing parent directories, asks the user to authorize the exact directory, and persists a grant.
- `SecurityScopedResourceAccess.withAccess` starts and stops a one-shot scope only if starting succeeded.

### Known entitlement risk

The app persists `.withSecurityScope` bookmark data but does **not** include `com.apple.security.files.bookmarks.app-scope`. Apple documents that entitlement for app-scoped security bookmarks that must resolve across launches. Whether restoration works without it was not verified on a clean signed sandboxed launch. Treat cross-launch folder restoration as requiring validation.

### Corruption handling

- Watched-folder and file-access records are JSON blobs in `UserDefaults`.
- A top-level decode failure marks the store corrupt, quarantines the original bytes once under a `.corruptBackup` key, returns an empty list, and refuses further saves while corrupt.
- A single unresolvable record is retained in memory and re-appended on save, but is not shown in the list.
- The UI warns about corrupt bookmark data and preserves it rather than overwriting.
- There is no restore/export UI for quarantined bookmark data.

## Data at Rest

| Data | Location | Notes |
| --- | --- | --- |
| Audio files | User-selected locations | Modified in place; no app backup |
| Bookmarks | `UserDefaults` (`watchedFolderRecords`, `fileAccessGrantRecords`, plus `.corruptBackup` keys) | Security-scoped data; separate per bundle ID |
| Preferences | `UserDefaults` | Includes conflict policy and UI state |
| Save issue log | `<Application Support>/AudioMator/SaveIssueLog.json` inside the sandbox container | 200 entries; file names + messages; `.corrupt` quarantine copies |
| Rename recovery journal | `<Application Support>/AudioMator/RenameJournal/` inside the sandbox container | One versioned JSON manifest per rename operation plus a stable lock file. Records absolute original/temporary/intended paths and local file-entry identity evidence only; retained until restored, acknowledged, or confirmed complete. Never contains metadata, drafts, tag values, or scope bookmarks. |
| Raw metadata dump | In memory / pasteboard | Includes full path and tag values; not logged |

There is no database, cache of audio content, Keychain item, or credential.

The raw metadata dump intentionally contains the full file path and tag values. It is displayed only on user request and can be copied to the pasteboard. Treat it as sensitive when sharing diagnostics.

## Logging and Telemetry

- App source contains no `print`, `debugPrint`, `NSLog`, `os_log`, or `Logger` calls. `SensitiveLoggingPolicyTests` scans every Swift file under `AudioMator/` and its detector self-test confirms it recognizes all five APIs and fails closed if the regex breaks.
- The policy test covers app source only; it does not scan the external package or audit runtime log output.
- There is no telemetry, analytics, crash-reporting SDK, or remote logging.
- The save issue log stores file names and warning/error strings. It is local and user-visible. The app does not intentionally store full paths there, but backend error strings are not formally guaranteed to be value-free.

## Network Activity

All app requests are HTTP GETs. There is no upload path, multipart body, or request authentication. Opening the Online Metadata window or choosing a provider only prepares local query fields; provider clients are invoked only by an explicit provider Search/Return action, LRCLIB Auto Apply, or the explicit Find in MusicBrainz command. No full file path or audio bytes are sent.

| Service | Hosts contacted by the app | Data sent |
| --- | --- | --- |
| MusicBrainz | `musicbrainz.org` | Lucene query terms and identifiers derived from tags, file names, or parent/grandparent folder names (title, artist, album, album artist, track number/total, duration, release date/year, country, status, format, release/recording MBIDs, ISRC, barcode, filters), or a lookup MBID with fixed options |
| iTunes | `itunes.apple.com` | search term (tags/file/folder-derived or typed), storefront country, media/entity/limit, album/track ID, UPC, or Apple Music/iTunes link |
| Apple artwork | Apple-returned `artworkUrl100` host, `is5-ssl.mzstatic.com`, `a5.mzstatic.com` | image GET only |
| LRCLIB | `lrclib.net` | `track_name`, `artist_name`, `album_name`, `duration`; artist/album may be derived from parent/grandparent folder names |
| GitHub | `api.github.com` | repository release request; no auth token |
| GitHub Releases page | `github.com` | opened in the default browser, not requested by the app |

### Accuracy caveats

The in-app disclosure registry includes API lookups, artwork downloads, embedded provider pages, release notes, and manual updates. Remaining network considerations:

1. **Apple artwork hosts are not allow-listed.** `thumbnailURL` and `standardURL` keep whatever host Apple returned; only hires/uncompressed URLs are rewritten. The disclosure mentions additional Apple-returned hosts.
2. **Embedded page navigation is restricted; subresources are not.** Initial URLs and navigation require HTTPS on `apple.com` or `musicbrainz.org` (including subdomains). WebKit uses non-persistent storage, but a page can load subresources from other hosts and use session cookies. This is disclosed in-app.
3. **Filename/folder-derived text can be sent** by MusicBrainz, iTunes, and LRCLIB when tags are missing; LRCLIB derives artist and album from parent/grandparent folder names. The disclosure summaries state the derived terms; a full file path and audio bytes are never request fields.
4. **`github.com` is opened externally** by `NSWorkspace`; update API requests go to `api.github.com`.
5. **Release notes include prereleases.** The client filters drafts only and requests the first 50 releases.

### Transport

- All app request URLs use HTTPS.
- No App Transport Security exceptions.
- No certificate pinning or custom trust evaluation.
- Default `URLSession.shared` behavior; no custom proxy/cookie/cache policy.

## Additional File Access Notes

- Directory monitoring holds one `O_EVTONLY` descriptor per monitored directory, capped at 128 per watched folder, with the root always monitored. Each descriptor records the device/inode and directory kind obtained by `fstat` on the opened descriptor.
- A directory is active only while that captured identity matches the current authorized path. Reconciliation compares retained descriptors against current path identities even when the path string is unchanged, replaces a mismatched or terminal instance only with a verified descriptor, and otherwise reports open/identity-degraded state instead of counting it as active. A `.rename`, `.delete` or `.revoke` event makes an instance terminal and closes its descriptor once; late events from a superseded instance are dropped by instance token.
- Removed folders stop monitors and release security scopes.
- Rename recovery classification reads only recorded paths; a missing or unauthorized folder is reported as unavailable, and restore requests access to the exact recorded folder before taking the journal lock.
- The monitoring status separates cap omissions, open failures (missing/inaccessible/revoked), identity mismatches (the path now refers to a different directory), scan failures and metadata read failures. It states that directory monitoring covers added/removed/renamed entries rather than in-place file edits.
- File access prompts validate that the chosen folder matches the requested directory exactly.

## Malformed and Untrusted Audio Files

- Container parsing is delegated to TagLib through `TagLibAudioMetadata`. The app does not implement a defensive parser of its own.
- Audio loads have no app-level file-size or complexity limit. Large or adversarial files are bounded only by the platform and the dependency.
- The app reads a fingerprint and a full snapshot before editing; unreadable or changed files fail closed.
- Integration tests use only small, valid committed fixtures. There is no fuzzing, malformed-file corpus, or memory-safety testing in this repository.
- The external package's robustness is not verified here.

Do not treat "the app did not crash on a valid fixture" as evidence of parser hardening.

## Metadata Write Safety

Existing protections:

- All writes go through the package's expected-version and atomic-commit path.
- Semantic writes preflight exact field capabilities.
- File identity (path/device/inode) and revision are revalidated inside the mutation reservation.
- Write authority is a single coherent observation from a validated full read. A rename publishes an authority-free display projection while reserved; only a same-entry bounded full readback restores editing. A failed full readback is fail closed even if stat/version probes succeed, so a changed destination cannot be written from an old preview.
- Conflict policies never clear the expected version; filesystem-identity-changing replacements are refused. Changed revisions also require verified package audio continuity before automatic rebasing.
- A failed write leaves the snapshot and draft unchanged.
- A successful write with a failed reload is reported as committed-with-warning.
- Rename is two-phase and reports incomplete rollback locations. A durable rename journal is written and flushed before any file move, reports `prepared`/`committed` state after process termination, and is removed only after verified completion, verified rollback/restore, or explicit user acknowledgement. Rename moves use same-directory `renameatx_np(RENAME_EXCL)` on held directory descriptors, verify the destination entry identity after every move, and reject volumes that cannot provide exclusive renames before staging.
- A blocked rename-recovery path rejects metadata writes and rename planning until the recorded operation is restored or acknowledged; automatic reads never clear that state.
- Erase-all requires an unchanged revision and reports best-effort warnings.
- Batch writes are per-file and report partial success.

Data-loss characteristics:

- Writes are in place; there is no automatic backup or undo.
- A partial batch can leave some files changed and others not.
- An incomplete rename rollback can leave files at temporary or destination paths. The app retains a prepared recovery record and reports the observed locations; it does not repair them automatically. An explicit Restore Original Names action verifies each entry and never overwrites an occupied name.
- Rename recovery is proven for process termination on supported host filesystems. Power-loss durability is limited to the barriers the host filesystem actually supports and is reported honestly; no stronger durability is claimed.
- A second AudioMator instance in the same bundle container is serialized by the journal lock. Other programs remain external writers: a source-name change between verification and the rename syscall and an external destination change are outside the app transaction.
- A durability-uncertain commit may have reached disk; the app tells the user not to retry as a failure.
- A malicious or buggy external parser could corrupt a file; the package owns that risk.

Recommended user practice: keep backups, test unfamiliar formats on copies, and review previews before applying batch operations.

## Dependency and Supply-Chain Risk

- `TagLibAudioMetadata` is pinned to an exact version and revision.
- It brings TagLib 2.3.1 (LGPL-2.1/MPL-1.1) and utf8-cpp (Boost 1.0); see [Third-Party Notices](../THIRD_PARTY_NOTICES.md). The app bundle includes the corresponding license texts.
- The package source is not vendored and was not audited for this documentation.
- No SCA, SBOM, dependency signature verification, or automated vulnerability scanning is configured.
- CI has read-only permissions and no secrets.
- There is no notarization automation; a distributed build's signature status must be verified separately.

## Existing Protections vs Recommended Improvements

### Existing

- App Sandbox, Hardened Runtime, user-selected file access.
- No audio upload or telemetry.
- Security-scoped bookmarks, corruption quarantine.
- Version checks, atomic package commit, conflict policies.
- No diagnostic logging of metadata.
- Serialized file mutations and bounded reload timeouts.
- Serial CI with signing disabled.

### Recommended, not implemented

1. Add `com.apple.security.files.bookmarks.app-scope` and verify cross-launch restoration on a signed sandboxed build.
2. Consider a host policy for artwork downloads and WebKit subresources; page navigation is already restricted.
3. Keep network disclosures aligned with provider queries, fallback data, and embedded browsing behavior.
4. Add a privacy manifest if required by distribution policy.
5. Add malformed-file/fuzz coverage and file-size limits for untrusted imports.
6. Add dependency scanning or an SBOM.
7. Add signed/notarized release automation with verified artifacts.
8. Replace source-only logging policy tests with runtime log checks where possible.
9. Add a documented incident/rollback procedure for published releases.

## Responsible Disclosure

Report vulnerabilities privately to `AudioMator@lloydME.com`. See [`SECURITY.md`](../../SECURITY.md) for the reporting policy. Do not open a public issue with an exploit or a user's media file before coordination.

Include:

- affected version/build and macOS version,
- a description and impact,
- minimal reproduction steps,
- whether the issue is in AudioMator, the external package, or a service,
- any suggested fix.

## Verification Status

Verified by source inspection on 2026-11-18:

- entitlements and sandbox/hardened-runtime settings in `Config/` and `project.pbxproj`,
- no upload code, no `httpMethod`/body/auth headers, no telemetry, no Keychain usage,
- no diagnostic logging in app source; `SensitiveLoggingPolicyTests` detector covers `print`, `debugPrint`, `NSLog`, `os_log`, and `Logger`,
- bookmark corruption quarantine and persistence keys,
- identity-verified capped directory monitoring (128 per watched folder),
- request hosts, query parameters, embedded-page allowlist, and non-persistent WebKit storage,
- five bundled license texts in the current Debug build product,
- absence of signing/notarization/release automation.

Not verified:

- cross-launch bookmark restoration on a signed sandboxed build,
- runtime network behavior of WebKit and Apple-supplied hosts,
- robustness against malformed files,
- external package security,
- signed/notarized distribution,
- CI runner provisioning,
- whether the Release bundle contains the five license texts (the current artifact script does not inspect resources).

## Save Issue-Log Recovery

Issue-log persistence is best effort and never traps on an I/O failure. Each unreadable history is copied to its own quarantine file before replacement. If that copy fails, persistence is disabled for that store instance so the unreadable original is retained; new issues remain visible in memory. This log is diagnostic history, not a backup of audio metadata.

## Audio-Content Identity Limits

Session recovery decisions are sticky named reasons across automatic reads and are rechecked by the shared executor after reservation acquisition, including writes submitted with stale editor targets. Explicit Reload from Disk is the recovery path after resolving pending drafts: it clears a pending move decision for the same URL and a resolved-path failure only when the full read observed the same device/inode; a successor entry requires explicit review. Automatic activation, watched-folder reads, and quick reimport clear nothing, and the F2 journal decision survives normal reload.

Path/device/inode continuity does not establish unchanged audio content. The loader requests the package's optional audio-content identity. When a revision changes, automatic typed/raw conflict resolution and Metadata Editor baseline refresh require matching non-nil audio identities; the final write retains the original audio token and exact current revision. Different PCM at the same inode is rejected under every policy. Formats or layouts without package audio-identity support require explicit reload after a revision change. Unchanged exact revisions remain writable. Tokens are session-only and hashing adds streaming I/O; optimistic checks do not eliminate the filesystem check/rename race.

## Related Documents

- [Online Metadata](../Architecture/ONLINE_METADATA.md)
- [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md)
- [File Revision and Reload](../Architecture/FILE_REVISION_AND_RELOAD.md)
- [Acknowledgements and Privacy](../ACKNOWLEDGEMENTS_AND_PRIVACY.md)
- [Third-Party Notices](../THIRD_PARTY_NOTICES.md)
- [Configuration](../Reference/CONFIGURATION.md)
