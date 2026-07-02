import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/format.dart';

class TimeEntryList extends StatelessWidget {
  final List<TimeEntry> entries;

  const TimeEntryList({super.key, required this.entries});

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
        return ListTile(
          title: Text(e.task),
          trailing: Text(Duration(seconds: e.seconds).hms),
        );
      },
    );
  }
}
