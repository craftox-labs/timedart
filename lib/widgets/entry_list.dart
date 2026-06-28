import 'package:flutter/material.dart';
import 'package:time_tracker/models/time_entry.dart'; // it uses TimeEntry → must import

class EntryList extends StatelessWidget {
  final List<TimeEntry> entries;

  const EntryList({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (context, i) => const Divider(),
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(title: Text(e.task), trailing: Text(_fmt(e.elapsed)));
      },
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}
