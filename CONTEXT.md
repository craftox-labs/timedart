# timedart

Domain language for the timedart time-tracking + invoicing app. One term per concept — when several words exist, the chosen one is canonical and the rest are listed under `_Avoid_`. Keep future work (and architecture reviews) speaking this vocabulary.

## Language

### Tracking

**Client**:
A person or organisation the work is billed to. Owns projects and a default rate.
_Avoid_: customer, account.

**Project**:
A billable body of work for one client. Carries an optional rate override and a reference code. Top of the tracking hierarchy under a client.
_Avoid_: job (the old name, renamed in schema v7), matter.

**Task**:
A named unit of work within a project. First-class entity between project and entry.
_Avoid_: activity, item.

**TimeEntry**:
A single tracked interval against a task — a start, a duration in seconds, and an optional note. The atom that a timer produces and an invoice line consumes.
_Avoid_: log, record, session (a session is the live timer, not the persisted interval).

**Timer session**:
The live, in-progress timing of a task before it becomes a `TimeEntry` — start/tick/finish state.
_Avoid_: stopwatch, tracker.

### Invoicing

**Invoice**:
A request for payment assembled from a project's time entries over a period. Rendered two ways from one `InvoiceDocument`: an on-screen preview and an exported PDF.
_Avoid_: bill, statement.

**InvoiceDocument**:
The resolved, pure domain model of an invoice — parties, lines, tax, totals, payment fields — with no layout or rendering concerns. The single input to layout.
_Avoid_: invoice model, DTO.

**Profile**:
The sender's billing identity — business name, logo, contact, bank/payment details, region, and which template it uses. Owns what appears on an invoice.
_Avoid_: account, sender, business.

**Template**:
The chosen visual look for an invoice (font, etc.), selected by a profile. Distinct from **theme** (reserved for future app-wide UI theming).
_Avoid_: theme, style, skin.

**Region**:
The sender's jurisdiction (`InvoiceRegion`) — drives tax label, currency, buyer tax-ID label, bank field set, and reverse-charge rules.
_Avoid_: locale, country.

### Architecture

**InvoiceLayoutPlan**:
The pure-data result of resolving an `InvoiceDocument` for layout — ordered section descriptors (masthead, party block, recipient grid, line table, totals, payments) with all presence decisions made and all geometry (column/cell widths, chunked payment rows) resolved. Both the preview and the PDF painter consume it as their one argument; it is the test surface where preview/PDF parity is asserted. Produced by `InvoiceLayout.resolve()`.
_Avoid_: scene, render tree, view model.

**Painter (adapter)**:
A renderer that turns an `InvoiceLayoutPlan` into one output toolkit — the Flutter preview painter and the `pdf` painter are the two adapters at this seam. A painter makes no layout decisions; it only draws primitives.
_Avoid_: renderer (loosely), view.

**EditorSession**:
The dirty / save / rebaseline lifecycle of a content-pane editor, extracted as one pure `ValueNotifier`-based object (no `BuildContext`). It holds a baseline **Editor snapshot** and reports `dirty` as `snapshot() != baseline`; `save()` persists then rebaselines; `rebaseline()` adopts the on-screen values as baseline after an async default-fill. The profile/template editors and the shell's unsaved-changes guard all read one session, replacing the per-editor `_computeDirty` copies and the shell's loose `_editorDirty`/`_currentEditorSave`.
_Avoid_: form controller, dirty flag.

**Editor snapshot**:
A small immutable value class capturing every edited field of one editor with an explicit `==` — the field-by-field diff relocated out of `_computeDirty`. Reverting a field to its original value makes the snapshot re-equal the baseline, clearing dirty for free. Also the record a Cancel reverts the on-screen fields to.
_Avoid_: draft, model.

**LogoValue**:
A logo (image bytes + MIME) compared by **content**, not identity, so an unchanged logo in an editor snapshot doesn't read as a dirty edit.
_Avoid_: image ref.

