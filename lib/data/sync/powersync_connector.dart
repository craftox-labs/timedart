import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';

import 'sync_config.dart';

/// The app's [PowerSyncBackendConnector] for the trial (PRD #189, Phase 4).
///
/// [fetchCredentials] points the client at the Cloud instance with a dashboard
/// **Dev Token** ([powerSyncUrl] / [powerSyncToken], injected at build time) —
/// this drives the read/stream-down path (4c's definition of done).
///
/// [uploadData] (the write path, Phase 4b / #209) POSTs the local CRUD queue to
/// the `upload-data` Supabase Edge Function ([supabaseFunctionUrl]), which
/// writes it to the source Postgres with the `service_role` key and stamps
/// `org_id` from the token. See `supabase/functions/upload-data/`.
class TimedartSyncConnector extends PowerSyncBackendConnector {
  TimedartSyncConnector({http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final http.Client _http;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // No creds compiled in → no sync (returning null leaves the client
    // disconnected rather than throwing). Real JWT/JWKS auth is Phase 5.
    if (powerSyncUrl.isEmpty || powerSyncToken.isEmpty) return null;
    return PowerSyncCredentials(endpoint: powerSyncUrl, token: powerSyncToken);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;

    if (supabaseFunctionUrl.isEmpty) {
      // Write endpoint not configured: keep the ops queued rather than dropping
      // them. Throwing leaves the transaction uncompleted; PowerSync retries.
      throw StateError(
        'SUPABASE_FUNCTION_URL is not set: '
        '${transaction.crud.length} local op(s) cannot be uploaded.',
      );
    }

    final response = await _http.post(
      Uri.parse(supabaseFunctionUrl),
      headers: {
        'Content-Type': 'application/json',
        // The Edge Function decodes org_id from this token's `sub` claim.
        'Authorization': 'Bearer $powerSyncToken',
      },
      body: jsonEncode({'batch': encodeCrudBatch(transaction.crud)}),
    );

    if (response.statusCode != 200) {
      // Non-200 → do NOT complete(): the ops stay in the local queue and
      // PowerSync retries the whole transaction with backoff. The Edge Function
      // only returns 5xx for retryable failures (never 4xx, which would wedge
      // the queue), so a retry is the correct response to any non-200 here.
      throw http.ClientException(
        'upload-data returned ${response.statusCode}: ${response.body}',
        Uri.parse(supabaseFunctionUrl),
      );
    }

    await transaction.complete();
  }
}

/// Serialise a PowerSync CRUD queue to the wire shape the `upload-data` Edge
/// Function expects: one `{op, type, id, data}` object per entry, where `op` is
/// `PUT`/`PATCH`/`DELETE`, `type` is the table name and `data` is the row's
/// column map (`null` for deletes).
List<Map<String, dynamic>> encodeCrudBatch(List<CrudEntry> crud) {
  return [
    for (final entry in crud)
      {
        'op': entry.op.toJson(),
        'type': entry.table,
        'id': entry.id,
        'data': entry.opData,
      },
  ];
}
