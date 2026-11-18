#!/usr/bin/env python3
"""Check relative links and anchors in AudioMator Markdown documentation.

Current-state documentation and repository instructions must keep working
links. Files under Docs/Engineering/HISTORY/ are a superseded archive: their
links may point at old locations, so those files are not sources of this check.
Links from current documents into the archive are checked for file existence.

Usage:
    python3 scripts/check-doc-links.py [--all]

Options:
    --all   Also check archived files under Docs/Engineering/HISTORY/.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

LINK_PATTERN = re.compile(r"\[[^\]]*\]\(([^)\s]+)")
HEADING_PATTERN = re.compile(r"^(#{1,6})\s+(.*)$")
EXTERNAL_PREFIXES = ("http://", "https://", "mailto:", "tel:")
ARCHIVE_PREFIX = "Docs/Engineering/HISTORY/"


def repository_root() -> Path:
    return Path(__file__).resolve().parent.parent


def tracked_markdown(root: Path) -> list[str]:
    try:
        output = subprocess.run(
            ["git", "ls-files", "*.md"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        return sorted({line for line in output.splitlines() if line})
    except (OSError, subprocess.CalledProcessError):
        return sorted(
            str(path.relative_to(root))
            for path in root.rglob("*.md")
            if ".git" not in path.parts and ".deriveddata-codex" not in path.parts
        )


def heading_slugs(path: Path) -> set[str]:
    slugs: set[str] = set()
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return slugs
    for line in text.splitlines():
        match = HEADING_PATTERN.match(line)
        if not match:
            continue
        heading = match.group(2).strip().lower()
        heading = re.sub(r"[^\w\u4e00-\u9fff\- ]", "", heading)
        slugs.add(heading.replace(" ", "-"))
    return slugs


def check_file(root: Path, relative_path: str, slug_cache: dict[str, set[str]]) -> list[str]:
    errors: list[str] = []
    source = root / relative_path
    try:
        text = source.read_text(encoding="utf-8")
    except OSError as error:
        return [f"{relative_path}: cannot read file ({error})"]

    for match in LINK_PATTERN.finditer(text):
        link = match.group(1)
        if link.startswith(EXTERNAL_PREFIXES):
            continue
        if link.startswith("#"):
            if link == "#":
                continue
            if link[1:].lower() not in slug_cache_for(root, relative_path, slug_cache):
                errors.append(f"{relative_path}: missing anchor {link}")
            continue

        target, _, anchor = link.partition("#")
        if not target:
            continue
        resolved = (source.parent / target).resolve()
        if not resolved.exists():
            errors.append(f"{relative_path}: missing target {link}")
            continue
        if anchor and resolved.suffix == ".md":
            try:
                cache_key = str(resolved)
                if cache_key not in slug_cache:
                    slug_cache[cache_key] = heading_slugs(resolved)
                if anchor.lower() not in slug_cache[cache_key]:
                    errors.append(f"{relative_path}: missing anchor {link}")
            except OSError:
                errors.append(f"{relative_path}: cannot read target of {link}")
    return errors


def slug_cache_for(root: Path, relative_path: str, cache: dict[str, set[str]]) -> set[str]:
    key = str((root / relative_path).resolve())
    if key not in cache:
        cache[key] = heading_slugs(root / relative_path)
    return cache[key]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--all",
        action="store_true",
        help="also check archived files under Docs/Engineering/HISTORY/",
    )
    arguments = parser.parse_args()

    root = repository_root()
    sources = tracked_markdown(root)
    if not arguments.all:
        sources = [path for path in sources if not path.startswith(ARCHIVE_PREFIX)]
    if not sources:
        print("check-doc-links: no Markdown files found", file=sys.stderr)
        return 1

    slug_cache: dict[str, set[str]] = {}
    errors: list[str] = []
    for relative_path in sources:
        errors.extend(check_file(root, relative_path, slug_cache))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        print(f"check-doc-links: {len(errors)} problem(s) in {len(sources)} file(s)", file=sys.stderr)
        return 1
    print(f"check-doc-links: {len(sources)} Markdown file(s) checked, no problems found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
