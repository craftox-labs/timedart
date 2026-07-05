import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:time_tracker/data/database.dart';

// Data-layer coverage for the invoice-branding tables (PRD #79): the v4→v5
// migration, idempotent seeding, and single-default resolution.

// Hand-built schema-v4 DDL: clients has the NOT NULL default_rate (from v4) but
// NOT the v5 contactName/phone; time_entries is the v3+ shape (description, no
// `task`); no branding tables. user_version = 4.
AppDatabase _openV4() {
  final raw = sqlite3.openInMemory();
  raw.execute('''
    CREATE TABLE clients (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, email TEXT, address TEXT, abn TEXT,
      default_rate REAL NOT NULL, archived_at INTEGER);
    CREATE TABLE jobs (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      client_id INTEGER NOT NULL REFERENCES clients (id), code TEXT NOT NULL UNIQUE,
      title TEXT NOT NULL, rate REAL, status TEXT NOT NULL DEFAULT 'active',
      created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')));
    CREATE TABLE tasks (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      job_id INTEGER NOT NULL REFERENCES jobs (id), title TEXT NOT NULL,
      rate REAL, status TEXT NOT NULL DEFAULT 'active',
      created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')));
    CREATE TABLE time_entries (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      job_id INTEGER NOT NULL REFERENCES jobs (id),
      task_id INTEGER REFERENCES tasks (id), description TEXT,
      started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, seconds INTEGER NOT NULL);
    INSERT INTO clients (id, name, default_rate) VALUES (1, 'Acme', 100);
    PRAGMA user_version = 4;
  ''');
  return AppDatabase(NativeDatabase.opened(raw));
}

void main() {
  test('v4→v5 adds branding tables and the new Client columns', () async {
    final db = _openV4();
    addTearDown(db.close);

    // The three branding tables now exist (querying them would throw otherwise).
    expect(await db.select(db.themes).get(), isEmpty);
    expect(await db.select(db.profiles).get(), isEmpty);
    expect(await db.select(db.templates).get(), isEmpty);

    // The new nullable Client columns are usable end to end.
    await db.updateClient(
      id: 1,
      name: 'Acme',
      contactName: 'Jane Doe',
      email: 'jane@acme.test',
      phone: '+61 400 000 000',
      defaultRate: 100,
    );
    final c = await (db.select(db.clients)..where((t) => t.id.equals(1)))
        .getSingle();
    expect(c.contactName, 'Jane Doe');
    expect(c.phone, '+61 400 000 000');
  });

  test('ensureInvoiceDefaults seeds a default template once (idempotent)',
      () async {
    final db = _openV4();
    addTearDown(db.close);

    await db.ensureInvoiceDefaults();
    await db.ensureInvoiceDefaults(); // second call must be a no-op

    expect((await db.select(db.templates).get()).length, 1);
    final tpl = await db.defaultTemplate();
    expect(tpl, isNotNull);
    expect(tpl!.isDefault, isTrue);
    // The default template resolves to a seeded theme + profile.
    final theme = await db.themeById(tpl.themeId);
    final profile = await db.profileById(tpl.profileId);
    expect(theme.name, 'timedart');
    expect(theme.isDefault, isTrue);
    expect(profile.isDefault, isTrue);
  });

  test('setDefaultTheme moves the default to exactly one row', () async {
    final db = _openV4();
    addTearDown(db.close);

    final a = await db.insertTheme(_theme('A', isDefault: true));
    final b = await db.insertTheme(_theme('B'));

    await db.setDefaultTheme(b);

    final themes = await db.select(db.themes).get();
    final defaults = themes.where((t) => t.isDefault).map((t) => t.id).toList();
    expect(defaults, [b]);
    expect((await db.themeById(a)).isDefault, isFalse);
  });
}

ThemesCompanion _theme(String name, {bool isDefault = false}) =>
    ThemesCompanion.insert(
      name: name,
      colorBackground: 0xFF000000,
      colorSurface: 0xFF111111,
      colorPrimary: 0xFF69E228,
      colorText: 0xFFFFFFFF,
      colorAccent: 0xFF2E6C0F,
      isDefault: Value(isDefault),
    );
