import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';

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
