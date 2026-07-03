import 'package:time_tracker/data/database.dart';

// The side panel is a tree (clients → jobs) but keyboard navigation moves over
// a *flat* list of the currently-visible rows. This file owns that flattening,
// plus the search filter, as a pure function so it can be unit-tested and the
// widget just renders whatever list it returns.

sealed class PanelRow {
  const PanelRow();
  int get clientId;
}

class ClientRow extends PanelRow {
  final Client client;
  final bool expanded; // is this client's job list showing?
  final bool hasJobs; // are there any (visible) jobs to expand into?
  const ClientRow({
    required this.client,
    required this.expanded,
    required this.hasJobs,
  });
  @override
  int get clientId => client.id;
}

class JobRow extends PanelRow {
  final Client client;
  final Job job;
  const JobRow({required this.client, required this.job});
  @override
  int get clientId => client.id;
}

// Build the flattened, visible row list.
//
// [isExpanded] resolves *effective* expansion for a client id — the widget
// folds in its manual expand/collapse set plus the auto rules (searching, the
// selected job's client). A collapsed client contributes only its ClientRow;
// an expanded one is followed by a JobRow per visible job.
//
// Search semantics mirror the previous _SidePanelListView: a client shows if
// its name matches or any job matches; a name hit keeps all its jobs, otherwise
// only the matching jobs.
List<PanelRow> buildPanelRows({
  required List<Client> clients,
  required List<Job> jobs,
  required String query,
  required bool Function(int clientId) isExpanded,
}) {
  final jobsByClient = <int, List<Job>>{};
  for (final j in jobs) {
    jobsByClient.putIfAbsent(j.clientId, () => []).add(j);
  }

  final q = query.trim().toLowerCase();
  final searching = q.isNotEmpty;
  bool jobMatches(Job j) => '${j.code} ${j.title}'.toLowerCase().contains(q);

  final rows = <PanelRow>[];
  for (final c in clients) {
    final clientJobs = jobsByClient[c.id] ?? const <Job>[];

    List<Job> shown;
    if (!searching) {
      shown = clientJobs;
    } else {
      final nameHit = c.name.toLowerCase().contains(q);
      final matched = clientJobs.where(jobMatches).toList();
      if (!nameHit && matched.isEmpty) continue; // client hidden entirely
      shown = nameHit ? clientJobs : matched;
    }

    final expanded = isExpanded(c.id);
    rows.add(
      ClientRow(client: c, expanded: expanded, hasJobs: shown.isNotEmpty),
    );
    if (expanded) {
      for (final j in shown) {
        rows.add(JobRow(client: c, job: j));
      }
    }
  }
  return rows;
}
