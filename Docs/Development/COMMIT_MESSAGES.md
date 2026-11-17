# Commit Messages

Status: current. This page is the canonical commit-message contract for AudioMator. It applies to every new commit on `main`, whether written by a contributor or an automated agent. `AGENTS.md` repeats the rules that must hold without opening this page, and `CONTRIBUTING.md` links here. Commits created before this contract may not match it; do not rewrite published history to enforce it without the maintainer's explicit approval.

## The rule

Every commit has exactly one subject line and, optionally, a body.

```text
type(scope): imperative summary
```

- `type` is one of the types below.
- `scope` is optional, lowercase, and kebab-case.
- The summary starts with a lowercase verb in the imperative mood and ends without a period.

The subject must describe one logical change. Do not mix an unrelated refactor, formatting pass, or dependency bump into a behavior commit.

## Types

| Type | Use for | Example |
| --- | --- | --- |
| `feat` | New user-visible behavior or capability | `feat: add batch field copy and cut to Metadata Exchange` |
| `fix` | Defect fix or hardened boundary | `fix: guard unsafe field transfers and verify on-disk results` |
| `docs` | Documentation, records, and evidence only | `docs: record published 0.8.0 release gate` |
| `test` | Tests, fixtures, and test support | `test: assert literal legacy date owners` |
| `perf` | Measured performance or concurrency improvement | `perf: reuse unchanged files during watched-folder rescans` |
| `build` | Xcode project, toolchain, package resolution, or build scripts | `build: lower deployment targets for legacy WebKit compatibility` |
| `ci` | Hosted or local continuous-integration gates | `ci: require complete named test evidence` |
| `chore` | Dependency adoption, housekeeping, and maintenance | `chore: adopt published TagLibAudioMetadata 0.8.1` |
| `refactor` | Behavior-preserving restructuring | `refactor: migrate package API references to field identities` |
| `style` | Formatting and presentation-only changes | `style: refine metadata field transfer control layout` |
| `revert` | Reverting an earlier change | `revert: restore conservative glass HUD styling` |
| `merge` | Integrating a branch | `merge: integrate internal-numbering-recovery (PR #53)` |

If a change genuinely spans two types, split it. Do not invent new types.

## Scope

Use a scope only when it names an established area and the change is confined to it. Good scopes are short, lowercase, and kebab-case, for example `musicbrainz`, `settings`, `inspector`, `watched-folders`, or `metadata-editor`. Omit the scope when the change touches several layers or the type already makes the area obvious. Do not invent a scope for a single commit.

## Summary

- Write in the imperative: `add`, `fix`, `guard`, `record`, `remove`, `reuse`, not `Added` or `Adds`.
- Start with a lowercase letter or digit. Put proper nouns and acronyms later so the sentence still starts with a verb: `feat: add XCTest coverage for metadata logic`, not `feat: XCTest coverage…`.
- Keep it at most 72 characters; aim for 50 or fewer.
- Do not end with a period.
- Do not use a trailing `!` unless the change is a breaking contract change; record breaking changes in the body instead.
- Do not include commit hashes, issue numbers as decoration, or "This commit…" phrasing.
- Do not wrap the subject.

## Merge commits

GitHub's generated `Merge pull request #N from owner/branch` subject is not used.

- Pull-request merge: `merge: integrate <branch> (PR #N)`, using the PR head branch exactly as it appears in the PR, for example `merge: integrate taglib080Integration (PR #51)`.
- Local integration merge: `merge: integrate <source> into <target>`, for example `merge: integrate main into feat/acknowledgments`.
- Keep the merge body short: one line naming the integrated work is enough. Do not paste a second subject into the body.

## Reverts

Use `revert: <imperative summary of what is restored or removed>`, for example `revert: restore iTunes Search link mode title`. Put the reason in the body, and keep a `This reverts commit <sha>.` line when that helps traceability.

## Bodies

A body is optional. Add one when the subject alone would leave the reason, boundary, or verification unclear.

- Separate the body from the subject with one blank line.
- Explain why the change exists and what it changes at a boundary; do not restate the subject.
- Note migrations, compatibility consequences, or intentionally deferred work explicitly.
- Wrap prose near 72 columns. Keep trailers such as `Signed-off-by` and `Co-authored-by` at the end.

## Examples

These are real AudioMator subjects before and after the contract was applied in November 2026.

| Before | After |
| --- | --- |
| `Guard unsafe metadata field transfers and verify on-disk results` | `fix: guard unsafe field transfers and verify on-disk results` |
| `Record published 0.8.0 release gate and unsigned archive acceptance` | `docs: record published 0.8.0 release gate` |
| `merge: pull request #53 from ChrisLloydME/internal-numbering-recovery` | `merge: integrate internal-numbering-recovery (PR #53)` |
| `Adopt published TagLibAudioMetadata 0.8.1` | `chore: adopt published TagLibAudioMetadata 0.8.1` |
| `revert: HUD styling to conservative glass design` | `revert: restore conservative glass HUD styling` |

## Rewording before publishing

- Amend or reword local, unpushed commits freely: `git commit --amend` for the last commit, `git rebase -i <base>` for a local series.
- Do not rewrite commits that are already on `origin/main` without the maintainer's explicit approval. A message-only rewrite still changes every descendant SHA and requires a force-push.
- When approved, back up first (`git branch backup/pre-rewrite-<date> <sha>` and a bundle), change only message content, verify that trees, parents, author, committer, and bodies are unchanged, then publish with `git push --force-with-lease`.
- Never combine a message rewrite with content changes.

## Checking

`scripts/check-commit-messages.py` is an advisory checker for this contract. It validates the subject format, type, scope shape, lowercase imperative start, length, trailing punctuation, merge form, and duplicate subjects. It reports violations but does not rewrite history or fail a build by itself.

```bash
python3 scripts/check-commit-messages.py --range origin/main..HEAD
python3 scripts/check-commit-messages.py --all
```

The range form checks the commits a branch adds; `--all` checks `main`. Older commits may still fail; that is expected for history written before this contract.

## Related Documents

- [Documentation Maintenance](DOCUMENTATION.md)
- [Testing](TESTING.md)
- [AGENTS.md](../../AGENTS.md)
- [Contributing](../../CONTRIBUTING.md)
