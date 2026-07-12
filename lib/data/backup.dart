import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/id.dart';

/// The first schema whose ids are text UUIDv7 (PRD #189, Phase 2c). A backup
/// written at an earlier schema carries integer ids, so [decodeBackup] re-keys
/// its raw rows to fresh UUIDs before building the (text-id) data classes.
const int _firstUuidSchemaVersion = 13;

// Portable, self-describing backup of the whole database (PRD #189, Phase 1a,
// issue #190). The safeguard that lets a user rescue their data across the
// clean-break UUID migration coming in Phase 2 — so the on-disk envelope carries
// a schema-version tag the (forward-compatible) importer in #191 keys off.
//
// Deliberately Flutter-free (only drift + dart:core) so the future companion CLI
// can reuse it verbatim ([[cli-plan]]). UI glue (file dialog, snackbars) lives
// in the shell; the file save helper in lib/util.

/// Bumped when the *envelope* shape changes (not the DB schema — that's tracked
/// separately by [Backup.schemaVersion]). v1 is the initial JSON layout.
const int backupFormatVersion = 1;

/// Magic marker so a wrong file is rejected before we try to parse tables.
const String backupFormatMarker = 'timedart-backup';

/// Thrown by [decodeBackup] when the bytes are not a valid timedart backup —
/// bad UTF-8/JSON, wrong/absent marker, or a table that isn't the expected
/// shape. The UI owns the user-facing wording.
class BackupFormatException implements Exception {
  final String message;
  const BackupFormatException(this.message);
  @override
  String toString() => 'BackupFormatException: $message';
}

/// Thrown by [restoreBackup] when a backup can't be imported into this app —
/// currently only when it was written by a *newer* schema than this build
/// understands (a forward-incompatible downgrade). The UI owns the wording.
class BackupIncompatibleException implements Exception {
  final int backupSchemaVersion;
  final int appSchemaVersion;
  const BackupIncompatibleException(
    this.backupSchemaVersion,
    this.appSchemaVersion,
  );
  @override
  String toString() =>
      'BackupIncompatibleException(backup v$backupSchemaVersion > app '
      'v$appSchemaVersion)';
}

/// An in-memory copy of every table's rows. Typed drift data classes, so it has
/// value equality per row and round-trips cleanly through [encodeBackup] /
/// [decodeBackup].
class BackupSnapshot {
  final List<Client> clients;
  final List<Project> projects;
  final List<Task> tasks;
  final List<TimeEntry> timeEntries;
  final List<InvoiceTemplate> templates;
  final List<InvoiceProfile> profiles;
  final List<AppSetting> settings;

  const BackupSnapshot({
    required this.clients,
    required this.projects,
    required this.tasks,
    required this.timeEntries,
    required this.templates,
    required this.profiles,
    required this.settings,
  });

  @override
  bool operator ==(Object other) =>
      other is BackupSnapshot &&
      _listEq(clients, other.clients) &&
      _listEq(projects, other.projects) &&
      _listEq(tasks, other.tasks) &&
      _listEq(timeEntries, other.timeEntries) &&
      _listEq(templates, other.templates) &&
      _listEq(profiles, other.profiles) &&
      _listEq(settings, other.settings);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(clients),
    Object.hashAll(projects),
    Object.hashAll(tasks),
    Object.hashAll(timeEntries),
    Object.hashAll(templates),
    Object.hashAll(profiles),
    Object.hashAll(settings),
  );
}

/// A decoded backup: the envelope metadata plus its [snapshot]. [schemaVersion]
/// is the DB schema the file was written at — the linchpin for #191's
/// cross-version (forward-compatible) restore.
class Backup {
  final int formatVersion;
  final int schemaVersion;
  final DateTime exportedAt;
  final BackupSnapshot snapshot;

  const Backup({
    required this.formatVersion,
    required this.schemaVersion,
    required this.exportedAt,
    required this.snapshot,
  });
}

/// Read every row of every table into a [BackupSnapshot]. Goes through the same
/// public drift accessors all reads use; no new methods on [AppDatabase].
Future<BackupSnapshot> readBackupSnapshot(AppDatabase db) async => BackupSnapshot(
  clients: await db.select(db.clients).get(),
  projects: await db.select(db.projects).get(),
  tasks: await db.select(db.tasks).get(),
  timeEntries: await db.select(db.timeEntries).get(),
  templates: await db.select(db.templates).get(),
  profiles: await db.select(db.profiles).get(),
  settings: await db.select(db.appSettings).get(),
);

