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
flutter test              # unit tests
flutter build linux       # release build (verifies the native build)
```

For iterative work there's `./dev.sh`: it runs `build_runner watch` (regenerating `*.g.dart` from
drift on save) alongside `flutter run -d linux`, and hot-reloads on any change under `lib/` (debounced).
See the comments at the bottom of the script for the manual reload/restart/quit commands.

The local database lives in the platform app-support directory (e.g. `~/.local/share/` on Linux),
not the project folder.

## Keyboard navigation

The side panel is fully keyboard-drivable in the wide layout (arrow keys or vim keys). A row cursor
moves over the flattened list of clients and the jobs of expanded clients:

| Key | Action |
| --- | --- |
| `j` / `↓`, `k` / `↑` | move the cursor down / up |
| `l` / `→` / `Enter` | expand a collapsed client · step into an expanded one · open a job |
| `h` / `←` | collapse an expanded client · from a job, jump to its parent |
| `gg` / `G` | jump to the first / last row |
| `n` / `N` | next / previous job row (handy while searching) |
| `/` | focus the search field (`Esc` returns to the cursor) |
| `Tab`, `Ctrl+←/→` | toggle focus between the side panel and the tracker pane |
| `Ctrl-h` / `Ctrl-l` | focus the panel / tracker directly |
| `Ctrl-w` then `h` / `l` | vim window-motion equivalent |

The focused row shows a subtle outline, distinct from the highlighted *selected* job.

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
│   │   ├── adaptive_shell.dart  owns selection + detail view (sealed _Detail) + keyboard focus
│   │   ├── side_panel.dart      clients→jobs nav; select/edit/add/invoice + keyboard row cursor
│   │   └── panel_rows.dart      pure flattener: (clients, jobs, query, expanded) → row list
│   ├── tracker/               the timer and its session history
│   │   ├── timer_view.dart      selection-driven timer
│   │   ├── timer_controls.dart  start/pause/resume/finish controls
│   │   └── time_entry_list.dart recorded-entry list (filtered to the selected job)
│   ├── clients/               client_form.dart — create/edit/delete client
│   ├── jobs/                  job_form.dart — create/edit/delete job
│   └── invoices/              per-job PDF invoicing (read-only leaf)
│       ├── invoice_view.dart    date range → itemised preview → export
│       └── invoice_pdf.dart     pure PDF builder (bytes out)
└── widgets/                   shared UI primitives (ContentBody, confirm dialog, …)
```

**State flow:** `AdaptiveShell` holds `_selectedJobId` (what the timer records against) and a sealed
`_Detail` value for the content pane (timer / edit-job / edit-client / invoice). The side panel sends
actions up via callbacks; children read state via props. Editing and invoicing render in the content
pane rather than as pushed routes.

## Development workflow

Work lands one issue per branch, reviewed as a PR and squash-merged so `main` stays a clean,
linear history of feature-sized commits.

```sh
git switch -c feat/<slug>            # branch off main, one issue per branch

# ... implement ...

flutter analyze && flutter test      # both must pass before a PR
flutter build linux                  # verify the native build

git commit                           # small, focused commits; reference the issue (#NN)
git push -u origin feat/<slug>
gh pr create --fill                   # open the PR (closes #NN)
```

- **Review** the diff before merging — `gh pr view --web`, or the `/review` and `/code-review`
  helpers if you're driving this with Claude Code.
- **Squash-merge** so the PR collapses to a single commit on `main`:

  ```sh
  gh pr merge --squash --delete-branch
  git switch main && git pull         # sync your local main
  ```

- Stacked PRs: if a branch builds on another unmerged branch, base the PR on that branch and
  retarget it to `main` once the parent merges.

## Roadmap

Tracked as [GitHub issues](https://github.com/tm-ox/time_tracker/issues). **Core complete:**
persistence, jobs, clients & rates, adaptive layout, full CRUD, per-job PDF invoices, and
keyboard navigation (#39). Open: visual polish (#20), job archive (#12), bundle JetBrains Mono
(#22), stored/immutable invoice snapshots (#26), content-pane keymap (#41).
