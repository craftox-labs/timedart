import '../data/database.dart';

/// The CLI's own version — kept in lockstep with the app's pubspec `version`
/// (the CLI is built from, and versioned with, the app it peers with).
const String kCliVersion = '0.9.0';

/// The one-line `--version` string: the CLI version, the exact database schema
/// version this binary speaks (it refuses any other — see the schema guard),
/// and its sync-awareness. Slice 1–4 ship the plain local-SQLite path; the
/// A remote-sync-attached mode is a later (design-reserved) capability.
String versionLine() =>
    'timedart CLI $kCliVersion '
    '(db schema v${AppDatabase.latestSchemaVersion}, sync: off — plain local SQLite)';
