import 'package:timedart/data/database.dart';

// The tracker content pane is a tree (tasks → their time entries) but keyboard
// navigation moves over a *flat* list of the currently-visible rows. This file
// owns that flattening as a pure function (mirrors panel_rows.dart), so it's
// unit-testable and the widget just renders whatever list it returns.

sealed class TaskListRow {
  const TaskListRow();
  int get taskId;
}

class TaskHeaderRow extends TaskListRow {
  final Task task;
  final bool expanded; // are this task's entries showing?
  final int totalSeconds; // rolled-up tracked time across its entries
  final int entryCount;
  const TaskHeaderRow({
    required this.task,
    required this.expanded,
    required this.totalSeconds,
    required this.entryCount,
  });
  @override
  int get taskId => task.id;
}

class TaskEntryRow extends TaskListRow {
  final Task task;
  final TimeEntry entry;
  const TaskEntryRow({required this.task, required this.entry});
  @override
  int get taskId => task.id;
}

// Flatten (tasks, their entries, expansion) into the visible row list. A
// collapsed task contributes only its header; an expanded one is followed by a
// TaskEntryRow per entry (in the order [entries] arrives — watchEntriesForProject
// sorts newest-first). Entries with no taskId are ignored (shouldn't happen
// post-migration). [totalSeconds] rolls up every entry, expanded or not.
List<TaskListRow> buildTaskRows({
  required List<Task> tasks,
  required List<TimeEntry> entries,
  required bool Function(int taskId) isExpanded,
}) {
  final byTask = <int, List<TimeEntry>>{};
  for (final e in entries) {
    final tid = e.taskId;
    if (tid != null) byTask.putIfAbsent(tid, () => []).add(e);
  }

  final rows = <TaskListRow>[];
  for (final t in tasks) {
    final es = byTask[t.id] ?? const <TimeEntry>[];
    final total = es.fold<int>(0, (sum, e) => sum + e.seconds);
    final expanded = isExpanded(t.id);
    rows.add(
      TaskHeaderRow(
        task: t,
        expanded: expanded,
        totalSeconds: total,
        entryCount: es.length,
      ),
    );
    if (expanded) {
      for (final e in es) {
        rows.add(TaskEntryRow(task: t, entry: e));
      }
    }
  }
  return rows;
}
