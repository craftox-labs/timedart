import 'package:flutter/material.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/tracker/task_rows.dart';
import 'package:time_tracker/widgets/focus_ring.dart';

// Renders the flattened task/entry rows: a task header (title, rolled-up time,
// amount) that expands to its indented time entries. Purely presentational —
// the cursor index, expansion, and callbacks are owned by TimerView. Styling
// mirrors the side panel (dense tiles, group dividers, edit_note action) so the
// two navigable lists feel identical.
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
      padding: const EdgeInsets.symmetric(vertical: AppTokens.space4xs),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        final tile = FocusRing(
          key: i == cursor ? cursorKey : null,
          focused: i == cursor && cursorActive,
          edgesOnly: true,
          child: switch (row) {
            TaskHeaderRow() => _taskTile(context, row),
            TaskEntryRow() => _entryTile(context, row),
          },
        );

        // A divider above each task group (except the first) and breathing room
        // after a task's last entry — mirrors the side panel's grouping.
        final dividerBefore = i > 0 && row is TaskHeaderRow;
        final lastEntry = row is TaskEntryRow &&
            (i + 1 >= rows.length || rows[i + 1] is TaskHeaderRow);
        if (!dividerBefore && !lastEntry) return tile;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dividerBefore)
              const Divider(
                height: AppTokens.strokeThin,
                thickness: AppTokens.strokeThin,
                color: AppTokens.colorBorder,
              ),
            tile,
            if (lastEntry) const SizedBox(height: AppTokens.spaceSm),
          ],
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
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.spaceMd),
      horizontalTitleGap: AppTokens.space2xs,
      onTap: () => onToggle(row.taskId),
      leading: Icon(
        row.expanded ? Icons.expand_more : Icons.chevron_right,
        size: AppTokens.iconSm,
        color: row.expanded
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        row.task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: AppTokens.fontSizeSm,
          fontWeight: FontWeight.w400,
          color: theme.colorScheme.onSurface,
        ),
      ),
      subtitle: Text(
        amount == null ? count : '$count · ${formatMoney(amount)}',
        style: TextStyle(
          fontSize: AppTokens.fontSizeXs,
          fontWeight: FontWeight.w300,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      // Edit sits to the LEFT of the time so the fixed-width time column stays
      // clean and the edit icons line up (matching the side panel's caps).
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            iconSize: AppTokens.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit task',
            onPressed: () => onEditTask(row.task),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Text(
            Duration(seconds: row.totalSeconds).hms,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      // Indent under the task header; right inset matches so the time column
      // lines up with the task rows' time.
      contentPadding: const EdgeInsets.fromLTRB(
        AppTokens.space2xl,
        AppTokens.space3xs,
        AppTokens.spaceMd,
        AppTokens.space3xs,
      ),
      onTap: () => onEditEntry(e),
      title: Text(
        when,
        style: TextStyle(
          fontSize: AppTokens.fontSizeXs,
          fontWeight: FontWeight.w300,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        Duration(seconds: e.seconds).hms,
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}
