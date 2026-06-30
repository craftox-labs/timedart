import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/shell/side_panel.dart';
import 'package:time_tracker/features/tracker/timer_view.dart';

class AdaptiveShell extends StatefulWidget {
  const AdaptiveShell({super.key, required this.db});
  final AppDatabase db;
  @override
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  int? _selectedJobId; // the shared state, lifted up here

  void _selectJob(int id) => setState(() => _selectedJobId = id);

  @override
  void initState() {
    super.initState();
    widget.db.ensureDefaultJob().then((id) {
      if (mounted) {
        setState(() => _selectedJobId ??= id); // default only if unset
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = TimerView(db: widget.db, jobId: _selectedJobId);

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth >= AppTokens.breakpointMd) {
          return Scaffold(
            body: Row(
              children: [
                Expanded(child: content),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 240,
                  child: SidePanel(
                    db: widget.db,
                    selectedJobId: _selectedJobId,
                    onSelect: _selectJob, // no pop — panel is persistent
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('Time Tracker')),
          endDrawer: Drawer(
            child: SidePanel(
              db: widget.db,
              selectedJobId: _selectedJobId,
              onSelect: (id) {
                _selectJob(id);
                Navigator.pop(context); // close the drawer — only here
              },
            ),
          ),
          body: content,
        );
      },
    );
  }
}
