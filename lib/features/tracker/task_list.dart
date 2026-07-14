import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:timedart/constants/format.dart';
import 'package:timedart/constants/text_styles.dart';
import 'package:timedart/constants/tokens.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/tracker/task_rows.dart';
import 'package:timedart/widgets/focus_ring.dart';
import 'package:timedart/widgets/tap_target.dart';
import 'package:timedart/constants/layout.dart';

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
            // The first task peeks its swipe actions open once on first load
            // (narrow only) to advertise the gesture.
            TaskHeaderRow() => _taskTile(context, row, hintSwipe: i == 0),
            TaskEntryRow() => _entryTile(context, row),
          },
        );

        // A divider above each task group (except the first) and breathing room
        // after a task's last entry — mirrors the side panel's grouping.
        final dividerBefore = i > 0 && row is TaskHeaderRow;
        final lastEntry =
            row is TaskEntryRow &&
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

  double _leadingWidth(BuildContext context) =>
      context.tapColumn(AppTokens.iconMd);

  Widget _taskTile(
    BuildContext context,
    TaskHeaderRow row, {
    bool hintSwipe = false,
  }) {
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
    final narrow = context.isNarrow;
    final armed = row.taskId == selectedTaskId;
    final actionBg = armed
        ? theme
              .colorScheme
              .surfaceContainerHighest // == selectedTileColor
        : theme.colorScheme.surface; // == the unselected row bg

    final duration = Text(
      Duration(seconds: row.totalSeconds).hms,
      // rowTitle (not rowMeta) to match this row's title size — this
      // trailing text previously had no explicit style of its own and
      // inherited size/weight from the ListTile theme default.
      style: theme.extension<AppTextStyles>()!.rowTitle.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    // Wide: Add-entry then edit sit to the LEFT of the fixed-width time so the
    // time column stays aligned and the action icons line up (like the panel
    // caps). On narrow those move to the swipe panel; the time joins the meta
    // line and the swipe-hint chevron rides the title line (see below).
    final Widget? wideTrailing = narrow
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              appIconButton(
                icon: Icons.add,
                iconSize: AppTokens.iconMd,
                tooltip: 'Add entry (A)',
                onPressed: () => onAddEntryToTask(row.taskId),
              ),
              const SizedBox(width: AppTokens.spaceSm),
              appIconButton(
                icon: Icons.edit_note,
                tooltip: 'Edit task (e)',
                onPressed: () => onEditTask(row.task),
              ),
              // Wider gap before the time so its column aligns with the "Tasks"
              // header (add button → Invoice uses spaceMd).
              const SizedBox(width: AppTokens.spaceXl),
              duration,
            ],
          );

    // Narrow swipe-hint chevron — non-interactive, on the title line. The glyph
    // is centred in a square icon box, so a small horizontal nudge lands it in
    // the same column as the time on the meta line below (tune this offset).
    final chevronHint = Transform.translate(
      offset: const Offset(AppTokens.space4xs, 0),
      child: Icon(
        Icons.chevron_left,
        size: AppTokens.iconSm,
        color: theme.colorScheme.primary,
      ),
    );

    // Narrow time — meta size/colour, sitting in-line on the meta line (so the
    // swipe-hint chevron above it stays column-aligned).
    final metaDuration = Text(
      Duration(seconds: row.totalSeconds).hms,
      style: theme.extension<AppTextStyles>()!.rowMeta.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final tile = ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      minTileHeight: context.isNarrow ? AppTokens.minTouchTarget : null,
      // Armed fill is painted by an in-flow ColoredBox around the tile (below),
      // not ListTile.selectedTileColor — the latter could paint past the row and
      // over the header while scrolling. A bounded box can't overflow the row.
      // A hair of horizontal content inset so text/actions aren't flush to the
      // edge; the fill still spans the full tile width.
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space3xs,
      ),
      horizontalTitleGap: AppTokens.space2xs,
      // Tapping the row arms the task for the timer; the chevron toggles expand.
      onTap: () => onSelectTask(row.taskId),
      leading: TapTarget(
        onTap: () => onToggle(row.taskId),
        child: Icon(
          row.expanded ? Icons.expand_more : Icons.chevron_right,
          size: AppTokens.iconMd,
          color: row.expanded
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      // Narrow puts the swipe-hint chevron on the title line and the small time
      // in-line on the meta line; wide keeps plain text + the trailing actions.
      title: narrow
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    row.task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.extension<AppTextStyles>()!.rowTitle,
                  ),
                ),
                chevronHint,
              ],
            )
          : Text(
              row.task.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.extension<AppTextStyles>()!.rowTitle,
            ),
      subtitle: narrow
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.extension<AppTextStyles>()!.rowMeta,
                  ),
                ),
                const SizedBox(width: AppTokens.space2xs),
                metaDuration,
              ],
            )
          : Text(subtitle, style: theme.extension<AppTextStyles>()!.rowMeta),
      trailing: wideTrailing,
    );

    // Bounded armed fill: a ColoredBox around the row, so it can never paint
    // past the row's own box (e.g. over the header) the way selectedTileColor
    // could while scrolling.
    Widget armedWrap(Widget child) => armed
        ? ColoredBox(
            color: theme.colorScheme.surfaceContainerHighest,
            child: child,
          )
        : child;

    if (!narrow) return armedWrap(tile);

    // Narrow: swipe left to reveal Add entry / Edit task, freeing the row's
    // width so the meta line stops wrapping. The first task peeks its actions
    // open once on first load (_HintSlidable) to advertise the gesture; the
    // title-line chevron is the persistent hint.
    return armedWrap(
      _HintSlidable(
        slidableKey: ValueKey(row.taskId),
        hint: hintSwipe,
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.5,
          children: [
            SlidableAction(
              onPressed: (_) => onAddEntryToTask(row.taskId),
              icon: Icons.add,
              label: 'Add',
              backgroundColor: actionBg,
              foregroundColor: theme.colorScheme.primary,
            ),
            SlidableAction(
              onPressed: (_) => onEditTask(row.task),
              icon: Icons.edit_note,
              label: 'Edit',
              backgroundColor: actionBg,
              foregroundColor: theme.colorScheme.primary,
            ),
          ],
        ),
        child: tile,
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
    final narrow = context.isNarrow;

    final whenText = Text(
      when,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.extension<AppTextStyles>()!.rowMeta,
    );
    // Narrow: small time in-line on the meta (when) line, matching the task row.
    final entryTimeSmall = Text(
      Duration(seconds: e.seconds).hms,
      style: theme.extension<AppTextStyles>()!.rowMeta.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -4),
      minTileHeight: context.isNarrow ? AppTokens.minTouchTarget : null,
      // A transparent leading spacer the width of the task chevron + the same
      // gap and padding, so the entry text lines up exactly under the task
      // title; the time column still aligns on the right.
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space3xs,
      ),
      horizontalTitleGap: AppTokens.space2xs,
      leading: SizedBox(width: _leadingWidth(context)),
      onTap: () => onEditEntry(e),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasName)
            Text(
              desc,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.extension<AppTextStyles>()!.entryTitle,
            ),
          if (narrow)
            Row(
              children: [
                Expanded(child: whenText),
                const SizedBox(width: AppTokens.space2xs),
                entryTimeSmall,
              ],
            )
          else
            whenText,
        ],
      ),
      subtitle: null,
      // Wide keeps the larger time in the centred trailing slot; narrow moved it
      // in-line above.
      trailing: narrow
          ? null
          : Text(
              Duration(seconds: e.seconds).hms,
              style: theme.extension<AppTextStyles>()!.rowTitle.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
    );
  }
}

