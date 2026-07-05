# timedart

**Track your hours the way you think about your work — client, job, task — and turn them into an invoice in a couple of clicks.**

timedart is a fast, local-first time tracker for people who bill by the hour. Your data lives on your machine, the timer is always one keypress away, and every recorded minute rolls straight up into a per-job PDF invoice. Built with Flutter, it runs as a native desktop app and adapts down to a phone from the same codebase.

---

## Why timedart

- **Structured, not scattered.** Organise work as **clients → jobs → tasks**, and record each timed session as an **entry** under a task. Your history reads like your workload, not a flat log.
- **A timer that stays out of the way.** Start, pause, resume, and finish with a single key — from anywhere in the app. The running session survives while you edit a client, add a job, or preview an invoice.
- **Rates that just resolve.** Set a default rate on a client, override it per job or per task; every entry bills at the right rate automatically.
- **Invoices in seconds.** Pick a job and a date range, preview the itemised entries and total, and export a clean PDF — no spreadsheet round-trip.
- **Yours, on your disk.** Everything persists locally in SQLite. No account, no cloud, no sync — nothing leaves your machine.
- **Keyboard-first.** The whole app is drivable without the mouse, vim-style. Press `?` any time for the full shortcut map.
- **One app, every screen.** A roomy two-pane layout on desktop folds into a drawer on narrow windows — same features throughout.

## Feature tour

- **Timer** — `hh:mm:ss` count-up bound to a task, with start / pause / resume / finish. Name a session or let it inherit the task title.
- **Clients, jobs & tasks** — full create / edit / delete for each, in quick modal editors. Deletes are guarded so you can't accidentally erase billable history.
- **Entries** — adjust the task, note, start time, and duration of any recorded segment after the fact.
- **Invoicing** — per-job, date-ranged, itemised at the effective rate, exported to a branded PDF. Pick the profile and set an invoice number at export; the date range is chosen in a compact modal.
- **Invoice branding** — design how invoices look and read: reusable **templates** (colours, logo, font) and **profiles** (business identity, bank / payment details, currency, optional tax) that each carry a template. Edit them under **App Settings → Branding** with a live, A4-proportioned preview beside the form.
- **Adaptive UI** — persistent side panel + content pane when there's room; a drawer when there isn't.
- **Design** — a considered Material 3 theme in the timedart green, Urbanist throughout, and a single design-token source so it stays consistent.

## Keyboard

timedart is built to be flown from the keyboard. Navigation is identical across the side panel and the tracker, so the same keys work wherever your cursor is.

| Keys | Action |
| --- | --- |
| `j` / `k` · `↓` / `↑` | move the cursor |
| `gg` / `G` | jump to first / last |
| `l` / `→` | open / expand |
| `h` / `←` | collapse / go to parent |
| `Enter` | select / activate |
| `e` | edit the focused item |
| `Tab` · `Ctrl`+`←`/`→` · `Ctrl-w` `h`/`l` | switch panes |
| `/` | search |
| `Ctrl`+`,` | open Settings (branding) |
| `Space` | start / pause / resume the timer (from any pane) |
| `f` · `i` | finish · focus the description |
| `a` / `A` | add (job / client in the panel · task / entry in the tracker) |
| `d` | delete, from inside an edit modal |
| `Enter` / `Ctrl`+`S` · `Esc` | save · cancel in any editor |
| `?` | show the full shortcut overlay |

## Running it

Requires the Flutter SDK ([install guide](https://docs.flutter.dev/get-started/install)).

```sh
flutter pub get
flutter run -d linux      # native desktop (primary target)
flutter run -d chrome     # web, for a quick demo
flutter analyze           # static analysis (should be clean)
flutter test              # unit tests
flutter build linux       # release build
```

For iterative work there's `./dev.sh`: it runs `build_runner watch` (regenerating `*.g.dart` from
drift on save) alongside `flutter run -d linux`, and hot-reloads on changes under `lib/`.

The database lives in the platform app-support directory (e.g. `~/.local/share/` on Linux), not the
project folder.

## Under the hood

Flutter + [drift](https://drift.simonbinder.eu) (SQLite) with foreign keys enforced, so deletes can
never orphan data. Organised **feature-first** — each feature owns its widgets, with shared
primitives and design tokens pulled out:

```
lib/
├── main.dart              wires the database into the adaptive shell
├── constants/             design tokens, Material 3 theme, formatting helpers
├── data/database.dart     drift tables + queries (Clients / Jobs / Tasks / TimeEntries
│                          · invoice Templates / Profiles)
├── features/
│   ├── shell/             adaptive master–detail shell, side panel, branding-mode panel, shortcut overlay
│   ├── tracker/           timer, task list, task/entry editors
│   ├── clients/ · jobs/   client & job editors
│   ├── invoices/          per-job PDF invoicing + invoice branding
│   │                      (template / profile editors, shared live A4 preview)
│   └── deletions.dart     shared, guarded delete flows
└── widgets/               shared UI primitives
```

The shell holds the selected job (what the timer records against) and the content pane's state.
Client / job / task / entry editing happens in adaptive modals over the pane; invoicing and the
branding editors live in the content pane itself — a settings mode that swaps the side panel for
Templates / Profiles sections, driven by the same keyboard navigation.

## Roadmap

Core is complete and in daily-driver shape: persistent tracking across clients, jobs, and tasks;
full editing everywhere; per-job PDF invoices with customisable branding; and end-to-end keyboard
control. Next on the horizon:

- PDF polish — print-safe margins, and A4 / Letter as a page-size setting.
- Stored, immutable invoice snapshots.
- Bulk actions to clear out old clients and jobs in one deliberate step.
- Archiving jobs you're done with, to keep the working set tidy.
- Ongoing design polish.

## Development

Work lands one change per branch, reviewed as a PR and squash-merged so `main` stays a clean,
linear history. `flutter analyze` and `flutter test` should both pass before every PR.
