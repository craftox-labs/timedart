import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/backup.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/sync_activation.dart';
import 'package:timedart/data/sync/sync_seed.dart';
import 'package:timedart/data/sync/sync_token.dart';

/// Phase 4d (#211): the pure pieces of the enable-sync flow.
void main() {
  group('tokenSubject', () {
    // The real trial dev token (subject "timedart"). Only the payload matters —
    // tokenSubject never verifies the signature (trial compromise).
    const trialToken =
        'eyJhbGciOiJSUzI1NiIsImtpZCI6InBvd2Vyc3luYy1kZXYtMzIyM2Q0ZTMifQ.'
        'eyJzdWIiOiJ0aW1lZGFydCIsImlhdCI6MTc4NDY4OTY0NSwiaXNzIjoiaHR0cHM6Ly9wb3'
        'dlcnN5bmMtYXBpLmpvdXJuZXlhcHBzLmNvbSIsImF1ZCI6Imh0dHBzOi8vNmE1ZjYzNGMz'
        'Njc3NzE5NThiNDk3ZTU4LnBvd2Vyc3luYy5qb3VybmV5YXBwcy5jb20iLCJleHAiOjE3OD'
        'Q3MzI4NDV9.sig';

    test('decodes the sub claim', () {
      expect(tokenSubject(trialToken), 'timedart');
    });

    test('returns null for empty / malformed / sub-less tokens', () {
      expect(tokenSubject(''), isNull);
      expect(tokenSubject('not-a-jwt'), isNull);
      expect(tokenSubject('only.two'), isNull); // payload "two" isn't base64 JSON
    });
  });

  group('SyncActivation', () {
    test('round-trips through JSON', () {
      const a = SyncActivation(
        enabled: true,
        orgId: 'timedart',
        seedPending: true,
      );
      expect(SyncActivation.fromJson(a.toJson()), a);
    });

    test('defaults to sync-off', () {
      const a = SyncActivation();
      expect(a.enabled, isFalse);
      expect(a.orgId, isEmpty);
      expect(a.seedPending, isFalse);
    });

    test('fromJson tolerates missing / wrong-typed keys', () {
      expect(SyncActivation.fromJson(const {}), const SyncActivation());
      expect(
        SyncActivation.fromJson(const {'enabled': 'yes', 'orgId': 42}),
        const SyncActivation(), // non-bool enabled, non-string orgId → defaults
      );
    });
  });

  group('stampOrgId', () {
    final when = DateTime(2020, 1, 1);
    final snapshot = BackupSnapshot(
      clients: [Client(id: 'c1', name: 'A', defaultRate: 100)],
      projects: [
        Project(
          id: 'p1',
          clientId: 'c1',
          code: 'X',
          title: 'P',
          status: 'active',
          createdAt: when,
        ),
      ],
      tasks: [
        Task(
          id: 't1',
          projectId: 'p1',
          title: 'T',
          status: 'active',
          createdAt: when,
        ),
      ],
      timeEntries: [
        TimeEntry(
          id: 'e1',
          projectId: 'p1',
          startedAt: when,
          endedAt: when,
          seconds: 0,
        ),
      ],
      templates: const [],
      profiles: const [],
      settings: const [AppSetting(key: 'k', value: 'v')],
    );

    test('stamps org_id on every content row', () {
      final s = stampOrgId(snapshot, 'timedart');
      expect(s.clients.single.orgId, 'timedart');
      expect(s.projects.single.orgId, 'timedart');
      expect(s.tasks.single.orgId, 'timedart');
      expect(s.timeEntries.single.orgId, 'timedart');
    });

    test('leaves device-local settings untouched', () {
      final s = stampOrgId(snapshot, 'timedart');
      expect(s.settings, snapshot.settings);
    });
  });
}
