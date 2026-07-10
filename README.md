# timedart

**Track your hours the way you think about your work — client, project, task — and turn them into an invoice in a couple of clicks.**

timedart is a fast, local-first time tracker for people who bill by the hour. Your data lives on your machine, the timer is always one keypress away, and every recorded minute rolls straight up into a per-project PDF invoice. Built with Flutter, it runs as a native desktop app and adapts down to a phone from the same codebase.

---

## Why timedart

- **Structured, not scattered.** Organise work as **clients → projects → tasks**, and record each timed session as an **entry** under a task. Your history reads like your workload, not a flat log.
- **A timer that stays out of the way.** Start, pause, resume, and finish with a single key — from anywhere in the app. The running session survives while you edit a client, add a project, or preview an invoice.
- **Rates that just resolve.** Set a default rate on a client, override it per project or per task; every entry bills at the right rate automatically.
- **Invoices in seconds.** Pick a project and a date range, preview the itemised entries and total, and export a clean PDF — no spreadsheet round-trip.
- **Yours, on your disk.** Everything persists locally in SQLite. No account, no cloud, no sync — nothing leaves your machine.
- **Keyboard-first.** The whole app is drivable without the mouse, vim-style. Press `?` any time for the full shortcut map.
- **One app, every screen.** A roomy two-pane layout on desktop folds into a drawer on narrow windows — same features throughout.

## Feature tour

- **First-run onboarding** — a brief branded intro on launch, then a skippable setup that explains how timedart works and captures your business identity (name, logo, email) and region — which auto-sets your currency and tax label — straight into your default invoice profile. Re-run it any time from **Settings → General**.
- **Timer** — `hh:mm:ss` count-up bound to a task, with start / pause / resume / finish. Name a session or let it inherit the task title.
- **Clients, projects & tasks** — full create / edit / delete for each, in quick modal editors. Deletes are guarded so you can't accidentally erase billable history.
- **Entries** — adjust the task, note, start time, and duration of any recorded segment after the fact.
- **Invoicing** — per-project, date-ranged, itemised at the effective rate, exported to a branded PDF. Pick the profile and set an invoice number at export; the date range is chosen in a compact modal.
- **Invoice branding** — design how invoices look and read: reusable **templates** (colours, logo, font) and **profiles** (business identity, region-aware bank / payment details, currency, optional tax) that each carry a template. Manage them under **Settings**: selecting one opens a read-only preview first, with an Edit action that reveals the form (protected by an unsaved-changes prompt if you navigate away mid-edit).
- **Adaptive UI** — persistent side panel + content pane when there's room; a drawer when there isn't.
- **Design** — a considered Material 3 theme in the timedart green, Mona Sans throughout, and a single design-token source so it stays consistent.

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
| `Ctrl`+`,` | open Settings |
| `Space` | start / pause / resume the timer (from any pane) |
| `f` · `i` | finish · focus the description |
| `a` / `A` | add (project / client in the panel · task / entry in the tracker) |
| `d` | delete, from inside an edit modal |
| `Ctrl`+`S` · `Esc` | save · cancel in any editor |
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
├── main.dart              wires the database into the root gate + adaptive shell
├── constants/             design tokens, Material 3 theme, formatting helpers
├── data/database.dart     drift tables + queries (Clients / Projects / Tasks / TimeEntries
│                          · invoice Templates / Profiles · AppSettings)
├── features/
│   ├── onboarding/        first-run gate, startup intro, stepped setup wizard
│   ├── shell/             adaptive master–detail shell, side panel, Settings panel, shortcut overlay
│   ├── tracker/           timer, task list, task/entry editors
│   ├── clients/ · projects/   client & project editors
│   ├── invoices/          per-project PDF invoicing + invoice branding
│   │                      (template / profile editors, shared live A4 preview)
│   └── deletions.dart     shared, guarded delete flows
└── widgets/               shared UI primitives
```

`main.dart` mounts a root gate that plays the intro, runs first-run onboarding when needed, then hands
off to the shell. The shell holds the selected project (what the timer records against) and the content
pane's state. Client / project / task / entry editing happens in adaptive modals over the pane; invoicing
and the branding editors live in the content pane itself — a Settings mode that swaps the side panel for
Templates / Profiles / General sections, driven by the same keyboard navigation. Opening a template or
profile shows it read-only first; Edit reveals the form in place, and leaving with unsaved changes
prompts to save, discard, or stay.

## Roadmap

Core is complete and in daily-driver shape: first-run onboarding; persistent tracking across clients,
projects, and tasks; full editing everywhere; per-project PDF invoices with customisable, region-aware
branding; and end-to-end keyboard control. Next on the horizon:

- PDF polish — print-safe margins, and A4 / Letter as a page-size setting.
- Stored, immutable invoice snapshots.
- Bulk actions to clear out old clients and projects in one deliberate step.
- Archiving projects you're done with, to keep the working set tidy.
- A richer, illustrated "how it works" step in onboarding.
- Ongoing design polish.

## Development

Work lands one change per branch, reviewed as a PR and squash-merged so `main` stays a clean,
linear history. `flutter analyze` and `flutter test` should both pass before every PR.

## License

timedart is open source under the [MIT License](LICENSE) — © 2026 Craftox.