// --- Swipe-hint peek --------------------------------------------------------
// How far to crack the end pane open (fraction of row width; the pane's full
// extentRatio is 0.5, so ~0.22 reveals a sliver of the first action), and how
// long to hold it open before it settles back.
const double _swipeHintPeek = 0.22;
const Duration _swipeHintOpen = Duration(milliseconds: 280);
const Duration _swipeHintHold = Duration(milliseconds: 650);

/// Wraps a [Slidable] and, when [hint] is set, peeks its end action pane open
/// once (per app run) shortly after first layout, then closes it — a one-off
/// discovery nudge for the swipe gesture. Honours reduced-motion.
class _HintSlidable extends StatefulWidget {
  final Key slidableKey;
  final Widget child;
  final ActionPane endActionPane;
  final bool hint;

  const _HintSlidable({
    required this.slidableKey,
    required this.child,
    required this.endActionPane,
    this.hint = false,
  });

  @override
  State<_HintSlidable> createState() => _HintSlidableState();
}

class _HintSlidableState extends State<_HintSlidable>
    with SingleTickerProviderStateMixin {
  // Once per app run — a discovery nudge, not a nag. (Upgrade to once-ever by
  // gating on an AppSettings flag if we want it to stop after the first launch.)
  static bool _peeked = false;

  late final SlidableController _controller = SlidableController(this);

  @override
  void initState() {
    super.initState();
    if (widget.hint && !_peeked) {
      _peeked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _peek());
    }
  }

  Future<void> _peek() async {
    if (!mounted) return;
    // Respect the OS "reduce motion" setting — no auto-animation then.
    if (MediaQuery.of(context).disableAnimations) return;
    await _controller.openTo(
      -_swipeHintPeek,
      duration: _swipeHintOpen,
      curve: Curves.easeOut,
    );
    await Future<void>.delayed(_swipeHintHold);
    if (!mounted) return;
    await _controller.close(curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Slidable(
    key: widget.slidableKey,
    controller: _controller,
    endActionPane: widget.endActionPane,
    child: widget.child,
  );
}
