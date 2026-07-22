import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:powersync/powersync.dart';
import 'package:timedart/data/sync/powersync_connector.dart';

/// Phase 4b (#209): the write path's core safety contract — `complete()` fires
/// only on a 200, and any other outcome throws (leaving the ops queued for
/// retry, never dropped or wedged).
void main() {
  final entry = CrudEntry(1, UpdateType.put, 'clients', 'c1', 1, {'name': 'A'});

  Future<void> noopComplete({String? writeCheckpoint}) async {}

  test('200 → completes the transaction and posts the batch', () async {
    http.Request? seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response('{"applied":1}', 200);
    });
    final connector = TimedartSyncConnector(
      httpClient: client,
      functionUrl: 'https://example.test/upload-data',
      token: 'the-token',
    );

    var completed = false;
    await connector.uploadCrudBatch([entry], ({writeCheckpoint}) async {
      completed = true;
    });

    expect(completed, isTrue);
    // The batch and bearer reached the endpoint.
    expect(seen!.headers['Authorization'], 'Bearer the-token');
    final body = jsonDecode(seen!.body) as Map<String, dynamic>;
    expect(body['batch'], [
      {
        'op': 'PUT',
        'type': 'clients',
        'id': 'c1',
        'data': {'name': 'A'},
      },
    ]);
  });

  test('non-200 → throws and does NOT complete (ops stay queued)', () async {
    final client = MockClient((_) async => http.Response('boom', 500));
    final connector = TimedartSyncConnector(
      httpClient: client,
      functionUrl: 'https://example.test/upload-data',
      token: 'the-token',
    );

    var completed = false;
    await expectLater(
      connector.uploadCrudBatch([entry], ({writeCheckpoint}) async {
        completed = true;
      }),
      throwsA(isA<SyncUploadException>()),
    );
    expect(completed, isFalse);
  });

  test('missing endpoint → throws without posting or completing', () async {
    var posted = false;
    final client = MockClient((_) async {
      posted = true;
      return http.Response('', 200);
    });
    final connector = TimedartSyncConnector(
      httpClient: client,
      functionUrl: '',
      token: 'the-token',
    );

    await expectLater(
      connector.uploadCrudBatch([entry], noopComplete),
      throwsA(isA<SyncUploadException>()),
    );
    expect(posted, isFalse);
  });
}
