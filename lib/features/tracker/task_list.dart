import 'package:flutter/material.dart';
import 'package:timedart/constants/format.dart';
import 'package:timedart/constants/text_styles.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/tracker/task_rows.dart';
import 'package:timedart/widgets/focus_ring.dart';

// Renders the flattened task/entry rows: a task header (title, rolled-up time,
// amount) that expands to its indented time entries. Purely presentational —
// the cursor index, expansion, and callbacks are owned by TimerView. Styling
// mirrors the side panel (dense tiles, group dividers, edit_note action) so the
// two navigable lists feel identical.
class TaskList extends StatelessWidget {
  final List<TaskListRow> rows;
  final double? rate; // effective project/client rate; a task may override it
  final String? selectedTaskId; // the task the timer is armed on / tracking
  final int cursor;
  final bool cursorActive;
  final Key? cursorKey; // rides the cursor row for ensureVisible
  final ScrollController? scrollController;
  final void Function(String taskId) onSelectTask; // arm for the timer
  final void Function(String taskId) onToggle; // expand/collapse
  final void Function(String taskId) onAddEntryToTask;
  final void Function(Task) onEditTask;
  final void Function(TimeEntry) onEditEntry;

  const TaskList({
    super.key,
    required this.rows,
    required this.rate,
    required this.onSelectTask,
    required this.onToggle,
    required this.onAddEntryToTask,
    required this.onEditTask,
    required this.onEditEntry,
    this.selectedTaskId,
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
      // No top padding: the first task's focus ring sits flush against the
      // section divider above. A little breathing room at the bottom only.
      padding: const EdgeInsets.only(bottom: AppTokens.space4xs),
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
    // count · @$rate/hr · $amount — rate/amount drop out when no rate is set.
    final subtitle = [
      count,
      if (effective != null) '@${formatMoney(effective)}/hr',
      if (amount != null) formatMoney(amount),
    ].join(' · ');
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      selected: row.taskId == selectedTaskId, // armed/tracking → green pill
      // A hair of horizontal content inset so text/actions aren't flush to the
      // edge; the selected fill still spans the full tile width.
      contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.space3xs),
      horizontalTitleGap: AppTokens.space2xs,
      // Tapping the row arms the task for the timer; the chevron toggles expand.
      onTap: () => onSelectTask(row.taskId),
      leading: GestureDetector(
        onTap: () => onToggle(row.taskId),
        child: Icon(
          row.expanded ? Icons.expand_more : Icons.chevron_right,
          size: AppTokens.iconSm,
          color: row.expanded
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        row.task.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.extension<AppTextStyles>()!.rowTitle,
      ),
      subtitle: Text(
        subtitle,
        style: theme.extension<AppTextStyles>()!.rowMeta,
      ),
      // Add-entry then edit sit to the LEFT of the fixed-width time so the time
      // column stays aligned and the action icons line up (like the panel caps).
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add),
            iconSize: AppTokens.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Add entry (A)',
            onPressed: () => onAddEntryToTask(row.taskId),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          IconButton(
            icon: const Icon(Icons.edit_note),
            iconSize: AppTokens.iconMd,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Edit task (e)',
            onPressed: () => onEditTask(row.task),
          ),
          // Wider gap before the time so its column aligns with the "Tasks"
          // header (add button → Invoice uses spaceMd).
          const SizedBox(width: AppTokens.spaceMd),
          Text(
            Duration(seconds: row.totalSeconds).hms,
            // rowTitle (not rowMeta) to match this row's title size — this
            // trailing text previously had no explicit style of its own and
            // inherited size/weight from the ListTile theme default.
            style: theme.extension<AppTextStyles>()!.rowTitle.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(BuildContext context, TaskEntryRow row) {
    final theme = Theme.of(context);
    final e = row.entry;
    final loc = MaterialLocalizations.of(context);
    String time(DateTime d) => loc.formatTimeOfDay(TimeOfDay.fromDateTime(d));
    final when =
        '${loc.formatMediumDate(e.startedAt)} · '
        '${time(e.startedAt)} – ${time(e.endedAt)}';
    final desc = e.description?.trim();
    final hasName = desc != null && desc.isNotEmpty;
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      // A transparent leading spacer the width of the task chevron + the same
      // gap and padding, so the entry text lines up exactly under the task
      // title; the time column still aligns on the right.
      contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.space3xs),
      horizontalTitleGap: AppTokens.space2xs,
      leading: const SizedBox(width: AppTokens.iconSm),
      onTap: () => onEditEntry(e),
      title: Text(
        hasName ? desc : when,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.extension<AppTextStyles>()!.rowMeta,
      ),
      subtitle: hasName
          ? Text(
              when,
              style: theme.extension<AppTextStyles>()!.rowMeta.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            )
          : null,
      trailing: Text(
        Duration(seconds: e.seconds).hms,
        // rowTitle (not rowMeta) — like the task row's duration above, this
        // previously had no explicit style and inherited the ListTile theme
        // default's size, independent of this row's own (smaller) title.
        style: theme.extension<AppTextStyles>()!.rowTitle.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
