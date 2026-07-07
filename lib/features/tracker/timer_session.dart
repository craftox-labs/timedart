/// What a finished session should be persisted as.
class FinishedSession {
  final int projectId;
  final int taskId;
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
  int? _boundProjectId;
  int? _boundTaskId;

  int get elapsed => _elapsed;
  bool get isRunning => _running;
  int? get boundProjectId => _boundProjectId;
  int? get boundTaskId => _boundTaskId;
  bool get hasSession => _running || _elapsed > 0;

  /// Start or resume. Binds [projectId]/[taskId] at first start so a selection
  /// change mid-session can't misattribute time; a no-op while running.
  void start(int? projectId, int? taskId, {required DateTime now}) {
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
