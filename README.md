# time_tracker

A local-first **time-tracking desktop app** that records time against jobs and clients and
(eventually) generates PDF invoices. Built with Flutter for one codebase across Linux desktop and
Android, with web available for demos.

## What it does

- Start / pause / resume / finish a timer and record the session as a **time entry** (`hh:mm:ss`).
- Organise entries under **jobs** (each with a code, title, and optional rate) tied to **clients**
  (each with an optional default rate).
- Effective rate resolves per entry as `job.rate ?? client.defaultRate`.
- Entries persist locally in SQLite via [drift](https://drift.simonbinder.eu).
- **Adaptive layout**: a persistent side panel beside the timer on wide windows; the panel collapses
  into a drawer when narrow.

## Running it

Requires the Flutter SDK ([install guide](https://docs.flutter.dev/get-started/install)).

```sh
flutter pub get
flutter run -d linux      # Linux desktop (primary target)
flutter run -d chrome     # web, for a quick demo
flutter analyze           # static analysis (should be clean)
```

The local database lives in the platform app-support directory (e.g. `~/.local/share/` on Linux),
not the project folder.

## Project structure

Organised **feature-first** — each feature owns its widgets, with shared building blocks pulled out:

```
lib/
├── main.dart                  app entry; wires the database into AdaptiveShell
├── constants/                 cross-cutting design + helpers
│   ├── tokens.dart            AppTokens: spacing, breakpoints, radii, type, palette, icon sizes
│   ├── theme.dart             buildAppTheme() — Material 3 theme from tokens
│   └── format.dart            formatting helpers (e.g. Duration.hms)
├── data/
│   └── database.dart          drift database, tables, queries (Clients / Jobs / TimeEntries)
├── features/
│   ├── shell/                 the adaptive master–detail shell
│   │   ├── adaptive_shell.dart  owns selection state; switches panel vs drawer by width
│   │   └── side_panel.dart      clients→jobs navigation panel (drives selection)
│   ├── tracker/               the timer and its session history
│   │   ├── timer_view.dart      selection-driven timer
│   │   ├── timer_controls.dart  start/pause/resume/finish controls
│   │   └── time_entry_list.dart recorded-entry list
│   ├── clients/               client management (list, form, screen)
│   └── jobs/                  job management (screen)
└── widgets/                   shared UI primitives (ContentAppBar, ContentBody)
```

**State flow:** selection state (`_selectedJobId`) is lifted into `AdaptiveShell`; the side panel sets
it (callbacks up), the timer reads it (props down).

## Roadmap

Tracked as [GitHub issues](https://github.com/tm-ox/time_tracker/issues). Done: persistence, jobs,
clients & rates, adaptive layout. Next: editing/deleting records (#18, #19), polish (#20), then PDF
invoices (#6).
