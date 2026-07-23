import 'package:drift/drift.dart' show Value;

import 'package:timedart/data/database.dart';
import 'package:timedart/data/id.dart';

import 'timer_session.dart';

/// The outcome of [TimerStore.reconcile] — how the in-memory session changed in
/// response to the live active-timer row, so the UI layer can drive its ticker
/// and description field without re-inspecting private store state.
enum TimerReconcile {
  /// The row already matched the session (e.g. the app's own write) — no-op.
  unchanged,

  /// A previously-unowned timer was adopted (external start): seed the
  /// description from the row.
  adopted,

  /// An owned session's run state changed (external pause/resume): do NOT
  /// touch the user's description field.
  updated,

  /// The live timer went away (external stop/tombstone): session reset.
  cleared,
}

/// Owns persistence of the single active-timer row (PRD #189, Phase 3),
/// bridging the pure [TimerSession] state machine to the DB so a running timer
/// survives a restart and syncs across devices. Transitions mirror
/// TimerSession's (start / pause / finish) and additionally write the durable
/// row; [recover] rebuilds the in-memory session from a persisted row on
/// startup.
///
/// The row is written only on transitions, never per tick — `accumulatedSeconds`
/// freezes tracked time at each transition and `runningSince` marks the current
/// run's start, so elapsed is *derived* (see [ActiveTimers]) and a crash mid-run
/// recovers the true elapsed from the wall clock, not from counted ticks.
///
/// Deliberately Flutter-free (like [TimerSession]) so the future companion CLI
/// can reuse it; the UI drives [tick] from its own clock and renders [session].
class TimerStore {
  TimerStore(this._db);

  final AppDatabase _db;
  final TimerSession _session = TimerSession();
  String? _rowId; // the persisted active-timer row, once created
  String? _recoveredDescription; // session note read back on recover()

  TimerSession get session => _session;

  /// The session note restored from the persisted row on [recover] (null if
  /// none / no row). The UI seeds its description field from this.
  String? get recoveredDescription => _recoveredDescription;

  /// Rebuild the in-memory session from the persisted live row, if any. Elapsed
  /// is derived: frozen accumulated seconds plus the gap since the run resumed.
  Future<void> recover({required DateTime now}) async {
    final row = await _db.activeTimer();
    if (row == null) return;
    _rowId = row.id;
    _recoveredDescription = row.description;
    final runningSince = row.runningSince;
    final gap = runningSince == null
        ? 0
        : now.difference(runningSince).inSeconds;
    _session.restore(
      elapsed: row.accumulatedSeconds + (gap < 0 ? 0 : gap),
      startedAt: row.startedAt,
      projectId: row.projectId,
      taskId: row.taskId,
      running: runningSince != null,
    );
  }

  /// Reconcile the in-memory session to the single live active-timer [row] (or
  /// null when none is live), so an *external* write to `active_timer` — the
  /// companion CLI — is reflected in the running GUI. Meant
  /// to be driven by [AppDatabase.watchActiveTimer] emissions.
  ///
  /// Returns a [TimerReconcile] telling the caller how the session changed so it
  /// can drive its ticker / description field, or [TimerReconcile.unchanged]
  /// when the row already matches the current session — which is the case for
  /// the app's OWN writes (they emit on this stream too), making them no-ops and
  /// avoiding any refresh loop or elapsed jitter. Never writes to the DB.
  TimerReconcile reconcile(ActiveTimer? row, {required DateTime now}) {
    if (row == null) {
      // External stop / tombstone: nothing is live. Clear any local session.
      if (!_session.hasSession && _rowId == null) {
        return TimerReconcile.unchanged;
      }
      _session.reset();
      _rowId = null;
      _recoveredDescription = null;
      return TimerReconcile.cleared;
    }

    final running = row.runningSince != null;
    final matches =
        _session.hasSession &&
        _session.boundProjectId == row.projectId &&
        _session.boundTaskId == row.taskId &&
        _session.isRunning == running;
    if (matches) return TimerReconcile.unchanged; // our own state / no change

    // Adopting a timer the controller didn't previously own (external start),
    // versus updating an owned session's run state (external pause/resume).
    final adopted = !_session.hasSession;

    final gap = row.runningSince == null
        ? 0
        : now.difference(row.runningSince!).inSeconds;
    _rowId = row.id;
    _recoveredDescription = row.description;
    _session.restore(
      elapsed: row.accumulatedSeconds + (gap < 0 ? 0 : gap),
      startedAt: row.startedAt,
      projectId: row.projectId,
      taskId: row.taskId,
      running: running,
    );
    return adopted ? TimerReconcile.adopted : TimerReconcile.updated;
  }

