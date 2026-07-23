import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';
import 'package:timedart/data/sync/delta/merge.dart';

// Phase 5a delta-sync (#294): the pure LWW merge rule + the Postgres wire codec.
// No database, no network — the correctness core of pull, pinned exhaustively.

void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1000);
  final t1 = DateTime.fromMillisecondsSinceEpoch(2000);

  group('decideClientMerge (LWW)', () {
    test('local absent → apply', () {
      expect(
        decideClientMerge(localUpdatedAt: null, remoteUpdatedAt: t0),
        MergeAction.apply,
      );
    });

    test('remote strictly newer → apply', () {
      expect(
        decideClientMerge(localUpdatedAt: t0, remoteUpdatedAt: t1),
        MergeAction.apply,
      );
    });

    test('remote older → skip', () {
      expect(
        decideClientMerge(localUpdatedAt: t1, remoteUpdatedAt: t0),
        MergeAction.skip,
      );
    });

    test('equal clocks → skip (idempotent; kills push↔pull echo)', () {
      expect(
        decideClientMerge(localUpdatedAt: t0, remoteUpdatedAt: t0),
        MergeAction.skip,
      );
    });

    test('remote unclocked with a local row present → skip', () {
      expect(
        decideClientMerge(localUpdatedAt: t0, remoteUpdatedAt: null),
        MergeAction.skip,
      );
    });

    test('local row present but unclocked → apply (clocked remote wins)', () {
      expect(
        decideClientMerge(localUpdatedAt: null, remoteUpdatedAt: t0),
        MergeAction.apply,
      );
    });
  });

  group('decideClientMergeFor (tombstones ride the same rule)', () {
    Client client({required DateTime? updatedAt, DateTime? deletedAt}) => Client(
      id: 'c1',
      name: 'Acme',
      defaultRate: 100,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );

    RemoteClient remote({required DateTime? updatedAt, DateTime? deletedAt}) =>
        RemoteClient(
          id: 'c1',
          orgId: 'org1',
          name: 'Acme',
          contactName: null,
          email: null,
          phone: null,
          address: null,
          abn: null,
          defaultRate: 100,
          archivedAt: null,
          createdAt: null,
          updatedAt: updatedAt,
          deletedAt: deletedAt,
          serverSeq: 5,
        );

    test('newer remote tombstone → apply (delete propagates)', () {
      expect(
        decideClientMergeFor(
          client(updatedAt: t0),
          remote(updatedAt: t1, deletedAt: t1),
        ),
        MergeAction.apply,
      );
    });

    test('stale remote tombstone against a newer local edit → skip', () {
      expect(
        decideClientMergeFor(
          client(updatedAt: t1),
          remote(updatedAt: t0, deletedAt: t0),
        ),
        MergeAction.skip,
      );
    });

    test('no local row → apply', () {
      expect(
        decideClientMergeFor(null, remote(updatedAt: t0)),
        MergeAction.apply,
      );
    });
  });

  group('client wire codec (Postgres shape: snake_case, epoch-ms)', () {
    final client = Client(
      id: 'c1',
      orgId: 'org1',
      name: 'Acme',
      contactName: 'Jo',
      email: 'jo@acme.test',
      phone: '123',
      address: '1 St',
      abn: 'A1',
      defaultRate: 125.5,
      archivedAt: null,
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('clientToWire uses snake_case keys and epoch-ms ints', () {
      expect(clientToWire(client), {
        'id': 'c1',
        'org_id': 'org1',
        'name': 'Acme',
        'contact_name': 'Jo',
        'email': 'jo@acme.test',
        'phone': '123',
        'address': '1 St',
        'abn': 'A1',
        'default_rate': 125.5,
        'archived_at': null,
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
    });

    test('server_seq is never in the push payload (server authors it)', () {
      expect(clientToWire(client).containsKey('server_seq'), isFalse);
    });

    test('RemoteClient.fromWire round-trips the wire map', () {
      final wire = {
        ...clientToWire(client),
        'server_seq': 42,
      };
      final r = RemoteClient.fromWire(wire);
      expect(r.id, 'c1');
      expect(r.orgId, 'org1');
      expect(r.name, 'Acme');
      expect(r.contactName, 'Jo');
      expect(r.defaultRate, 125.5);
      expect(r.createdAt, t0);
      expect(r.updatedAt, t1);
      expect(r.deletedAt, isNull);
      expect(r.serverSeq, 42);
    });

    test('toCompanion carries the remote updatedAt verbatim (no re-stamp)', () {
      final r = RemoteClient.fromWire({...clientToWire(client), 'server_seq': 1});
      final companion = r.toCompanion();
      expect(companion.updatedAt.value, t1);
      expect(companion.id.value, 'c1');
      expect(companion.deletedAt.value, isNull);
    });

    test('a tombstone wire row decodes with deletedAt set', () {
      final wire = {
        ...clientToWire(client),
        'deleted_at': 3000,
        'updated_at': 3000,
        'server_seq': 7,
      };
      final r = RemoteClient.fromWire(wire);
      expect(r.deletedAt, DateTime.fromMillisecondsSinceEpoch(3000));
      expect(r.updatedAt, DateTime.fromMillisecondsSinceEpoch(3000));
    });
  });
}