/// Read the current DB and encode it as backup bytes in one step. [exportedAt]
/// is injected (not read from a clock here) so callers stay in control and the
/// pure path is testable.
Future<Uint8List> exportBackupBytes(
  AppDatabase db, {
  required DateTime exportedAt,
}) async {
  final snapshot = await readBackupSnapshot(db);
  return encodeBackup(
    snapshot,
    schemaVersion: db.schemaVersion,
    exportedAt: exportedAt,
  );
}

/// What [sanitizeSnapshot] dropped to make a backup referentially consistent.
/// Real DBs can carry orphans SQLite never caught (FK isn't enforced
/// retroactively, so a historical delete/migration with FK off leaves children
/// pointing at a gone parent); a faithful export dumps them, and a restore must
/// not choke on them. [total] > 0 means the imported data differs from the file.
class SnapshotRepair {
  final int droppedProjects; // client missing
  final int droppedTasks; // project missing
  final int droppedEntries; // project or task missing
  final int clearedTemplateRefs; // profile.templateId pointed at a gone template
  const SnapshotRepair({
    this.droppedProjects = 0,
    this.droppedTasks = 0,
    this.droppedEntries = 0,
    this.clearedTemplateRefs = 0,
  });
  int get total =>
      droppedProjects + droppedTasks + droppedEntries + clearedTemplateRefs;
  bool get isClean => total == 0;
}

/// Make a snapshot referentially consistent: drop rows whose FK parent is
/// absent (cascading — dropping a project drops its tasks and entries), and null
/// a profile's dangling `templateId` (nullable → resolves to the default).
/// Pure; returns the cleaned snapshot and a [SnapshotRepair] of what changed.
({BackupSnapshot snapshot, SnapshotRepair repair}) sanitizeSnapshot(
  BackupSnapshot s,
) {
  final clientIds = {for (final c in s.clients) c.id};
  final projects = [
    for (final p in s.projects)
      if (clientIds.contains(p.clientId)) p,
  ];
  final projectIds = {for (final p in projects) p.id};
  final tasks = [
    for (final t in s.tasks)
      if (projectIds.contains(t.projectId)) t,
  ];
  final taskIds = {for (final t in tasks) t.id};
  final entries = [
    for (final e in s.timeEntries)
      if (projectIds.contains(e.projectId) &&
          (e.taskId == null || taskIds.contains(e.taskId)))
        e,
  ];
  final templateIds = {for (final t in s.templates) t.id};
  var clearedTemplateRefs = 0;
  final profiles = [
    for (final p in s.profiles)
      if (p.templateId == null || templateIds.contains(p.templateId))
        p
      else
        () {
          clearedTemplateRefs++;
          return p.copyWith(templateId: const Value(null));
        }(),
  ];

  final clean = BackupSnapshot(
    clients: s.clients,
    projects: projects,
    tasks: tasks,
    timeEntries: entries,
    templates: s.templates,
    profiles: profiles,
    settings: s.settings,
  );
  return (
    snapshot: clean,
    repair: SnapshotRepair(
      droppedProjects: s.projects.length - projects.length,
      droppedTasks: s.tasks.length - tasks.length,
      droppedEntries: s.timeEntries.length - entries.length,
      clearedTemplateRefs: clearedTemplateRefs,
    ),
  );
}

/// Restore a decoded [backup] into [db], **replacing all existing data**
/// (PRD #189, Phase 1b, #191). Runs in one transaction: wipe every table, then
/// re-insert the snapshot preserving row ids. All-or-nothing — a failure rolls
/// back and leaves the current data intact. Returns a [SnapshotRepair] so the
/// caller can tell the user if any orphaned rows were skipped.
///
/// The snapshot is [sanitizeSnapshot]d first, so a backup with dangling FKs
/// (orphans from historical data) restores what's valid instead of failing.
/// FK checks are deferred to commit as a belt-and-suspenders against insert
/// order (the pragma auto-resets at end of transaction).
///
/// Forward-compatibility seam: a backup from a *newer* schema is rejected
/// ([BackupIncompatibleException]); a same-or-older backup is imported. A
/// pre-v13 (integer-keyed) export is re-keyed to text UUIDv7 ids inside
/// [decodeBackup] (see [_rekeyLegacyGraph]) before it reaches this function, so
/// by here every row already carries the v13 text ids the schema expects.
Future<SnapshotRepair> restoreBackup(AppDatabase db, Backup backup) async {
  if (backup.schemaVersion > db.schemaVersion) {
    throw BackupIncompatibleException(backup.schemaVersion, db.schemaVersion);
  }
  final (snapshot: s, :repair) = sanitizeSnapshot(backup.snapshot);
  await db.transaction(() async {
    await db.customStatement('PRAGMA defer_foreign_keys = ON');
    await db.delete(db.timeEntries).go();
    await db.delete(db.tasks).go();
    await db.delete(db.projects).go();
    await db.delete(db.profiles).go();
    await db.delete(db.templates).go();
    await db.delete(db.clients).go();
    await db.delete(db.appSettings).go();
    // ids preserved (nullToAbsent: false keeps explicit nulls so the restore is
    // exact).
    await db.batch((b) {
      b.insertAll(db.clients, [for (final r in s.clients) r.toCompanion(false)]);
      b.insertAll(db.templates, [
        for (final r in s.templates) r.toCompanion(false),
      ]);
      b.insertAll(db.projects, [
        for (final r in s.projects) r.toCompanion(false),
      ]);
      b.insertAll(db.tasks, [for (final r in s.tasks) r.toCompanion(false)]);
      b.insertAll(db.profiles, [
        for (final r in s.profiles) r.toCompanion(false),
      ]);
      b.insertAll(db.timeEntries, [
        for (final r in s.timeEntries) r.toCompanion(false),
      ]);
      b.insertAll(db.appSettings, [
        for (final r in s.settings) r.toCompanion(false),
      ]);
    });
  });
  return repair;
}

