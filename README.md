# time_tracker

A local-first **time-tracking desktop app** that records time against jobs and clients and
(eventually) generates PDF invoices. Built with Flutter for one codebase across Linux desktop and
Android, with web available for demos.

## What it does

- Start / pause / resume / finish a timer and record the session as a **time entry** (`hh:mm:ss`).
- Organise entries under **jobs** (each with a code, title, and optional rate) tied to **clients**
  (each with an optional default rate).
- Effective rate resolves per entry as `job.rate ?? client.defaultRate`.
- Entries persist locally in SQLite via [drift](https://drift.simonbinder.eu), with foreign keys
  enforced so deletes can't orphan data.
- Create, edit, and delete clients and jobs inline; **per-job PDF invoices** — pick a date range,
  preview the itemised entries at the effective rate, and export to a PDF file.
- **Adaptive layout**: a persistent side panel beside the content on wide windows; the panel collapses
  into a drawer when narrow. Editing/invoicing happens in the content pane (master–detail), not on
  separate screens.

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
│   │   ├── adaptive_shell.dart  owns selection + which detail view is shown (sealed _Detail)
│   │   └── side_panel.dart      clients→jobs nav; select/edit/add/invoice actions
│   ├── tracker/               the timer and its session history
│   │   ├── timer_view.dart      selection-driven timer
│   │   ├── timer_controls.dart  start/pause/resume/finish controls
│   │   └── time_entry_list.dart recorded-entry list (filtered to the selected job)
│   ├── clients/               client_form.dart — create/edit/delete client
│   ├── jobs/                  job_form.dart — create/edit/delete job
│   └── invoices/              per-job PDF invoicing (read-only leaf)
│       ├── invoice_view.dart    date range → itemised preview → export
│       └── invoice_pdf.dart     pure PDF builder (bytes out)
└── widgets/                   shared UI primitives (ContentAppBar, ContentBody)
```

**State flow:** `AdaptiveShell` holds `_selectedJobId` (what the timer records against) and a sealed
`_Detail` value for the content pane (timer / edit-job / edit-client / invoice). The side panel sends
actions up via callbacks; children read state via props. Editing and invoicing render in the content
pane rather than as pushed routes.

## Roadmap

Tracked as [GitHub issues](https://github.com/tm-ox/time_tracker/issues). **Core complete:**
persistence, jobs, clients & rates, adaptive layout, full CRUD, and per-job PDF invoices. Open:
visual polish (#20), job archive (#12), bundle JetBrains Mono (#22), stored/immutable invoice
snapshots (#26).
