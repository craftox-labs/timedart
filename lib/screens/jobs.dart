import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/widgets/content_app_bar.dart';
import 'package:time_tracker/widgets/content_body.dart';
import 'package:time_tracker/tokens.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key, required this.db});
  final AppDatabase db;
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  final _code = TextEditingController();
  final _title = TextEditingController();
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients();
  int? _clientId;
  late final Stream<List<JobWithRate>> _jobsWithRateStream = widget.db
      .watchJobsWithRate();

  @override
  void dispose() {
    // lifecycle
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
                  const SizedBox(width: kSizedBoxSm),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _title,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                  ),
                  const SizedBox(width: kSizedBoxSm),
                  FilledButton(
                    onPressed: () async {
                      if (_code.text.trim().isEmpty ||
                          _title.text.trim().isEmpty ||
                          _clientId == null) {
                        return;
                      }
                      await widget.db.addJob(
                        clientId: _clientId!,
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
            StreamBuilder<List<Client>>(
              stream: _clientsStream,
              builder: (context, snap) {
                final clients = snap.data ?? [];
                final value = clients.any((c) => c.id == _clientId)
                    ? _clientId
                    : null;
                return DropdownButton<int>(
                  value: value,
                  hint: const Text('Client'),
                  items: [
                    for (final c in clients)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (id) => setState(() => _clientId = id),
                );
              },
            ),
            Expanded(
              child: StreamBuilder<List<JobWithRate>>(
                stream: _jobsWithRateStream,
                builder: (context, snap) {
                  final rows = snap.data ?? [];
                  return ListView(
                    children: [
                      for (final r in rows)
                        ListTile(
                          title: Text(r.job.title),
                          subtitle: Text(r.job.code),
                          trailing: Text(
                            r.effectiveRate != null
                                ? '\$${r.effectiveRate!.toStringAsFixed(2)}/hr'
                                : 'no rate set',
                          ), // null = un-billable, surface it
                        ),
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
