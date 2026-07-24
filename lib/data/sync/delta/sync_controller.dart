import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:timedart/data/database.dart';
import 'package:timedart/data/sync/delta/sync_service.dart';

// Phase 5c delta-sync (#294) — the trigger coordinator.
//
// 5a/5b built a single sync *pass* (DeltaSyncService.syncAll) fired only by the
// maintainer's "Sync now" button. 5c is what drives that pass automatically:
// on app foreground, after a timer stops, and on a light periodic tick — plus a
// persistent status the UI can watch instead of a one-shot snackbar. It also
// makes the whole thing robust to being called from several triggers at once
// and to being offline.
//
// Two invariants hold everything together:
//   1. **One pass at a time.** A trigger that fires mid-pass doesn't start a
//      second concurrent pass (which would double-push and race the outbox
//      drain guard); it sets a re-run flag so the latest local changes still
//      go out on a single follow-up pass.
//   2. **Background triggers are silent.** They only move [status]; they never
//      surface a snackbar (a sync every few minutes would be noise). Only the
//      explicit "Sync now" reports its result to the user — it awaits
//      [syncNow] and reads [lastResult]/[lastError].
//
// Everything here is inert unless `deltaSyncConfigured` — the shell only
// constructs a controller in a maintainer's ENABLE_DELTA_SYNC build, so
// released builds never schedule a tick, observe lifecycle, or touch the
// network.

/// What kicked off a pass — for logging and to decide snackbar vs silent.
enum SyncTrigger {
  /// The maintainer tapped "Sync now". The only trigger that reports back.
  manual,

  /// The app returned to the foreground (resumed lifecycle state).
  foreground,

  /// A running timer was just stopped and its entry committed.
  timerStop,

  /// A running-timer state change (start/pause) that records no entry (#300) —
  /// pushes the live timer so it shows as running/paused on the other device.
  timerChanged,

  /// The periodic safety-net tick (mainly to pull the other device's edits
  /// while this one sits open).
  periodic,

  /// The maintainer just turned sync on — the first pass signs in and adopts
  /// any offline-created local rows (Phase 5d).
  enable,
}

/// Coarse state of the sync engine, surfaced to the maintainer status line.
enum SyncPhase { idle, syncing }

/// The base gap between periodic ticks when things are healthy.
const Duration kPeriodicSyncInterval = Duration(minutes: 5);

/// The ceiling the periodic gap backs off to after repeated failures, so an
/// offline device settles to one retry every [kMaxBackoff] instead of hammering.
const Duration kMaxBackoff = Duration(minutes: 30);

/// How long a single pass may run before it's treated as failed. Without this a
/// pass whose network call hangs (the device went offline mid-request) sits in
/// [SyncPhase.syncing] until the OS socket timeout finally fires — which in
/// practice only resolves when connectivity returns. A generous bound: a
/// healthy pass over this app's tiny dataset finishes in well under a second,
/// so 15s won't false-trip on a slow-but-working link, yet a dead network
/// surfaces as `offline` within it.
const Duration kSyncTimeout = Duration(seconds: 15);

/// Owns automatic sync scheduling and the observable sync status. A
/// [ChangeNotifier] so a status widget can rebuild on every transition.
class SyncController extends ChangeNotifier {
  SyncController(
    this._db, {
    Future<SyncResult> Function()? runner,
    DateTime Function()? clock,
    this.enablePeriodic = true,
    this.periodicInterval = kPeriodicSyncInterval,
    this.syncTimeout = kSyncTimeout,
    bool startEnabled = false,
  })  : _clock = clock ?? DateTime.now,
        _enabled = startEnabled {
    // Build the default service once (it flips `enableSyncOutbox` on and holds
    // a transport/auth). Tests inject a [runner] instead and skip this.
    _runner = runner ?? (() => (_service ??= DeltaSyncService(_db)).syncAll());
  }

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Whether the periodic safety-net tick is armed. Off in tests that drive
  /// passes by hand.
  final bool enablePeriodic;

  /// The healthy gap between periodic ticks (widened by backoff on failure).
  final Duration periodicInterval;

  /// The per-pass deadline: a pass exceeding this is failed as offline instead
  /// of hanging on a dead socket (see [kSyncTimeout]).
  final Duration syncTimeout;
  late final Future<SyncResult> Function() _runner;
  DeltaSyncService? _service;

  // ── Observable status ──────────────────────────────────────────────────
  SyncPhase _phase = SyncPhase.idle;
  SyncPhase get phase => _phase;

  /// The last completed pass's result (skipped passes included). Null until the
  /// first pass finishes.
  SyncResult? _lastResult;
  SyncResult? get lastResult => _lastResult;

  /// The error from the last pass, if it threw (e.g. offline). Cleared on the
  /// next success.
  Object? _lastError;
  Object? get lastError => _lastError;

