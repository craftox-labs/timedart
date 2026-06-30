import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/format.dart';

class TimeEntryList extends StatelessWidget {
  final List<TimeEntry> entries;

  const TimeEntryList({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
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
