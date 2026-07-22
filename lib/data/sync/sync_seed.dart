import 'package:drift/drift.dart' show Value;

import '../backup.dart';

/// Stamp [orgId] onto the four synced content tables of a [BackupSnapshot],
/// leaving the device-local tables (templates, profiles, settings) untouched.
///
/// This is the client-side half of the Phase-4d seed: when sync is first
/// enabled, the plain-local rows are copied into the fresh PowerSync-backed
/// store, and each synced row must carry the personal `org_id` so it (a) matches
/// the sync-rule scope on the way down and (b) uploads under the right tenant.
/// New writes after seeding are stamped server-side by the Edge Function; this
/// covers the pre-existing rows that predate sync.
///
/// Pure (no I/O) so it unit-tests without a database. templates/profiles carry
/// an `orgId` column too but stay device-local in the trial (they rejoin sync in
/// Phase 5), so they are deliberately not stamped here.
BackupSnapshot stampOrgId(BackupSnapshot snapshot, String orgId) {
  final org = Value(orgId);
  return BackupSnapshot(
    clients: [for (final c in snapshot.clients) c.copyWith(orgId: org)],
    projects: [for (final p in snapshot.projects) p.copyWith(orgId: org)],
    tasks: [for (final t in snapshot.tasks) t.copyWith(orgId: org)],
    timeEntries: [for (final e in snapshot.timeEntries) e.copyWith(orgId: org)],
    templates: snapshot.templates,
    profiles: snapshot.profiles,
    settings: snapshot.settings,
  );
}
