# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-03

First release.

### Browsing and editing
- Sidebar listing tables, views, indexes and triggers, with a filter field and per-object
  actions (rename, drop, empty, copy `CREATE`, query).
- Paged data browser with server-side sorting and a free-form `WHERE` filter, so large tables
  stay responsive.
- Row editing: insert, update and delete. Rows are addressed by `rowid`, falling back to the
  primary key for `WITHOUT ROWID` tables; views are detected as read-only.
- NULLs, blobs and numeric values are rendered distinctly; blobs round-trip through `x'…'`
  hex literals in the row editor.

### Schema management
- Create tables with a column builder: type, PRIMARY KEY, AUTOINCREMENT, NOT NULL, UNIQUE,
  DEFAULT, composite keys and `WITHOUT ROWID`.
- Add, rename and drop columns; rename and drop tables; create and drop indexes.
- Structure tab showing columns, foreign keys and indexes; DDL tab showing the original
  `CREATE` statement.

### Queries
- Multi-statement SQL editor with `⌘R`, `EXPLAIN QUERY PLAN`, per-run timing and
  affected-row counts, plus a result grid and query templates.
- Export any result set or table page to CSV, TSV, JSON or `INSERT` statements.

### Journal and WAL files
- Reads `-wal`, `-shm` and `-journal` sidecars, so data committed to the write-ahead log but
  not yet merged into the main file is visible in the app and in QuickLook previews.
- Degrades gracefully when the sidecars cannot be opened in place: a temporary copy of the
  whole file set first, then an `immutable` read that is labelled as showing the last
  checkpointed state.
- Opening a `-wal` / `-shm` / `-journal` file opens the database it belongs to.
- **Checkpoint WAL** action and a journal-file panel in the Info tab.

### QuickLook
- Preview extension showing tables, columns, row counts and sample rows.
- Thumbnail extension drawing a database card with the first table names.
- Both extensions can be enabled, disabled and re-registered from Settings.

### Settings
- **General** — language, and whether to read sidecar files.
- **File Types** — which extensions count as databases, user-defined extensions, and binding
  QLite as their default application.
- **QuickLook** — extension state and re-registration.

### Localization
- English and Simplified Chinese, switchable at runtime without relaunching.
- `Scripts/check-localization.sh` verifies that every translation defines the same keys.

### Maintenance and tooling
- `PRAGMA integrity_check`, `VACUUM`, and a database info panel with page size, encoding,
  journal mode and user version.
- DMG and PKG installers, a Makefile, and a GitHub Actions workflow that checks translations,
  runs the tests and builds installers for tags.

[1.0.0]: https://github.com/Clizo1209/QLite/releases/tag/v1.0.0
