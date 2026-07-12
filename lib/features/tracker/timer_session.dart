/// What a finished session should be persisted as.
class FinishedSession {
  final String projectId;
  final String taskId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int seconds;
  const FinishedSession({
    required this.projectId,
    required this.taskId,
    required this.startedAt,
    required this.endedAt,
    required this.seconds,
  });
}

/// The timekeeping state machine, free of Flutter.
///
/// The project is bound at first [start], so switching — or losing — the selection
/// mid-session can't misattribute or silently discard tracked time. The clock
/// lives in the widget and drives [tick]; persistence lives in the widget too.
/// [finish] returns what to save *without* clearing, so a failed write can be
/// retried against an intact session — call [reset] only after a good write.
///
/// [start] and [finish] take `now` as a parameter rather than reading the clock
/// themselves, so the rules are testable without waiting on real time.
class TimerSession {
  int _elapsed = 0;
  bool _running = false;
  DateTime? _startedAt;
  String? _boundProjectId;
  String? _boundTaskId;

  int get elapsed => _elapsed;
  bool get isRunning => _running;
  DateTime? get startedAt => _startedAt;
  String? get boundProjectId => _boundProjectId;
  String? get boundTaskId => _boundTaskId;
  bool get hasSession => _running || _elapsed > 0;

  /// Rebuild the session from persisted state (PRD #189, Phase 3 recovery). Used
  /// by the [TimerStore] to restore a DB-backed timer on startup; [elapsed] is
  /// the already-derived tracked seconds (accumulated + any running gap).
  void restore({
    required int elapsed,
    required DateTime? startedAt,
    required String? projectId,
    required String? taskId,
    required bool running,
  }) {
    _elapsed = elapsed;
    _startedAt = startedAt;
    _boundProjectId = projectId;
    _boundTaskId = taskId;
    _running = running;
  }

  /// Start or resume. Binds [projectId]/[taskId] at first start so a selection
  /// change mid-session can't misattribute time; a no-op while running.
  void start(String? projectId, String? taskId, {required DateTime now}) {
    if (_running) return;
    _startedAt ??= now;
    _boundProjectId ??= projectId;
    _boundTaskId ??= taskId;
    _running = true;
  }

  void pause() => _running = false;

  /// Advance one second.
  void tick() => _elapsed++;

  /// Stop and return what to persist, or null when there's nothing to record
  /// (empty session, or no project was ever bound). Does not clear.
  FinishedSession? finish({required DateTime now}) {
    _running = false;
    if (_elapsed == 0 || _boundProjectId == null || _boundTaskId == null) {
      return null;
    }
    return FinishedSession(
      projectId: _boundProjectId!,
      taskId: _boundTaskId!,
      startedAt: _startedAt ?? now,
      endedAt: now,
      seconds: _elapsed,
    );
  }

  void reset() {
    _elapsed = 0;
    _running = false;
    _startedAt = null;
    _boundProjectId = null;
    _boundTaskId = null;
  }
}
