/// The result of a `timer status` query — a plain, I/O-free value object that
/// the (equally pure) formatter renders. Kept separate from the command so both
/// the formatter and its tests depend only on data, never on a live database.
class TimerStatusResult {
  /// Whether a timer exists at all (running OR paused). When false, every other
  /// field is at its empty default and the state is "idle".
  final bool hasTimer;

  /// True while the clock is advancing; false when the timer is paused.
  final bool running;

  /// Derived tracked seconds (accumulated + any in-progress run), computed from
  /// the wall clock at query time. Zero when idle.
  final int elapsedSeconds;

  final String? projectId;
  final String? projectCode;
  final String? projectTitle;
  final String? taskId;
  final String? taskTitle;

  /// The in-progress session note.
  final String? description;

  /// When the current session started (bound at first start).
  final DateTime? startedAt;

  const TimerStatusResult({
    required this.hasTimer,
    this.running = false,
    this.elapsedSeconds = 0,
    this.projectId,
    this.projectCode,
    this.projectTitle,
    this.taskId,
    this.taskTitle,
    this.description,
    this.startedAt,
  });

  /// The idle state: no timer running.
  static const TimerStatusResult idle = TimerStatusResult(hasTimer: false);
}
