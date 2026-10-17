# Security Policy

## Reporting a Vulnerability

Report security issues privately to:

**AudioMator@lloydME.com**

Please do not open a public issue containing an exploit, a user's media file, or sensitive metadata before coordination.

Include:

- affected AudioMator version and build,
- macOS version,
- a description of the issue and its impact,
- minimal reproduction steps,
- whether the issue is in AudioMator, the `TagLibAudioMetadata` package, or a third-party service,
- any suggested fix or mitigation.

You should receive an acknowledgment. There is no bug bounty program and no guaranteed response time.

## Supported Versions

Security fixes are developed against the current `main` branch and the latest published release. Older releases are not maintained with backports unless the maintainer decides otherwise.

## Scope

In scope:

- sandbox or entitlement bypasses,
- unintended file access, modification, or data loss,
- unsafe handling of untrusted audio files in AudioMator's own code,
- disclosure of local data through logs, caches, or network requests,
- injection or unsafe rendering in embedded web content,
- supply-chain or build-process issues in this repository.

Out of scope for this repository:

- vulnerabilities in macOS, WebKit, TagLib, or `TagLibAudioMetadata` themselves; report those upstream (AudioMator can coordinate a mitigation),
- issues requiring an already-compromised Mac or administrator access,
- service availability or rate limits,
- social engineering.

## Security-Relevant Behavior

AudioMator:

- is sandboxed with user-selected read/write and outgoing network access,
- uses security-scoped bookmarks for persistent folder access,
- does not upload audio file content,
- has no telemetry, analytics, or crash reporting,
- does not store credentials or API tokens,
- serializes file mutations and uses the dependency's expected-version commit guard,
- does not automatically install updates.

Known limitations and unverified areas are documented in [Security and Data Integrity](Docs/Security/SECURITY_AND_DATA_INTEGRITY.md). Do not assume a protection that is listed as recommended or unverified.

## Disclosure

Coordinate a disclosure timeline with the maintainer. Once a fix is available, the issue and its impact may be described in release notes without exposing user data or exploit details that would put users at risk.
