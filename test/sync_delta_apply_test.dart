import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/backup.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/active_timer_wire.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';
import 'package:timedart/data/sync/delta/delta_keys.dart';
import 'package:timedart/data/sync/delta/merge.dart';
import 'package:timedart/data/sync/delta/profile_wire.dart';
import 'package:timedart/data/sync/delta/project_wire.dart';
import 'package:timedart/data/sync/delta/sync_queries.dart';
import 'package:timedart/data/sync/delta/task_wire.dart';
import 'package:timedart/data/sync/delta/time_entry_wire.dart';

// Phase 5b delta-sync (#294): the DB seam against a real (in-memory) drift DB —
// the sync_outbox dirty-tracker enqueued at the write choke-points, the
// fromRemote apply path (no re-stamp, no echo, no enqueue), LWW at the DB
// boundary for all four tables, adoption across all four, and outbox read/clear.

void main() {
  late AppDatabase db;
  final t0 = DateTime.fromMillisecondsSinceEpoch(1000);
  final t1 = DateTime.fromMillisecondsSinceEpoch(2000);
  final t2 = DateTime.fromMillisecondsSinceEpoch(3000);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    // Simulate a delta build: content-table writes enqueue into the outbox.
    db.enableSyncOutbox = true;
  });
  tearDown(() => db.close());

  // Raw inserts (bypass the choke-points → no auto-enqueue) so timestamps and
  // org are fully controlled and the outbox starts empty for a test.
  Future<void> insertClient({
    required String id,
    String name = 'Acme',
    String? orgId,
    double rate = 100,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => db.into(db.clients).insert(ClientsCompanion.insert(
        id: Value(id),
        name: name,
        defaultRate: rate,
        orgId: Value(orgId),
        updatedAt: Value(updatedAt),
        deletedAt: Value(deletedAt),
      ));

  RemoteClient remoteClient({
    required String id,
    String name = 'Acme',
    String? orgId = 'org1',
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
        defaultRate: 100,
        archivedAt: null,
        createdAt: null,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        serverSeq: serverSeq,
      );

  group('outbox enqueue at the write choke-points', () {
    test('addClient / updateClient / deleteClient each enqueue the row',
        () async {
      final id = await db.addClient(name: 'Acme', defaultRate: 100);
      expect(await db.outboxRowIds(kTableClients), [id]);

      await db.clearOutbox(kTableClients, [id]);
      await db.updateClient(id: id, name: 'Renamed', defaultRate: 120);
      expect(await db.outboxRowIds(kTableClients), [id]);

      await db.clearOutbox(kTableClients, [id]);
      await db.deleteClient(id);
      expect(await db.outboxRowIds(kTableClients), [id]);
    });

    test('archiveClient enqueues', () async {
      final id = await db.addClient(name: 'Acme', defaultRate: 100);
      await db.clearOutbox(kTableClients, [id]);
      await db.archiveClient(id);
      expect(await db.outboxRowIds(kTableClients), [id]);
    });

    test('the full project/task/entry add-chain enqueues each table', () async {
      final client = await db.addClient(name: 'Acme', defaultRate: 100);
      final project =
          await db.addProject(clientId: client, code: 'P1', title: 'Proj');
      final task = await db.addTask(projectId: project, title: 'Task');
      await db.addEntry(
        projectId: project,
        taskId: task,
        startedAt: t0,
        endedAt: t1,
        seconds: 60,
      );
      expect(await db.outboxRowIds(kTableClients), [client]);
      expect(await db.outboxRowIds(kTableProjects), [project]);
      expect(await db.outboxRowIds(kTableTasks), [task]);
      expect((await db.outboxRowIds(kTableTimeEntries)).length, 1);
    });

    test('deleteClientCascade enqueues the parent AND every live descendant',
        () async {
      final client = await db.addClient(name: 'Acme', defaultRate: 100);
      final project =
          await db.addProject(clientId: client, code: 'P1', title: 'Proj');
      final task = await db.addTask(projectId: project, title: 'Task');
      await db.addEntry(
        projectId: project,
        taskId: task,
        startedAt: t0,
        endedAt: t1,
        seconds: 60,
      );
      // Clear the adds so we observe only the cascade's enqueues.
      await db.clearOutbox(kTableClients, [client]);
      await db.clearOutbox(kTableProjects, [project]);
      await db.clearOutbox(kTableTasks, [task]);
      await db.clearOutbox(
          kTableTimeEntries, await db.outboxRowIds(kTableTimeEntries));

      await db.deleteClientCascade(client);
      expect(await db.outboxRowIds(kTableClients), [client]);
      expect(await db.outboxRowIds(kTableProjects), [project]);
      expect(await db.outboxRowIds(kTableTasks), [task]);
      expect((await db.outboxRowIds(kTableTimeEntries)).length, 1);
    });

    test('with enableSyncOutbox off (released path) nothing is enqueued',
        () async {
      db.enableSyncOutbox = false;
      final id = await db.addClient(name: 'Acme', defaultRate: 100);
      await db.updateClient(id: id, name: 'X', defaultRate: 1);
      await db.deleteClient(id);
      expect(await db.outboxRowIds(kTableClients), isEmpty);
    });

    test('the fromRemote apply path does NOT enqueue (structural echo guard)',
        () async {
      await db.applyRemoteClient(remoteClient(id: 'a', updatedAt: t1));
      expect(await db.outboxRowIds(kTableClients), isEmpty,
          reason: 'applying a pulled row must never re-queue it for push');
    });
  });

  group('push reads (byIds include tombstones)', () {
    test('clientsByIds returns live and tombstoned rows, skips unknown ids',
        () async {
      await insertClient(id: 'a', updatedAt: t0);
      await insertClient(id: 'b', updatedAt: t1, deletedAt: t1);
      final rows = await db.clientsByIds(['a', 'b', 'ghost']);
      expect(rows.map((c) => c.id).toSet(), {'a', 'b'});
    });

    test('empty id list short-circuits to no rows', () async {
      expect(await db.clientsByIds(const []), isEmpty);
    });
  });

  group('outbox clear', () {
    test('clearOutbox removes only the named ids for that table', () async {
      final a = await db.addClient(name: 'A', defaultRate: 1);
      final b = await db.addClient(name: 'B', defaultRate: 1);
      await db.clearOutbox(kTableClients, [a]);
      expect(await db.outboxRowIds(kTableClients), [b]);
    });

    test('queuedBefore guard: a row re-queued after the snapshot survives clear',
        () async {
      // Simulate the drain race: id 'a' queued during the pass (queuedAt = t2),
      // AFTER the pass snapshot (t1). Clearing with queuedBefore: t1 must leave
      // it — its new state hasn't been pushed yet.
      await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
            targetTable: kTableClients,
            rowId: 'a',
            queuedAt: Value(t2),
          ));
      await db.clearOutbox(kTableClients, ['a'], queuedBefore: t1);
      expect(await db.outboxRowIds(kTableClients), ['a'],
          reason: 're-queued-during-pass row must not be dropped');
      // A snapshot in a strictly later second does clear it. (drift stores
      // DateTime as unix SECONDS, so the guard's granularity is 1s — the
      // conservative direction: a same-second concurrent enqueue is kept, never
      // dropped.)
      await db.clearOutbox(kTableClients, ['a'],
          queuedBefore: DateTime.fromMillisecondsSinceEpoch(4000));
      expect(await db.outboxRowIds(kTableClients), isEmpty);
    });
  });

  group('restoreBackup enqueues restored content rows (no silent hole)', () {
    test('restored clients/projects land in the outbox when sync is active',
        () async {
      // Build a snapshot on a sync-OFF source db (nothing pre-queued).
      final src = AppDatabase(NativeDatabase.memory());
      addTearDown(src.close);
      final client = await src.addClient(name: 'Acme', defaultRate: 100);
      final project =
          await src.addProject(clientId: client, code: 'P1', title: 'Proj');
      final snapshot = await readBackupSnapshot(src);

      // Restore into the sync-ON db (setUp already set enableSyncOutbox = true).
      await restoreBackup(
        db,
        Backup(
          formatVersion: backupFormatVersion,
          schemaVersion: db.schemaVersion,
          exportedAt: DateTime.fromMillisecondsSinceEpoch(0),
          snapshot: snapshot,
        ),
      );

      expect(await db.outboxRowIds(kTableClients), contains(client));
      expect(await db.outboxRowIds(kTableProjects), contains(project));
    });

    test('restore into a sync-OFF db enqueues nothing', () async {
      db.enableSyncOutbox = false;
      final src = AppDatabase(NativeDatabase.memory());
      addTearDown(src.close);
      await src.addClient(name: 'Acme', defaultRate: 100);
      final snapshot = await readBackupSnapshot(src);
      await restoreBackup(
        db,
        Backup(
          formatVersion: backupFormatVersion,
          schemaVersion: db.schemaVersion,
          exportedAt: DateTime.fromMillisecondsSinceEpoch(0),
          snapshot: snapshot,
        ),
      );
      expect(await db.outboxRowIds(kTableClients), isEmpty);
    });
  });

  group('applyRemoteClient via LWW gate', () {
    Future<MergeAction> applyIfNewer(RemoteClient r) async {
      final local = await db.clientByIdIncludingDeleted(r.id);
      final action = decideClientMergeFor(local, r);
      if (action == MergeAction.apply) await db.applyRemoteClient(r);
      return action;
    }

    test('local absent → inserted, remote clock kept', () async {
      expect(await applyIfNewer(remoteClient(id: 'a', updatedAt: t1)),
          MergeAction.apply);
      final row = await db.clientByIdIncludingDeleted('a');
      expect(row!.orgId, 'org1');
      expect(row.updatedAt, t1);
    });

    test('equal clock re-apply is a skip (idempotent, echo-free)', () async {
      await insertClient(id: 'a', updatedAt: t1);
      expect(await applyIfNewer(remoteClient(id: 'a', updatedAt: t1)),
          MergeAction.skip);
    });

    test('older remote does not clobber newer local', () async {
      await insertClient(id: 'a', name: 'LocalNew', updatedAt: t2);
      expect(await applyIfNewer(remoteClient(id: 'a', updatedAt: t0)),
          MergeAction.skip);
      expect((await db.clientByIdIncludingDeleted('a'))!.name, 'LocalNew');
    });

    test('remote tombstone applies as a local soft-delete', () async {
      await insertClient(id: 'a', updatedAt: t0);
      await applyIfNewer(remoteClient(id: 'a', updatedAt: t1, deletedAt: t1));
      expect((await db.clientByIdIncludingDeleted('a'))!.deletedAt, t1);
    });
  });

  group('applyRemote for projects / tasks / time_entries (LWW + apply)', () {
    // A minimal parent chain so FK-enforced child applies succeed.
    Future<void> seedTree() async {
      await insertClient(id: 'c1', orgId: 'org1', updatedAt: t0);
      await db.applyRemoteProject(RemoteProject(
        id: 'p1',
        orgId: 'org1',
        clientId: 'c1',
        code: 'P1',
        title: 'Proj',
        rate: null,
        status: 'active',
        archivedAt: null,
        createdAt: t0,
        updatedAt: t0,
        deletedAt: null,
        serverSeq: 1,
      ));
      await db.applyRemoteTask(RemoteTask(
        id: 't1',
        orgId: 'org1',
        projectId: 'p1',
        title: 'Task',
        rate: null,
        status: 'active',
        createdAt: t0,
        updatedAt: t0,
        deletedAt: null,
        serverSeq: 2,
      ));
    }

    test('project applies and keeps the remote updatedAt', () async {
      await seedTree();
      final local = await db.projectByIdIncludingDeleted('p1');
      expect(local, isNot(null));
      expect(local!.updatedAt, t0);
      expect(local.clientId, 'c1');
    });

    test('task applies under its project', () async {
      await seedTree();
      final t = await db.taskByIdIncludingDeleted('t1');
      expect(t!.projectId, 'p1');
    });

    test('time entry applies under project + task, seconds preserved',
        () async {
      await seedTree();
      await db.applyRemoteTimeEntry(RemoteTimeEntry(
        id: 'e1',
        orgId: 'org1',
        projectId: 'p1',
        taskId: 't1',
        description: 'note',
        startedAt: t0,
        endedAt: t1,
        seconds: 90,
        createdAt: t0,
        updatedAt: t1,
        deletedAt: null,
        serverSeq: 3,
      ));
      final e = await db.timeEntryByIdIncludingDeleted('e1');
      expect(e!.seconds, 90);
      expect(e.updatedAt, t1);
    });

    test('applying children does NOT enqueue them (echo guard, all tables)',
        () async {
      await seedTree();
      expect(await db.outboxRowIds(kTableProjects), isEmpty);
      expect(await db.outboxRowIds(kTableTasks), isEmpty);
    });
  });

  group('adoption / re-home across all four tables', () {
    test('claims null-org AND different-org rows, bumps updatedAt, enqueues',
        () async {
      // Three clients: one with no org (local-only), one on a DIFFERENT org
      // (used anon sync / another account), one already on the target org.
      // A project chain (raw inserts, so nothing is pre-queued).
      await insertClient(id: 'c1', orgId: null, updatedAt: t0);
      await insertClient(id: 'c2', orgId: 'other-org', updatedAt: t0);
      await insertClient(id: 'c3', orgId: 'mine', updatedAt: t0);
      await db.into(db.projects).insert(ProjectsCompanion.insert(
            id: const Value('p1'),
            clientId: 'c1',
            code: const Value('P1'),
            title: 'Proj',
            createdAt: Value(t0),
            updatedAt: Value(t0),
          ));

      // c1 (null) + c2 (other-org) are claimed; c3 (already mine) is not.
      expect(await db.adoptOrphanClients('mine'), 2);
      expect(await db.adoptOrphanProjects('mine'), 1);
      expect(await db.adoptOrphanTasks('mine'), 0);
      expect(await db.adoptOrphanTimeEntries('mine'), 0);

      final c1 = await db.clientByIdIncludingDeleted('c1');
      final c2 = await db.clientByIdIncludingDeleted('c2');
      final c3 = await db.clientByIdIncludingDeleted('c3');
      expect(c1!.orgId, 'mine');
      expect(c2!.orgId, 'mine', reason: 'different-org row re-homed to account');
      expect(c3!.orgId, 'mine', reason: 'already on the org — untouched');
      expect(c1.updatedAt!.isAfter(t0), isTrue);
      expect(c2.updatedAt!.isAfter(t0), isTrue);

      // Both claimed rows are queued for the push; the already-scoped one isn't.
      expect(await db.outboxRowIds(kTableClients), unorderedEquals(['c1', 'c2']));
      expect(await db.outboxRowIds(kTableProjects), ['p1']);
    });

    test('is a no-op (0, no enqueue) when every row is already on the org',
        () async {
      await insertClient(id: 'c1', orgId: 'mine', updatedAt: t0);
      expect(await db.adoptOrphanClients('mine'), 0);
      expect(await db.outboxRowIds(kTableClients), isEmpty);
    });

    test('active timers are adopted too (#300)', () async {
      // An unbound timer created offline (raw insert → not pre-queued).
      await db.into(db.activeTimers).insert(ActiveTimersCompanion.insert(
            id: const Value('a1'),
            updatedAt: Value(t0),
          ));
      expect(await db.adoptOrphanActiveTimers('mine'), 1);
      final row = await db.activeTimerByIdIncludingDeleted('a1');
      expect(row!.orgId, 'mine');
      expect(row.updatedAt!.isAfter(t0), isTrue);
      expect(await db.outboxRowIds(kTableActiveTimers), ['a1']);
    });
  });

  group('active timer sync (#300)', () {
    test('saveActiveTimer enqueues; tombstoneActiveTimer enqueues', () async {
      await db.saveActiveTimer(
        ActiveTimersCompanion.insert(id: const Value('a1')),
      );
      expect(await db.outboxRowIds(kTableActiveTimers), ['a1']);

      await db.clearOutbox(kTableActiveTimers, ['a1']);
      await db.tombstoneActiveTimer('a1');
      expect(await db.outboxRowIds(kTableActiveTimers), ['a1']);
    });

    test('sync-OFF path (enableSyncOutbox false) enqueues nothing', () async {
      db.enableSyncOutbox = false;
      await db.saveActiveTimer(
        ActiveTimersCompanion.insert(id: const Value('a1')),
      );
      await db.tombstoneActiveTimer('a1');
      expect(await db.outboxRowIds(kTableActiveTimers), isEmpty);
    });

    test('the fromRemote apply path does NOT enqueue (echo guard)', () async {
      await db.applyRemoteActiveTimer(RemoteActiveTimer(
        id: 'a1',
        orgId: 'org1',
        projectId: null,
        taskId: null,
        description: null,
        startedAt: t0,
        accumulatedSeconds: 0,
        runningSince: t0,
        createdAt: t0,
        updatedAt: t1,
        deletedAt: null,
        serverSeq: 1,
      ));
      expect(await db.outboxRowIds(kTableActiveTimers), isEmpty);
      final row = await db.activeTimerByIdIncludingDeleted('a1');
      expect(row!.updatedAt, t1, reason: 'remote clock kept verbatim');
    });

    test('LWW: newer remote applies, older is skipped', () async {
      await db.applyRemoteActiveTimer(RemoteActiveTimer(
        id: 'a1', orgId: 'o', projectId: null, taskId: null, description: null,
        startedAt: t0, accumulatedSeconds: 5, runningSince: null,
        createdAt: t0, updatedAt: t1, deletedAt: null, serverSeq: 1,
      ));
      final local = await db.activeTimerByIdIncludingDeleted('a1');
      // Older remote → skip (would clobber).
      expect(
        decideActiveTimerMergeFor(
          local,
          RemoteActiveTimer(
            id: 'a1', orgId: 'o', projectId: null, taskId: null,
            description: null, startedAt: t0, accumulatedSeconds: 99,
            runningSince: t0, createdAt: t0, updatedAt: t0, deletedAt: null,
            serverSeq: 2,
          ),
        ),
        MergeAction.skip,
      );
    });
  });

  group('branding sync — templates & profiles (#320)', () {
    Future<String> seedTemplate() =>
        db.insertTemplate(TemplatesCompanion.insert(
          name: 'Brand',
          colorBackground: 1,
          colorSurface: 2,
          colorPrimary: 3,
          colorText: 4,
          colorAccent: 5,
          fontFamily: const Value('Outfit'),
        ));

    test('insert/update/delete/setDefault enqueue templates', () async {
      final id = await seedTemplate();
      expect(await db.outboxRowIds(kTableTemplates), [id]);

      await db.clearOutbox(kTableTemplates, [id]);
      await db.updateTemplateById(id, const TemplatesCompanion(name: Value('X')));
      expect(await db.outboxRowIds(kTableTemplates), [id]);

      await db.clearOutbox(kTableTemplates, [id]);
      await db.deleteTemplate(id);
      expect(await db.outboxRowIds(kTableTemplates), [id]);
    });

    test('setDefaultTemplate enqueues BOTH the old default and the new one',
        () async {
      final a = await seedTemplate();
      await db.setDefaultTemplate(a); // a is now default
      final b = await seedTemplate();
      await db.clearOutbox(kTableTemplates, [a, b]);
      await db.setDefaultTemplate(b); // flips a→false, b→true
      expect(await db.outboxRowIds(kTableTemplates), unorderedEquals([a, b]));
    });

    test('setDefault does NOT bump updatedAt on unrelated (non-default) rows',
        () async {
      // Regression (#320 review): an unfiltered clear-write bumped every row's
      // updatedAt without enqueuing it → its clock races the server and a
      // concurrent remote edit loses LWW. c is a non-default row: setDefault(b)
      // must leave c untouched.
      final a = await seedTemplate();
      await db.setDefaultTemplate(a);
      final b = await seedTemplate();
      final c = await seedTemplate(); // non-default, never touched
      final cBefore = (await db.templateByIdIncludingDeleted(c))!.updatedAt;
      await db.clearOutbox(
          kTableTemplates, await db.outboxRowIds(kTableTemplates));
      await db.setDefaultTemplate(b);
      expect((await db.templateByIdIncludingDeleted(c))!.updatedAt, cBefore,
          reason: 'unrelated row clock must not advance');
      expect(await db.outboxRowIds(kTableTemplates), unorderedEquals([a, b]),
          reason: 'only the cleared-old + new default are enqueued');
    });

    test('insert/update/delete enqueue profiles', () async {
      final id = await db.insertProfile(ProfilesCompanion.insert(name: 'P'));
      expect(await db.outboxRowIds(kTableProfiles), [id]);
      await db.clearOutbox(kTableProfiles, [id]);
      await db.updateProfileById(id, const ProfilesCompanion(email: Value('e')));
      expect(await db.outboxRowIds(kTableProfiles), [id]);
    });

    test('sync-OFF path enqueues neither table', () async {
      db.enableSyncOutbox = false;
      final t = await seedTemplate();
      await db.setDefaultTemplate(t);
      await db.insertProfile(ProfilesCompanion.insert(name: 'P'));
      expect(await db.outboxRowIds(kTableTemplates), isEmpty);
      expect(await db.outboxRowIds(kTableProfiles), isEmpty);
    });

    test('adoption claims templates + profiles', () async {
      // Raw inserts (no org, not pre-queued).
      await db.into(db.templates).insert(TemplatesCompanion.insert(
            id: const Value('tpl1'),
            name: 'Brand',
            colorBackground: 1, colorSurface: 2, colorPrimary: 3,
            colorText: 4, colorAccent: 5,
            fontFamily: const Value('Outfit'),
            updatedAt: Value(t0),
          ));
      await db.into(db.profiles).insert(ProfilesCompanion.insert(
            id: const Value('pr1'),
            name: 'P',
            updatedAt: Value(t0),
          ));
      expect(await db.adoptOrphanTemplates('mine'), 1);
      expect(await db.adoptOrphanProfiles('mine'), 1);
      expect((await db.templateByIdIncludingDeleted('tpl1'))!.orgId, 'mine');
      expect((await db.profileByIdIncludingDeleted('pr1'))!.orgId, 'mine');
      expect(await db.outboxRowIds(kTableTemplates), ['tpl1']);
      expect(await db.outboxRowIds(kTableProfiles), ['pr1']);
    });

    test('applyRemoteProfile does NOT clobber a local logo BLOB, no enqueue',
        () async {
      final logo = Uint8List.fromList([9, 8, 7]);
      // A local profile with a logo already set (raw insert → not queued).
      await db.into(db.profiles).insert(ProfilesCompanion.insert(
            id: const Value('pr1'),
            name: 'P',
            logo: Value(logo),
            logoMime: const Value('image/png'),
            updatedAt: Value(t0),
          ));
      // A newer remote wins LWW; its toCompanion omits logo bytes.
      await db.applyRemoteProfile(RemoteProfile.fromWire({
        'id': 'pr1', 'org_id': 'mine', 'name': 'P renamed',
        'logo_path': 'mine/pr1-abc.png', 'logo_mime': 'image/png',
        'is_default': 0, 'currency': 'USD', 'region': 'au',
        'updated_at': 2000, 'server_seq': 1,
      }));
      final row = await db.profileByIdIncludingDeleted('pr1');
      expect(row!.name, 'P renamed'); // row fields applied
      expect(row.logo, logo, reason: 'local logo bytes preserved, not nulled');
      expect(row.logoPath, 'mine/pr1-abc.png');
      expect(await db.outboxRowIds(kTableProfiles), isEmpty,
          reason: 'apply path never enqueues');
    });

    test('logo helpers (setLocalLogoPath/Bytes, clearLocalLogo) do not enqueue',
        () async {
      await db.into(db.profiles).insert(ProfilesCompanion.insert(
            id: const Value('pr1'), name: 'P', updatedAt: Value(t0)));
      await db.setLocalLogoPath('pr1', 'mine/pr1-x.png');
      await db.setLocalLogoBytes(
          'pr1', Uint8List.fromList([1, 2]), 'image/png');
      final row = await db.profileByIdIncludingDeleted('pr1');
      expect(row!.logoPath, 'mine/pr1-x.png');
      expect(row.logo, Uint8List.fromList([1, 2]));
      expect(row.updatedAt, t0, reason: 'logo helpers never re-clock');
      await db.clearLocalLogo('pr1');
      expect((await db.profileByIdIncludingDeleted('pr1'))!.logo, equals(null));
      expect(await db.outboxRowIds(kTableProfiles), isEmpty);
    });
  });
}
