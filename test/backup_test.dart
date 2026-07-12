import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/backup.dart';
import 'package:timedart/data/database.dart';

// Coverage for the backup codec + snapshot reader (PRD #189, Phase 1a, #190).
// The codec is a pure deep module: build a snapshot, encode, decode, assert the
// round-trip and the version envelope. The reader test proves it works over
// real drift rows (all columns) including a null logo blob.

// Audit timestamps (schema v11) — a fixed local time; values are arbitrary but
// must be local (drift decodes epoch millis to local; DateTime.== needs isUtc
// to match) and stable so round-trips compare equal.
final _ts = DateTime(2026, 1, 1);

BackupSnapshot _sampleSnapshot() => BackupSnapshot(
  clients: [
    Client(
      id: 'c1',
      name: 'Acme Pty Ltd',
      contactName: 'Wile E.',
      email: 'a@b.com',
      phone: null,
      address: null,
      abn: null,
      defaultRate: 120.0,
      archivedAt: null,
      createdAt: _ts,
      updatedAt: _ts,
    ),
  ],
  projects: [
    Project(
      id: 'p2',
      clientId: 'c1',
      code: 'ACME-1',
      title: 'Website',
      rate: null,
      status: 'active',
      createdAt: DateTime(2026, 1, 2, 3, 4, 5),
      updatedAt: _ts,
    ),
  ],
  tasks: [
    Task(
      id: 't3',
      projectId: 'p2',
      title: 'Design',
      rate: 150.0,
      status: 'active',
      createdAt: DateTime(2026, 1, 3),
      updatedAt: _ts,
    ),
  ],
  timeEntries: [
    TimeEntry(
      id: 'e4',
      projectId: 'p2',
      taskId: 't3',
      description: 'wireframes',
      startedAt: DateTime(2026, 1, 3, 9),
      endedAt: DateTime(2026, 1, 3, 11),
      seconds: 7200,
      createdAt: _ts,
      updatedAt: _ts,
    ),
  ],
  templates: [
    InvoiceTemplate(
      id: 'tpl5',
      name: 'timedart',
      colorBackground: 0xFF11140E,
      colorSurface: 0xFF23241F,
      colorPrimary: 0xFF69E228,
      colorText: 0xFFE8F5E0,
      colorAccent: 0xFF2E6C0F,
      fontFamily: 'Mona',
      isDefault: true,
      createdAt: _ts,
      updatedAt: _ts,
    ),
  ],
  profiles: [
    InvoiceProfile(
      id: 'pf6',
      name: 'Default',
      businessName: 'My Studio',
      // A real blob: exercises the base64 serializer path.
      logo: Uint8List.fromList([0, 1, 2, 250, 255]),
      logoMime: 'image/png',
      email: null,
      phone: null,
      website: null,
      address: null,
      abn: null,
      payeeName: null,
      bankName: null,
      bankBsb: null,
      bankAccount: null,
      swift: null,
      paymentLink: null,
      currency: 'AUD',
      taxLabel: 'GST',
      taxRate: 10.0,
      isDefault: true,
      templateId: 'tpl5',
      region: 'au',
      iban: null,
      sortCode: null,
      routingNumber: null,
      payid: null,
      institutionNumber: null,
      transitNumber: null,
      showBank: true,
      showPaymentLink: true,
      showTax: true,
      showRateColumn: true,
      showTimeColumn: true,
      reverseCharge: false,
      createdAt: _ts,
      updatedAt: _ts,
    ),
  ],
  settings: [
    AppSetting(key: 'onboarding_complete', value: 'true', updatedAt: _ts),
  ],
);

