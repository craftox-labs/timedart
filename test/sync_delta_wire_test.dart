import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/active_timer_wire.dart';
import 'package:timedart/data/sync/delta/logo_storage.dart';
import 'package:timedart/data/sync/delta/merge.dart';
import 'package:timedart/data/sync/delta/profile_wire.dart';
import 'package:timedart/data/sync/delta/project_wire.dart';
import 'package:timedart/data/sync/delta/task_wire.dart';
import 'package:timedart/data/sync/delta/template_wire.dart';
import 'package:timedart/data/sync/delta/time_entry_wire.dart';

// Phase 5b delta-sync (#294): the Postgres wire codecs for the three tables 5b
// adds (projects/tasks/time_entries) + their per-table LWW convenience — pure,
// no database, no network. Mirrors the client codec tests in
// sync_delta_merge_test.dart.

void main() {
  final t0 = DateTime.fromMillisecondsSinceEpoch(1000);
  final t1 = DateTime.fromMillisecondsSinceEpoch(2000);

  group('project wire codec', () {
    final project = Project(
      id: 'p1',
      orgId: 'org1',
      clientId: 'c1',
      code: 'P1',
      title: 'Proj',
      rate: 90.0,
      status: 'active',
      archivedAt: null,
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('projectToWire → snake_case keys, epoch-ms, plain rate, no server_seq',
        () {
      expect(projectToWire(project), {
        'id': 'p1',
        'org_id': 'org1',
        'client_id': 'c1',
        'code': 'P1',
        'title': 'Proj',
        'rate': 90.0,
        'status': 'active',
        'archived_at': null,
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
      expect(projectToWire(project).containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips, toCompanion keeps remote updatedAt verbatim',
        () {
      final r =
          RemoteProject.fromWire({...projectToWire(project), 'server_seq': 7});
      expect(r.id, 'p1');
      expect(r.clientId, 'c1');
      expect(r.rate, 90.0);
      expect(r.status, 'active');
      expect(r.createdAt, t0);
      expect(r.serverSeq, 7);
      expect(r.toCompanion().updatedAt.value, t1);
    });

    test('a tombstone wire row decodes with deletedAt set', () {
      final r = RemoteProject.fromWire({
        ...projectToWire(project),
        'deleted_at': 3000,
        'updated_at': 3000,
        'server_seq': 1,
      });
      expect(r.deletedAt, DateTime.fromMillisecondsSinceEpoch(3000));
    });

    test('a code-less project round-trips a null code (#331)', () {
      // copyWith takes a Value for the nullable column; Value(null) sets it
      // null (Value.absent would instead keep the existing 'P1').
      final codeless = project.copyWith(code: const Value(null));
      expect(codeless.code, isNull);
      final wire = projectToWire(codeless);
      expect(wire['code'], isNull);
      final r = RemoteProject.fromWire({...wire, 'server_seq': 1});
      expect(r.code, isNull);
      expect(r.toCompanion().code.value, isNull);
    });
  });

  group('task wire codec (no archived_at column)', () {
    final task = Task(
      id: 't1',
      orgId: 'org1',
      projectId: 'p1',
      title: 'Task',
      rate: null,
      status: 'active',
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('taskToWire → expected shape, no archived_at, no server_seq', () {
      final wire = taskToWire(task);
      expect(wire, {
        'id': 't1',
        'org_id': 'org1',
        'project_id': 'p1',
        'title': 'Task',
        'rate': null,
        'status': 'active',
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
      expect(wire.containsKey('archived_at'), isFalse);
      expect(wire.containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips + toCompanion verbatim updatedAt', () {
      final r = RemoteTask.fromWire({...taskToWire(task), 'server_seq': 3});
      expect(r.projectId, 'p1');
      expect(r.rate, isNull);
      expect(r.createdAt, t0);
      expect(r.serverSeq, 3);
      expect(r.toCompanion().updatedAt.value, t1);
    });
  });

  group('time entry wire codec', () {
    final entry = TimeEntry(
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
    );

    test('timeEntryToWire → epoch-ms times, plain seconds, no server_seq', () {
      expect(timeEntryToWire(entry), {
        'id': 'e1',
        'org_id': 'org1',
        'project_id': 'p1',
        'task_id': 't1',
        'description': 'note',
        'started_at': 1000,
        'ended_at': 2000,
        'seconds': 90,
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
      expect(timeEntryToWire(entry).containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips (nullable taskId, non-null times/seconds)', () {
      final r = RemoteTimeEntry.fromWire({
        ...timeEntryToWire(entry),
        'task_id': null,
        'server_seq': 9,
      });
      expect(r.taskId, isNull);
      expect(r.startedAt, t0);
      expect(r.endedAt, t1);
      expect(r.seconds, 90);
      expect(r.serverSeq, 9);
      expect(r.toCompanion().updatedAt.value, t1);
    });
  });

  group('active timer wire codec (#300)', () {
    final timer = ActiveTimer(
      id: 'a1',
      orgId: 'org1',
      projectId: 'p1',
      taskId: 't1',
      description: 'note',
      startedAt: t0,
      accumulatedSeconds: 42,
      runningSince: t1,
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('activeTimerToWire → snake_case, epoch-ms, no server_seq', () {
      expect(activeTimerToWire(timer), {
        'id': 'a1',
        'org_id': 'org1',
        'project_id': 'p1',
        'task_id': 't1',
        'description': 'note',
        'started_at': 1000,
        'accumulated_seconds': 42,
        'running_since': 2000,
        'created_at': 1000,
        'updated_at': 2000,
        'deleted_at': null,
      });
      expect(activeTimerToWire(timer).containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips; paused (running_since null) + unbound decode', () {
      final r = RemoteActiveTimer.fromWire({
        ...activeTimerToWire(timer),
        'project_id': null,
        'task_id': null,
        'running_since': null,
        'server_seq': 5,
      });
      expect(r.projectId, isNull); // unbound timer syncs fine
      expect(r.taskId, isNull);
      expect(r.runningSince, isNull); // paused
      expect(r.accumulatedSeconds, 42);
      expect(r.startedAt, t0);
      expect(r.serverSeq, 5);
      expect(r.toCompanion().updatedAt.value, t1); // remote clock verbatim
    });

    test('a tombstone (finished/discarded timer) decodes with deletedAt', () {
      final r = RemoteActiveTimer.fromWire({
        ...activeTimerToWire(timer),
        'deleted_at': 3000,
        'updated_at': 3000,
        'server_seq': 1,
      });
      expect(r.deletedAt, DateTime.fromMillisecondsSinceEpoch(3000));
    });

    test('accumulated_seconds missing/null defaults to 0', () {
      final r = RemoteActiveTimer.fromWire({
        ...activeTimerToWire(timer),
        'accumulated_seconds': null,
        'server_seq': 1,
      });
      expect(r.accumulatedSeconds, 0);
    });

    test('decideActiveTimerMergeFor: newer remote applies, older skips', () {
      ActiveTimer local(DateTime u) => ActiveTimer(
            id: 'a1',
            orgId: 'org1',
            projectId: 'p1',
            taskId: 't1',
            description: 'note',
            startedAt: t0,
            accumulatedSeconds: 42,
            runningSince: t1,
            createdAt: t0,
            updatedAt: u,
            deletedAt: null,
          );
      RemoteActiveTimer rt(DateTime u) => RemoteActiveTimer(
            id: 'a1',
            orgId: 'org1',
            projectId: 'p1',
            taskId: 't1',
            description: 'note',
            startedAt: t0,
            accumulatedSeconds: 42,
            runningSince: t1,
            createdAt: t0,
            updatedAt: u,
            deletedAt: null,
            serverSeq: 1,
          );
      expect(decideActiveTimerMergeFor(local(t0), rt(t1)), MergeAction.apply);
      expect(decideActiveTimerMergeFor(local(t1), rt(t0)), MergeAction.skip);
      // Two devices, DIFFERENT work → different ids → no local match → apply
      // (the row coexists rather than clobbering the other's timer).
      expect(decideActiveTimerMergeFor(null, rt(t0)), MergeAction.apply);
    });
  });

  group('template wire codec (#320, first synced table with a bool)', () {
    final template = InvoiceTemplate(
      id: 'tpl1',
      orgId: 'org1',
      name: 'Brand',
      colorBackground: 0xFF11140E,
      colorSurface: 0xFF23241F,
      colorPrimary: 0xFF69E228,
      colorText: 0xFFE2E3D8,
      colorAccent: 0xFF2E6C0F,
      fontFamily: 'Outfit',
      isDefault: true,
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('templateToWire → colours as ints, is_default as 1/0, no server_seq',
        () {
      final w = templateToWire(template);
      expect(w['color_primary'], 0xFF69E228);
      expect(w['font_family'], 'Outfit');
      expect(w['is_default'], 1);
      expect(w['updated_at'], 2000);
      expect(w.containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips; is_default 0 decodes false', () {
      final r = RemoteTemplate.fromWire({...templateToWire(template), 'server_seq': 4});
      expect(r.isDefault, isTrue);
      expect(r.colorAccent, 0xFF2E6C0F);
      expect(r.serverSeq, 4);
      expect(r.toCompanion().updatedAt.value, t1);
      final off =
          RemoteTemplate.fromWire({...templateToWire(template), 'is_default': 0});
      expect(off.isDefault, isFalse);
    });
  });

  group('profile wire codec (#320, logo via Storage not a column)', () {
    final profile = InvoiceProfile(
      id: 'pr1',
      orgId: 'org1',
      name: 'Default',
      businessName: 'Acme Pty',
      logo: Uint8List.fromList([1, 2, 3]),
      logoMime: 'image/png',
      logoPath: 'org1/pr1-abc.png',
      email: 'a@b.co',
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
      templateId: 'tpl1',
      region: 'au',
      iban: null,
      sortCode: null,
      routingNumber: null,
      payid: null,
      institutionNumber: null,
      transitNumber: null,
      showBank: true,
      showPaymentLink: false,
      showTax: true,
      showRateColumn: true,
      showTimeColumn: false,
      reverseCharge: false,
      createdAt: t0,
      updatedAt: t1,
      deletedAt: null,
    );

    test('profileToWire carries logo_path/logo_mime but NOT the bytes', () {
      final w = profileToWire(profile);
      expect(w['logo_path'], 'org1/pr1-abc.png');
      expect(w['logo_mime'], 'image/png');
      expect(w.containsKey('logo'), isFalse);
      expect(w['is_default'], 1);
      expect(w['show_payment_link'], 0);
      expect(w['show_time_column'], 0);
      expect(w['tax_rate'], 10.0);
      expect(w['template_id'], 'tpl1');
      expect(w.containsKey('server_seq'), isFalse);
    });

    test('fromWire round-trips; toCompanion OMITS logo (no clobber)', () {
      final r = RemoteProfile.fromWire({...profileToWire(profile), 'server_seq': 8});
      expect(r.logoPath, 'org1/pr1-abc.png');
      expect(r.showPaymentLink, isFalse);
      expect(r.showBank, isTrue);
      expect(r.taxRate, 10.0);
      expect(r.serverSeq, 8);
      final c = r.toCompanion();
      expect(c.logo.present, isFalse,
          reason: 'logo bytes reconcile via Storage, never via the row apply');
      expect(c.logoPath.value, 'org1/pr1-abc.png');
      expect(c.updatedAt.value, t1);
    });

    test('missing show_* booleans default to true (backfill-safe)', () {
      final w = profileToWire(profile)
        ..remove('show_bank')
        ..remove('show_tax');
      final r = RemoteProfile.fromWire(w);
      expect(r.showBank, isTrue);
      expect(r.showTax, isTrue);
    });

    test('decideProfileMergeFor / decideTemplateMergeFor delegate to LWW', () {
      final rp = RemoteProfile.fromWire(profileToWire(profile));
      expect(decideProfileMergeFor(null, rp), MergeAction.apply);
    });
  });

  group('logoObjectPath (#320) — deterministic, content-addressed', () {
    final bytesA = Uint8List.fromList([10, 20, 30]);
    final bytesB = Uint8List.fromList([10, 20, 31]);

    test('same inputs → same path (idempotent upload key)', () {
      expect(
        logoObjectPath('org1', 'pr1', bytesA, 'image/png'),
        logoObjectPath('org1', 'pr1', bytesA, 'image/png'),
      );
    });

    test('org is the first path segment (Storage RLS folder)', () {
      final p = logoObjectPath('org1', 'pr1', bytesA, 'image/png');
      expect(p.split('/').first, 'org1');
      expect(p.endsWith('.png'), isTrue);
    });

    test('different bytes → different path (cache-busts a swapped logo)', () {
      expect(
        logoObjectPath('org1', 'pr1', bytesA, 'image/png'),
        isNot(logoObjectPath('org1', 'pr1', bytesB, 'image/png')),
      );
    });

    test('mime picks the extension', () {
      expect(logoObjectPath('o', 'p', bytesA, 'image/jpeg').endsWith('.jpg'),
          isTrue);
      expect(logoObjectPath('o', 'p', bytesA, null).endsWith('.bin'), isTrue);
    });

    test('hash segment is exactly 16 lowercase hex chars (no signed "-")', () {
      // Regression: FNV-1a on native is signed → the old code leaked a leading
      // '-' and never padded. Path shape must be <org>/<profileId>-<16hex>.<ext>.
      final p = logoObjectPath('org1', 'pr1', bytesA, 'image/png');
      final hashPart = p.substring('org1/pr1-'.length, p.length - '.png'.length);
      expect(hashPart, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });

  group('per-table LWW conveniences delegate to the one rule', () {
    test('decideProjectMergeFor: newer remote applies, older skips', () {
      Project local(DateTime u) => Project(
            id: 'p1',
            clientId: 'c1',
            code: 'P1',
            title: 'P',
            status: 'active',
            createdAt: t0,
            updatedAt: u,
          );
      RemoteProject rp(DateTime u) => RemoteProject(
            id: 'p1',
            orgId: 'o',
            clientId: 'c1',
            code: 'P1',
            title: 'P',
            rate: null,
            status: 'active',
            archivedAt: null,
            createdAt: t0,
            updatedAt: u,
            deletedAt: null,
            serverSeq: 1,
          );
      expect(decideProjectMergeFor(local(t0), rp(t1)), MergeAction.apply);
      expect(decideProjectMergeFor(local(t1), rp(t0)), MergeAction.skip);
      expect(decideProjectMergeFor(null, rp(t0)), MergeAction.apply);
    });
  });
}
