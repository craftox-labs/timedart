import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/client_wire.dart';

// Phase 5a delta-sync (#294) — the pure conflict rule for applying a pulled row.
//
// Conflict resolution is **row-level last-write-wins by `updatedAt`**. It is the
// whole correctness core of pull, so it lives here as a pure function over the
// two rows' clocks — no database, no network — and is exhaustively unit-tested
// (local-absent / remote-newer / remote-older / equal / tombstone).
//
// A tombstone needs no special case: a soft-delete is an ordinary update that
// sets `deletedAt` and bumps `updatedAt`, so "remote is strictly newer" already
// carries deletes across. The `fromRemote` apply path (see sync_queries.dart)
// writes the remote row verbatim — `updatedAt` included — so an applied row is a
// fixed point and re-pulling it is a no-op (kills the push↔pull echo loop).

enum MergeAction {
  /// The remote row wins — upsert it locally via the `fromRemote` path.
  apply,

  /// The local copy is as new or newer — ignore the remote row.
  skip,
}

/// Decide whether a pulled remote row should overwrite the local copy.
///
/// - **Local absent** ([localUpdatedAt] == null): apply. A local row that exists
///   but carries a null `updatedAt` (legacy/unclocked) is treated the same — the
///   clocked remote is at least as authoritative.
/// - **Remote unclocked** (remote null, local present): skip — a row with no
///   clock can never win LWW.
/// - Otherwise apply iff the remote clock is **strictly after** the local one.
///   Equal → skip: idempotent, and the reason a just-pushed row echoing back is
///   a no-op.
MergeAction decideClientMerge({
  required DateTime? localUpdatedAt,
  required DateTime? remoteUpdatedAt,
}) {
  if (localUpdatedAt == null) return MergeAction.apply;
  if (remoteUpdatedAt == null) return MergeAction.skip;
  return remoteUpdatedAt.isAfter(localUpdatedAt)
      ? MergeAction.apply
      : MergeAction.skip;
}

/// Convenience over [decideClientMerge] for a whole row against its local match
/// (or null when there's no local row with that id).
MergeAction decideClientMergeFor(Client? local, RemoteClient remote) =>
    decideClientMerge(
      localUpdatedAt: local?.updatedAt,
      remoteUpdatedAt: remote.updatedAt,
    );
