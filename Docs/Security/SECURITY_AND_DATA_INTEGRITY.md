# Security and Data Integrity

This document describes the security-relevant behavior that exists in AudioMator, separates protections from recommended improvements, and states what has not been verified. It does not claim that AudioMator is secure against any particular threat.

## Scope and Trust Model

AudioMator is a sandboxed macOS app that edits files the user selects. Its main trust boundaries are:

1. **User-selected files** — untrusted input parsed by TagLib; modified in place after explicit user action.
2. **The external metadata package** — trusted to parse and write containers, but not audited by this repository.
3. **Online services** — untrusted HTTP responses consumed by provider clients.
4. **Embedded web content** — Apple/MusicBrainz pages loaded in WebKit.
5. **Local persisted state** — preferences, bookmarks, and the save issue log.

There is no server component, account system, telemetry, or remote code execution.

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
| Bookmarks | `UserDefaults` | Security-scoped data; separate per bundle ID |
| Preferences | `UserDefaults` | Includes conflict policy and UI state |
| Save issue log | `Application Support/AudioMator/SaveIssueLog.json` | 200 entries; file names + messages |
| Raw metadata dump | In memory / pasteboard | Includes full path and tag values; not logged |

There is no database, cache of audio content, Keychain item, or credential.

The raw metadata dump intentionally contains the full file path and tag values. It is displayed only on user request and can be copied to the pasteboard. Treat it as sensitive when sharing diagnostics.

## Logging and Telemetry

- App source contains no `print`, `debugPrint`, `NSLog`, `os_log`, or `Logger` calls. `SensitiveLoggingPolicyTests` enforces the first three and the removed metadata logger markers.
- The policy test does not cover `os_log` or `Logger`, and it scans only `AudioMator/`, not the external package.
- There is no telemetry, analytics, crash-reporting SDK, or remote logging.
- The save issue log stores file names and warning/error strings. It is local and user-visible. The app does not intentionally store full paths there, but backend error strings are not formally guaranteed to be value-free.

## Network Activity

All app requests are HTTP GETs. There is no upload path, multipart body, or request authentication.

| Service | Hosts contacted by the app | Data sent |
| --- | --- | --- |
| MusicBrainz | `musicbrainz.org` | Lucene query terms and identifiers derived from tags or filename/path fallback |
| iTunes | `itunes.apple.com` | search term, country, media/entity/limit, album/track ID, or UPC |
| Apple artwork | Apple-returned `artworkUrl100` host, `is5-ssl.mzstatic.com`, `a5.mzstatic.com` | image GET only |
| LRCLIB | `lrclib.net` | track name, artist, album, duration |
| GitHub | `api.github.com` | repository release request; no auth token |
| GitHub Releases page | `github.com` | opened in the default browser, not requested by the app |

### Accuracy caveats

The in-app disclosure registry lists a fixed set of hosts and summaries. Current code has these gaps:

1. **Apple artwork hosts are not allow-listed.** `thumbnailURL` and `standardURL` keep whatever host Apple returned; only hires/uncompressed URLs are rewritten. Additional `*.mzstatic.com` shards could be contacted.
2. **Embedded web pages are not disclosed as network sources.** iTunes `trackViewUrl`/`collectionViewUrl` and MusicBrainz pages load in `WKWebView` with default configuration and no host allow-list. WebKit may load subresources and cookies beyond the API hosts.
3. **Some listed data is not actually sent.** The disclosure text mentions iTunes track number, duration, artist ID, and catalog ID; those are not URL parameters. It also mentions MusicBrainz disc information; the Lucene builder does not emit a disc clause.
4. **Filename/path-derived text can be sent** by MusicBrainz, iTunes, and LRCLIB when tags are missing. Only the LRCLIB text explicitly mentioned filename fallback.
5. **`github.com` is not an app request host.** It is opened externally by `NSWorkspace`.
6. **Release notes include prereleases.** The client filters drafts only and requests the first 50 releases.

These are documentation defects to fix as behavior is clarified; they are not claims that data is being misused by a third party.

### Transport

- All app request URLs use HTTPS.
- No App Transport Security exceptions.
- No certificate pinning or custom trust evaluation.
- Default `URLSession.shared` behavior; no custom proxy/cookie/cache policy.

## Additional File Access Notes

- Directory monitoring holds one `O_EVTONLY` descriptor per monitored directory, capped at 128 per watched folder, with the root always monitored.
- Removed folders stop monitors and release security scopes.
- The monitoring status reports omitted/failed/scanned-error counts.
- `securityScopedSupplementalMutationDirectoryURLs` is declared and cleaned up but never populated; it is effectively dead state.
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
- Conflict policies never clear the expected version; replacement is refused.
- A failed write leaves the snapshot and draft unchanged.
- A successful write with a failed reload is reported as committed-with-warning.
- Rename is two-phase and reports incomplete rollback locations.
- Erase-all requires an unchanged revision and reports best-effort warnings.
- Batch writes are per-file and report partial success.

Data-loss characteristics:

- Writes are in place; there is no automatic backup or undo.
- A partial batch can leave some files changed and others not.
- An incomplete rename rollback can leave files at temporary or destination paths; the app reports locations but does not repair them.
- A durability-uncertain commit may have reached disk; the app tells the user not to retry as a failure.
- A malicious or buggy external parser could corrupt a file; the package owns that risk.

Recommended user practice: keep backups, test unfamiliar formats on copies, and review previews before applying batch operations.

## Dependency and Supply-Chain Risk

- `TagLibAudioMetadata` is pinned to an exact version and revision.
- It brings TagLib, which is LGPL/MPL licensed; see [Third-Party Notices](../THIRD_PARTY_NOTICES.md).
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
2. Allow-list hosts for artwork downloads and embedded web pages.
3. Correct the in-app network disclosure and add filename/path fallback to all provider summaries.
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

Verified by source inspection:

- entitlements, sandbox/hardened-runtime settings,
- no upload code, no telemetry, no credential storage,
- no diagnostic logging in app source,
- bookmark corruption handling,
- capped directory monitoring,
- request hosts and parameters,
- absence of signing/notarization/release automation.

Not verified:

- cross-launch bookmark restoration on a signed sandboxed build,
- runtime network behavior of WebKit and Apple-supplied hosts,
- robustness against malformed files,
- external package security,
- signed/notarized distribution,
- CI runner provisioning.

## Related Documents

- [Online Metadata](../Architecture/ONLINE_METADATA.md)
- [Metadata Pipeline](../Architecture/METADATA_PIPELINE.md)
- [File Revision and Reload](../Architecture/FILE_REVISION_AND_RELOAD.md)
- [Acknowledgements and Privacy](../ACKNOWLEDGEMENTS_AND_PRIVACY.md)
- [Third-Party Notices](../THIRD_PARTY_NOTICES.md)
- [Configuration](../Reference/CONFIGURATION.md)
