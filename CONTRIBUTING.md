# Contributing to QLite

Thanks for taking the time to contribute.

## Getting set up

```bash
brew install xcodegen
make project   # generates QLite.xcodeproj
make test      # runs the unit tests
make run       # builds and launches the app
```

`QLite.xcodeproj` is generated from `project.yml` and is not tracked in git. Whenever you add,
move or delete a source file, run `make project` so the Xcode project picks it up.

`make strings` checks that every translation defines the same keys; CI runs it too.

## Where code goes

- **`Sources/QLiteKit`** — everything that talks to SQLite. It must not import AppKit or
  SwiftUI, because the QuickLook extensions link against it too. New database behaviour
  belongs here and should come with tests.
- **`Sources/QLite`** — the app: window management, menus, SwiftUI views and `DatabaseModel`,
  which is the single place UI actions turn into QLiteKit calls.
- **`Sources/QLitePreview` / `Sources/QLiteThumbnail`** — QuickLook extensions. Keep them
  cheap: they run for every file the user selects in Finder. They stay sandboxed even though
  the app does not, so they cannot assume access to a database's sidecar files — use
  `Database.openForReading(url:)`, which falls back on its own.
- **`Resources/Localization`** — user-visible strings. Never hard-code English in a view; add
  a key to every `.lproj/Localizable.strings` and read it with `L("key")`.

## Style

- Swift API Design Guidelines; 4-space indentation; no trailing whitespace.
- Comments explain *why*, not *what*. Skip comments that restate the code.
- Never interpolate user-supplied identifiers into SQL directly — use `quoteIdentifier(_:)`
  and bound parameters. There is a test (`testIdentifierQuotingSurvivesHostileNames`) that
  guards this.
- The app is deliberately not sandboxed (reading `-wal` sidecars, registering QuickLook
  extensions and binding default apps all require it). Do not add entitlements that assume a
  container.

## Pull requests

1. Fork and branch off `main`.
2. Add tests for new QLiteKit behaviour; `make test` and `make strings` must pass.
3. Update `CHANGELOG.md` under `## [Unreleased]`.
4. Describe what you changed and how you verified it, including any manual UI testing.

## Reporting bugs

Include your macOS version, the QLite version, and — where possible — a small database file
that reproduces the problem. If a query or schema operation failed, paste the exact error
message shown in the status bar.
