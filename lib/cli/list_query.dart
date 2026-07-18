import 'package:drift/drift.dart';

import '../data/database.dart';
import 'list_result.dart';

// ── Read models for `list projects` / `list tasks` ─────────────────────────
// Live (non-soft-deleted) rows only, read through the shared data layer. The
// selectors an agent needs to target work (UUID + human name) come straight
// from here.

/// Map a live [Client] row to its list/CRUD-result shape.
ClientListItem clientListItem(Client c) => ClientListItem(
  id: c.id,
  name: c.name,
  defaultRate: c.defaultRate,
  contactName: c.contactName,
  email: c.email,
  phone: c.phone,
  address: c.address,
  abn: c.abn,
  archived: c.archivedAt != null,
);

/// All live clients, name-ordered.
Future<List<ClientListItem>> queryClients(AppDatabase db) async {
  final clients = await (db.select(db.clients)
        ..where((c) => c.deletedAt.isNull())
        ..orderBy([(c) => OrderingTerm.asc(c.name)]))
      .get();
  return [for (final c in clients) clientListItem(c)];
}

/// All live projects, title-ordered, each with its owning client's name.
Future<List<ProjectListItem>> queryProjects(AppDatabase db) async {
  final projects = await (db.select(db.projects)
        ..where((p) => p.deletedAt.isNull())
        ..orderBy([(p) => OrderingTerm.asc(p.title)]))
      .get();
  final clients = await (db.select(
    db.clients,
  )..where((c) => c.deletedAt.isNull())).get();
  final clientName = {for (final c in clients) c.id: c.name};

  return [
    for (final p in projects)
      ProjectListItem(
        id: p.id,
        code: p.code,
        title: p.title,
        clientId: p.clientId,
        clientName: clientName[p.clientId],
        rate: p.rate,
        archived: p.archivedAt != null,
      ),
  ];
}

/// Map a single live [Project] to its list/CRUD-result shape, given its owning
/// client's name (looked up by the caller).
ProjectListItem projectListItem(Project p, {String? clientName}) =>
    ProjectListItem(
      id: p.id,
      code: p.code,
      title: p.title,
      clientId: p.clientId,
      clientName: clientName,
      rate: p.rate,
      archived: p.archivedAt != null,
    );

/// Map a single live [Task] to its list/CRUD-result shape, given its owning
/// project's code/title (looked up by the caller).
TaskListItem taskListItem(Task t, {String? projectCode, String? projectTitle}) =>
    TaskListItem(
      id: t.id,
      title: t.title,
      projectId: t.projectId,
      projectCode: projectCode,
      projectTitle: projectTitle,
      rate: t.rate,
    );

/// Map a live [TimeEntry] row to its list/CRUD-result shape, given its owning
/// project's code/title and (if task-bound) the task's title — looked up by
/// the caller.
EntryListItem entryListItem(
  TimeEntry e, {
  String? projectCode,
  String? projectTitle,
  String? taskTitle,
}) => EntryListItem(
  id: e.id,
  projectId: e.projectId,
  projectCode: projectCode,
  projectTitle: projectTitle,
  taskId: e.taskId,
  taskTitle: taskTitle,
  description: e.description,
  seconds: e.seconds,
  startedAt: e.startedAt,
  endedAt: e.endedAt,
);

/// Live time entries, most-recent-first (by [TimeEntry.endedAt] — matching
/// [AppDatabase.watchEntriesForProject]/[watchEntriesForTask]). Optionally
/// scoped to [projectId] and/or [taskId], and to entries whose
/// [TimeEntry.startedAt] falls within [since]..[until] inclusive (issue #284).
Future<List<EntryListItem>> queryEntries(
  AppDatabase db, {
  String? projectId,
  String? taskId,
  DateTime? since,
  DateTime? until,
}) async {
  final query = db.select(db.timeEntries)
    ..where((e) => e.deletedAt.isNull())
    ..orderBy([(e) => OrderingTerm.desc(e.endedAt)]);
  if (projectId != null) query.where((e) => e.projectId.equals(projectId));
  if (taskId != null) query.where((e) => e.taskId.equals(taskId));
  if (since != null) query.where((e) => e.startedAt.isBiggerOrEqualValue(since));
  if (until != null) query.where((e) => e.startedAt.isSmallerOrEqualValue(until));
  final entries = await query.get();

  final projects = await (db.select(
    db.projects,
  )..where((p) => p.deletedAt.isNull())).get();
  final projectById = {for (final p in projects) p.id: p};
  final tasks = await (db.select(
    db.tasks,
  )..where((t) => t.deletedAt.isNull())).get();
  final taskById = {for (final t in tasks) t.id: t};

  return [
    for (final e in entries)
      entryListItem(
        e,
        projectCode: projectById[e.projectId]?.code,
        projectTitle: projectById[e.projectId]?.title,
        taskTitle: e.taskId == null ? null : taskById[e.taskId]?.title,
      ),
  ];
}

/// Live tasks, title-ordered. Scoped to [projectId] when given, else across all
/// live projects (each row carries its project's code/title for context).
Future<List<TaskListItem>> queryTasks(
  AppDatabase db, {
  String? projectId,
}) async {
  final query = db.select(db.tasks)
    ..where((t) => t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm.asc(t.title)]);
  if (projectId != null) query.where((t) => t.projectId.equals(projectId));
  final tasks = await query.get();

  final projects = await (db.select(
    db.projects,
  )..where((p) => p.deletedAt.isNull())).get();
  final byId = {for (final p in projects) p.id: p};

  return [
    for (final t in tasks)
      TaskListItem(
        id: t.id,
        title: t.title,
        projectId: t.projectId,
        projectCode: byId[t.projectId]?.code,
        projectTitle: byId[t.projectId]?.title,
        rate: t.rate,
      ),
  ];
}
