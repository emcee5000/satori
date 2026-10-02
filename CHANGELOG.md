# Changelog

All notable changes to Satori are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.3.3] - 2026-10-02

### Changed

- **Intel Macs supported.** The download is now a universal app that runs natively on Apple silicon and Intel.

### Fixed

- First-launch instructions now describe macOS 15 and later, where right-click → Open no longer works: open
  **System Settings → Privacy & Security** and click **Open Anyway**.

## [1.3.2] - 2026-10-02

### Changed

- Satori has its own address: **https://satorigtd.app**. Old `emcee5000.github.io/satori` links redirect there.
- Settings → Sync → Connect iPhone now links to https://satorigtd.app/app/. If you added the phone app to your
  Home Screen from the old address, add it again from the new one and paste the setup link from your Mac.

## [1.3.1] - 2026-10-02

### Fixed

- Weekly Review couldn't be clicked in the sidebar while its "due" label was showing.

## [1.3.0] - 2026-10-02

### Added

- **Undo and redo** (⌘Z / ⇧⌘Z) for changes to to-dos and projects. Undo only reverts what you changed on this
  Mac, never changes that arrived from the phone, and the undo syncs to the phone too.
- **Find** (⌘F): search to-do and project titles and notes, then jump to the result.
- **Repeating to-dos**: every day, weekday, week, month or year, on both the Mac and the phone. Completing one adds
  the next.
- **Capture from any app** with ⌃⌥Space (can be turned off in Settings).
- **Due-date reminders** as notifications on the morning a to-do is due, at a time you choose.
- **Connect iPhone**: a setup link (and QR code) in Settings → Sync fills in the repo and token on the phone.
- Sync commit messages say what changed, e.g. "Sync from phone: 1 added, 2 completed".
- Tests for sync merging, the shared file format, undo, search, reminders and repeats, run on every push.

### Fixed

- With `SATORI_DATA_DIR` set, sync is now always off, so test or demo data can't reach your real sync repo.

## [1.2.0] - 2026-10-02

### Changed

- **Near real-time sync.** Changes now reach the other device within a few seconds instead of up to a minute. Both
  apps check for changes every 3 seconds while open, using ETags so that unchanged checks don't count against the
  GitHub API rate limit, and upload about a second after an edit.

### Fixed

- On the phone, a sync no longer clears a half-typed capture or an edit in progress.

## [1.1.0] - 2026-10-02

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

[Unreleased]: https://github.com/emcee5000/satori/compare/v1.3.3...HEAD
[1.3.3]: https://github.com/emcee5000/satori/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/emcee5000/satori/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/emcee5000/satori/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/emcee5000/satori/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/emcee5000/satori/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/emcee5000/satori/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/emcee5000/satori/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/emcee5000/satori/releases/tag/v1.0.0
