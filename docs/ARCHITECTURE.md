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
  Theme.swift             Colours and the status line
  TextScale.swift         App-wide text zoom (scaledFont)
scripts/
  build-app.sh            Builds and optionally installs Satori.app
  make-icon.swift         Draws the app icon
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
      "due": null, "starred": false, "createdAt": "…", "completedAt": null, "trashedAt": null }
  ]
}
```

`bucket` is one of `inbox`, `next`, `waiting`, `someday` or `reference`. Missing fields fall back to defaults
when decoding, which keeps older and newer files compatible.
