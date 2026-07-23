import 'package:drift/drift.dart';

import 'package:timedart/data/database.dart';

// Phase 5a delta-sync (#294) — the Postgres wire shape for a `clients` row.
//
// `public.clients` (see scratch/phase5-5a-backend.sql) uses snake_case columns,
// stores every DateTime as an epoch-**millisecond** bigint, and lets the server
// author `server_seq` via a trigger. This codec is the single translation seam
// between the app's drift `Client` (camelCase fields, `DateTime?`) and that wire
// map — pure, so it unit-tests without a database or network.
//
// Kept deliberately explicit (no reflection / toJson key-munging): the column
// list is the app↔backend contract for one table, so it should read literally.

/// Encode a local [Client] as the JSON map pushed to `public.clients` (upsert
/// payload). `server_seq` is **omitted** — it is server-authored; the client
/// never writes it. `org_id` is included (adoption stamps it locally first);
/// RLS `WITH CHECK` still enforces membership server-side.
Map<String, dynamic> clientToWire(Client c) => {
  'id': c.id,
  'org_id': c.orgId,
  'name': c.name,
  'contact_name': c.contactName,
  'email': c.email,
  'phone': c.phone,
  'address': c.address,
  'abn': c.abn,
  'default_rate': c.defaultRate,
  'archived_at': _toMs(c.archivedAt),
  'created_at': _toMs(c.createdAt),
  'updated_at': _toMs(c.updatedAt),
  'deleted_at': _toMs(c.deletedAt),
};

/// A remote `clients` row parsed from PostgREST JSON: the fields needed to make
/// a last-write-wins decision ([updatedAt]) and to apply the row locally, plus
/// the server-authored [serverSeq] the pull cursor advances on.
class RemoteClient {
  final String id;
  final String? orgId;
  final String name;
  final String? contactName;
  final String? email;
  final String? phone;
  final String? address;
  final String? abn;
  final double defaultRate;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;

  /// Server-authored ordering key (`public.sync_seq`). Absent only in tests /
  /// hand-built rows; every row PostgREST returns carries one.
  final int? serverSeq;

  const RemoteClient({
    required this.id,
    required this.orgId,
    required this.name,
    required this.contactName,
    required this.email,
    required this.phone,
    required this.address,
    required this.abn,
    required this.defaultRate,
    required this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.serverSeq,
  });

  /// Decode a PostgREST JSON row (snake_case, epoch-ms ints) into a value.
  factory RemoteClient.fromWire(Map<String, dynamic> m) => RemoteClient(
    id: m['id'] as String,
    orgId: m['org_id'] as String?,
    name: m['name'] as String,
    contactName: m['contact_name'] as String?,
    email: m['email'] as String?,
    phone: m['phone'] as String?,
    address: m['address'] as String?,
    abn: m['abn'] as String?,
    defaultRate: (m['default_rate'] as num).toDouble(),
    archivedAt: _fromMs(m['archived_at']),
    createdAt: _fromMs(m['created_at']),
    updatedAt: _fromMs(m['updated_at']),
    deletedAt: _fromMs(m['deleted_at']),
    serverSeq: (m['server_seq'] as num?)?.toInt(),
  );

  /// The drift companion for a local apply. Every column is an explicit [Value]
  /// (including nulls) so `insertOnConflictUpdate` overwrites the whole row —
  /// crucially, `updatedAt` is set to the **remote's** clock, never re-stamped
  /// to now, so the applied row is a fixed point (no push↔pull echo).
  ClientsCompanion toCompanion() => ClientsCompanion(
    id: Value(id),
    orgId: Value(orgId),
    name: Value(name),
    contactName: Value(contactName),
    email: Value(email),
    phone: Value(phone),
    address: Value(address),
    abn: Value(abn),
    defaultRate: Value(defaultRate),
    archivedAt: Value(archivedAt),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    deletedAt: Value(deletedAt),
  );
}

int? _toMs(DateTime? d) => d?.millisecondsSinceEpoch;

DateTime? _fromMs(Object? ms) =>
    ms == null ? null : DateTime.fromMillisecondsSinceEpoch((ms as num).toInt());
