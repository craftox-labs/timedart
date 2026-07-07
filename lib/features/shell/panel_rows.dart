import 'package:time_tracker/data/database.dart';

// The side panel is a tree (clients → projects) but keyboard navigation moves over
// a *flat* list of the currently-visible rows. This file owns that flattening,
// plus the search filter, as a pure function so it can be unit-tested and the
// widget just renders whatever list it returns.

sealed class PanelRow {
  const PanelRow();
  int get clientId;
}

class ClientRow extends PanelRow {
  final Client client;
  final bool expanded; // is this client's project list showing?
  final bool hasProjects; // are there any (visible) projects to expand into?
  const ClientRow({
    required this.client,
    required this.expanded,
    required this.hasProjects,
  });
  @override
  int get clientId => client.id;
}

class ProjectRow extends PanelRow {
  final Client client;
  final Project project;
  const ProjectRow({required this.client, required this.project});
  @override
  int get clientId => client.id;
}

// Build the flattened, visible row list.
//
// [isExpanded] resolves *effective* expansion for a client id — the widget
// folds in its manual expand/collapse set plus the auto rules (searching, the
// selected project's client). A collapsed client contributes only its ClientRow;
// an expanded one is followed by a ProjectRow per visible project.
//
// Search semantics mirror the previous _SidePanelListView: a client shows if
// its name matches or any project matches; a name hit keeps all its projects, otherwise
// only the matching projects.
List<PanelRow> buildPanelRows({
  required List<Client> clients,
  required List<Project> projects,
  required String query,
  required bool Function(int clientId) isExpanded,
}) {
  final projectsByClient = <int, List<Project>>{};
  for (final j in projects) {
    projectsByClient.putIfAbsent(j.clientId, () => []).add(j);
  }

  final q = query.trim().toLowerCase();
  final searching = q.isNotEmpty;
  bool projectMatches(Project j) => '${j.code} ${j.title}'.toLowerCase().contains(q);

  final rows = <PanelRow>[];
  for (final c in clients) {
    final clientProjects = projectsByClient[c.id] ?? const <Project>[];

    List<Project> shown;
    if (!searching) {
      shown = clientProjects;
    } else {
      final nameHit = c.name.toLowerCase().contains(q);
      final matched = clientProjects.where(projectMatches).toList();
      if (!nameHit && matched.isEmpty) continue; // client hidden entirely
      shown = nameHit ? clientProjects : matched;
    }

    final expanded = isExpanded(c.id);
    rows.add(
      ClientRow(client: c, expanded: expanded, hasProjects: shown.isNotEmpty),
    );
    if (expanded) {
      for (final j in shown) {
        rows.add(ProjectRow(client: c, project: j));
      }
    }
  }
  return rows;
}
