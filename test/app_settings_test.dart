import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:timedart/data/database.dart';

// Coverage for the app-settings key-value store + its v9→v10 migration (PRD
// #133). Mirrors profile_region_migration_test.dart: hand-build the prior
// schema, open AppDatabase over it to run onUpgrade, then assert behaviour.

// Hand-built schema-v9 DDL: templates + profiles at the v9 shape (all region
// feature columns present), and no app_settings table. user_version = 9 so
// opening runs only the v9→v10 step.
AppDatabase _openV9() {
  final raw = sqlite3.openInMemory();
  raw.execute('''
    CREATE TABLE templates (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, color_background INTEGER NOT NULL,
      color_surface INTEGER NOT NULL, color_primary INTEGER NOT NULL,
      color_text INTEGER NOT NULL, color_accent INTEGER NOT NULL,
      font_family TEXT NOT NULL DEFAULT 'Mona',
      is_default INTEGER NOT NULL DEFAULT 0);
    CREATE TABLE profiles (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL, business_name TEXT NOT NULL DEFAULT '',
      logo BLOB, logo_mime TEXT, email TEXT, phone TEXT, website TEXT,
      address TEXT, abn TEXT, payee_name TEXT, bank_name TEXT, bank_bsb TEXT,
      bank_account TEXT, swift TEXT, payment_link TEXT,
      currency TEXT NOT NULL DEFAULT 'USD', tax_label TEXT, tax_rate REAL,
      is_default INTEGER NOT NULL DEFAULT 0,
      template_id INTEGER REFERENCES templates (id),
      region TEXT NOT NULL DEFAULT 'au', iban TEXT, sort_code TEXT,
      routing_number TEXT, payid TEXT, institution_number TEXT,
      transit_number TEXT, show_bank INTEGER NOT NULL DEFAULT 1,
      show_payment_link INTEGER NOT NULL DEFAULT 1,
      show_tax INTEGER NOT NULL DEFAULT 1,
      show_rate_column INTEGER NOT NULL DEFAULT 1,
      show_time_column INTEGER NOT NULL DEFAULT 1,
      reverse_charge INTEGER NOT NULL DEFAULT 0);
    INSERT INTO templates (id, name, color_background, color_surface,
      color_primary, color_text, color_accent) VALUES (1, 'T', 0, 0, 0, 0, 0);
    INSERT INTO profiles (id, name, business_name, is_default)
      VALUES (1, 'Default', 'Acme Pty Ltd', 1);
    PRAGMA user_version = 9;
  ''');
  return AppDatabase(NativeDatabase.opened(raw));
}

void main() {
  test('v9→v10 adds app_settings without touching existing data', () async {
    final db = _openV9();
    addTearDown(db.close);

    // Existing profile survives the migration untouched.
    final profile = await db.defaultProfile();
    expect(profile, isNotNull);
    expect(profile!.businessName, 'Acme Pty Ltd');

    // Fresh table → onboarding not yet complete.
    expect(await db.isOnboardingComplete(), isFalse);

    // The flag round-trips through the new table.
    await db.setOnboardingComplete();
    expect(await db.isOnboardingComplete(), isTrue);

    // Clearing it (the Settings "Re-run setup" / test-reset path) works.
    await db.setOnboardingComplete(false);
    expect(await db.isOnboardingComplete(), isFalse);
  });

  test('fresh install (onCreate) reports onboarding not complete', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    // A brand-new DB built via onCreate/createAll has the table but no row.
    expect(await db.isOnboardingComplete(), isFalse);
    await db.setOnboardingComplete();
    expect(await db.isOnboardingComplete(), isTrue);
  });

  test('installId mints once and is stable across calls', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final first = await db.installId();
    expect(first, isNotEmpty);
    // Subsequent calls return the SAME id — minted once, then persisted.
    expect(await db.installId(), first);
    expect(await db.installId(), first);
  });

  test('installId persists across reopen (survives restart)', () async {
    final dir = await Directory.systemTemp.createTemp('timedart_install_id');
    final file = File('${dir.path}/db.sqlite');
    addTearDown(() => dir.delete(recursive: true));

    final db1 = AppDatabase(NativeDatabase(file));
    final id = await db1.installId();
    await db1.close();

    // Reopen the same file → the id is read back, not re-minted.
    final db2 = AppDatabase(NativeDatabase(file));
    addTearDown(db2.close);
    expect(await db2.installId(), id);
  });

  test('distinct installs get distinct ids', () async {
    final a = AppDatabase(NativeDatabase.memory());
    final b = AppDatabase(NativeDatabase.memory());
    addTearDown(a.close);
    addTearDown(b.close);
    expect(await a.installId(), isNot(await b.installId()));
  });
}
