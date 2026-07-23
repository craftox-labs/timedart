import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';

// Phase 5a delta-sync (#294) — the database seam for sync, kept OUT of the
// giant database.dart as an extension so all delta code stays under
// lib/data/sync/delta/. These are the three DB operations sync needs that the
// normal CRUD surface doesn't expose:
//
//   • clientsToPush   — read dirty rows INCLUDING tombstones (every app read
//                       filters `deletedAt IS NULL`; push must see deletes).
//   • applyRemoteClient — the `fromRemote` write path: upsert a pulled row
//                       WITHOUT re-stamping `updatedAt`, so the applied row is a
//                       fixed point (no push↔pull echo). The normal
//                       updateClient/deleteClient always bump `updatedAt`.
//   • adoptOrphanClients — stamp org_id on offline-created rows at first
//                       sign-in, bumping `updatedAt` so the watermark pushes them.

extension DeltaSyncClientQueries on AppDatabase {
  /// Dirty `clients` for push: every row (live AND tombstoned) whose
  /// `updatedAt` is strictly after [since] (the last-pushed watermark). Rows
  /// with a null `updatedAt` are excluded — they carry no clock to compare and
  /// predate sync. A null [since] returns everything (first push after sign-in).
  Future<List<Client>> clientsToPush(DateTime? since) {
    final q = select(clients);
    if (since != null) {
      q.where((c) => c.updatedAt.isBiggerThanValue(since));
    } else {
      q.where((c) => c.updatedAt.isNotNull());
    }
    return q.get();
  }

  /// The local match for a pulled id, or null. Unlike [getClient] this does NOT
  /// filter tombstones — LWW must compare against a locally-deleted row too, so
  /// a remote un-delete (or a staler remote delete) resolves correctly.
  Future<Client?> clientByIdIncludingDeleted(String id) =>
      (select(clients)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// Apply a pulled row via the `fromRemote` path: a full-row upsert keyed by
  /// `id` that writes the remote's `updatedAt` verbatim (never `DateTime.now()`).
  /// Idempotent (upsert by PK) and echo-free (equal `updatedAt` round-trips to a
  /// LWW no-op). Callers gate on [decideClientMerge] first; this just writes.
  Future<void> applyRemoteClient(RemoteClient remote) =>
      into(clients).insertOnConflictUpdate(remote.toCompanion());

  /// Adoption (first sign-in): stamp [orgId] onto every local client that has
  /// none, bumping `updatedAt` to now so the push watermark picks them up.
  /// Non-destructive — only `org_id` and `updatedAt` change. Returns the number
  /// of rows adopted.
  Future<int> adoptOrphanClients(String orgId) =>
      (update(clients)..where((c) => c.orgId.isNull())).write(
        ClientsCompanion(orgId: Value(orgId), updatedAt: Value(DateTime.now())),
      );

  // ── Sync-local key/value (device-local `app_settings`, never synced) ──
  // Own accessors rather than database.dart's private _getSetting/_setSetting,
  // so the whole delta layer stays in lib/data/sync/delta/.

  /// Read a `sync.`-namespaced setting, or null if unset.
  Future<String?> syncSetting(String key) async =>
      (await (select(appSettings)
                ..where((s) => s.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  /// Upsert a `sync.`-namespaced setting.
  Future<void> setSyncSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: Value(key),
          value: Value(value),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
