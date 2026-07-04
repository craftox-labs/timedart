import 'package:flutter/material.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/tracker/task_rows.dart';
import 'package:time_tracker/widgets/focus_ring.dart';

// Renders the flattened task/entry rows: a task header (title, rolled-up time,
// amount) that expands to its indented time entries. Purely presentational —
// the cursor index, expansion, and callbacks are owned by TimerView.
class TaskList extends StatelessWidget {
  final List<TaskListRow> rows;
  final double? rate; // effective job/client rate; a task may override it
  final int cursor;
  final bool cursorActive;
  final Key? cursorKey; // rides the cursor row for ensureVisible
  final ScrollController? scrollController;
  final void Function(int taskId) onToggle;
  final void Function(Task) onEditTask;
  final void Function(TimeEntry) onEditEntry;

  const TaskList({
    super.key,
    required this.rows,
    required this.rate,
    required this.onToggle,
    required this.onEditTask,
    required this.onEditEntry,
    this.cursor = 0,
    this.cursorActive = false,
    this.cursorKey,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          'No tasks yet — start the timer or add one.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView.builder(
      controller: scrollController,
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return FocusRing(
          key: i == cursor ? cursorKey : null,
          focused: i == cursor && cursorActive,
          edgesOnly: true,
          child: switch (row) {
            TaskHeaderRow() => _taskTile(context, row),
            TaskEntryRow() => _entryTile(context, row),
          },
        );
      },
    );
  }

  Widget _taskTile(BuildContext context, TaskHeaderRow row) {
    final theme = Theme.of(context);
    final effective = row.task.rate ?? rate;
    final hours = row.totalSeconds / 3600;
    final amount = effective == null ? null : hours * effective;
    final count = row.entryCount == 1 ? '1 entry' : '${row.entryCount} entries';
    return ListTile(
      leading: Icon(
        row.expanded ? Icons.expand_more : Icons.chevron_right,
        size: AppTokens.iconMd,
      ),
      title: Text(row.task.title),
      subtitle: Text(
        amount == null ? count : '$count · ${formatMoney(amount)}',
        style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w300),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(Duration(seconds: row.totalSeconds).hms),
          IconButton(
            icon: const Icon(Icons.edit, size: AppTokens.iconSm),
            visualDensity: VisualDensity.compact,
            tooltip: 'Edit task',
            onPressed: () => onEditTask(row.task),
          ),
        ],
      ),
      onTap: () => onToggle(row.taskId),
    );
  }

  Widget _entryTile(BuildContext context, TaskEntryRow row) {
    final e = row.entry;
    final loc = MaterialLocalizations.of(context);
    String time(DateTime d) => loc.formatTimeOfDay(TimeOfDay.fromDateTime(d));
    final when =
        '${loc.formatMediumDate(e.startedAt)} · '
        '${time(e.startedAt)} – ${time(e.endedAt)}';
    return ListTile(
      // Indent so entries read as children of the task header above.
      contentPadding: const EdgeInsets.only(
        left: AppTokens.space2xl,
        right: AppTokens.spaceMd,
      ),
      dense: true,
      title: Text(
        when,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w300),
      ),
      trailing: Text(Duration(seconds: e.seconds).hms),
      onTap: () => onEditEntry(e),
    );
  }
}
