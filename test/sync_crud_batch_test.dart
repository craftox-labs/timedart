import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart';
import 'package:timedart/data/sync/powersync_connector.dart';

/// Phase 4b (#209): the CRUD queue must serialise to the `{op, type, id, data}`
/// wire shape the `upload-data` Edge Function reads. This is the app↔backend
/// contract, so pin it.
void main() {
  CrudEntry entry(UpdateType op, String table, String id,
          [Map<String, dynamic>? data]) =>
      CrudEntry(1, op, table, id, 1, data);

  test('encodes op verb, table, id and data per entry', () {
    final batch = encodeCrudBatch([
      entry(UpdateType.put, 'clients', 'c1', {'name': 'Acme', 'org_id': null}),
      entry(UpdateType.patch, 'projects', 'p1', {'code': 'X'}),
      entry(UpdateType.delete, 'time_entries', 'e1'),
    ]);

    expect(batch, [
      {
        'op': 'PUT',
        'type': 'clients',
        'id': 'c1',
        'data': {'name': 'Acme', 'org_id': null},
      },
      {
        'op': 'PATCH',
        'type': 'projects',
        'id': 'p1',
        'data': {'code': 'X'},
      },
      {
        'op': 'DELETE',
        'type': 'time_entries',
        'id': 'e1',
        'data': null,
      },
    ]);
  });

  test('empty queue encodes to an empty batch', () {
    expect(encodeCrudBatch([]), isEmpty);
  });
}
