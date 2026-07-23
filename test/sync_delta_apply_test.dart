import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';
import 'package:timedart/data/sync/delta/merge.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';

// Phase 5a delta-sync (#294): the DB seam against a real (in-memory) drift DB —
// the push-read (tombstones included), the fromRemote apply path (no re-stamp /
// no echo), LWW at the DB boundary, and adoption.

void main() {
  late AppDatabase db;
  final t0 = DateTime.fromMillisecondsSinceEpoch(1000);
  final t1 = DateTime.fromMillisecondsSinceEpoch(2000);
  final t2 = DateTime.fromMillisecondsSinceEpoch(3000);

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Insert a client row with fully explicit fields (bypasses addClient so
  /// timestamps are controlled).
  Future<void> insertClient({
    required String id,
    String name = 'Acme',
    String? orgId,
    double rate = 100,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => db.into(db.clients).insert(
    ClientsCompanion.insert(
      id: Value(id),
      name: name,
      defaultRate: rate,
      orgId: Value(orgId),
      updatedAt: Value(updatedAt),
      deletedAt: Value(deletedAt),
    ),
  );

  RemoteClient remote({
    required String id,
    String name = 'Acme',
    String? orgId = 'org1',
    double rate = 100,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int serverSeq = 1,
  }) => RemoteClient(
    id: id,
    orgId: orgId,
    name: name,
    contactName: null,
    email: null,
    phone: null,
    address: null,
    abn: null,
    defaultRate: rate,
    archivedAt: null,
    createdAt: null,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
    serverSeq: serverSeq,
  );

  /// Apply a remote row exactly as sync_service would: LWW-gate, then write.
  Future<MergeAction> applyIfNewer(RemoteClient r) async {
    final local = await db.clientByIdIncludingDeleted(r.id);
    final action = decideClientMergeFor(local, r);
    if (action == MergeAction.apply) await db.applyRemoteClient(r);
    return action;
  }

  group('clientsToPush', () {
    test('null watermark returns all clocked rows including tombstones',
        () async {
      await insertClient(id: 'a', updatedAt: t0);
      await insertClient(id: 'b', updatedAt: t1, deletedAt: t1); // tombstoned
      final rows = await db.clientsToPush(null);
      expect(rows.map((c) => c.id).toSet(), {'a', 'b'});
    });

    test('watermark excludes rows at or before it', () async {
      await insertClient(id: 'a', updatedAt: t0);
      await insertClient(id: 'b', updatedAt: t2);
      final rows = await db.clientsToPush(t1);
      expect(rows.map((c) => c.id), ['b']);
    });

    test('rows with null updatedAt are never pushed', () async {
      await insertClient(id: 'a', updatedAt: null);
      expect(await db.clientsToPush(null), isEmpty);
    });
  });

  group('applyRemoteClient via LWW gate', () {
    test('local absent → row is inserted', () async {
      final action = await applyIfNewer(remote(id: 'a', updatedAt: t1));
      expect(action, MergeAction.apply);
      final row = await db.clientByIdIncludingDeleted('a');
      expect(row!.orgId, 'org1');
      expect(row.updatedAt, t1);
    });

    test('newer remote overwrites and preserves the remote updatedAt (no '
        're-stamp → echo-free)', () async {
      await insertClient(id: 'a', name: 'Old', updatedAt: t0);
      await applyIfNewer(remote(id: 'a', name: 'New', updatedAt: t1));
      final row = await db.clientByIdIncludingDeleted('a');
      expect(row!.name, 'New');
      expect(row.updatedAt, t1, reason: 'must keep remote clock, not now()');
    });

    test('re-applying the same row is a no-op (idempotent, no echo)', () async {
      await insertClient(id: 'a', updatedAt: t1);
      final second = await applyIfNewer(remote(id: 'a', updatedAt: t1));
      expect(second, MergeAction.skip);
    });

    test('older remote does not clobber a newer local edit', () async {
      await insertClient(id: 'a', name: 'LocalNew', updatedAt: t2);
      final action = await applyIfNewer(remote(id: 'a', name: 'Stale', updatedAt: t0));
      expect(action, MergeAction.skip);
      final row = await db.clientByIdIncludingDeleted('a');
      expect(row!.name, 'LocalNew');
    });

    test('remote tombstone applies as a local soft-delete', () async {
      await insertClient(id: 'a', updatedAt: t0);
      await applyIfNewer(remote(id: 'a', updatedAt: t1, deletedAt: t1));
      final row = await db.clientByIdIncludingDeleted('a');
      expect(row!.deletedAt, t1);
      // and it drops out of the normal (deletedAt IS NULL) read
      final live = await db.watchClients(includeArchived: true).first;
      expect(live.where((c) => c.id == 'a'), isEmpty);
    });
  });

  group('adoptOrphanClients', () {
    test('stamps org_id on null-org rows and bumps updatedAt into the push set',
        () async {
      await insertClient(id: 'a', orgId: null, updatedAt: t0);
      await insertClient(id: 'b', orgId: 'existing', updatedAt: t0);

      final count = await db.adoptOrphanClients('mine');
      expect(count, 1);

      final a = await db.clientByIdIncludingDeleted('a');
      final b = await db.clientByIdIncludingDeleted('b');
      expect(a!.orgId, 'mine');
      expect(b!.orgId, 'existing', reason: 'already-scoped rows untouched');
      expect(
        a.updatedAt!.isAfter(t0),
        isTrue,
        reason: 'bumped so the watermark picks it up for push',
      );
      // the freshly-adopted row is now dirty relative to an old watermark
      final toPush = await db.clientsToPush(t0);
      expect(toPush.map((c) => c.id), contains('a'));
    });
  });
}