void main() {
  // The restore test legitimately opens a source + target in-memory DB in one
  // test; silence drift's multiple-databases dev warning.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('snapshot round-trips through encode → decode unchanged', () {
    final snapshot = _sampleSnapshot();
    final when = DateTime.utc(2026, 7, 12, 8, 30);

    // schemaVersion 13 is the current text-id schema, so decode does NOT re-key
    // (the legacy int→uuid path has its own test); the round-trip is exact.
    final bytes = encodeBackup(snapshot, schemaVersion: 13, exportedAt: when);
    final decoded = decodeBackup(bytes);

    expect(decoded.snapshot, snapshot);
    expect(decoded.formatVersion, backupFormatVersion);
    expect(decoded.schemaVersion, 13);
    expect(decoded.exportedAt, when);
    // The logo blob survives base64 encoding intact.
    expect(decoded.snapshot.profiles.single.logo, snapshot.profiles.single.logo);
  });

  test('encoded backup is plain JSON with the version envelope', () {
    final bytes = encodeBackup(
      _sampleSnapshot(),
      schemaVersion: 13,
      exportedAt: DateTime.utc(2026, 7, 12),
    );
    final root = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(root['format'], backupFormatMarker);
    expect(root['formatVersion'], backupFormatVersion);
    expect(root['schemaVersion'], 13);
    expect((root['data'] as Map)['clients'], isA<List>());
  });

  group('decode rejects malformed input', () {
    test('non-JSON bytes', () {
      expect(
        () => decodeBackup(Uint8List.fromList(utf8.encode('not json'))),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('JSON without the timedart marker', () {
      final bytes = Uint8List.fromList(utf8.encode(json.encode({'foo': 'bar'})));
      expect(
        () => decodeBackup(bytes),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('a table row of the wrong shape', () {
      // A non-numeric defaultRate is malformed for the required real column
      // (ids are text now, so a string id is no longer a shape error).
      final bytes = Uint8List.fromList(
        utf8.encode(
          json.encode({
            'format': backupFormatMarker,
            'formatVersion': 1,
            'schemaVersion': 13,
            'exportedAt': DateTime.utc(2026, 7, 12).toIso8601String(),
            'data': {
              'clients': [
                {'id': 'c1', 'name': 'x', 'defaultRate': 'not-a-number'},
              ],
            },
          }),
        ),
      );
      expect(
        () => decodeBackup(bytes),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  test('reader captures real DB rows and they round-trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.ensureInvoiceDefaults();
    final clientId = await db.addClient(name: 'Beta', defaultRate: 90.0);
    final projectId = await db.addProject(
      clientId: clientId,
      code: 'B-1',
      title: 'App',
    );
    final taskId = await db.addTask(projectId: projectId, title: 'Build');
    await db.addEntry(
      projectId: projectId,
      taskId: taskId,
      startedAt: DateTime.utc(2026, 5, 1, 9),
      endedAt: DateTime.utc(2026, 5, 1, 10),
      seconds: 3600,
    );

    final snapshot = await readBackupSnapshot(db);
    expect(snapshot.clients, hasLength(1)); // Beta (ensureInvoiceDefaults seeds no client)
    expect(snapshot.projects, hasLength(1));
    expect(snapshot.tasks, hasLength(1));
    expect(snapshot.timeEntries, hasLength(1));
    expect(snapshot.templates, hasLength(1));
    expect(snapshot.profiles, hasLength(1));

    final bytes = encodeBackup(
      snapshot,
      schemaVersion: db.schemaVersion,
      exportedAt: DateTime.utc(2026, 7, 12),
    );
    expect(decodeBackup(bytes).snapshot, snapshot);
  });

  group('restore (import)', () {
    test('replaces all existing data with the backup', () async {
      // Seed the db with data the import must wipe.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.ensureInvoiceDefaults();
      final oldClient = await db.addClient(name: 'OldCo', defaultRate: 1);
      await db.addProject(clientId: oldClient, code: 'OLD', title: 'Legacy');

      // A different backup (built via the same reader on a second db).
      final source = AppDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      await source.ensureInvoiceDefaults();
      final c = await source.addClient(name: 'NewCo', defaultRate: 200);
      final p = await source.addProject(
        clientId: c,
        code: 'NEW-1',
        title: 'Fresh',
      );
      final t = await source.addTask(projectId: p, title: 'Kickoff');
      await source.addEntry(
        projectId: p,
        taskId: t,
        startedAt: DateTime.utc(2026, 6, 1, 9),
        endedAt: DateTime.utc(2026, 6, 1, 10),
        seconds: 3600,
      );
      final wanted = await readBackupSnapshot(source);
      final backup = decodeBackup(
        encodeBackup(
          wanted,
          schemaVersion: source.schemaVersion,
          exportedAt: DateTime.utc(2026, 7, 12),
        ),
      );

      await restoreBackup(db, backup);

      // The old data is gone and the db now equals the backup exactly.
      expect(await readBackupSnapshot(db), wanted);
      final clients = await db.select(db.clients).get();
      expect(clients.map((c) => c.name), ['NewCo']);
    });

    test('restores a multi-project snapshot regardless of insert order', () async {
      // Regression: drift's batch groups statements by SQL and can insert a
      // child (task/entry) before its parent (project), tripping FK 787 on real
      // data. restoreBackup defers FK checks to commit, so this must succeed.
      final source = AppDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      await source.ensureInvoiceDefaults();
      final client = await source.addClient(name: 'MultiCo', defaultRate: 100);
      final projectIds = <String>[];
      for (var i = 1; i <= 6; i++) {
        projectIds.add(
          await source.addProject(
            clientId: client,
            code: 'P$i',
            title: 'Proj $i',
          ),
        );
      }
      // Task + entry under a non-first project (mirrors the field failure: a
      // task on project id 3).
      final midProject = projectIds[2];
      final taskId = await source.addTask(
        projectId: midProject,
        title: 'Mid task',
      );
      await source.addEntry(
        projectId: midProject,
        taskId: taskId,
        startedAt: DateTime.utc(2026, 6, 2, 9),
        endedAt: DateTime.utc(2026, 6, 2, 10),
        seconds: 3600,
      );
      final wanted = await readBackupSnapshot(source);
      final backup = decodeBackup(
        encodeBackup(
          wanted,
          schemaVersion: source.schemaVersion,
          exportedAt: DateTime.utc(2026, 7, 12),
        ),
      );

      // Target already has (different) data to be replaced.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final old = await db.addClient(name: 'OldCo', defaultRate: 1);
      await db.addProject(clientId: old, code: 'OLD', title: 'Legacy');

      await restoreBackup(db, backup);
      expect(await readBackupSnapshot(db), wanted);
    });

    test('rejects a backup from a newer schema', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final future = Backup(
        formatVersion: backupFormatVersion,
        schemaVersion: db.schemaVersion + 1,
        exportedAt: DateTime.utc(2026, 7, 12),
        snapshot: const BackupSnapshot(
          clients: [],
          projects: [],
          tasks: [],
          timeEntries: [],
          templates: [],
          profiles: [],
          settings: [],
        ),
      );
      expect(
        () => restoreBackup(db, future),
        throwsA(isA<BackupIncompatibleException>()),
      );
    });

    test('repairs orphaned rows (dangling FKs) instead of failing', () async {
      // Reproduces the field failure: a real export where a project was deleted
      // long ago (FK off) leaving orphaned tasks + entries pointing at it. The
      // import must drop the orphans and restore what's valid, reporting counts.
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final backup = Backup(
        formatVersion: backupFormatVersion,
        schemaVersion: db.schemaVersion,
        exportedAt: DateTime.utc(2026, 7, 12),
        snapshot: BackupSnapshot(
          clients: [
            Client(
              id: 'c1',
              name: 'Co',
              contactName: null,
              email: null,
              phone: null,
              address: null,
              abn: null,
              defaultRate: 100,
              archivedAt: null,
              createdAt: _ts,
              updatedAt: _ts,
            ),
          ],
          projects: [
            Project(
              id: 'p1',
              clientId: 'c1',
              code: 'P1',
              title: 'Real',
              rate: null,
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: _ts,
            ),
          ],
          tasks: [
            // valid (project p1)
            Task(
              id: 't1',
              projectId: 'p1',
              title: 'Keep',
              rate: null,
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: _ts,
            ),
            // orphan (project p3 gone)
            Task(
              id: 't5',
              projectId: 'p3',
              title: 'Orphan',
              rate: null,
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: _ts,
            ),
          ],
          timeEntries: [
            // valid
            TimeEntry(
              id: 'e1',
              projectId: 'p1',
              taskId: 't1',
              description: null,
              startedAt: DateTime(2026, 1, 1, 9),
              endedAt: DateTime(2026, 1, 1, 10),
              seconds: 3600,
              createdAt: _ts,
              updatedAt: _ts,
            ),
            // orphan (project p3 gone)
            TimeEntry(
              id: 'e8',
              projectId: 'p3',
              taskId: 't5',
              description: null,
              startedAt: DateTime(2026, 1, 1, 9),
              endedAt: DateTime(2026, 1, 1, 10),
              seconds: 3600,
              createdAt: _ts,
              updatedAt: _ts,
            ),
          ],
          templates: const [],
          profiles: const [],
          settings: const [],
        ),
      );

      final repair = await restoreBackup(db, backup);

      expect(repair.droppedTasks, 1);
      expect(repair.droppedEntries, 1);
      expect(repair.isClean, isFalse);
      // The valid rows landed; the orphans did not.
      expect(await db.select(db.tasks).get(), hasLength(1));
      expect((await db.select(db.tasks).get()).single.title, 'Keep');
      expect(await db.select(db.timeEntries).get(), hasLength(1));
    });

    test('re-keys a legacy (int-keyed, pre-v13) backup into UUIDs', () async {
      // The safeguard payoff: a pre-Phase-2 export carried autoincrement int
      // ids. Build a real v13 snapshot, rewrite it to look like a v12 export
      // (integer ids + schemaVersion 12) plus an injected orphan, then import.
      // decodeBackup must re-key every id to a fresh uuid preserving the
      // client→project→task→entry graph, and sanitize must drop the orphan.
      final source = AppDatabase(NativeDatabase.memory());
      addTearDown(source.close);
      final c = await source.addClient(name: 'Legacy Co', defaultRate: 50);
      final p = await source.addProject(clientId: c, code: 'L-1', title: 'Work');
      final t = await source.addTask(projectId: p, title: 'Build');
      await source.addEntry(
        projectId: p,
        taskId: t,
        startedAt: DateTime.utc(2026, 1, 1, 9),
        endedAt: DateTime.utc(2026, 1, 1, 10),
        seconds: 3600,
      );
      final root =
          json.decode(
                utf8.decode(
                  encodeBackup(
                    await readBackupSnapshot(source),
                    schemaVersion: 13,
                    exportedAt: DateTime.utc(2026, 7, 12),
                  ),
                ),
              )
              as Map<String, dynamic>;

      // Rewrite every string id/FK to a distinct int via one shared map, so a
      // FK lands on the same int as the id it references (uuids are globally
      // unique, so a single map is unambiguous).
      final ints = <String, int>{};
      int intFor(String uuid) => ints.putIfAbsent(uuid, () => ints.length + 1);
      final data = root['data'] as Map<String, dynamic>;
      void toInts(String table, List<String> keys) {
        for (final row in (data[table] as List).cast<Map<String, dynamic>>()) {
          for (final k in ['id', ...keys]) {
            if (row[k] != null) row[k] = intFor(row[k] as String);
          }
        }
      }

      toInts('clients', const []);
      toInts('projects', const ['clientId']);
      toInts('tasks', const ['projectId']);
      toInts('timeEntries', const ['projectId', 'taskId']);

      // Inject an orphan task pointing at a project int that doesn't exist.
      final tasks = data['tasks'] as List;
      final orphan = Map<String, dynamic>.from(tasks.first as Map);
      orphan['id'] = 9998;
      orphan['projectId'] = 9999; // no such project
      orphan['title'] = 'Orphan';
      tasks.add(orphan);

      root['schemaVersion'] = 12; // a pre-v13 (int-keyed) export
      final backup = decodeBackup(
        Uint8List.fromList(utf8.encode(json.encode(root))),
      );

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repair = await restoreBackup(db, backup);

      // The orphan task was dropped; the real graph survived, re-keyed to uuids.
      expect(repair.droppedTasks, 1);
      final client = (await db.select(db.clients).get()).single;
      final project = (await db.select(db.projects).get()).single;
      final task = (await db.select(db.tasks).get()).single;
      final entry = (await db.select(db.timeEntries).get()).single;
      expect(client.name, 'Legacy Co');
      expect(task.title, 'Build');
      // Ids are now uuids (not the ints we wrote), and the relationships hold.
      expect(int.tryParse(client.id), isNull, reason: 're-keyed to a uuid');
      expect(project.clientId, client.id);
      expect(task.projectId, project.id);
      expect(entry.projectId, project.id);
      expect(entry.taskId, task.id);
    });

    test('a failing restore rolls back, leaving current data intact', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final keep = await db.addClient(name: 'KeepCo', defaultRate: 5);
      await db.addProject(clientId: keep, code: 'K-1', title: 'Keep');

      // Two projects sharing a code violates the UNIQUE(code) constraint —
      // something sanitize can't fix — so the batch insert fails and the whole
      // transaction must roll back.
      Project proj(String id, String code) => Project(
        id: id,
        clientId: 'c1',
        code: code,
        title: 'P$id',
        rate: null,
        status: 'active',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: _ts,
      );
      final broken = Backup(
        formatVersion: backupFormatVersion,
        schemaVersion: db.schemaVersion,
        exportedAt: DateTime.utc(2026, 7, 12),
        snapshot: BackupSnapshot(
          clients: [
            Client(
              id: 'c1',
              name: 'NewCo',
              contactName: null,
              email: null,
              phone: null,
              address: null,
              abn: null,
              defaultRate: 1,
              archivedAt: null,
              createdAt: _ts,
              updatedAt: _ts,
            ),
          ],
          projects: [proj('p1', 'DUP'), proj('p2', 'DUP')], // clash
          tasks: const [],
          timeEntries: const [],
          templates: const [],
          profiles: const [],
          settings: const [],
        ),
      );

      await expectLater(restoreBackup(db, broken), throwsA(anything));
      // Original data survived the rolled-back import.
      final clients = await db.select(db.clients).get();
      expect(clients.map((c) => c.name), ['KeepCo']);
      expect(await db.select(db.projects).get(), hasLength(1));
    });
  });
}
