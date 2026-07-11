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

## Principles

- **The invoice is a print artifact, not app chrome.** Preview/PDF styling follows the user's profile/template and is deliberately independent of `AppTextStyles`/theme, so re-skinning the app never mutates an exported invoice. Persisted, user-defined styling is separate from global app styling.
- **Shared primitives, separate semantics.** The palette, spacing scale, radius scale, and font family live once in `tokens.dart`; both the app theme and the invoice's own tokens *reference* those primitives. Invoice semantic choices (label weight, muted alpha, masthead gaps) stay owned by the invoice, not the app.
- **Parity is structural, not comment-enforced.** Preview and PDF agree because they consume the same `InvoiceLayoutPlan`, not because a `// Mirrors …` comment says so.
