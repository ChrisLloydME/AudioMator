# AudioMator Wiki

AudioMator is a local-first audio metadata editor for macOS and iPadOS. It is built around a TagLib-powered metadata pipeline and focuses on inspecting, organizing, editing, verifying, and enriching local music files.

## Navigation

- [Project Overview](Project-Overview.md)
- [Installation and Build](Installation-and-Build.md)
- [Core Features](Core-Features.md)
- [User Guide](User-Guide.md)
- [Architecture](Architecture.md)
- [Repository Layout](Repository-Layout.md)
- [Configuration](Configuration.md)
- [Development Guide](Development-Guide.md)
- [Testing Guide](Testing-Guide.md)
- [FAQ](FAQ.md)
- [Troubleshooting](Troubleshooting.md)
- [Contributing](Contributing.md)
- [Release Notes and Versioning](Release-Notes-Draft.md)

## Where to Start

End users should start with [Project Overview](Project-Overview.md), [Core Features](Core-Features.md), [User Guide](User-Guide.md), and [FAQ](FAQ.md).

Developers and maintainers should start with [Architecture](Architecture.md), [Repository Layout](Repository-Layout.md), [Configuration](Configuration.md), [Development Guide](Development-Guide.md), and [Testing Guide](Testing-Guide.md).

## Project Boundaries

AudioMator performs ordinary metadata editing locally. Network access happens only when a user explicitly starts an online feature such as MusicBrainz lookup, iTunes metadata or artwork lookup, LRCLIB lyrics lookup, GitHub release-note lookup, or the manual macOS update check.

The iPadOS app is intentionally not a full macOS feature clone. It uses document picking and sheet-based tools, while watched folders and the multi-window desktop workflow are macOS-only.
