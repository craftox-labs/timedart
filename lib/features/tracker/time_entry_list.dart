import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/widgets/focus_ring.dart';

class TimeEntryList extends StatelessWidget {
  final List<TimeEntry> entries;
  final double? rate; // effective job/client rate ($/h); null when unset
  final void Function(TimeEntry)? onEditEntry; // tap a row to edit
  final int cursor; // keyboard cursor index
  final bool cursorActive; // draw the focus ring on the cursor row
  final Key? cursorKey; // rides the cursor row for ensureVisible
  final ScrollController? scrollController;

  const TimeEntryList({
    super.key,
    required this.entries,
    this.rate,
    this.onEditEntry,
    this.cursor = 0,
    this.cursorActive = false,
    this.cursorKey,
    this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No time recorded for this job yet.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView.separated(
      controller: scrollController,
      itemCount: entries.length,
      separatorBuilder: (context, i) => const Divider(),
      itemBuilder: (context, i) {
        final e = entries[i];
        final focused = i == cursor && cursorActive;
        final loc = MaterialLocalizations.of(context);
        String time(DateTime d) =>
            loc.formatTimeOfDay(TimeOfDay.fromDateTime(d));
        // When it happened: date + start–end time, always shown.
        final when =
            '${loc.formatMediumDate(e.startedAt)} · '
            '${time(e.startedAt)} – ${time(e.endedAt)}';
        // Rate is a per-job/client constant; the amount is this entry's share.
        // Money is appended only when the effective rate is known.
        final money = rate == null
            ? ''
            : ' · ${formatMoney(rate!)}/h · '
                  '${formatMoney((e.seconds / 3600) * rate!)}';
        return FocusRing(
          // The key rides the cursor row so ensureVisible can scroll to it.
          key: i == cursor ? cursorKey : null,
          focused: focused,
          edgesOnly: true, // full-width rows: top/bottom rules, no side borders
          child: ListTile(
            title: Text(e.task),
            subtitle: Text(
              '$when$money',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w300),
            ),
            trailing: Text(Duration(seconds: e.seconds).hms),
            onTap: onEditEntry == null ? null : () => onEditEntry!(e),
          ),
        );
      },
    );
  }
}
