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

BackupSnapshot _sampleSnapshot() => BackupSnapshot(
  clients: [
    Client(
      id: 1,
      name: 'Acme Pty Ltd',
      contactName: 'Wile E.',
      email: 'a@b.com',
      phone: null,
      address: null,
      abn: null,
      defaultRate: 120.0,
      archivedAt: null,
    ),
  ],
  projects: [
    Project(
      id: 2,
      clientId: 1,
      code: 'ACME-1',
      title: 'Website',
      rate: null,
      status: 'active',
      createdAt: DateTime(2026, 1, 2, 3, 4, 5),
    ),
  ],
  tasks: [
    Task(
      id: 3,
      projectId: 2,
      title: 'Design',
      rate: 150.0,
      status: 'active',
      createdAt: DateTime(2026, 1, 3),
    ),
  ],
  timeEntries: [
    TimeEntry(
      id: 4,
      projectId: 2,
      taskId: 3,
      description: 'wireframes',
      startedAt: DateTime(2026, 1, 3, 9),
      endedAt: DateTime(2026, 1, 3, 11),
      seconds: 7200,
    ),
  ],
  templates: [
    InvoiceTemplate(
      id: 5,
      name: 'timedart',
      colorBackground: 0xFF11140E,
      colorSurface: 0xFF23241F,
      colorPrimary: 0xFF69E228,
      colorText: 0xFFE8F5E0,
      colorAccent: 0xFF2E6C0F,
      fontFamily: 'Mona',
      isDefault: true,
    ),
  ],
  profiles: [
    InvoiceProfile(
      id: 6,
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
      templateId: 5,
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
    ),
  ],
  settings: [const AppSetting(key: 'onboarding_complete', value: 'true')],
);

void main() {
  // The restore test legitimately opens a source + target in-memory DB in one
  // test; silence drift's multiple-databases dev warning.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('snapshot round-trips through encode → decode unchanged', () {
    final snapshot = _sampleSnapshot();
    final when = DateTime.utc(2026, 7, 12, 8, 30);

    final bytes = encodeBackup(snapshot, schemaVersion: 10, exportedAt: when);
    final decoded = decodeBackup(bytes);

    expect(decoded.snapshot, snapshot);
    expect(decoded.formatVersion, backupFormatVersion);
    expect(decoded.schemaVersion, 10);
    expect(decoded.exportedAt, when);
    // The logo blob survives base64 encoding intact.
    expect(decoded.snapshot.profiles.single.logo, snapshot.profiles.single.logo);
  });

  test('encoded backup is plain JSON with the version envelope', () {
    final bytes = encodeBackup(
      _sampleSnapshot(),
      schemaVersion: 10,
      exportedAt: DateTime.utc(2026, 7, 12),
    );
    final root = json.decode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(root['format'], backupFormatMarker);
    expect(root['formatVersion'], backupFormatVersion);
    expect(root['schemaVersion'], 10);
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
      final bytes = Uint8List.fromList(
        utf8.encode(
          json.encode({
            'format': backupFormatMarker,
            'formatVersion': 1,
            'schemaVersion': 10,
            'exportedAt': DateTime.utc(2026, 7, 12).toIso8601String(),
            'data': {
              'clients': [
                {'id': 'not-an-int', 'name': 'x'},
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

    test('a failing restore rolls back, leaving current data intact', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final keep = await db.addClient(name: 'KeepCo', defaultRate: 5);
      await db.addProject(clientId: keep, code: 'K-1', title: 'Keep');

      // A backup with a dangling FK (project → non-existent client) makes the
      // parents-first insert fail; the transaction must roll back.
      final broken = Backup(
        formatVersion: backupFormatVersion,
        schemaVersion: db.schemaVersion,
        exportedAt: DateTime.utc(2026, 7, 12),
        snapshot: BackupSnapshot(
          clients: const [],
          projects: [
            Project(
              id: 1,
              clientId: 999, // no such client
              code: 'X',
              title: 'Dangling',
              rate: null,
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
            ),
          ],
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
