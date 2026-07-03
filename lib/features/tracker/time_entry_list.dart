import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/format.dart';

class TimeEntryList extends StatelessWidget {
  final List<TimeEntry> entries;
  final double? rate; // effective job/client rate ($/h); null when unset
  final void Function(TimeEntry)? onEditEntry; // tap a row to edit

  const TimeEntryList({
    super.key,
    required this.entries,
    this.rate,
    this.onEditEntry,
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
      itemCount: entries.length,
      separatorBuilder: (context, i) => const Divider(),
      itemBuilder: (context, i) {
        final e = entries[i];
        // Rate is a per-job/client constant; the amount is this entry's share.
        final amount = rate == null ? null : (e.seconds / 3600) * rate!;
        return ListTile(
          title: Text(e.task),
          subtitle: rate == null
              ? null
              : Text(
                  '${formatMoney(rate!)}/h · ${formatMoney(amount!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          trailing: Text(Duration(seconds: e.seconds).hms),
          onTap: onEditEntry == null ? null : () => onEditEntry!(e),
        );
      },
    );
  }
}
