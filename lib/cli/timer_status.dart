import 'package:drift/drift.dart';

import '../data/database.dart';
import '../features/tracker/timer_store.dart';
import 'timer_status_result.dart';

// ── `timer status` read model ──────────────────────────────────────────────
// Reads the active timer through the shared `lib/data` layer — no
// reimplementation of the timekeeping rules. Elapsed is derived from the wall
// clock exactly as the GUI derives it (via [TimerStore.recover]), then the
// bound project/task are resolved to human labels for the formatter.

/// Query the current timer state from [db], deriving elapsed at [now].
Future<TimerStatusResult> queryTimerStatus(
  AppDatabase db, {
  required DateTime now,
}) async {
  final store = TimerStore(db);
  // recover() rebuilds the pure session from the persisted active-timer row,
  // deriving elapsed = accumulated + (running ? now - runningSince : 0).
  await store.recover(now: now);
  final session = store.session;

  if (!session.hasSession) return TimerStatusResult.idle;

  String? projectCode;
  String? projectTitle;
  final projectId = session.boundProjectId;
  if (projectId != null) {
    try {
      final project = await db.getProject(projectId);
      projectCode = project.code;
      projectTitle = project.title;
    } catch (_) {
      // Bound project no longer live (soft-deleted): leave labels null; the id
      // is still reported so the state is never silently wrong.
    }
  }

  String? taskTitle;
  final taskId = session.boundTaskId;
  if (taskId != null) {
    final task = await (db.select(
      db.tasks,
    )..where((t) => t.id.equals(taskId) & t.deletedAt.isNull())).getSingleOrNull();
    taskTitle = task?.title;
  }

  return TimerStatusResult(
    hasTimer: true,
    running: session.isRunning,
    elapsedSeconds: session.elapsed,
    projectId: projectId,
    projectCode: projectCode,
    projectTitle: projectTitle,
    taskId: taskId,
    taskTitle: taskTitle,
    description: store.recoveredDescription,
    startedAt: session.startedAt,
  );
}
