import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:timedart/data/database.dart';

// Verifies the v8 → v9 migration (region-aware invoicing, PRD #117): a schema-v8
// database gains the region + all remaining feature columns, and existing
// profiles backfill their region from the AU-shaped BSB heuristic.
void main() {
  test('v8→v9 adds region + feature columns and backfills region', () async {
    // Hand-build a schema-v8 database: templates (FK target) + profiles at the
    // v8 shape (logo already on profiles; none of the v9 columns present).
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
        template_id INTEGER REFERENCES templates (id));
      INSERT INTO templates (id, name, color_background, color_surface,
        color_primary, color_text, color_accent) VALUES (1, 'T', 0, 0, 0, 0, 0);
      -- One AU-shaped profile (has a BSB) and one without.
      INSERT INTO profiles (id, name, bank_bsb, is_default)
        VALUES (1, 'Aussie', '062-000', 1);
      INSERT INTO profiles (id, name, is_default)
        VALUES (2, 'Global', 0);
      PRAGMA user_version = 8;
    ''');

    // Opening AppDatabase over the seeded connection runs onUpgrade(8→9).
    final db = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(db.close);

    final profiles = await db.select(db.profiles).get();
    expect(profiles.length, 2);

    // Region backfilled from the BSB heuristic.
    final aussie = profiles.firstWhere((p) => p.id == 1);
    final global = profiles.firstWhere((p) => p.id == 2);
    expect(aussie.region, 'au');
    expect(global.region, 'other');

    // The new columns exist with their defaults; a fresh insert works against
    // the migrated schema.
    expect(aussie.showBank, isTrue);
    expect(aussie.showTax, isTrue);
    expect(aussie.reverseCharge, isFalse);
    expect(aussie.iban, isNull);

    await db.insertProfile(
      ProfilesCompanion.insert(name: 'New', region: const Value('uk')),
    );
    final added = (await db.select(db.profiles).get())
        .firstWhere((p) => p.name == 'New');
    expect(added.region, 'uk');
    expect(added.showPaymentLink, isTrue); // column default applied on insert
  });
}
