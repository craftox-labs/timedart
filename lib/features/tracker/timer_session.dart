/// What a finished session should be persisted as.
class FinishedSession {
  final int jobId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int seconds;
  const FinishedSession({
    required this.jobId,
    required this.startedAt,
    required this.endedAt,
    required this.seconds,
  });
}

/// The timekeeping state machine, free of Flutter.
///
/// The job is bound at first [start], so switching — or losing — the selection
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
  int? _boundJobId;

  int get elapsed => _elapsed;
  bool get isRunning => _running;
  int? get boundJobId => _boundJobId;
  bool get hasSession => _running || _elapsed > 0;

  /// Start or resume. Binds [jobId] at first start; a no-op while running.
  void start(int? jobId, {required DateTime now}) {
    if (_running) return;
    _startedAt ??= now;
    _boundJobId ??= jobId;
    _running = true;
  }

  void pause() => _running = false;

  /// Advance one second.
  void tick() => _elapsed++;

  /// Stop and return what to persist, or null when there's nothing to record
  /// (empty session, or no job was ever bound). Does not clear.
  FinishedSession? finish({required DateTime now}) {
    _running = false;
    if (_elapsed == 0 || _boundJobId == null) return null;
    return FinishedSession(
      jobId: _boundJobId!,
      startedAt: _startedAt ?? now,
      endedAt: now,
      seconds: _elapsed,
    );
  }

  void reset() {
    _elapsed = 0;
    _running = false;
    _startedAt = null;
    _boundJobId = null;
  }
}