  /// Start or resume; binds project/task at first start (a no-op while running).
  /// [description] is the current session note, persisted so it survives a
  /// restart (finalised on [finish], which reads the live field).
  Future<void> start(
    String? projectId,
    String? taskId, {
    required DateTime now,
    String? description,
  }) async {
    if (_session.isRunning) return;
    _session.start(projectId, taskId, now: now);
    await _persist(now: now, running: true, description: description);
  }

  Future<void> pause({required DateTime now, String? description}) async {
    if (!_session.isRunning) return;
    _session.pause();
    await _persist(now: now, running: false, description: description);
  }

  /// Advance the in-memory display clock one second (durable state is unchanged
  /// — it's derived from timestamps, not ticked).
  void tick() => _session.tick();

  /// Stop: persist the finished span as a [TimeEntry], tombstone the
  /// active-timer row, and reset the session. Returns what was saved, or null
  /// when there's nothing to record (empty session or no bound project/task).
  Future<FinishedSession?> finish({
    required DateTime now,
    String? description,
  }) async {
    final finished = _session.finish(now: now);
    if (finished != null) {
      await _db.addEntry(
        projectId: finished.projectId,
        taskId: finished.taskId,
        description: description,
        startedAt: finished.startedAt,
        endedAt: finished.endedAt,
        seconds: finished.seconds,
      );
    }
    final rowId = _rowId;
    if (rowId != null) {
      await _db.tombstoneActiveTimer(rowId);
      _rowId = null;
    }
    _session.reset();
    return finished;
  }

  /// Discard the running/paused timer WITHOUT recording a [TimeEntry]: tombstone
  /// the active-timer row and reset the session. Symmetric with [finish] minus
  /// the entry write — the abandon path for a mistaken session. Call [recover]
  /// first; a no-op when no row was recovered.
  Future<void> discard() async {
    final rowId = _rowId;
    if (rowId != null) {
      await _db.tombstoneActiveTimer(rowId);
      _rowId = null;
    }
    _recoveredDescription = null;
    _session.reset();
  }

  /// Edit the live timer in place — change its session note and/or rebind its
  /// project/task — WITHOUT recording an entry. Rewrites the active-timer row
  /// through [_persist], so elapsed is re-frozen into `accumulatedSeconds` and
  /// the derived total is unchanged (no reset of tracked time, no run-state
  /// flip). Run state and [startedAt] are preserved. Rebinding goes through the
  /// session so the single-active-timer invariant holds and an open GUI's
  /// [reconcile] sees the change as an `updated` (never `cleared`) transition.
  ///
  /// Pass [setDescription] to change the note (to [description], which may be
  /// null to clear it); a non-null [projectId]/[taskId] rebinds that facet.
  /// Caller must have [recover]ed a live session.
  Future<void> editRunning({
    required DateTime now,
    bool setDescription = false,
    String? description,
    String? projectId,
    String? taskId,
  }) async {
    if (setDescription) _recoveredDescription = description;
    if (projectId != null || taskId != null) {
      _session.rebind(projectId: projectId, taskId: taskId);
    }
    await _persist(
      now: now,
      running: _session.isRunning,
      description: _recoveredDescription,
    );
  }

  Future<void> _persist({
    required DateTime now,
    required bool running,
    String? description,
  }) async {
    final id = _rowId ??= idGen.newId();
    await _db.saveActiveTimer(
      ActiveTimersCompanion(
        id: Value(id),
        projectId: Value(_session.boundProjectId),
        taskId: Value(_session.boundTaskId),
        description: Value(description),
        startedAt: Value(_session.startedAt),
        // Frozen at each transition: at start it's the pre-run base, at pause the
        // full tracked total (recovery adds the running gap on top).
        accumulatedSeconds: Value(_session.elapsed),
        runningSince: Value(running ? now : null),
      ),
    );
  }
}
