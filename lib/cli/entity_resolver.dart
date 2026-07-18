import '../data/database.dart';
import 'exit_codes.dart';

// ── Project / task selectors (id-or-name) ──────────────────────────────────
// Verbs accept a stable UUID *or* a human-friendly name for a project/task, so
// scripting is unambiguous while interactive use stays ergonomic (PRD #270,
// user story 7). Resolution goes through the shared `lib/data` layer and
// respects soft-delete (only live entities are selectable). A selector that
// matches nothing, or more than one entity, is a distinct, clearly-messaged
// error (see [CliExit.unknownEntity] / [CliExit.ambiguousEntity]). Reused by
// the write verbs now and by `list`/`log` in the next slice.

/// Resolve [query] to a single live [Project]. Matches, in order of precedence:
/// an exact UUID id, then an exact project `code`, then an exact `title`.
/// Throws [CliException] on no match or an ambiguous name.
Future<Project> resolveProject(AppDatabase db, String query) async {
  final live = await (db.select(
    db.projects,
  )..where((p) => p.deletedAt.isNull())).get();

  final byId = live.where((p) => p.id == query).toList();
  if (byId.length == 1) return byId.first;

  final byName = live
      .where((p) => p.code == query || p.title == query)
      .toList();
  return _one<Project>(
    byName,
    kind: 'project',
    query: query,
    describe: (p) => '${p.code} "${p.title}" (${p.id})',
  );
}

/// Resolve [query] to a single live [Task] *within* [projectId]. Matches an
/// exact UUID id then an exact `title`. Throws [CliException] on no match or an
/// ambiguous name.
Future<Task> resolveTask(
  AppDatabase db,
  String projectId,
  String query,
) async {
  final live = await db.tasksForProject(projectId); // already deletedAt-filtered

  final byId = live.where((t) => t.id == query).toList();
  if (byId.length == 1) return byId.first;

  final byName = live.where((t) => t.title == query).toList();
  return _one<Task>(
    byName,
    kind: 'task',
    query: query,
    describe: (t) => '"${t.title}" (${t.id})',
  );
}

/// Resolve [query] to a single live [Client]. Matches an exact UUID id then an
/// exact `name` (clients have no code). Throws [CliException] on no match or an
/// ambiguous name.
Future<Client> resolveClient(AppDatabase db, String query) async {
  final live = await (db.select(
    db.clients,
  )..where((c) => c.deletedAt.isNull())).get();

  final byId = live.where((c) => c.id == query).toList();
  if (byId.length == 1) return byId.first;

  final byName = live.where((c) => c.name == query).toList();
  return _one<Client>(
    byName,
    kind: 'client',
    query: query,
    describe: (c) => '"${c.name}" (${c.id})',
  );
}

/// Resolve [query] to a single live [Task], optionally scoped to [projectId].
/// With a project it defers to [resolveTask]; without one it matches a UUID id
/// across all live tasks, then an exact `title` across all live tasks (so a
/// task can be targeted for edit/delete without naming its project, as long as
/// the title is unique). Throws [CliException] on no match / ambiguity.
Future<Task> resolveTaskAnywhere(
  AppDatabase db,
  String query, {
  String? projectId,
}) async {
  if (projectId != null) return resolveTask(db, projectId, query);

  final live = await (db.select(
    db.tasks,
  )..where((t) => t.deletedAt.isNull())).get();

  final byId = live.where((t) => t.id == query).toList();
  if (byId.length == 1) return byId.first;

  final byName = live.where((t) => t.title == query).toList();
  return _one<Task>(
    byName,
    kind: 'task',
    query: query,
    describe: (t) => '"${t.title}" (project ${t.projectId}, ${t.id})',
  );
}

T _one<T>(
  List<T> matches, {
  required String kind,
  required String query,
  required String Function(T) describe,
}) {
  if (matches.isEmpty) {
    throw CliException(
      'No live $kind matches "$query". Use the exact name or its UUID.',
      CliExit.unknownEntity,
    );
  }
  if (matches.length > 1) {
    final list = matches.map((m) => '  - ${describe(m)}').join('\n');
    throw CliException(
      'Ambiguous $kind "$query" — ${matches.length} matches:\n$list\n'
      'Disambiguate with the UUID.',
      CliExit.ambiguousEntity,
    );
  }
  return matches.single;
}
