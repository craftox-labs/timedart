import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';

// Auth slice 1 (#310): the identity-cache clear run on every account change
// (email sign-in / sign-out). It must drop the cached org_id and every pull
// cursor — so the next pass re-resolves the (possibly new) account's org and
// re-pulls from seq 0 — while leaving the device opt-in flag and local content
// rows untouched (no wipe on sign-out).
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('clearSyncIdentityState drops org_id + all cursors, keeps the rest',
      () async {
    // Identity-scoped state that must be dropped.
    await db.setSyncSetting(kSyncOrgId, 'org-anon');
    await db.setSyncSetting(syncCursorKey(kTableClients), '10');
    await db.setSyncSetting(syncCursorKey(kTableProjects), '20');
    await db.setSyncSetting(syncCursorKey(kTableTasks), '30');
    await db.setSyncSetting(syncCursorKey(kTableTimeEntries), '40');
    // Device/opt-in state + a local row that must survive (no wipe).
    await db.setSyncSetting(kSyncEnabled, '1');
    await db.addClient(name: 'Acme', defaultRate: 100);

    await db.clearSyncIdentityState();

    expect(await db.syncSetting(kSyncOrgId), isNull);
    expect(await db.syncSetting(syncCursorKey(kTableClients)), isNull);
    expect(await db.syncSetting(syncCursorKey(kTableProjects)), isNull);
    expect(await db.syncSetting(syncCursorKey(kTableTasks)), isNull);
    expect(await db.syncSetting(syncCursorKey(kTableTimeEntries)), isNull);

    // Opt-in flag and local data are identity-independent — untouched.
    expect(await db.syncSetting(kSyncEnabled), '1');
    expect((await db.select(db.clients).get()).length, 1);
  });

  test('clearSyncIdentityState is a no-op when nothing is cached', () async {
    await db.clearSyncIdentityState();
    expect(await db.syncSetting(kSyncOrgId), isNull);
  });
}
