import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/shell/panel_rows.dart';

final _t = DateTime(2026, 1, 1);

Client _client(int id, String name) =>
    Client(id: id, name: name, defaultRate: 0);
Project _project(int id, int clientId, String code, String title) => Project(
  id: id,
  clientId: clientId,
  code: code,
  title: title,
  status: 'active',
  createdAt: _t,
);

void main() {
  final acme = _client(1, 'Acme');
  final globex = _client(2, 'Globex');
  final a1 = _project(10, 1, 'A-1', 'Website');
  final a2 = _project(11, 1, 'A-2', 'Mobile app');
  final g1 = _project(20, 2, 'G-1', 'Consulting');
  final clients = [acme, globex];
  final projects = [a1, a2, g1];

  // Nothing expanded.
  bool none(int _) => false;
  // Everything expanded.
  bool all(int _) => true;

  group('buildPanelRows — no search', () {
    test('collapsed clients contribute only their header row', () {
      final rows = buildPanelRows(
        clients: clients,
        projects: projects,
        query: '',
        isExpanded: none,
      );
      expect(rows.length, 2);
      expect(rows.every((r) => r is ClientRow), isTrue);
      expect((rows[0] as ClientRow).hasProjects, isTrue);
      expect((rows[0] as ClientRow).expanded, isFalse);
    });

    test('an expanded client is followed by its project rows, in order', () {
      final rows = buildPanelRows(
        clients: clients,
        projects: projects,
        query: '',
        isExpanded: (id) => id == 1, // only Acme
      );
      // Acme header, A-1, A-2, then Globex header (collapsed).
      expect(rows.length, 4);
      expect((rows[0] as ClientRow).client.id, 1);
      expect((rows[1] as ProjectRow).project.id, 10);
      expect((rows[2] as ProjectRow).project.id, 11);
      expect((rows[3] as ClientRow).client.id, 2);
    });

    test('client with no projects reports hasProjects=false', () {
      final rows = buildPanelRows(
        clients: [_client(3, 'Empty')],
        projects: const [],
        query: '',
        isExpanded: all,
      );
      expect(rows.single, isA<ClientRow>());
      expect((rows.single as ClientRow).hasProjects, isFalse);
    });
  });

  group('buildPanelRows — searching', () {
    test('a project-code match keeps only the matching project under its client', () {
      final rows = buildPanelRows(
        clients: clients,
        projects: projects,
        query: 'mobile',
        isExpanded: none, // search forces expansion at the widget layer, but
        // the builder trusts isExpanded — here we pass a searching resolver:
      );
      // With none(), even a matching client stays collapsed in the model.
      // The widget always passes `searching || ...`, so emulate that:
      final expandedRows = buildPanelRows(
        clients: clients,
        projects: projects,
        query: 'mobile',
        isExpanded: all,
      );
      expect(rows.whereType<ClientRow>().length, 1); // only Acme shows
      expect((rows.single as ClientRow).client.id, 1);
      // Expanded: Acme + just A-2 (the mobile match).
      expect(expandedRows.length, 2);
      expect((expandedRows[1] as ProjectRow).project.id, 11);
    });

    test('a client-name match keeps all of that client\'s projects', () {
      final rows = buildPanelRows(
        clients: clients,
        projects: projects,
        query: 'acme',
        isExpanded: all,
      );
      // Acme + both its projects; Globex hidden.
      expect(rows.length, 3);
      expect((rows[0] as ClientRow).client.id, 1);
      expect(rows.whereType<ProjectRow>().map((r) => r.project.id), [10, 11]);
    });

    test('no match hides the client entirely', () {
      final rows = buildPanelRows(
        clients: clients,
        projects: projects,
        query: 'zzz',
        isExpanded: all,
      );
      expect(rows, isEmpty);
    });
  });
}