**Entity editor** (`EntityForm` + `showEntityEditor`):
The shared modal chrome for the four CRUD editors (client / project / task / entry) — the modal counterpart to the content-pane `EditorSession`. `showEntityEditor<T>` is the one adaptive presenter (centred `Dialog` wide / bottom sheet narrow); `EntityForm` is the one scaffold (title + the form's fields + Delete/Cancel/Save action row + the `d`-to-delete hotkey). Each form supplies only its fields and its submit/cancel/delete logic (validation, DB write, save-error snackbar, popping the route) — the chrome is shared, the entity logic is not.
_Avoid_: dialog, sheet (for the concept), form base class.

**Keymap**:
The single registry of the app's keyboard model — a list of `Binding`s mapping key strokes to a `KeyIntent`, tagged with a `scope` and the help metadata. `Keymap.resolve(event, detector, scopes)` answers key→intent (chords included) for the four raw-key handlers (shell, side panel, settings panel, tracker); the help dialog iterates the same registry, so it can't drift. Flutter's `Shortcuts`/`Actions` can't express the vim multi-key sequences, hence a custom registry over the existing raw `onKeyEvent` handlers.
_Avoid_: shortcuts table, key map (two words).

**Binding**:
One registry entry: a `KeyIntent`, its `scope`, the single-press `strokes` (alternatives) or a chord (`prefix` + completion strokes), and the help caps/description. Panes own **intent→action** (the same intent drives different code per pane); the Keymap owns **key→intent**.
_Avoid_: shortcut, mapping.

**Binding scope** (`KeyScope`):
Where a binding is live — `global` (pane switch, help, search, settings, timer), `list` (shared cursor nav), `panel`/`tracker`/`settings` (pane-specific), `editor` (help-only; the edit modals bind these in their own `CallbackShortcuts`). A handler resolves against its own scope(s) plus `global`.
_Avoid_: mode, context.

**ChordDetector**:
Per-handler state for an in-progress multi-key sequence (`gg`, `G`, `Ctrl-w h/l`) — the armed prefix. One instance per raw-key handler, `reset()` on a focus excursion. Replaces the hand-rolled `_pendingG`/`_pendingCtrlW` copies; the pane that owns the completion keys (h/l) must own the chord, which is why each list pane holds its own detector.
_Avoid_: pending flag, sequence state.

**Backup (BackupSnapshot / codec)**:
The whole database as one portable file (PRD #189, Phase 1). `BackupSnapshot` is an in-memory copy of every table's rows (typed drift data classes, value equality); `readBackupSnapshot` fills it via the same public drift accessors all reads use. `encodeBackup`/`decodeBackup` serialise it to/from self-describing JSON bytes carrying a version envelope — a `format` marker, the backup `formatVersion`, and the DB `schemaVersion` it was written at (the tag a later, forward-compatible importer keys off across the Phase 2 UUID migration). `decodeBackup` validates and throws `BackupFormatException` (never a partial result). `restoreBackup` imports a decoded backup **replace-all** in one transaction (wipe every table, re-insert with ids preserved; all-or-nothing) — it `sanitizeSnapshot`s first (drops rows whose FK parent is absent — orphans a real DB can carry because SQLite never enforces FKs retroactively — and nulls a dangling `templateId`, returning a `SnapshotRepair` count the UI surfaces), rejects a backup from a *newer* schema (`BackupIncompatibleException`), and re-keys a *pre-v13 (integer-keyed)* export to UUIDs on decode (`_rekeyLegacyGraph`, keyed off the envelope `schemaVersion`) so an older backup still restores into the UUID schema. Deliberately Flutter-free (lives in `lib/data`) so the future CLI can reuse it; blob columns (the profile logo) are base64-encoded via a small `ValueSerializer` wrapper since drift's default JSON serializer can't represent bytes. UI glue lives in the shell (Settings → General → Export/Import, replace-all behind a confirm); the platform save helper is `lib/util/save_file.dart` (a generalised `pdf_saver`), the picker `lib/util/pick_file.dart`.
_Avoid_: dump, snapshot (for the file), sync (unrelated — that's Phase 4).

**Row audit timestamps** (`createdAt` / `updatedAt`):
Every table carries `createdAt` and `updatedAt` (schema v11, PRD #189 Phase 2a) — the change-tracking sync will do last-write-wins on. New rows get them from a Dart `clientDefault`; `updatedAt` is re-stamped on every update at the single `AppDatabase` mutation choke-point (no feature code writes drift directly, so it can't be bypassed). The columns are nullable purely so the `ALTER ADD COLUMN` migration is legal (SQLite forbids a non-constant default on add); the v11 migration backfills existing rows to the migration time.
_Avoid_: modified date, mtime.

**Soft-delete (`deletedAt` tombstone)**:
The six content tables carry a nullable `deletedAt` (schema v12, PRD #189 Phase 2b). Deletes are **soft** — `deleteX` sets `deletedAt = now` (and bumps `updatedAt`) instead of a hard `DELETE`, so a removal propagates across devices once sync lands (a hard DELETE just reappears from the other device). NULL = live. Every read/watch query filters `deletedAt IS NULL`; the referential guards (`DeleteBlockedException`) count only **live** children, so a parent whose children are all tombstoned can itself be deleted. Two deliberate exceptions stay unfiltered so history still resolves: `templateById`/`profileById` (a since-deleted template/profile a past invoice points at) and `ensureDefaultProject`'s lookup (which *resurrects* a tombstoned `GENERAL` rather than colliding on its unique `code`). `readBackupSnapshot` also stays unfiltered on purpose — it dumps tombstones so deletes travel through a backup/restore. Distinct from `Clients.archivedAt`, which is a user-facing "archive" state, not a sync tombstone.
_Avoid_: trash, recycle (UI concepts); "archive" (means `archivedAt`).

**UUIDv7 primary keys**:
Every content-table PK and FK is a text **UUIDv7** (schema v13, PRD #189 Phase 2c) — not an autoincrement int — because sync needs ids that don't collide across devices (`AppSettings` keeps its natural text key). New rows get one from the pure `IdGenerator` (`lib/data/id.dart`, `idGen.newId()`) via a drift `clientDefault`; methods that must return the new id (`addClient`/`addProject`/`addTask`/`insertTemplate`/`insertProfile`/`ensureDefaultProject`) generate it up-front, since drift's `insert()` yields the int rowid, not the text id. The v12→v13 migration re-keys **in place**: it drops orphans (like `sanitizeSnapshot`), builds an old-id→UUIDv7 map per table in temp tables, then rebuilds each table via `TableMigration` whose `columnTransformer` remaps id + every FK through `CAST(... AS TEXT)` subqueries — affinity-agnostic, since the historical rebuild steps leave id columns with mixed int/text affinity.
_Avoid_: GUID, ULID, autoincrement (the old model), rowid (drift's, unrelated to the PK).

**DB-backed timer (`ActiveTimer` / `TimerStore`)**:
The running timer is a persisted, syncable DB row (schema v14; `description` added v15; PRD #189 Phase 3), not just the in-memory `TimerSession` singleton — so it survives a restart and (once sync lands) travels across devices. At most one **live** (`deletedAt IS NULL`) `ActiveTimer` row exists. The in-progress session note (`description`) rides on the row too, persisted on each transition, so a recovered timer restores its note (the UI seeds its field from `TimerStore.recoveredDescription`); `finish` reads the live field for the final entry. Elapsed time is **derived, never ticked into the DB**: `accumulatedSeconds` freezes tracked time at each pause and `runningSince` marks the current run's start (`null` = paused), so live elapsed = `accumulatedSeconds + (runningSince == null ? 0 : now − runningSince)`. The row is written only on transitions (start/pause/resume/finish), which keeps sync quiet and lets a crash mid-run recover true elapsed from the wall clock rather than counted ticks. `TimerStore` (`features/tracker/timer_store.dart`, Flutter-free for CLI reuse) owns the row and wraps the unchanged pure `TimerSession`; it exposes the same transitions plus `recover()` (rebuild the session from the row on startup) and, on `finish`, writes the `TimeEntry` then **tombstones** the row (Phase 2b). `TimerController` holds one `TimerStore` and drives the per-second UI ticker; the shell recovers it in `initState`.
_Avoid_: stopwatch, session (that's the in-memory `TimerSession`), presence (there's no real-time channel — sync is eventual/LWW).

## Principles

- **The invoice is a print artifact, not app chrome.** Preview/PDF styling follows the user's profile/template and is deliberately independent of `AppTextStyles`/theme, so re-skinning the app never mutates an exported invoice. Persisted, user-defined styling is separate from global app styling.
- **Shared primitives, separate semantics.** The palette, spacing scale, radius scale, and font family live once in `tokens.dart`; both the app theme and the invoice's own tokens *reference* those primitives. Invoice semantic choices (label weight, muted alpha, masthead gaps) stay owned by the invoice, not the app.
- **Parity is structural, not comment-enforced.** Preview and PDF agree because they consume the same `InvoiceLayoutPlan`, not because a `// Mirrors …` comment says so.
