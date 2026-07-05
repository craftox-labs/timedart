import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:time_tracker/data/database.dart';

// Data-layer coverage for the invoice-branding tables (PRD #79): the migrations
// (v4→v6 and v5→v6), idempotent seeding, and single-default resolution.

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

// Hand-built schema-v5 DDL: the branding era before templates folded into
// profiles — a `themes` table (visual style), `profiles` WITHOUT template_id,
// and a `templates` theme+profile pairing. clients carries the v5 columns.
// user_version = 5 so opening runs only the v5→v6 step.
AppDatabase _openV5() {
  final raw = sqlite3.openInMemory();
  raw.execute('''
    CREATE TABLE clients (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, contact_name TEXT, email TEXT, phone TEXT,
      address TEXT, abn TEXT, default_rate REAL NOT NULL, archived_at INTEGER);
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
    CREATE TABLE themes (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, logo BLOB, logo_mime TEXT,
      color_background INTEGER NOT NULL, color_surface INTEGER NOT NULL,
      color_primary INTEGER NOT NULL, color_text INTEGER NOT NULL,
      color_accent INTEGER NOT NULL, font_family TEXT NOT NULL DEFAULT 'Urbanist',
      is_default INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE profiles (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, business_name TEXT NOT NULL DEFAULT '', email TEXT,
      phone TEXT, website TEXT, address TEXT, abn TEXT, payee_name TEXT,
      bank_name TEXT, bank_bsb TEXT, bank_account TEXT, swift TEXT,
      payment_link TEXT, currency TEXT NOT NULL DEFAULT 'USD', tax_label TEXT,
      tax_rate REAL, is_default INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE templates (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, theme_id INTEGER NOT NULL REFERENCES themes (id),
      profile_id INTEGER NOT NULL REFERENCES profiles (id),
      is_default INTEGER NOT NULL DEFAULT 0);
    INSERT INTO clients (id, name, default_rate) VALUES (1, 'Acme', 100);
    INSERT INTO themes (id, name, color_background, color_surface, color_primary,
      color_text, color_accent, is_default)
      VALUES (7, 'brand', 1, 2, 3, 4, 5, 1);
    INSERT INTO profiles (id, name, is_default) VALUES (3, 'Mine', 1);
    INSERT INTO templates (id, name, theme_id, profile_id, is_default)
      VALUES (1, 'pair', 7, 3, 1);
    PRAGMA user_version = 5;
  ''');
  return AppDatabase(NativeDatabase.opened(raw));
}

void main() {
  test('v4→v6 builds the template + profile tables and Client columns', () async {
    final db = _openV4();
    addTearDown(db.close);

    // The current branding tables exist (querying them would throw otherwise).
    expect(await db.select(db.templates).get(), isEmpty);
    expect(await db.select(db.profiles).get(), isEmpty);

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

  test('v5→v6 renames themes→templates and backfills profile.templateId',
      () async {
    final db = _openV5();
    addTearDown(db.close);

    // The old theme (id 7) is now a template; the pairing table is gone.
    final tpl = await db.templateById(7);
    expect(tpl.name, 'brand');
    expect(tpl.isDefault, isTrue);

    // The profile's templateId was backfilled from the old pairing (theme 7).
    final profile = await db.profileById(3);
    expect(profile.templateId, 7);
  });

  test('ensureInvoiceDefaults seeds a template + linked profile (idempotent)',
      () async {
    final db = _openV4();
    addTearDown(db.close);

    await db.ensureInvoiceDefaults();
    await db.ensureInvoiceDefaults(); // second call must be a no-op

    expect((await db.select(db.templates).get()).length, 1);
    final tpl = await db.defaultTemplate();
    expect(tpl, isNotNull);
    expect(tpl!.isDefault, isTrue);
    expect(tpl.name, 'timedart');
    // The seeded profile is the default and points at the seeded template.
    final profile = await db.defaultProfile();
    expect(profile, isNotNull);
    expect(profile!.isDefault, isTrue);
    expect(profile.templateId, tpl.id);
  });

  test('setDefaultTemplate moves the default to exactly one row', () async {
    final db = _openV4();
    addTearDown(db.close);

    final a = await db.insertTemplate(_template('A', isDefault: true));
    final b = await db.insertTemplate(_template('B'));

    await db.setDefaultTemplate(b);

    final templates = await db.select(db.templates).get();
    final defaults =
        templates.where((t) => t.isDefault).map((t) => t.id).toList();
    expect(defaults, [b]);
    expect((await db.templateById(a)).isDefault, isFalse);
  });
}

TemplatesCompanion _template(String name, {bool isDefault = false}) =>
    TemplatesCompanion.insert(
      name: name,
      colorBackground: 0xFF000000,
      colorSurface: 0xFF111111,
      colorPrimary: 0xFF69E228,
      colorText: 0xFFFFFFFF,
      colorAccent: 0xFF2E6C0F,
      isDefault: Value(isDefault),
    );
