#!/usr/bin/env python3
"""Advisory checker for the AudioMator commit-message contract.

The contract is documented in Docs/Development/COMMIT_MESSAGES.md. This tool
reports violations; it does not rewrite history or fail a build by itself.

Usage:
  python3 scripts/check-commit-messages.py --range origin/main..HEAD
  python3 scripts/check-commit-messages.py --all

Exit codes: 0 when no violations, 1 when violations are found, 2 when git
cannot read the requested range.
"""

import argparse
import re
import subprocess
import sys

TYPES = (
    "feat",
    "fix",
    "docs",
    "test",
    "perf",
    "build",
    "ci",
    "chore",
    "refactor",
    "style",
    "revert",
    "merge",
)

SUBJECT_RE = re.compile(
    r"^(?P<type>[a-z]+)(?:\((?P<scope>[a-z0-9][a-z0-9-]*)\))?: (?P<summary>.+)$"
)
MERGE_RE = re.compile(r"^merge: integrate \S+(?: into \S+)?(?: \(PR #\d+\))?$")
LOWERCASE_START = re.compile(r"^[a-z0-9]")
MAX_SUBJECT = 72

RECORD_SEPARATOR = "\x1e"
FIELD_SEPARATOR = "\x1f"


def read_commits(range_spec):
    """Return commit metadata for range_spec in git log order."""
    fmt = f"%H{FIELD_SEPARATOR}%P{FIELD_SEPARATOR}%B{RECORD_SEPARATOR}"
    result = subprocess.run(
        ["git", "log", "--no-show-signature", f"--format={fmt}", range_spec],
        capture_output=True,
        text=True,
    )
    if result.returncode:
        raise SystemExit(
            f"cannot read git range {range_spec!r}: {result.stderr.strip()}"
        )

    commits = []
    for record in result.stdout.split(RECORD_SEPARATOR):
        record = record.strip("\n")
        if not record:
            continue
        sha, parents, message = record.split(FIELD_SEPARATOR, 2)
        subject, _, body = message.partition("\n")
        commits.append(
            {
                "sha": sha,
                "subject": subject,
                "parents": parents.split(),
                "body": body.strip("\n"),
            }
        )
    return commits


def check_subject(commit):
    """Return (errors, warnings) for one commit."""
    subject = commit["subject"]
    is_merge = len(commit["parents"]) > 1
    errors = []
    warnings = []

    if not subject:
        return ["empty subject"], warnings

    if subject != subject.rstrip():
        errors.append("subject has trailing whitespace")

    if subject.startswith("Merge "):
        return (
            [
                "GitHub-style merge subject; use 'merge: integrate <branch> (PR #N)'"
            ],
            warnings,
        )

    match = SUBJECT_RE.match(subject)
    if not match:
        errors.append(
            "subject must be 'type(scope): imperative summary' with a known type"
        )
        return errors, warnings

    type_name = match.group("type")
    summary = match.group("summary")

    if type_name not in TYPES:
        errors.append(f"unknown type '{type_name}'")

    if subject.endswith("."):
        errors.append("subject must not end with a period")

    if len(subject) > MAX_SUBJECT:
        errors.append(f"subject is {len(subject)} characters (maximum {MAX_SUBJECT})")

    if type_name == "merge":
        if not MERGE_RE.match(subject):
            errors.append(
                "merge subject must be 'merge: integrate <branch> (PR #N)' or "
                "'merge: integrate <source> into <target>'"
            )
        if not is_merge:
            warnings.append("'merge:' subject on a commit with one parent")
    else:
        if is_merge:
            errors.append("merge commit must use a 'merge: integrate …' subject")
        if not LOWERCASE_START.match(summary):
            errors.append(
                "summary must start lowercase with a verb, for example "
                "'add …', not 'Add …'"
            )

    return errors, warnings


def duplicate_subject_warnings(commits):
    seen = {}
    for commit in commits:
        seen.setdefault(commit["subject"], []).append(commit["sha"])
    warnings = []
    for subject, shas in seen.items():
        if len(shas) > 1:
            joined = ", ".join(sha[:10] for sha in shas)
            warnings.append(f"duplicate subject '{subject}' in {joined}")
    return warnings


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--range",
        dest="range_spec",
        default="origin/main..HEAD",
        help="git revision range to check (default: origin/main..HEAD)",
    )
    group.add_argument(
        "--all",
        action="store_true",
        help="check every commit reachable from main",
    )
    args = parser.parse_args(argv)

    range_spec = "main" if args.all else args.range_spec
    commits = read_commits(range_spec)

    errors_by_commit = []
    warnings_by_commit = []
    for commit in commits:
        errors, warnings = check_subject(commit)
        if errors:
            errors_by_commit.append((commit, errors))
        if warnings:
            warnings_by_commit.append((commit, warnings))

    warnings = duplicate_subject_warnings(commits)
    error_count = sum(len(entries) for _, entries in errors_by_commit)
    warning_count = sum(len(entries) for _, entries in warnings_by_commit) + len(
        warnings
    )

    for commit, entries in errors_by_commit:
        print(f"{commit['sha'][:10]} {commit['subject']}")
        for entry in entries:
            print(f"  error: {entry}")

    for commit, entries in warnings_by_commit:
        print(f"{commit['sha'][:10]} {commit['subject']}")
        for entry in entries:
            print(f"  warning: {entry}")

    for entry in warnings:
        print(f"warning: {entry}")

    print(
        f"checked {len(commits)} commits in {range_spec!r}: "
        f"{error_count} errors, {warning_count} warnings"
    )
    return 1 if error_count else 0


if __name__ == "__main__":
    sys.exit(main())