/// Serialise a snapshot to pretty-printed JSON bytes with the version envelope.
Uint8List encodeBackup(
  BackupSnapshot s, {
  required int schemaVersion,
  required DateTime exportedAt,
}) {
  List<Map<String, dynamic>> rows<T extends DataClass>(List<T> items) =>
      [for (final r in items) r.toJson(serializer: _serializer)];

  final root = <String, dynamic>{
    'format': backupFormatMarker,
    'formatVersion': backupFormatVersion,
    'schemaVersion': schemaVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'data': {
      'clients': rows(s.clients),
      'projects': rows(s.projects),
      'tasks': rows(s.tasks),
      'timeEntries': rows(s.timeEntries),
      'templates': rows(s.templates),
      'profiles': rows(s.profiles),
      'settings': rows(s.settings),
    },
  };
  return Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(root)),
  );
}

/// Parse backup bytes back into a [Backup]. Throws [BackupFormatException] on
/// anything that isn't a well-formed timedart backup — never a partial result.
Backup decodeBackup(Uint8List bytes) {
  final Object? root;
  try {
    root = json.decode(utf8.decode(bytes));
  } catch (_) {
    throw const BackupFormatException('not valid UTF-8 JSON');
  }
  if (root is! Map) throw const BackupFormatException('not a JSON object');
  if (root['format'] != backupFormatMarker) {
    throw const BackupFormatException('not a timedart backup file');
  }
  final formatVersion = _int(root, 'formatVersion');
  final schemaVersion = _int(root, 'schemaVersion');
  final exportedAt = _dateTime(root, 'exportedAt');

  final data = root['data'];
  if (data is! Map) throw const BackupFormatException('missing data section');

  // Forward-compat re-key (PRD #189, Phase 2c): a pre-v13 backup has integer
  // ids, but the current data classes expect text UUIDv7 ids. Re-key the raw
  // JSON graph — new uuid per row, every FK rewritten to match — BEFORE fromJson,
  // so an int-keyed export (e.g. the safeguard beta users are taking now)
  // restores into the v13 schema with all relationships intact. Dangling FKs are
  // left pointing at ids no row will own, so [sanitizeSnapshot] drops them just
  // as it does for a same-version restore.
  if (schemaVersion < _firstUuidSchemaVersion) {
    _rekeyLegacyGraph(data);
  }

  List<T> table<T extends DataClass>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    final raw = data[key];
    if (raw == null) return const []; // tolerate an absent table
    if (raw is! List) throw BackupFormatException('"$key" is not a list');
    try {
      return [
        for (final row in raw)
          fromJson((row as Map).cast<String, dynamic>()),
      ];
    } catch (e) {
      throw BackupFormatException('malformed row in "$key": $e');
    }
  }

  final snapshot = BackupSnapshot(
    clients: table('clients', (m) => Client.fromJson(m, serializer: _serializer)),
    projects:
        table('projects', (m) => Project.fromJson(m, serializer: _serializer)),
    tasks: table('tasks', (m) => Task.fromJson(m, serializer: _serializer)),
    timeEntries: table(
      'timeEntries',
      (m) => TimeEntry.fromJson(m, serializer: _serializer),
    ),
    templates: table(
      'templates',
      (m) => InvoiceTemplate.fromJson(m, serializer: _serializer),
    ),
    profiles: table(
      'profiles',
      (m) => InvoiceProfile.fromJson(m, serializer: _serializer),
    ),
    settings:
        table('settings', (m) => AppSetting.fromJson(m, serializer: _serializer)),
  );

  return Backup(
    formatVersion: formatVersion,
    schemaVersion: schemaVersion,
    exportedAt: exportedAt,
    snapshot: snapshot,
  );
}

