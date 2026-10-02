# Architecture

Satori is a single-target Swift package with no dependencies. It's built with SwiftUI and the Observation
framework, and it targets macOS 14+.

## Layout

```
Package.swift
Sources/Satori/
  SatoriApp.swift         App entry, scenes (window, settings, menu bar), menu commands
  Store.swift             Observable app state, persistence, queries and mutations
  Models.swift            TaskItem, Project, Bucket, Destination, Pane, AppData
  ContentView.swift       Split view, sidebar, list header, sheets
  TaskListView.swift      The to-do list, rows, context menu and keyboard handling
  DetailViews.swift       Inspector, project header, Projects overview, project picker
  ProcessInboxView.swift  The guided clarify flow
  ReviewAndCapture.swift  Weekly Review, menu-bar capture, Settings
  ShortcutsView.swift     The keyboard cheat sheet
  Sync.swift              GitHub sync: merging, Keychain token, polling
  Theme.swift             Colours and the status line
  TextScale.swift         App-wide text zoom (scaledFont)
scripts/
  build-app.sh            Builds and optionally installs Satori.app
  make-icon.swift         Draws the app icon
site/                     The project website (GitHub Pages, deployed on push)
site/app/                 The phone web app (core.js = data model and merge, app.js = UI and sync)
docs/                     Documentation and the README icon
```

## State: `Store`

`Store` is an `@Observable`, `@MainActor` class and the single source of truth. Views read it from the
environment (`@Environment(Store.self)`).

- **`data: AppData`** is everything that gets saved. Any change schedules a debounced save (0.4 s), and the app
  saves again on quit.
- **UI state** that several views share lives on the store too: `selection` (current sidebar destination),
  `showInspector`, sheet flags, `focusRequest` and `activePane`.
- **Queries** like `tasks(for:)` compute each list from the flat task array. Lists aren't stored separately, so a
  task can't end up in two places.
- **Mutations** (`send(_:to:)`, `toggleComplete`, `assign(_:toProject:)` and so on) are the only way views change data.

## The GTD model

Each `TaskItem` has a `bucket` (inbox, next, waiting, someday, reference) plus optional `projectID`, `context`,
`deferUntil` (start date), `due`, and a `starred` flag for Today. The sidebar lists are derived from those fields:

| List | Rule |
|------|------|
| Inbox | bucket is `inbox` |
| Today | starred or due by today, not scheduled, not someday/reference |
| Next Actions | bucket is `next`, not scheduled, and its project (if any) is active |
| Scheduled | `deferUntil` is in the future |
| Waiting For | bucket is `waiting`, not scheduled |
| Someday/Maybe | bucket is `someday` (plus someday projects) |
| Logbook / Trash | `completedAt` / `trashedAt` is set |

`send(_:to:)` translates "move this to list X" into field changes. For example, moving to Next clears the start
date so the item actually appears there.

A project is **stalled** when it's active and has no unscheduled next action.

## Keyboard focus

Keyboard navigation is built from three pieces:

1. **`Pane`** (`sidebar`, `list`, `newTask`, `inspector`) names the focusable areas.
2. **`store.focusRequest`** asks a pane to take focus. Each view watches it, claims requests meant for it, then
   clears the request. This works across separate views and for views that haven't appeared yet.
3. **`store.activePane`** records where focus is, which drives the hints in the `StatusLine`.

Menu commands use `@FocusedValue(\.selectedTaskID)`, so ⌘ + letter acts on the selected to-do whichever list is showing.

## Styling

- All text goes through `.scaledFont(_:)`, which applies the monospaced design and the user's text-zoom level.
  macOS ignores Dynamic Type, so this is how ⌘+ / ⌘− work. macOS lists reset fonts inside rows, so row text sets
  its font explicitly.
- All colours come from `Theme`.

## Sync

Sync is optional and uses a private GitHub repo as the meeting point. `SyncService` (Mac) and `app.js` (web)
follow the same loop: fetch `data.json` through the GitHub contents API, merge, and write it back only if
the merged copy differs. A write includes the file's `sha`, so if another device wrote first, GitHub rejects it
and the loop fetches and merges again.

Merging (`AppData.merge` on the Mac, `Satori.merge` in `core.js`):

- **Items:** each task or project carries `updatedAt`; the more recent copy wins. Local mutations only bump
  `updatedAt` when something actually changed.
- **Deletions:** permanent deletes are recorded in `deleted` (ID → date) and win over any copy. Records older than
  90 days are dropped.
- **Settings** (contexts, review state): the Mac does a three-way merge against the copy from the last successful
  sync; the web app doesn't edit settings and always takes the synced copy.

Dates are written as ISO 8601 without fractional seconds; both sides also accept fractional seconds.

## Data file format

`~/Library/Application Support/Satori/data.json` is pretty-printed JSON with ISO 8601 dates:

```json
{
  "contexts": ["@home", "@work"],
  "lastReview": "2026-10-02T16:00:00Z",
  "reviewChecks": [],
  "projects": [
    { "id": "UUID", "title": "Launch website", "outcome": "Site is live",
      "isSomeday": false, "createdAt": "…", "completedAt": null, "trashedAt": null }
  ],
  "tasks": [
    { "id": "UUID", "title": "Email Sam the draft", "notes": "", "bucket": "next",
      "projectID": "UUID", "context": "@work", "waitingOn": "", "deferUntil": null,
      "due": null, "starred": false, "createdAt": "…", "updatedAt": "…", "completedAt": null, "trashedAt": null }
  ],
  "deleted": { "UUID": "2026-10-02T16:00:00Z" }
}
```

`bucket` is one of `inbox`, `next`, `waiting`, `someday` or `reference`. Missing fields fall back to defaults
when decoding, which keeps older and newer files compatible.
