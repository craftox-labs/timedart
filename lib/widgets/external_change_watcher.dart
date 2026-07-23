import 'dart:async';

import 'package:flutter/widgets.dart';

import '../data/database.dart';
import '../data/external_change_detector.dart';

/// Keeps the running GUI in step with *external* database writes — the
/// companion CLI, or a delta-sync apply — with no manual
/// refresh (PRD #270, slice #274).
///
/// It is a thin lifecycle/timer shell around the pure [ExternalChangeDetector]:
/// while the app is foregrounded it polls `PRAGMA data_version` (~1s) and on
/// app-focus-gain (`resumed`), and whenever the detector reports a new value —
/// meaning another connection committed — it calls [AppDatabase.refreshAllStreams]
/// so every open `watch()` re-emits and the visible UI repaints. Polling stops
/// while backgrounded to avoid needless wakeups. `data_version` is stable across
/// this connection's own writes, so the app's own edits never trigger a refresh.
class ExternalChangeWatcher extends StatefulWidget {
  const ExternalChangeWatcher({
    super.key,
    required this.db,
    required this.child,
    this.interval = const Duration(seconds: 1),
  });

  final AppDatabase db;
  final Widget child;

  /// How often to poll while foregrounded.
  final Duration interval;

  @override
  State<ExternalChangeWatcher> createState() => _ExternalChangeWatcherState();
}

class _ExternalChangeWatcherState extends State<ExternalChangeWatcher>
    with WidgetsBindingObserver {
  final _detector = ExternalChangeDetector();
  Timer? _timer;
  bool _checking = false; // guards against overlapping async polls

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startPolling();
  }

  @override
  void dispose() {
    _stopPolling();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Focus regained: check immediately, then resume periodic polling.
      _startPolling();
      unawaited(_check());
    } else {
      // Backgrounded/inactive/hidden: stop waking up. Drop the baseline so the
      // first poll after resume re-establishes it without a spurious refresh
      // for changes we can't distinguish from our own across the gap.
      _stopPolling();
      _detector.reset();
    }
  }

  void _startPolling() {
    _timer ??= Timer.periodic(widget.interval, (_) => unawaited(_check()));
  }

  void _stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final version = await widget.db.dataVersion();
      if (_detector.observe(version)) {
        widget.db.refreshAllStreams();
      }
    } catch (_) {
      // A transient read failure (e.g. mid-close) must never crash the UI;
      // the next tick retries.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
