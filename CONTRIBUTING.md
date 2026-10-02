# Contributing to Satori

Thanks for your interest in Satori! This guide covers how to report problems, suggest ideas and send changes.

## Guiding principles

Satori aims to stay **small, native and keyboard-first**. Before proposing a feature, ask:

- **Is it GTD?** Features should support capture, clarify, organize, reflect or engage.
- **Does it work from the keyboard?** Every new action needs a shortcut and a mention in the status line or cheat sheet.
- **Does it keep the app simple?** No accounts, no network, no third-party dependencies.

When in doubt, open an issue to discuss it before writing code.

## Reporting bugs

Open a [bug report](https://github.com/emcee5000/satori/issues/new?template=bug_report.md) and include:

- your macOS version and how you installed Satori (release or source)
- the steps to reproduce, what you expected, and what happened
- a screenshot if it's a visual problem

Please don't attach your `data.json`, since it contains your tasks. If the bug depends on your data, describe its shape instead.

## Suggesting features

Open a [feature request](https://github.com/emcee5000/satori/issues/new?template=feature_request.md) that
describes the problem you're trying to solve, not only the solution.

## Development setup

You need macOS 14+ and the Swift toolchain (the Command Line Tools are enough).

```sh
git clone https://github.com/emcee5000/satori.git
cd satori
swift build          # compile
swift run            # run the app from the terminal
./scripts/build-app.sh   # build a full Satori.app into ./build
```

`swift run` uses your real data file. To experiment safely, point Satori at a scratch folder instead:

```sh
SATORI_DATA_DIR=/tmp/satori-dev swift run
```

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a tour of the code.

## Making changes

1. Fork the repo and create a branch from `main` (for example, `fix/inbox-focus` or `feature/light-theme`).
2. Keep changes focused. One pull request should do one thing.
3. Match the surrounding style:
   - SwiftUI with the `@Observable` `Store` as the single source of truth.
   - Route all text through `.scaledFont(...)` so ⌘+ / ⌘− keep working.
   - Use colours from `Theme`, not system colours.
   - Add a `.help("…")` tooltip with the shortcut for any new control.
4. Make sure `swift build` finishes with **no errors or warnings**.
5. Try your change in the running app, from the keyboard as well as the mouse.
6. Update the README, the in-app cheat sheet (`ShortcutsView.swift`) and `CHANGELOG.md` if behaviour or shortcuts change.
7. Open a pull request and fill in the template.

### Changing the data format

`data.json` belongs to users, so changes must be backward compatible:

- New fields need defaults and must be decoded with `decodeIfPresent` (see the `init(from:)` extensions in `Models.swift`).
- Never rename or remove a stored field without a migration.

### Changing the icon

The icon is drawn in code by `scripts/make-icon.swift`. Edit that file, run `./scripts/build-app.sh`, and refresh
`docs/icon.png` from the generated iconset (the 256 px image).

## Releasing (maintainers)

Releases are automated.

1. Make sure user-visible changes are listed under `## [Unreleased]` in `CHANGELOG.md`.
2. Run the release script from a clean `main`:
   ```sh
   ./scripts/release.sh 1.2.3
   ```
   It moves the Unreleased notes under the new version, updates `VERSION`, commits, tags `v1.2.3` and pushes.
3. The **Release** workflow builds `Satori.app` on GitHub and publishes the release with `Satori.zip` and the
   changelog notes.

Use patch versions (1.0.**x**) for fixes and polish, and minor versions (1.**x**.0) for new features.
Dependabot keeps the GitHub Actions up to date with weekly pull requests.

## Code of Conduct

By taking part, you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
