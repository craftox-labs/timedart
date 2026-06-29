import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/tokens.dart';
import 'package:time_tracker/screens/clients.dart';
import 'package:time_tracker/screens/jobs.dart';

class SelectionPanel extends StatefulWidget {
  const SelectionPanel({
    super.key,
    required this.db,
    this.selectedJobId,
    this.onSelect,
  });
  final AppDatabase db;
  final int? selectedJobId;
  final void Function(int)? onSelect;

  @override
  State<SelectionPanel> createState() => _SelectionPanelState();
}

class _SelectionPanelState extends State<SelectionPanel> {
  late final Stream<List<Client>> _clientsStream = widget.db.watchClients();
  late final Stream<List<Job>> _jobsStream = widget.db.watchJobs();

  void _openClients() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ClientsScreen(db: widget.db)));
  void _openJobs() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => JobsScreen(db: widget.db)));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Client>>(
      stream: _clientsStream,
      builder: (context, clientSnap) {
        final clients = clientSnap.data ?? [];
        return StreamBuilder<List<Job>>(
          stream: _jobsStream,
          builder: (context, jobSnap) {
            final jobs = jobSnap.data ?? [];
            final jobsByClient = <int, List<Job>>{};
            for (final j in jobs) {
              jobsByClient.putIfAbsent(j.clientId, () => []).add(j);
            }
            return ListView(
              children: [
                for (final c in clients)
                  ExpansionTile(
                    key: PageStorageKey(
                      c.id,
                    ), // keep expand state across rebuilds
                    controlAffinity:
                        ListTileControlAffinity.leading, // chevron left
                    title: Text(c.name),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit clients',
                      onPressed: _openClients,
                    ),
                    children: [
                      for (final j in jobsByClient[c.id] ?? const <Job>[])
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: kRowInset,
                          ),
                          title: Text(j.code),
                          subtitle: Text(j.title),
                          selected: j.id == widget.selectedJobId,
                          onTap: () => widget.onSelect?.call(j.id),
                        ),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: kRowInset,
                        ),
                        leading: const Icon(Icons.add),
                        title: const Text('Add job'),
                        onTap: _openJobs,
                      ),
                    ],
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Add client'),
                  onTap: _openClients,
                ),
              ],
            );
          },
        );
      },
    );
  }
}
