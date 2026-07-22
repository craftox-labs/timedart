import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:powersync/powersync.dart';

import 'sync_config.dart';

/// Raised when the CRUD upload cannot be applied, so PowerSync retries the whole
/// transaction (the ops stay in the local queue — nothing is dropped). Mirrors
/// the typed-exception-per-failure-mode convention in `lib/data/backup.dart`
/// (`BackupFormatException`, `BackupIncompatibleException`, …). [statusCode] is
/// the Edge Function's HTTP status when the failure was a non-200 response, null
/// when the endpoint was not configured.
class SyncUploadException implements Exception {
  final String message;
  final int? statusCode;
  const SyncUploadException(this.message, {this.statusCode});
  @override
  String toString() => 'SyncUploadException($message)';
}

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
///
/// The endpoint/token/HTTP client are injectable (defaulting to the build-time
/// consts) so the upload contract can be unit-tested without a live PowerSync
/// database or network.
class TimedartSyncConnector extends PowerSyncBackendConnector {
  TimedartSyncConnector({
    http.Client? httpClient,
    String? functionUrl,
    String? token,
  }) : _http = httpClient ?? http.Client(),
       _functionUrl = functionUrl ?? supabaseFunctionUrl,
       _token = token ?? powerSyncToken;

  final http.Client _http;
  final String _functionUrl;
  final String _token;

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    // No creds compiled in → no sync (returning null leaves the client
    // disconnected rather than throwing). Real JWT/JWKS auth is Phase 5.
    if (powerSyncUrl.isEmpty || _token.isEmpty) return null;
    return PowerSyncCredentials(endpoint: powerSyncUrl, token: _token);
  }

  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) return;
    await uploadCrudBatch(transaction.crud, transaction.complete);
  }

  /// Apply one CRUD transaction: POST the batch to the Edge Function and
  /// [complete] it **only** on a 200. Any other outcome throws
  /// [SyncUploadException] and leaves the transaction uncompleted, so the ops
  /// stay queued and PowerSync retries with backoff (the Edge Function returns
  /// 5xx only for retryable failures — it never 4xxs, which would wedge the
  /// queue). Split out from [uploadData] so it is testable without a live
  /// PowerSync database.
  Future<void> uploadCrudBatch(
    List<CrudEntry> crud,
    Future<void> Function({String? writeCheckpoint}) complete,
  ) async {
    if (_functionUrl.isEmpty) {
      // Write endpoint not configured: keep the ops queued rather than dropping
      // them (throwing leaves the transaction uncompleted → PowerSync retries).
      throw SyncUploadException(
        'SUPABASE_FUNCTION_URL is not set: '
        '${crud.length} local op(s) cannot be uploaded.',
      );
    }

    final response = await _http.post(
      Uri.parse(_functionUrl),
      headers: {
        'Content-Type': 'application/json',
        // The Edge Function decodes org_id from this token's `sub` claim.
        'Authorization': 'Bearer $_token',
      },
      body: jsonEncode({'batch': encodeCrudBatch(crud)}),
    );

    if (response.statusCode != 200) {
      throw SyncUploadException(
        'upload-data returned ${response.statusCode}: ${response.body}',
        statusCode: response.statusCode,
      );
    }

    await complete();
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