/// Re-key a legacy (pre-v13, integer-keyed) backup graph in place: assign a
/// fresh UUIDv7 to every row's `id` and rewrite every FK to match, preserving
/// all relationships. Operates on the raw decoded JSON maps (before fromJson)
/// because the current data classes only accept text ids. FK keys are drift's
/// camelCase json names (clientId/projectId/taskId/templateId). A dangling FK
/// (no row owns that old id) is pointed at a fresh uuid no row will have, so the
/// downstream [sanitizeSnapshot] drops the orphan — same outcome as a
/// same-version restore.
void _rekeyLegacyGraph(Map<dynamic, dynamic> data) {
  Map<String, String> buildMap(String key) {
    final rows = data[key];
    final map = <String, String>{};
    if (rows is List) {
      for (final row in rows) {
        if (row is Map && row['id'] != null) {
          map[row['id'].toString()] = idGen.newId();
        }
      }
    }
    return map;
  }

  final clientIds = buildMap('clients');
  final projectIds = buildMap('projects');
  final taskIds = buildMap('tasks');
  final entryIds = buildMap('timeEntries');
  final templateIds = buildMap('templates');
  final profileIds = buildMap('profiles');

  // Map a FK's old value to the parent's new uuid; a missing parent (orphan)
  // becomes a fresh uuid that matches nothing, so sanitizeSnapshot drops it.
  String remap(Map<String, String> parent, Object old) =>
      parent[old.toString()] ?? idGen.newId();

  void rekey(
    String key,
    Map<String, String> selfIds,
    void Function(Map<dynamic, dynamic> row) rewriteFks,
  ) {
    final rows = data[key];
    if (rows is! List) return;
    for (final row in rows) {
      if (row is! Map) continue;
      if (row['id'] != null) row['id'] = selfIds[row['id'].toString()];
      rewriteFks(row);
    }
  }

  rekey('clients', clientIds, (_) {});
  rekey('projects', projectIds, (r) {
    if (r['clientId'] != null) r['clientId'] = remap(clientIds, r['clientId']);
  });
  rekey('tasks', taskIds, (r) {
    if (r['projectId'] != null) {
      r['projectId'] = remap(projectIds, r['projectId']);
    }
  });
  rekey('timeEntries', entryIds, (r) {
    if (r['projectId'] != null) {
      r['projectId'] = remap(projectIds, r['projectId']);
    }
    if (r['taskId'] != null) r['taskId'] = remap(taskIds, r['taskId']);
  });
  rekey('templates', templateIds, (_) {});
  rekey('profiles', profileIds, (r) {
    if (r['templateId'] != null) {
      r['templateId'] = remap(templateIds, r['templateId']);
    }
  });
}

int _int(Map<dynamic, dynamic> m, String key) {
  final v = m[key];
  if (v is int) return v;
  throw BackupFormatException('"$key" is not an integer');
}

DateTime _dateTime(Map<dynamic, dynamic> m, String key) {
  final v = m[key];
  final parsed = v is String ? DateTime.tryParse(v) : null;
  if (parsed == null) throw BackupFormatException('"$key" is not a timestamp');
  return parsed;
}

const _serializer = _JsonSafeSerializer();

/// drift's default JSON serializer can't represent blob (`Uint8List`) columns —
/// the profile logo — in JSON. This wrapper base64-encodes blobs and delegates
/// everything else (incl. DateTime → epoch millis) to the defaults, so the
/// backup file is plain JSON.
class _JsonSafeSerializer extends ValueSerializer {
  const _JsonSafeSerializer();

  static const _defaults = ValueSerializer.defaults();

  // True when T is `Uint8List` or `Uint8List?` — i.e. a blob column.
  static bool _isBlob<T>() => <Uint8List>[] is List<T>;

  @override
  T fromJson<T>(dynamic json) {
    if (json is String && _isBlob<T>()) return base64.decode(json) as T;
    return _defaults.fromJson<T>(json);
  }

  @override
  dynamic toJson<T>(T value) {
    if (value is Uint8List) return base64.encode(value);
    return _defaults.toJson<T>(value);
  }
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
