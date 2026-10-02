# Changelog

All notable changes to Satori are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Project website at https://emcee5000.github.io/satori/, deployed automatically from `site/`.
- Screenshot in the README and on the website.
- `SATORI_DATA_DIR` environment variable to run Satori against a separate data folder.
- **Satori for iPhone**: a lightweight, installable web app at https://emcee5000.github.io/satori/app/ with capture,
  lists, projects and editing. Works offline.
- **Sync** between the Mac and the phone through a private GitHub repo you own (Settings → Sync). The newest edit
  wins per item, deletions stick, and every sync is a commit.

### Fixed

- Jumping to a list with ⌥⌘ + letter now puts keyboard focus in the new list, so arrow keys work right away.

## [1.0.1] - 2026-10-02

### Changed

- Simpler app icon: a glowing ensō around a single block cursor.
- Releases are now built and published automatically when a version is tagged.

## [1.0.0] - 2026-10-02

The first public release.

### Added

- GTD lists: Inbox, Today, Next Actions (grouped by context), Scheduled, Waiting For, Someday/Maybe, Reference,
  Projects, Logbook and Trash.
- Process Inbox: a guided clarify flow (actionable? → under 2 minutes? → project? → delegate? → defer), with a key for every answer.
- Projects with a desired outcome, progress rings, and warnings when a project has no next action.
- Weekly Review checklist (Get Clear, Get Current, Get Creative) with inline capture.
- Menu-bar quick capture.
- Keyboard-first navigation: first-letter shortcuts to move items (⌘ + letter) and jump to lists (⌥⌘ + letter),
  arrow keys between panes, Space to capture, and Return/Esc to edit.
- `@context` tagging inline while typing a to-do.
- A status line showing the keys available in the current pane, hover tooltips, and a cheat sheet (`?` or ⌘/).
- Adjustable text size (⌘+, ⌘−, ⌘0).
- Ghostty-inspired terminal theme and a glowing ensō icon.
- Local JSON storage with tolerant decoding and protection against overwriting unreadable files.

[Unreleased]: https://github.com/emcee5000/satori/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/emcee5000/satori/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/emcee5000/satori/releases/tag/v1.0.0
