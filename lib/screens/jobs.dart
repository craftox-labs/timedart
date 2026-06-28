import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/widgets/content_app_bar.dart';
import 'package:time_tracker/widgets/content_body.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, required this.db});
  final AppDatabase db;
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final _code = TextEditingController();
  final _title = TextEditingController();

  @override
  void dispose() {
    // the lifecycle discipline, again
    _code.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ContentAppBar(title: 'Jobs', showBack: true),
      body: ContentBody(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      decoration: const InputDecoration(labelText: 'Code'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () async {
                      if (_code.text.trim().isEmpty ||
                          _title.text.trim().isEmpty) {
                        return;
                      }
                      await widget.db.addJob(
                        code: _code.text.trim(),
                        title: _title.text.trim(),
                      );
                      _code.clear();
                      _title.clear();
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Job>>(
                stream: widget.db
                    .watchJobs(), // fine here — build runs rarely on this screen
                builder: (context, snap) {
                  final jobs = snap.data ?? [];
                  return ListView(
                    children: [
                      for (final j in jobs)
                        ListTile(title: Text(j.title), subtitle: Text(j.code)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