  /// When the last *successful* (didSync) pass completed. Drives "synced 2m
  /// ago". Null until one succeeds.
  DateTime? _lastSyncedAt;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// What triggered the pass currently running (or the last one). For logs.
  SyncTrigger? get lastTrigger => _lastTrigger;
  SyncTrigger? _lastTrigger;

  // ── Scheduling state ─────────────────────────────────────────────────────
  Future<void>? _inFlight;
  bool _rerunQueued = false;
  int _consecutiveFailures = 0;
  Timer? _periodicTimer;
  bool _enabled;
  bool _disposed = false;

  /// True while a pass is in flight — exposed for tests and callers that want to
  /// avoid piling on.
  bool get isSyncing => _inFlight != null;

  /// Whether the maintainer has opted delta sync ON (Phase 5d). While off, every
  /// trigger is a no-op — no sign-in, no network, no periodic tick — so a
  /// local-only device has zero server footprint. The shell mirrors the
  /// persisted `sync.delta.enabled` flag into this.
  bool get enabled => _enabled;

  /// Turn sync on or off. Turning ON arms the periodic tick and kicks a pass
  /// (which signs in + adopts offline-created local rows). Turning OFF cancels
  /// the tick and stops future triggers — it does NOT sign out or touch local
  /// data, so re-enabling resumes the same account and nothing is lost. Returns
  /// the enable pass's future (a no-op future when turning off or unchanged).
  Future<void> setEnabled(bool value) {
    if (_disposed || value == _enabled) return Future<void>.value();
    _enabled = value;
    notifyListeners();
    if (value) {
      _armPeriodic();
      return requestSync(SyncTrigger.enable);
    }
    _periodicTimer?.cancel();
    return Future<void>.value();
  }

  /// Request a sync. If one is already running, coalesce into a single re-run so
  /// the just-made change still goes out. Fire-and-forget safe: it never throws
  /// (errors land in [lastError]). Returns the in-flight future so [manual] can
  /// await the outcome. A no-op while sync is [enabled] == false.
  Future<void> requestSync(SyncTrigger trigger) {
    if (_disposed || !_enabled) return Future<void>.value();
    if (_inFlight != null) {
      _rerunQueued = true;
      return _inFlight!;
    }
    _lastTrigger = trigger;
    return _inFlight = _pump();
  }

  /// Await a full pass, used by the manual "Sync now" button so it can report
  /// the result. Coalesces exactly like [requestSync].
  Future<void> syncNow() => requestSync(SyncTrigger.manual);

  // Drain loop: run passes back-to-back while a re-run is queued, so a change
  // made during a pass is never stranded, then settle to idle.
  Future<void> _pump() async {
    _phase = SyncPhase.syncing;
    notifyListeners();
    try {
      do {
        _rerunQueued = false;
        await _runOnce();
      } while (_rerunQueued && !_disposed);
    } finally {
      _phase = SyncPhase.idle;
      _inFlight = null;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _runOnce() async {
    try {
      // Bound the pass: a hung network call (device went offline mid-request)
      // otherwise leaves us in `syncing` until the OS socket timeout, which in
      // practice only resolves when connectivity returns. On timeout the
      // abandoned pass keeps running to completion in the background; Dart's
      // Future.timeout silently discards its late result/error, so nothing
      // leaks. The outbox stays dirty, so nothing is lost — it re-pushes next
      // pass.
      final result = await _runner().timeout(syncTimeout);
      _lastResult = result;
      _lastError = null;
      if (result.didSync) _lastSyncedAt = _clock();
      _consecutiveFailures = 0;
    } catch (e) {
      // Offline / timeout / server error: keep the outbox dirty (the service
      // already left it so on a throw), record the error, and let backoff widen
      // the next periodic retry. Never rethrow — triggers are fire-and-forget.
      _lastError = e;
      _consecutiveFailures++;
    }
    if (!_disposed) notifyListeners();
    // Re-arm the periodic tick against the (possibly backed-off) interval.
    if (_enabled) _armPeriodic();
  }

  // Periodic tick, re-armed as a single-shot Timer each time so the interval can
  // widen under backoff. `2^failures × base`, capped at [kMaxBackoff].
  void _armPeriodic() {
    if (!enablePeriodic || _disposed || !_enabled) return;
    _periodicTimer?.cancel();
    _periodicTimer = Timer(_nextInterval(), () {
      requestSync(SyncTrigger.periodic);
    });
  }

  Duration _nextInterval() {
    if (_consecutiveFailures == 0) return periodicInterval;
    // Cap the shift so the multiplication can't overflow, then clamp the result.
    final shift = _consecutiveFailures.clamp(0, 20);
    final scaled = periodicInterval * (1 << shift);
    return scaled > kMaxBackoff ? kMaxBackoff : scaled;
  }

  @override
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    super.dispose();
  }
}
