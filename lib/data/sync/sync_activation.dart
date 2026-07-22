import 'dart:convert';
import 'dart:io';

import '../legacy_db_migration.dart'; // appDatabaseDirectory (native)

/// The runtime sync state, persisted OUTSIDE the database (PRD #189, Phase 4d).
///
/// Why a file and not an `app_settings` row: sync-on and sync-off open two
/// different SQLite files (`timedart-sync.sqlite` vs `timedart.sqlite`), each
/// with its OWN `app_settings` table — so a flag written before toggling would
/// not survive the switch. This small JSON file is read at startup, before
/// either database opens, to decide which connection to build. It lives beside
/// the databases in the app-support directory.
///
/// Enabling/disabling is a persisted intent that takes effect on the next app
/// launch (the DB executor is bound at construction; a live swap would mean
/// rebuilding the whole widget tree). [seedPending] marks that the plain-local
/// rows still need copying into the freshly-opened synced store.
class SyncActivation {
  /// Whether the synced (PowerSync) connection should be used.
  final bool enabled;

  /// The personal `org_id` stamped onto seeded rows — the sync token's `sub`.
  final String orgId;

  /// Set on enable, cleared once the local→synced seed has run.
  final bool seedPending;

  const SyncActivation({
    this.enabled = false,
    this.orgId = '',
    this.seedPending = false,
  });

  SyncActivation copyWith({bool? enabled, String? orgId, bool? seedPending}) =>
      SyncActivation(
        enabled: enabled ?? this.enabled,
        orgId: orgId ?? this.orgId,
        seedPending: seedPending ?? this.seedPending,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'orgId': orgId,
    'seedPending': seedPending,
  };

  factory SyncActivation.fromJson(Map<String, dynamic> json) => SyncActivation(
    enabled: json['enabled'] == true,
    orgId: json['orgId'] is String ? json['orgId'] as String : '',
    seedPending: json['seedPending'] == true,
  );

  @override
  bool operator ==(Object other) =>
      other is SyncActivation &&
      other.enabled == enabled &&
      other.orgId == orgId &&
      other.seedPending == seedPending;

  @override
  int get hashCode => Object.hash(enabled, orgId, seedPending);
}

Future<File> _activationFile() async {
  final dir = (await appDatabaseDirectory()) as Directory;
  return File('${dir.path}${Platform.pathSeparator}sync-activation.json');
}

/// Read the persisted sync state. A missing or unparseable file reads as the
/// default (sync off) — the app must always fall back to plain-local.
Future<SyncActivation> readSyncActivation() async {
  try {
    final file = await _activationFile();
    if (!await file.exists()) return const SyncActivation();
    final json = jsonDecode(await file.readAsString());
    return json is Map<String, dynamic>
        ? SyncActivation.fromJson(json)
        : const SyncActivation();
  } catch (_) {
    return const SyncActivation();
  }
}

Future<void> writeSyncActivation(SyncActivation activation) async {
  final file = await _activationFile();
  await file.writeAsString(jsonEncode(activation.toJson()));
}
