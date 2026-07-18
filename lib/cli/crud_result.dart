import '../data/database.dart';

// Re-export so the formatter (which renders an impact) needn't import the whole
// data layer just for this one type.
export '../data/database.dart' show DeleteImpact;

// ── Result of a destructive `delete` verb ──────────────────────────────────
// The create/edit/archive verbs render their entity through the shared
// list-item shapes (see output_formatter). Delete is the one that needs its own
// shape: it carries the cascade-impact count so the CLI can warn (or report)
// exactly what goes with the parent, mirroring the GUI's "Delete everything".

/// Outcome of a `delete`. When [deleted] is false the command **refused** for
/// lack of `--force`; [impact] then describes what *would* be removed. When
/// true, the cascade ran and [impact] describes what was removed with the
/// parent.
class DeleteOutcome {
  final String kind; // 'client' | 'project' | 'task' | 'entry'
  final String id;
  final String label; // human name for messages
  final DeleteImpact impact;
  final bool deleted;

  const DeleteOutcome({
    required this.kind,
    required this.id,
    required this.label,
    required this.impact,
    required this.deleted,
  });
}
