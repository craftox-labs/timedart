import 'package:drift/drift.dart';

import 'id.dart';
import 'sync/delta/delta_config.dart';

part 'database.g.dart'; // generated — doesn't exist until you run build_runner

// ── UUIDv7 primary keys (PRD #189, Phase 2c) ──────────────────────────────
// Every content-table PK is a text UUIDv7 (see [id.dart]) instead of an
// autoincrement int: sync needs ids that don't collide across devices. New rows
// get one via a Dart `clientDefault`; the PK is declared explicitly since it's no
// longer autoIncrement. The v12→v13 migration re-keys every existing row + FK.

class Clients extends Table {
  TextColumn get id => text().clientDefault(() => idGen.newId())();
  TextColumn get name => text().withLength(min: 1, max: 100)(); // organisation
  TextColumn get contactName => text().nullable()(); // the person (invoice TO)
  TextColumn get email => text().nullable()(); // nullable column
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get abn => text().nullable()();
  RealColumn get defaultRate => real()(); // $/hr fallback — required
  DateTimeColumn get archivedAt => dateTime().nullable()();
  // Row audit for sync (PRD #189, Phase 2a). createdAt/updatedAt default to now
  // on insert; updatedAt is re-stamped on every update at the AppDatabase
  // choke-point. Drives last-write-wins once sync lands. Nullable so the v11
  // ALTER ADD COLUMN is legal (SQLite forbids a non-constant default on add);
  // a Dart clientDefault keeps new rows populated.
  DateTimeColumn get createdAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  // Soft-delete tombstone for sync (PRD #189, Phase 2b). Deletes set this to
  // now (+ bump updatedAt) instead of hard-DELETEing, so the removal propagates
  // across devices (a hard DELETE just reappears from the other device). NULL =
  // live. Distinct from [archivedAt], which is a user-facing "archive" concept.
  // All reads/watch queries filter `deletedAt IS NULL`.
  DateTimeColumn get deletedAt => dateTime().nullable()();
  // Tenancy scope key for the optional sync layer (PRD #189, Phase 4). NULL on
  // the pure-local path (sync off) → completely inert, like [deletedAt]; the
  // enable/seed flow (Phase 4d) stamps it with the personal org_id when sync is
  // turned on. Sync rules scope each device to `org_id = auth.user_id()`. Only
  // on the six SYNCED content tables — app_settings/active_timers stay
  // device-local, so they carry no org_id.
  TextColumn get orgId => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Projects extends Table {
  TextColumn get id => text().clientDefault(() => idGen.newId())();
  TextColumn get clientId => text().references(Clients, #id)(); // FK
  TextColumn get code => text().unique()(); // human project number
  TextColumn get title => text()();
  RealColumn get rate => real().nullable()(); // overrides client default
  // addProject also stamps status/createdAt in Dart (not leaning on this SQL
  // default) so every row is explicitly complete at the insert choke-point —
  // mirrors updatedAt, and keeps the delta-sync push independent of column
  // defaults. Any new insert path for projects should do the same (#299).
  TextColumn get status => text().withDefault(const Constant('active'))();
  // User-facing "archive": hide a finished project from the active UI while
  // keeping it (and its history) for invoicing. Reversible; NULL = active.
  // Distinct from [deletedAt] (the sync tombstone). Mirrors [Clients.archivedAt].
  DateTimeColumn get archivedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // sync tombstone (2b)
  TextColumn get orgId => text().nullable()(); // scope key (Phase 4)
  @override
  Set<Column> get primaryKey => {id};
}

// A unit of work under a project. Owns many time-entry segments, so multiple
// sessions accumulate against one task. `rate` overrides the project's rate (used
// by a later invoicing pass); status leaves room for open/done/archived.
class Tasks extends Table {
  TextColumn get id => text().clientDefault(() => idGen.newId())();
  TextColumn get projectId => text().references(Projects, #id)();
  TextColumn get title => text()();
  RealColumn get rate => real().nullable()(); // overrides project.rate
  // See Projects.status: addTask stamps status/createdAt in Dart so the row is
  // explicitly complete for the delta-sync push (#299).
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // sync tombstone (2b)
  TextColumn get orgId => text().nullable()(); // scope key (Phase 4)
  @override
  Set<Column> get primaryKey => {id};
}

class TimeEntries extends Table {
  TextColumn get id => text().clientDefault(() => idGen.newId())();
  TextColumn get projectId => text().references(Projects, #id)();
  // An entry belongs to a task; [description] is an optional per-segment note
  // (e.g. "fixed the login bug"). Nullable — most entries just inherit the
  // task's title in the UI.
  TextColumn get taskId => text().nullable().references(Tasks, #id)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get seconds =>
      integer()(); // TRACKED time (excludes pauses) — see below
  DateTimeColumn get createdAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // sync tombstone (2b)
  TextColumn get orgId => text().nullable()(); // scope key (Phase 4)
  @override
  Set<Column> get primaryKey => {id};
}

// ── Invoice branding (see PRD #79) ────────────────────────────────────────
// Three data-only tables. Colours are stored as ARGB ints (0xAARRGGBB) so the
// data layer stays UI-free — the UI/PDF convert to Color/PdfColor. A logo is
// raw PNG/JPG bytes so it travels with the DB (no orphaned files).

/// An invoice *template*: colour scheme + font — the visual style a profile is
/// rendered with. Named "template" (not "theme") to leave "theme" free for
/// future app-wide UI theming. The logo lives on the [Profiles] (business
/// identity), not here — a template is pure look, reusable across profiles.
/// Exactly one row is the default (see [AppDatabase.setDefaultTemplate]).
@DataClassName('InvoiceTemplate')
class Templates extends Table {
  TextColumn get id => text().clientDefault(() => idGen.newId())();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get colorBackground => integer()();
  IntColumn get colorSurface => integer()();
  IntColumn get colorPrimary => integer()();
  IntColumn get colorText => integer()();
  IntColumn get colorAccent => integer()();
  TextColumn get fontFamily => text().withDefault(const Constant('Mona'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // sync tombstone (2b)
  TextColumn get orgId => text().nullable()(); // scope key (Phase 4)
  @override
  Set<Column> get primaryKey => {id};
}

/// The *details* of an invoice: sender identity + logo + payment + currency +
/// optional tax. Tax is null-by-default and international-neutral (a [taxLabel]
/// + percent [taxRate], or nothing). The logo lives here (business identity),
/// set once with the other business details, so it survives a change of visual
/// [Templates]. Reusable across templates; one row is the default.
@DataClassName('InvoiceProfile')
class Profiles extends Table {
  TextColumn get id => text().clientDefault(() => idGen.newId())();
  TextColumn get name =>
      text().withLength(min: 1, max: 100)(); // internal label
  TextColumn get businessName => text().withDefault(const Constant(''))();
  BlobColumn get logo => blob().nullable()(); // PNG/JPG bytes; null = no logo
  TextColumn get logoMime => text().nullable()(); // e.g. image/png
  TextColumn get email => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get website => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get abn => text().nullable()(); // ABN/ACN/company no.
  TextColumn get payeeName => text().nullable()();
  TextColumn get bankName => text().nullable()();
  TextColumn get bankBsb => text().nullable()();
  TextColumn get bankAccount => text().nullable()();
  TextColumn get swift => text().nullable()(); // SWIFT/BIC
  TextColumn get paymentLink => text().nullable()();
  TextColumn get currency => text().withDefault(const Constant('USD'))();
  TextColumn get taxLabel =>
      text().nullable()(); // e.g. GST, VAT; null = no tax
  RealColumn get taxRate => real().nullable()(); // percent, e.g. 10.0
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  // The template (visual style) this profile is rendered with. Null → the
  // default template. Replaces the old Theme+Profile pairing table.
  TextColumn get templateId => text().nullable().references(Templates, #id)();
  // ── Region-aware invoicing (PRD #117, schema v9) ────────────────────────
  // The region shapes tax label + buyer-tax-ID label + invoice title, and
  // which bank fields the editor exposes. Stored as InvoiceRegion.name.
  TextColumn get region => text().withDefault(const Constant('au'))();
  // Region-specific bank identifiers (reuse bankAccount/swift/bankBsb for the
  // universal account no. / BIC / AU BSB). Wired into the editor + renderers
  // by slice #121.
  TextColumn get iban => text().nullable()();
  TextColumn get sortCode => text().nullable()(); // UK
  TextColumn get routingNumber => text().nullable()(); // US ABA
  TextColumn get payid => text().nullable()(); // AU
  TextColumn get institutionNumber => text().nullable()(); // CA
  TextColumn get transitNumber => text().nullable()(); // CA
  // Invoice-inclusion defaults — deliberate omission of a block even when the
  // data exists. Overridable per invoice at export by slice #122.
  BoolColumn get showBank => boolean().withDefault(const Constant(true))();
  BoolColumn get showPaymentLink =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showTax => boolean().withDefault(const Constant(true))();
  BoolColumn get showRateColumn =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get showTimeColumn =>
      boolean().withDefault(const Constant(true))();
  // Reverse-charge (EU/UK B2B) — wired by slice #123.
  BoolColumn get reverseCharge =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // sync tombstone (2b)
  TextColumn get orgId => text().nullable()(); // scope key (Phase 4)
  @override
  Set<Column> get primaryKey => {id};
}

/// Local dirty-tracker for delta-sync (PRD #189, Phase 5b, schema v18). One row
/// per locally-mutated content row that still needs pushing: `(tableName,
/// rowId)` names it, `queuedAt` is when it was marked (diagnostic only —
/// ordering isn't relied on). Rows are enqueued at the AppDatabase write
/// choke-point (see [AppDatabase.markDirtyForSync]) and cleared on push-ack.
///
/// This REPLACES the 5a `updatedAt`-watermark dirty test, whose flaw was that a
/// row *pulled* from another device carried that device's clock (usually above
/// the local watermark) and got re-pushed once. A structural per-row flag has no
/// such echo: pulled rows are applied via the `fromRemote` path, which does NOT
/// enqueue. **Device-local — it carries no `org_id` and never syncs**, like
/// [AppSettings]/[ActiveTimers]. Enqueuing is gated on [enableSyncOutbox] so the
/// pure-local (sync-off) path never writes to it and it can't grow unbounded.
class SyncOutbox extends Table {
  // Named `targetTable` (not `tableName`) because drift reserves the getter
  // `tableName` on Table for overriding the SQL table name. Column is
  // `target_table`.
  TextColumn get targetTable => text()();
  TextColumn get rowId => text()();
  DateTimeColumn get queuedAt =>
      dateTime().clientDefault(() => DateTime.now())();
  @override
  Set<Column> get primaryKey => {targetTable, rowId};
}

/// App-level key-value preferences (PRD #133, schema v10). The single home for
/// flags that are app *state* rather than Profile *data* — first use is the
/// onboarding-complete flag + the stable per-install id; future app prefs
/// (page size, theme) belong here too. Values are stored as strings; typed
/// accessors on [AppDatabase] (e.g. [AppDatabase.isOnboardingComplete],
/// [AppDatabase.installId]) hide the key names and the encoding.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  @override
  Set<Column> get primaryKey => {key};
}

/// The single currently-running timer, persisted so it survives a restart and
/// syncs across devices (PRD #189, Phase 3) — the durable source of truth that
/// replaces the in-memory `TimerSession` singleton. At most one **live**
/// (`deletedAt IS NULL`) row exists; [AppDatabase.watchActiveTimer] reads it and
/// the timer store keeps it to one. Elapsed time is *derived*, never ticked into
/// the DB: [accumulatedSeconds] is the tracked time frozen at the last pause, and
/// [runningSince] is when the current run began (`null` = paused), so live
/// elapsed = `accumulatedSeconds + (runningSince == null ? 0 : now - runningSince)`.
/// The row is written only on transitions (start/pause/resume/finish), never per
/// tick, which keeps sync quiet. On finish the row is tombstoned (Phase 2b).
@DataClassName('ActiveTimer')
class ActiveTimers extends Table {
  TextColumn get id => text().clientDefault(() => idGen.newId())();
  // The bound work — nullable until the timer is bound at first start (mirrors
  // TimerSession binding project/task at start so a mid-session selection change
  // can't misattribute time).
  TextColumn get projectId => text().nullable().references(Projects, #id)();
  TextColumn get taskId => text().nullable().references(Tasks, #id)();
  // The in-progress session note (becomes the finished entry's description).
  // Persisted here so it survives a restart, not just the bound work (v15).
  TextColumn get description => text().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  IntColumn get accumulatedSeconds =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get runningSince => dateTime().nullable()(); // null = paused
  DateTimeColumn get createdAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().nullable().clientDefault(() => DateTime.now())();
  DateTimeColumn get deletedAt => dateTime().nullable()(); // tombstone on finish
  @override
  Set<Column> get primaryKey => {id};
}

/// Thrown by a delete when a referential-integrity rule blocks it: the row has
/// dependents that must be removed first. [entity] names what couldn't be
/// deleted ('client' | 'project' | 'task') for logging and tests; the UI owns
/// the user-facing wording (see features/deletions.dart).
class DeleteBlockedException implements Exception {
  final String entity;
  const DeleteBlockedException(this.entity);
  @override
  String toString() => 'DeleteBlockedException($entity)';
}

/// How many live descendants a cascade delete would remove, so the UI can warn
/// with real counts before deleting a parent and everything under it (#75).
/// Fields not applicable to a given level stay 0 (a task has only entries).
class DeleteImpact {
  final int projects;
  final int tasks;
  final int entries;
  const DeleteImpact({this.projects = 0, this.tasks = 0, this.entries = 0});
  int get total => projects + tasks + entries;
}

@DriftDatabase(
  tables: [
    Clients,
    Projects,
    Tasks,
    TimeEntries,
    Templates,
    Profiles,
    AppSettings,
    ActiveTimers,
    SyncOutbox,
  ],
)
class AppDatabase extends _$AppDatabase {
  // _$AppDatabase is generated.
  //
  // The executor is always injected — the Flutter/`drift_flutter` open path
  // lives in `app_database_flutter.dart` (imported only by the app), and the
  // pure-Dart CLI open path lives in `cli/db_open.dart`. Keeping AppDatabase
  // constructible from any [QueryExecutor] is what lets the non-Flutter CLI
  // (compiled with `dart compile exe`) import this file without pulling in
  // path_provider — a Flutter platform channel unavailable outside the app.
  AppDatabase(super.executor);

  /// Whether content-table writes enqueue a dirty-tracker row into [SyncOutbox]
  /// (PRD #189, Phase 5b). Defaults to [deltaSyncConfigured] — a build-time
  /// constant, so a released (sync-off) build never touches the outbox and it
  /// cannot grow unbounded (the branch tree-shakes away). Mutable so a delta
  /// build's startup can force it on, and tests can exercise the enqueue path
  /// without the `--dart-define` flags.
  bool enableSyncOutbox = deltaSyncConfigured;

  /// Mark content rows dirty for the next delta-sync push (Phase 5b). Called at
  /// every AppDatabase write choke-point for the four synced content tables,
  /// inside the same transaction as the mutation so a row can't commit unqueued.
  /// A no-op unless [enableSyncOutbox] is set. The `fromRemote` apply path
  /// (`applyRemote*` in sync_queries) deliberately does NOT call this — that is
  /// the structural echo guard that replaced 5a's clock watermark.
  Future<void> markDirtyForSync(String tableName, Iterable<String> ids) async {
    if (!enableSyncOutbox) return;
    final rows = [
      for (final id in ids)
        SyncOutboxCompanion(
          targetTable: Value(tableName),
          rowId: Value(id),
          queuedAt: Value(DateTime.now()),
        ),
    ];
    if (rows.isEmpty) return;
    await batch((b) => b.insertAllOnConflictUpdate(syncOutbox, rows));
  }

  /// The schema version this build ships with. The single source of truth for
  /// both drift's migration ladder and the CLI's schema-version guard (which
  /// refuses to open a DB whose on-disk `user_version` differs from this).
  static const int latestSchemaVersion = 18;

  @override
  int get schemaVersion => latestSchemaVersion;

  // drift doesn't enforce foreign keys unless we turn the pragma on per
  // connection. With it on, deleting a project that has time entries (or a
  // client that has projects) fails loudly instead of silently orphaning rows.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      // v1 → v2: introduce Tasks between Project and TimeEntry. Create the table,
      // add the (nullable) taskId column, then fold each distinct
      // (project, task-string) into one Task and repoint its entries. The old
      // `task` string column is left in place (dropped later in #57). FK
      // enforcement is off during migration (beforeOpen runs afterwards), so
      // the ALTER + backfill are safe.
      if (from < 2) {
        await m.createTable(tasks);
        await m.addColumn(timeEntries, timeEntries.taskId);
        // tasks is created at the current schema, whose id is now a *text* PK
        // with no SQL default (its uuid clientDefault only fires on drift
        // inserts, not this raw SQL). So synthesise a unique text id per distinct
        // (job, task) — a placeholder the v12→v13 re-key below replaces with a
        // real UUIDv7; it only has to be unique and match the FK set next. Every
        // id/FK comparison casts to TEXT so int (job_id) and text ids compare
        // consistently. time_entries at v1 still uses job_id, read from old rows.
        await customStatement(
          "INSERT INTO tasks (id, project_id, title) "
          "SELECT CAST(job_id AS TEXT) || '|' || task, CAST(job_id AS TEXT), task "
          "FROM (SELECT DISTINCT job_id, task FROM time_entries)",
        );
        await customStatement(
          "UPDATE time_entries SET task_id = ("
          "SELECT t.id FROM tasks t "
          "WHERE t.project_id = CAST(time_entries.job_id AS TEXT) "
          "AND t.title = time_entries.task)",
        );
      }
      // v2 → v3: the free-text `task` string is now redundant with taskId.
      // Rebuild time_entries to drop it and add an optional per-entry `name`
      // (starts null — names are set explicitly, not inherited from the task).
      if (from < 3) {
        // `description` is nullable so it needs no transformer — the rebuild
        // adds it as NULL and drops the old `task` column (gone from v3).
        // `projectId` maps from the old `job_id` column name; for from=1 the
        // from<2 block already created tasks with project_id, so time_entries
        // still has job_id at this point and the transformer bridges the gap.
        await m.alterTable(
          TableMigration(
            timeEntries,
            // createdAt/updatedAt (v11) + deletedAt (v12) are declared new here
            // so this rebuild to the current shape doesn't try to copy them from
            // the old table. deletedAt is plain nullable → fills NULL, no
            // transformer needed (unlike the timestamp cols).
            newColumns: [
              timeEntries.description,
              timeEntries.createdAt,
              timeEntries.updatedAt,
              timeEntries.deletedAt,
              timeEntries.orgId, // Phase 4 scope key — fills NULL like deletedAt
            ],
            columnTransformer: {
              timeEntries.projectId: const CustomExpression('job_id'),
              timeEntries.createdAt: currentDateAndTime,
              timeEntries.updatedAt: currentDateAndTime,
            },
          ),
        );
      }
      // v3 → v4: a client's default rate is now required (every project resolves
      // to at least the client default). Rebuild clients with the non-null column,
      // backfilling any pre-existing null rate to 0 so the copy can't violate.
      if (from < 4) {
        // TableMigration rebuilds `clients` to the CURRENT schema, which now
        // also carries contactName/phone (added in v5). Declare them here as
        // new nullable columns so this rebuild is self-consistent; the v4→v5
        // step below then only adds them for a DB coming straight from v4.
        await m.alterTable(
          TableMigration(
            clients,
            // createdAt/updatedAt (v11) + deletedAt (v12) declared new so this
            // rebuild to the current shape doesn't try to copy them from the old
            // table. deletedAt is plain nullable → fills NULL, no transformer.
            newColumns: [
              clients.contactName,
              clients.phone,
              clients.createdAt,
              clients.updatedAt,
              clients.deletedAt,
              clients.orgId, // Phase 4 scope key — fills NULL like deletedAt
            ],
            columnTransformer: {
              clients.defaultRate: coalesce([
                clients.defaultRate,
                const Constant(0.0),
              ]),
              clients.createdAt: currentDateAndTime,
              clients.updatedAt: currentDateAndTime,
            },
          ),
        );
      }
      // v4 → v5: invoice branding. Originally added three tables (themes,
      // profiles, a theme+profile pairing "templates"). v6 dropped the pairing
      // and renamed themes→templates, so for a pre-v5 DB we build the CURRENT
      // shape directly: the visual `templates` table + `profiles` (which already
      // carries templateId). The v5→v6 rename block below is skipped for these.
      if (from < 5) {
        await m.createTable(templates);
        await m.createTable(profiles);
        // Only for a DB coming straight from v4: a from<4 upgrade already got
        // these columns via the v3→v4 clients rebuild above (current schema).
        if (from >= 4) {
          await m.addColumn(clients, clients.contactName);
          await m.addColumn(clients, clients.phone);
        }
      }
      // v5 → v6: fold the Theme+Profile pairing into the profile. A v5 DB has
      // `themes`, a pairing `templates`, and `profiles` without templateId.
      // Rename themes→templates (the visual style), give profiles a templateId,
      // backfill it from each profile's pairing, then drop the pairing table.
      // Guarded to from==5 so pre-v5 upgrades (handled above) don't reach it.
      if (from == 5) {
        await customStatement('ALTER TABLE templates RENAME TO _pairing_old');
        await customStatement('ALTER TABLE themes RENAME TO templates');
        await m.addColumn(profiles, profiles.templateId);
        await customStatement(
          'UPDATE profiles SET template_id = ('
          'SELECT theme_id FROM _pairing_old '
          'WHERE _pairing_old.profile_id = profiles.id LIMIT 1)',
        );
        await customStatement('DROP TABLE _pairing_old');
      }
      // v6 → v7: rename jobs→projects and job_id→project_id throughout.
      // Guarded to from<7 — a v7+ database already has `projects` (renaming a
      // non-existent `jobs` throws, which is what broke the v7→v8 upgrade).
      // Every pre-v7 database has a `jobs` table, so the table rename runs for
      // all of them. Column renames are further guarded:
      //   - tasks.job_id: from<2 creates tasks fresh (project_id already); from≥2
      //     databases have job_id from a prior migration run.
      //   - time_entries.job_id: from<3 TableMigration already maps job_id→project_id
      //     via columnTransformer; from≥3 databases still have job_id.
      if (from < 7) {
        await customStatement('ALTER TABLE jobs RENAME TO projects');
        if (from >= 2) {
          await customStatement(
            'ALTER TABLE tasks RENAME COLUMN job_id TO project_id',
          );
        }
        if (from >= 3) {
          await customStatement(
            'ALTER TABLE time_entries RENAME COLUMN job_id TO project_id',
          );
        }
      }
      // v7 → v8: the logo moves from the template (visual style) to the profile
      // (business identity). Add logo/logo_mime to profiles, backfill each from
      // its resolved template (its templateId, else the default template), then
      // drop logo/logo_mime from templates via a rebuild to the current shape.
      // Bounded both ways (from>=5 && from<8): a from<5 upgrade built the current
      // tables directly above (logo already on profiles, absent from templates),
      // and the upper bound stops a future bump (v8→v9+) re-running these ops on
      // a v8 DB where profiles.logo already exists (addColumn would throw — the
      // same latent trap the unbounded v6→v7 rename hit). from∈{5,6,7} all reach
      // here with the logo still on templates (v5's themes had it; v5→v6 kept it).
      if (from >= 5 && from < 8) {
        await m.addColumn(profiles, profiles.logo);
        await m.addColumn(profiles, profiles.logoMime);
        await customStatement(
          'UPDATE profiles SET '
          'logo = (SELECT t.logo FROM templates t WHERE t.id = coalesce('
          'profiles.template_id, (SELECT id FROM templates WHERE is_default = 1 LIMIT 1))), '
          'logo_mime = (SELECT t.logo_mime FROM templates t WHERE t.id = coalesce('
          'profiles.template_id, (SELECT id FROM templates WHERE is_default = 1 LIMIT 1)))',
        );
        // Rebuild templates to the current schema — logo/logo_mime are no longer
        // declared, so the copy drops them; all remaining columns carry over.
        // createdAt/updatedAt (v11) + deletedAt (v12) declared new so the copy
        // doesn't look for them on the old table.
        await m.alterTable(
          TableMigration(
            templates,
            newColumns: [
              templates.createdAt,
              templates.updatedAt,
              templates.deletedAt,
              templates.orgId, // Phase 4 scope key — fills NULL like deletedAt
            ],
            columnTransformer: {
              templates.createdAt: currentDateAndTime,
              templates.updatedAt: currentDateAndTime,
            },
          ),
        );
      }
      // v8 → v9: region-aware invoicing (PRD #117). Add the region plus the
      // whole feature's remaining columns in one bump (region-specific bank
      // ids, invoice-inclusion flags, reverse-charge) — later slices wire them.
      // Bounded from>=5 && from<9: a from<5 upgrade built profiles at the
      // current shape above (all these columns already present, so addColumn
      // would throw), and the upper bound stops a future bump re-running these
      // on a v9 DB. from∈{5,6,7,8} all reach here without the v9 columns.
      if (from >= 5 && from < 9) {
        await m.addColumn(profiles, profiles.region);
        await m.addColumn(profiles, profiles.iban);
        await m.addColumn(profiles, profiles.sortCode);
        await m.addColumn(profiles, profiles.routingNumber);
        await m.addColumn(profiles, profiles.payid);
        await m.addColumn(profiles, profiles.institutionNumber);
        await m.addColumn(profiles, profiles.transitNumber);
        await m.addColumn(profiles, profiles.showBank);
        await m.addColumn(profiles, profiles.showPaymentLink);
        await m.addColumn(profiles, profiles.showTax);
        await m.addColumn(profiles, profiles.showRateColumn);
        await m.addColumn(profiles, profiles.showTimeColumn);
        await m.addColumn(profiles, profiles.reverseCharge);
        // Backfill region from the AU-shaped heuristic: a profile carrying a
        // BSB is Australian; everything else defaults to Other.
        await customStatement(
          "UPDATE profiles SET region = CASE "
          "WHEN bank_bsb IS NOT NULL AND bank_bsb != '' THEN 'au' "
          "ELSE 'other' END",
        );
      }
      // v9 → v10: app-level key-value settings (PRD #133). A brand-new table —
      // no existing DB at any prior version has it — so every upgrade path
      // (from∈1..9) must create it. Guarded from<10 so a future bump can't
      // re-run createTable on a v10 DB (which would throw "table exists").
      if (from < 10) {
        await m.createTable(appSettings);
      }
      // v10 → v11: row-audit timestamps for sync (PRD #189, Phase 2a). Add
      // updatedAt to every table + createdAt to those lacking it. The columns
      // are nullable (no default) so ALTER ADD COLUMN is legal; existing rows
      // are then backfilled to now. Some upgrade paths already created these
      // columns via an earlier createTable/rebuild to the current shape, so each
      // add is guarded by a PRAGMA existence check rather than a from-version.
      if (from < 11) {
        Future<bool> tableExists(String name) async => (await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
          variables: [Variable.withString(name)],
        ).get()).isNotEmpty;

        Future<void> addIfMissing(TableInfo t, GeneratedColumn c) async {
          final cols = await customSelect(
            'PRAGMA table_info(${t.actualTableName})',
          ).get();
          if (!cols.any((r) => r.read<String>('name') == c.name)) {
            await m.addColumn(t, c);
          }
        }

        // Add the timestamp columns (some paths already have them via an earlier
        // createTable/rebuild — hence add-if-missing), then backfill nulls to the
        // migration time. Skips tables absent in a partial DB (defensive; a real
        // v1–v10 DB has them all — covered by the schema-ladder tests).
        Future<void> ensure(
          TableInfo t, {
          GeneratedColumn? createdAt,
          required GeneratedColumn updatedAt,
        }) async {
          if (!await tableExists(t.actualTableName)) return;
          const now = "CAST(strftime('%s','now') AS INTEGER)";
          if (createdAt != null) {
            await addIfMissing(t, createdAt);
            await customStatement(
              'UPDATE ${t.actualTableName} SET created_at = $now '
              'WHERE created_at IS NULL',
            );
          }
          await addIfMissing(t, updatedAt);
          await customStatement(
            'UPDATE ${t.actualTableName} SET updated_at = $now '
            'WHERE updated_at IS NULL',
          );
        }

        await ensure(
          clients,
          createdAt: clients.createdAt,
          updatedAt: clients.updatedAt,
        );
        await ensure(projects, updatedAt: projects.updatedAt);
        await ensure(tasks, updatedAt: tasks.updatedAt);
        await ensure(
          timeEntries,
          createdAt: timeEntries.createdAt,
          updatedAt: timeEntries.updatedAt,
        );
        await ensure(
          templates,
          createdAt: templates.createdAt,
          updatedAt: templates.updatedAt,
        );
        await ensure(
          profiles,
          createdAt: profiles.createdAt,
          updatedAt: profiles.updatedAt,
        );
        await ensure(appSettings, updatedAt: appSettings.updatedAt);
      }
      // v11 → v12: soft-delete tombstones for sync (PRD #189, Phase 2b). Add a
      // nullable `deletedAt` to the six content tables. Nullable, no default →
      // existing rows get NULL (= live), no backfill. Some upgrade paths already
      // created the column via an earlier createTable/rebuild to the current
      // shape, so each add is guarded by a PRAGMA existence check (add-if-missing)
      // rather than a from-version — mirroring the v11 approach.
      if (from < 12) {
        Future<bool> tableExists(String name) async => (await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
          variables: [Variable.withString(name)],
        ).get()).isNotEmpty;

        Future<void> addDeletedAt(TableInfo t, GeneratedColumn c) async {
          if (!await tableExists(t.actualTableName)) return; // defensive
          final cols = await customSelect(
            'PRAGMA table_info(${t.actualTableName})',
          ).get();
          if (!cols.any((r) => r.read<String>('name') == c.name)) {
            await m.addColumn(t, c);
          }
        }

        await addDeletedAt(clients, clients.deletedAt);
        await addDeletedAt(projects, projects.deletedAt);
        await addDeletedAt(tasks, tasks.deletedAt);
        await addDeletedAt(timeEntries, timeEntries.deletedAt);
        await addDeletedAt(templates, templates.deletedAt);
        await addDeletedAt(profiles, profiles.deletedAt);
      }
      // v12 → v13: UUIDv7 primary keys for sync (PRD #189, Phase 2c). Re-key
      // every content-table int PK + FK to a text UUIDv7 in place, preserving all
      // relationships — nobody loses data. The historical rebuild steps above
      // leave id/FK columns with mixed affinity (a plain-v12 DB is all-int; a DB
      // that came up through a rebuild carries int-as-text), so every comparison
      // here casts to TEXT to stay affinity-agnostic. FK enforcement is off
      // during migration, so the intermediate states (a rebuilt child pointing at
      // a not-yet-rebuilt parent) are safe. Guarded from<13 so a future bump
      // can't re-run it. AppSettings keeps its natural text key — not re-keyed.
      if (from < 13) {
        // Some migration tests build a *partial* DB (only the tables a given
        // step touches), so every operation here is guarded on table existence —
        // mirroring the v11/v12 blocks. A real v1–v12 DB has all six.
        Future<bool> has(String name) async => (await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
          variables: [Variable.withString(name)],
        ).get()).isNotEmpty;

        // 1. Drop orphans first, cascade order (clients are the root, never
        //    orphaned). The live DB carries children whose FK parent is gone
        //    (SQLite never enforces FKs retroactively — see #196); mirror
        //    sanitizeSnapshot so the not-null FK re-map below can't hit a NULL.
        Future<void> dropOrphans(String sql, List<String> needs) async {
          for (final t in needs) {
            if (!await has(t)) return;
          }
          await customStatement(sql);
        }

        await dropOrphans(
          'DELETE FROM projects WHERE CAST(client_id AS TEXT) NOT IN '
          '(SELECT CAST(id AS TEXT) FROM clients)',
          ['projects', 'clients'],
        );
        await dropOrphans(
          'DELETE FROM tasks WHERE CAST(project_id AS TEXT) NOT IN '
          '(SELECT CAST(id AS TEXT) FROM projects)',
          ['tasks', 'projects'],
        );
        await dropOrphans(
          'DELETE FROM time_entries WHERE CAST(project_id AS TEXT) NOT IN '
          '(SELECT CAST(id AS TEXT) FROM projects) OR (task_id IS NOT NULL AND '
          'CAST(task_id AS TEXT) NOT IN (SELECT CAST(id AS TEXT) FROM tasks))',
          ['time_entries', 'projects', 'tasks'],
        );
        await dropOrphans(
          'UPDATE profiles SET template_id = NULL WHERE template_id IS NOT NULL '
          'AND CAST(template_id AS TEXT) NOT IN '
          '(SELECT CAST(id AS TEXT) FROM templates)',
          ['profiles', 'templates'],
        );

        // 2. Build an old-id → UUIDv7 map per (present) table (uuids come from
        //    Dart — SQLite has no UUID function) into a temp table keyed by the
        //    cast-to-text old id, so lookups below are affinity-agnostic.
        const contentTables = [
          'clients',
          'projects',
          'tasks',
          'time_entries',
          'templates',
          'profiles',
        ];
        final present = [
          for (final t in contentTables)
            if (await has(t)) t,
        ];
        for (final table in present) {
          await customStatement(
            'CREATE TEMP TABLE _idmap_$table '
            '(old_key TEXT PRIMARY KEY, new_id TEXT NOT NULL)',
          );
          final rows = await customSelect(
            'SELECT CAST(id AS TEXT) AS k FROM $table',
          ).get();
          for (final r in rows) {
            await customStatement(
              'INSERT INTO _idmap_$table (old_key, new_id) VALUES (?, ?)',
              [r.read<String>('k'), idGen.newId()],
            );
          }
        }

        // 3. Rebuild each present table to the v13 (text-id) shape, remapping its
        //    own id and every FK through the maps. TableMigration recreates the
        //    table at the current schema and copies via INSERT…SELECT; the
        //    columnTransformer subqueries supply the new text ids. A NULL FK
        //    (optional taskId / templateId) yields NULL from the subquery —
        //    preserved. A present child always has its parent present too (valid
        //    graph), so every referenced map exists.
        String mapped(String mapTable, String col) =>
            '(SELECT new_id FROM _idmap_$mapTable '
            'WHERE old_key = CAST($col AS TEXT))';

        Future<void> rekey(String name, TableMigration Function() build) async {
          if (await has(name)) await m.alterTable(build());
        }

        await rekey(
          'clients',
          () => TableMigration(
            clients,
            columnTransformer: {
              clients.id: CustomExpression(mapped('clients', 'id')),
            },
            // orgId (Phase 4) postdates v13 → absent from the table being
            // rebuilt; declare it new so the rebuild defaults it NULL (the later
            // from<17 add-if-missing then no-ops), mirroring projects.archivedAt.
            newColumns: [clients.orgId],
          ),
        );
        await rekey(
          'projects',
          () => TableMigration(
            projects,
            columnTransformer: {
              projects.id: CustomExpression(mapped('projects', 'id')),
              projects.clientId: CustomExpression(
                mapped('clients', 'client_id'),
              ),
            },
            // archivedAt (#246) postdates v13, so it's absent from the old table
            // being rebuilt — declare it new so the rebuild defaults it to NULL
            // (the later from<16 add-if-missing then no-ops). clients.archivedAt
            // predates v13, so its rekey needs no such declaration. orgId (Phase
            // 4) likewise postdates v13 → declared new on every content rekey.
            newColumns: [projects.archivedAt, projects.orgId],
          ),
        );
        await rekey(
          'tasks',
          () => TableMigration(
            tasks,
            columnTransformer: {
              tasks.id: CustomExpression(mapped('tasks', 'id')),
              tasks.projectId: CustomExpression(
                mapped('projects', 'project_id'),
              ),
            },
            newColumns: [tasks.orgId], // Phase 4 scope key postdates v13
          ),
        );
        await rekey(
          'time_entries',
          () => TableMigration(
            timeEntries,
            columnTransformer: {
              timeEntries.id: CustomExpression(mapped('time_entries', 'id')),
              timeEntries.projectId: CustomExpression(
                mapped('projects', 'project_id'),
              ),
              timeEntries.taskId: CustomExpression(mapped('tasks', 'task_id')),
            },
            newColumns: [timeEntries.orgId], // Phase 4 scope key postdates v13
          ),
        );
        await rekey(
          'templates',
          () => TableMigration(
            templates,
            columnTransformer: {
              templates.id: CustomExpression(mapped('templates', 'id')),
            },
            newColumns: [templates.orgId], // Phase 4 scope key postdates v13
          ),
        );
        await rekey(
          'profiles',
          () => TableMigration(
            profiles,
            columnTransformer: {
              profiles.id: CustomExpression(mapped('profiles', 'id')),
              profiles.templateId: CustomExpression(
                mapped('templates', 'template_id'),
              ),
            },
            newColumns: [profiles.orgId], // Phase 4 scope key postdates v13
          ),
        );

        // 4. Temp maps are per-connection — drop the ones we created.
        for (final table in present) {
          await customStatement('DROP TABLE _idmap_$table');
        }
      }
      // v13 → v14: DB-backed timer (PRD #189, Phase 3). A brand-new table for
      // the persisted active timer — no prior DB has it, so every upgrade path
      // creates it. Guarded from<14 so a future bump can't re-run createTable.
      if (from < 14) {
        await m.createTable(activeTimers);
      }
      // v14 → v15: persist the session note on the active-timer row so it
      // survives a restart (not just the bound project/task). Nullable add —
      // legal ALTER; guarded add-if-missing (a from<14 DB just created the table
      // at the current shape, which already has the column).
      if (from < 15) {
        final exists = (await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name = 'active_timers'",
        ).get()).isNotEmpty;
        if (exists) {
          final cols = await customSelect(
            'PRAGMA table_info(active_timers)',
          ).get();
          if (!cols.any((r) => r.read<String>('name') == 'description')) {
            await m.addColumn(activeTimers, activeTimers.description);
          }
        }
      }
      // v15 → v16: user-facing archive (#246). Add a nullable `archivedAt` to
      // projects (clients already carry the column). Nullable, no default →
      // existing rows are NULL (= active), no backfill. Add-if-missing (PRAGMA
      // check) so a rebuild path that already has the column doesn't throw —
      // and defensively ensure clients' column too.
      if (from < 16) {
        Future<bool> tableExists(String name) async => (await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
          variables: [Variable.withString(name)],
        ).get()).isNotEmpty;

        Future<void> addArchivedAt(TableInfo t, GeneratedColumn c) async {
          if (!await tableExists(t.actualTableName)) return; // defensive
          final cols = await customSelect(
            'PRAGMA table_info(${t.actualTableName})',
          ).get();
          if (!cols.any((r) => r.read<String>('name') == c.name)) {
            await m.addColumn(t, c);
          }
        }

        await addArchivedAt(clients, clients.archivedAt);
        await addArchivedAt(projects, projects.archivedAt);
      }
      // v16 → v17: tenancy scope key for the optional sync layer (PRD #189,
      // Phase 4c). Add a nullable `org_id` to the six SYNCED content tables
      // (app_settings/active_timers stay device-local → no org_id). Nullable, no
      // default → existing rows are NULL (= unscoped/local), no backfill; sync's
      // seed step (Phase 4d) stamps the personal org_id when it's enabled. Some
      // upgrade paths already created the column via an earlier rebuild to the
      // current shape, so each add is guarded add-if-missing (PRAGMA), mirroring
      // the v11/v12/v16 blocks.
      if (from < 17) {
        Future<bool> tableExists(String name) async => (await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
          variables: [Variable.withString(name)],
        ).get()).isNotEmpty;

        Future<void> addOrgId(TableInfo t, GeneratedColumn c) async {
          if (!await tableExists(t.actualTableName)) return; // defensive
          final cols = await customSelect(
            'PRAGMA table_info(${t.actualTableName})',
          ).get();
          if (!cols.any((r) => r.read<String>('name') == c.name)) {
            await m.addColumn(t, c);
          }
        }

        await addOrgId(clients, clients.orgId);
        await addOrgId(projects, projects.orgId);
        await addOrgId(tasks, tasks.orgId);
        await addOrgId(timeEntries, timeEntries.orgId);
        await addOrgId(templates, templates.orgId);
        await addOrgId(profiles, profiles.orgId);
      }
      // v17 → v18: delta-sync local dirty-tracker (PRD #189, Phase 5b). A brand
      // new device-local table (`sync_outbox`) — no existing table is touched,
      // so this is a plain create-if-missing (guarded so a rebuild path that
      // already made it doesn't collide). See [SyncOutbox].
      if (from < 18) {
        final exists = (await customSelect(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
          variables: [Variable.withString(syncOutbox.actualTableName)],
        ).get()).isNotEmpty;
        if (!exists) await m.createTable(syncOutbox);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  // ── First-run example data (PRD #133) ─────────────────────────────────────
  // A fresh install is seeded once with a small, deliberately generic example —
  // one client, two projects, a handful of tasks and time entries — so a new
  // user opens the app to a worked example of how tracking looks rather than a
  // blank slate. It's ordinary data: explore it, then archive or delete it when
  // you're ready for your own (see docs getting-started). There is no forced
  // "default project" — the app degrades to a clean empty state when every
  // project is gone (see [firstProjectId]).
  static const _exampleSeededKey = 'example_data_seeded';

  /// Seed the example data on first run — but only into a genuinely empty
  /// database, and only once (guarded by a flag). The flag is set either way,
  /// so removing the example data is permanent, and existing installs upgrading
  /// (which already hold data) are never seeded into.
  Future<void> seedFirstRunExampleData() async {
    if (await _getFlag(_exampleSeededKey)) return;
    final hasClient =
        await (select(clients)..limit(1)).getSingleOrNull() != null;
    final hasProject =
        await (select(projects)..limit(1)).getSingleOrNull() != null;
    if (!hasClient && !hasProject) {
      await _insertExampleData();
    }
    await _setFlag(_exampleSeededKey, true);
  }

  Future<void> _insertExampleData() => transaction(() async {
    final now = DateTime.now();
    final clientId = await addClient(
      name: 'Example Client',
      contactName: 'Jordan Example',
      email: 'hello@example.com',
      defaultRate: 80,
    );
    final projectA = await addProject(
      clientId: clientId,
      code: 'EXAMPLE',
      title: 'Example Project',
    );
    final projectB = await addProject(
      clientId: clientId,
      code: 'EXAMPLE2',
      title: 'Example Project 2',
      rate: 95,
    );
    final planning = await addTask(projectId: projectA, title: 'Planning');
    final design = await addTask(projectId: projectA, title: 'Design');
    final review = await addTask(projectId: projectA, title: 'Review');
    final research = await addTask(projectId: projectB, title: 'Research');
    final documentation =
        await addTask(projectId: projectB, title: 'Documentation');

    Future<void> entry(
      String projectId,
      String taskId,
      String note,
      int daysAgo,
      int seconds,
    ) {
      final started = now.subtract(Duration(days: daysAgo));
      return addEntry(
        projectId: projectId,
        taskId: taskId,
        description: note,
        startedAt: started,
        endedAt: started.add(Duration(seconds: seconds)),
        seconds: seconds,
      );
    }

    await entry(projectA, planning, 'Kickoff & scope', 9, 6300); // 1h45m
    await entry(projectA, design, 'First draft', 7, 7800); // 2h10m
    await entry(projectA, design, 'Layout revisions', 5, 4800); // 1h20m
    await entry(projectA, review, 'Feedback round', 3, 3000); // 0h50m
    await entry(projectA, planning, 'Client call', 2, 1800); // 0h30m
    await entry(projectB, research, 'Background reading', 6, 5400); // 1h30m
    await entry(projectB, research, 'Notes consolidation', 4, 2700); // 0h45m
    await entry(projectB, documentation, 'Write-up', 1, 7200); // 2h00m
  });

  /// The first live, non-archived project by the ordering the project list uses
  /// (title, ascending), or null when there are none. The shell opens on this,
  /// so it degrades cleanly to the empty state once all projects are gone.
  Future<String?> firstProjectId() async {
    final row = await (select(projects)
          ..where((p) => p.deletedAt.isNull() & p.archivedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.title)])
          ..limit(1))
        .getSingleOrNull();
    return row?.id;
  }

  Future<void> addEntry({
    required String projectId,
    required String taskId,
    String? description,
    required DateTime startedAt,
    required DateTime endedAt,
    required int seconds,
  }) => transaction(() async {
    // Generate the id up-front (rather than leaning on the clientDefault) so it
    // can be enqueued into the sync outbox in the same transaction.
    final id = idGen.newId();
    await into(timeEntries).insert(
      TimeEntriesCompanion.insert(
        id: Value(id),
        projectId: projectId,
        taskId: Value(taskId),
        description: Value(description),
        startedAt: startedAt,
        endedAt: endedAt,
        seconds: seconds,
      ),
    );
    await markDirtyForSync(timeEntries.actualTableName, [id]);
  });

  // [projectId] is required (not optional) so every caller states the entry's
  // owning project explicitly — this is how the CLI's `entry edit` keeps
  // `projectId` from going stale when `--task` rebinds the entry to a task
  // under a different project (issue #284): the caller resolves the new
  // task first, reads *its* projectId, and passes both here together.
  Future<void> updateEntry({
    required String id,
    required String projectId,
    required String taskId,
    String? description,
    required DateTime startedAt,
    required DateTime endedAt,
    required int seconds,
  }) => transaction(() async {
    await (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(
        projectId: Value(projectId),
        taskId: Value(taskId),
        description: Value(description),
        startedAt: Value(startedAt),
        endedAt: Value(endedAt),
        seconds: Value(seconds),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await markDirtyForSync(timeEntries.actualTableName, [id]);
  });

  // Soft-delete (sync tombstone): set deletedAt + bump updatedAt instead of a
  // hard DELETE, so the removal propagates across devices. Reads filter it out.
  Future<void> deleteEntry(String id) => transaction(() async {
    final now = DateTime.now();
    await (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await markDirtyForSync(timeEntries.actualTableName, [id]);
  });

  Future<String> addProject({
    required String clientId,
    required String code,
    required String title,
    double? rate,
  }) {
    final id = idGen.newId();
    return transaction(() async {
      await into(projects).insert(
        ProjectsCompanion.insert(
          id: Value(id),
          clientId: clientId,
          code: code,
          title: title,
          rate: rate == null ? const Value.absent() : Value(rate),
          // Stamp status/createdAt in Dart rather than leaning on the columns'
          // SQL defaults, so the row is explicitly complete at the insert
          // choke-point and the delta-sync push never sends a NULL for a
          // NOT NULL server column (#299).
          status: const Value('active'),
          createdAt: Value(DateTime.now()),
        ),
      );
      await markDirtyForSync(projects.actualTableName, [id]);
      return id;
    });
  }

  Future<void> updateProject({
    required String id,
    required String clientId,
    required String code,
    required String title,
    double? rate,
  }) => transaction(() async {
    await (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(
        clientId: Value(clientId),
        code: Value(code),
        title: Value(title),
        rate: Value(rate),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await markDirtyForSync(projects.actualTableName, [id]);
  });

  // Blocked while the project still has tasks or time entries (both FK-reference
  // it). Pre-checked in a transaction — portable and deterministic across the
  // native and web backends — rather than catching a backend-specific FK error.
  Future<void> deleteProject(String id) => transaction(() async {
    // Count only LIVE children — a project whose tasks/entries are all
    // soft-deleted can itself be deleted.
    final hasTasks =
        await (select(tasks)
              ..where((t) => t.projectId.equals(id) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull() !=
        null;
    final hasEntries =
        await (select(timeEntries)
              ..where((t) => t.projectId.equals(id) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull() !=
        null;
    if (hasTasks || hasEntries) throw const DeleteBlockedException('project');
    final now = DateTime.now();
    await (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await markDirtyForSync(projects.actualTableName, [id]);
  });

  // Joins clients so an archived (or deleted) client hides its projects too —
  // "archiving a client hides its projects" (#246). [includeArchived] false
  // (default) excludes archived projects and projects of archived clients; true
  // reveals both for the "Show archived" view.
  Stream<List<Project>> watchProjects({bool includeArchived = false}) {
    final q = select(projects).join([
      innerJoin(clients, clients.id.equalsExp(projects.clientId)),
    ])
      ..where(projects.deletedAt.isNull() & clients.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(projects.title)]);
    if (!includeArchived) {
      q.where(projects.archivedAt.isNull() & clients.archivedAt.isNull());
    }
    return q.map((row) => row.readTable(projects)).watch();
  }

  Stream<(Project, Client)?> watchProjectWithClient(String id) {
    final q = select(projects).join([
      innerJoin(clients, clients.id.equalsExp(projects.clientId)),
    ])..where(projects.id.equals(id) & projects.deletedAt.isNull());
    return q.watchSingleOrNull().map(
      (row) => row == null
          ? null
          : (row.readTable(projects), row.readTable(clients)),
    );
  }

  Stream<List<TimeEntry>> watchEntriesForProject(String projectId) =>
      (select(timeEntries)
            ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.endedAt)]))
          .watch();

  // --- Tasks ---

  Stream<List<Task>> watchTasksForProject(String projectId) =>
      (select(tasks)
            ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.title)]))
          .watch();

  Stream<List<TimeEntry>> watchEntriesForTask(String taskId) =>
      (select(timeEntries)
            ..where((t) => t.taskId.equals(taskId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.endedAt)]))
          .watch();

  Future<String> addTask({
    required String projectId,
    required String title,
    double? rate,
  }) {
    final id = idGen.newId();
    return transaction(() async {
      await into(tasks).insert(
        TasksCompanion.insert(
          id: Value(id),
          projectId: projectId,
          title: title,
          rate: rate == null ? const Value.absent() : Value(rate),
          // See addProject: stamp in Dart so status/createdAt are explicitly
          // set for the delta-sync push (#299).
          status: const Value('active'),
          createdAt: Value(DateTime.now()),
        ),
      );
      await markDirtyForSync(tasks.actualTableName, [id]);
      return id;
    });
  }

  Future<void> updateTask({
    required String id,
    required String title,
    double? rate,
  }) => transaction(() async {
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: Value(title),
        rate: Value(rate),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await markDirtyForSync(tasks.actualTableName, [id]);
  });

  // Blocked while the task still has time entries (they FK-reference it) —
  // matching how projects/clients guard their children. The caller surfaces
  // that as "delete its entries first".
  Future<void> deleteTask(String id) => transaction(() async {
    final hasEntries =
        await (select(timeEntries)
              ..where((t) => t.taskId.equals(id) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull() !=
        null;
    if (hasEntries) throw const DeleteBlockedException('task');
    final now = DateTime.now();
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await markDirtyForSync(tasks.actualTableName, [id]);
  });

  // [includeArchived] false (the default) hides archived clients — the active
  // list / pickers; true reveals them for the side panel's "Show archived".
  Stream<List<Client>> watchClients({bool includeArchived = false}) {
    final q = select(clients)
      ..where((c) => c.deletedAt.isNull())
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    if (!includeArchived) q.where((c) => c.archivedAt.isNull());
    return q.watch();
  }

  Stream<Project?> watchProject(String id) =>
      (select(projects)..where(
            (p) => p.id.equals(id) & p.deletedAt.isNull(),
          ))
          .watchSingleOrNull();

  Future<String> addClient({
    required String name,
    String? contactName,
    String? email,
    String? phone,
    String? address,
    String? abn,
    required double defaultRate,
  }) {
    final id = idGen.newId();
    return transaction(() async {
      await into(clients).insert(
        ClientsCompanion.insert(
          id: Value(id),
          name: name,
          contactName: Value(contactName),
          email: email == null ? const Value.absent() : Value(email),
          phone: Value(phone),
          address: Value(address),
          abn: Value(abn),
          defaultRate: defaultRate,
        ),
      );
      await markDirtyForSync(clients.actualTableName, [id]);
      return id;
    });
  }

  Future<void> updateClient({
    required String id,
    required String name,
    String? contactName,
    String? email,
    String? phone,
    String? address,
    String? abn,
    required double defaultRate,
  }) => transaction(() async {
    await (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(
        name: Value(name),
        contactName: Value(contactName),
        email: Value(email),
        phone: Value(phone),
        address: Value(address),
        abn: Value(abn),
        defaultRate: Value(defaultRate),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await markDirtyForSync(clients.actualTableName, [id]);
  });

  // Blocked while the client still has projects (they FK-reference it).
  Future<void> deleteClient(String id) => transaction(() async {
    final hasProjects =
        await (select(projects)
              ..where((p) => p.clientId.equals(id) & p.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull() !=
        null;
    if (hasProjects) throw const DeleteBlockedException('client');
    final now = DateTime.now();
    await (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await markDirtyForSync(clients.actualTableName, [id]);
  });

  // ── Active-timer guard (#248) ─────────────────────────────────────────────
  // A running timer binds one project (and optionally its task). Deleting or
  // archiving anything that binding falls under would strand the active_timers
  // row: on finish the store writes a live TimeEntry under a tombstoned/archived
  // parent — an orphan hidden from the active lists. The confirm flows call
  // these to block that (rare) case and ask the user to stop the timer first.
  // Each returns true iff the single LIVE timer is bound inside the subtree.
  Future<bool> isTimerBoundToTask(String taskId) async =>
      (await activeTimer())?.taskId == taskId;

  Future<bool> isTimerBoundToProject(String projectId) async =>
      (await activeTimer())?.projectId == projectId;

  Future<bool> isTimerBoundToClient(String clientId) async {
    final projectId = (await activeTimer())?.projectId;
    if (projectId == null) return false;
    // Raw lookup (no deletedAt filter): a timer bound to an already-tombstoned
    // project is exactly the dangling state we're guarding, so still count it.
    final project =
        await (select(projects)..where((p) => p.id.equals(projectId)))
            .getSingleOrNull();
    return project?.clientId == clientId;
  }

  // ── Cascade (bulk) delete (#75) ──────────────────────────────────────────
  // The per-level guards above stay the default; these are the deliberate,
  // count-warned escape hatch offered when a guarded delete is blocked. Each
  // soft-deletes every LIVE descendant and the parent in one transaction, so
  // it composes with the sync tombstone model. Entries reference their client
  // directly (clientId); tasks reach the client only via their project.

  // Tasks and entries carry no clientId — they reach the client only via their
  // projectId. This matches such a projectId column against the ids of the
  // client's projects, so it can filter both tables' rows for one client.
  Expression<bool> _underClient(Expression<String> projectIdCol, String clientId) {
    final projectIds = selectOnly(projects)
      ..addColumns([projects.id])
      ..where(projects.clientId.equals(clientId));
    return projectIdCol.isInQuery(projectIds);
  }

  // Count matching rows with a SQL COUNT aggregate rather than fetching them —
  // an impact preview shouldn't load a client's whole entry history into memory.
  Future<int> _countLive<T extends HasResultSet, R>(
    ResultSetImplementation<T, R> table,
    Expression<bool> filter,
  ) {
    final c = countAll();
    return (selectOnly(table)
          ..addColumns([c])
          ..where(filter))
        .map((row) => row.read(c)!)
        .getSingle();
  }

  // Ids of the LIVE rows a cascade is about to tombstone — read before the bulk
  // update (while `deletedAt IS NULL` still matches) so each can be enqueued
  // into the sync outbox. Only called when [enableSyncOutbox] is set.
  Future<List<String>> _liveIds<T extends HasResultSet, R>(
    ResultSetImplementation<T, R> table,
    GeneratedColumn<String> idCol,
    Expression<bool> filter,
  ) => (selectOnly(table)
        ..addColumns([idCol])
        ..where(filter))
      .map((row) => row.read(idCol)!)
      .get();

  /// Live descendant counts under a client (projects, tasks, entries).
  Future<DeleteImpact> clientDeleteImpact(String id) async {
    final projectCount = await _countLive(
      projects,
      projects.clientId.equals(id) & projects.deletedAt.isNull(),
    );
    final taskCount = await _countLive(
      tasks,
      _underClient(tasks.projectId, id) & tasks.deletedAt.isNull(),
    );
    final entryCount = await _countLive(
      timeEntries,
      _underClient(timeEntries.projectId, id) & timeEntries.deletedAt.isNull(),
    );
    return DeleteImpact(
      projects: projectCount,
      tasks: taskCount,
      entries: entryCount,
    );
  }

  /// Live descendant counts under a project (tasks, entries).
  Future<DeleteImpact> projectDeleteImpact(String id) async {
    final taskCount = await _countLive(
      tasks,
      tasks.projectId.equals(id) & tasks.deletedAt.isNull(),
    );
    final entryCount = await _countLive(
      timeEntries,
      timeEntries.projectId.equals(id) & timeEntries.deletedAt.isNull(),
    );
    return DeleteImpact(tasks: taskCount, entries: entryCount);
  }

  /// Live entry count under a task.
  Future<DeleteImpact> taskDeleteImpact(String id) async {
    final entryCount = await _countLive(
      timeEntries,
      timeEntries.taskId.equals(id) & timeEntries.deletedAt.isNull(),
    );
    return DeleteImpact(entries: entryCount);
  }

  Future<void> deleteClientCascade(String id) => transaction(() async {
    final now = DateTime.now();
    // Snapshot the live descendants BEFORE tombstoning them, so every cascaded
    // soft-delete is enqueued for sync (each is a normal tombstone upsert). Only
    // when the outbox is active — the pure-local path skips the extra reads.
    final entryIds = enableSyncOutbox
        ? await _liveIds(timeEntries, timeEntries.id,
            _underClient(timeEntries.projectId, id) & timeEntries.deletedAt.isNull())
        : const <String>[];
    final taskIds = enableSyncOutbox
        ? await _liveIds(tasks, tasks.id,
            _underClient(tasks.projectId, id) & tasks.deletedAt.isNull())
        : const <String>[];
    final projectIds = enableSyncOutbox
        ? await _liveIds(projects, projects.id,
            projects.clientId.equals(id) & projects.deletedAt.isNull())
        : const <String>[];
    await (update(timeEntries)
          ..where((e) => _underClient(e.projectId, id) & e.deletedAt.isNull()))
        .write(TimeEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await (update(tasks)
          ..where((t) => _underClient(t.projectId, id) & t.deletedAt.isNull()))
        .write(TasksCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await (update(projects)
          ..where((p) => p.clientId.equals(id) & p.deletedAt.isNull()))
        .write(ProjectsCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await markDirtyForSync(timeEntries.actualTableName, entryIds);
    await markDirtyForSync(tasks.actualTableName, taskIds);
    await markDirtyForSync(projects.actualTableName, projectIds);
    await markDirtyForSync(clients.actualTableName, [id]);
  });

  Future<void> deleteProjectCascade(String id) => transaction(() async {
    final now = DateTime.now();
    final entryIds = enableSyncOutbox
        ? await _liveIds(timeEntries, timeEntries.id,
            timeEntries.projectId.equals(id) & timeEntries.deletedAt.isNull())
        : const <String>[];
    final taskIds = enableSyncOutbox
        ? await _liveIds(tasks, tasks.id,
            tasks.projectId.equals(id) & tasks.deletedAt.isNull())
        : const <String>[];
    await (update(timeEntries)
          ..where((e) => e.projectId.equals(id) & e.deletedAt.isNull()))
        .write(TimeEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await (update(tasks)
          ..where((t) => t.projectId.equals(id) & t.deletedAt.isNull()))
        .write(TasksCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await markDirtyForSync(timeEntries.actualTableName, entryIds);
    await markDirtyForSync(tasks.actualTableName, taskIds);
    await markDirtyForSync(projects.actualTableName, [id]);
  });

  Future<void> deleteTaskCascade(String id) => transaction(() async {
    final now = DateTime.now();
    final entryIds = enableSyncOutbox
        ? await _liveIds(timeEntries, timeEntries.id,
            timeEntries.taskId.equals(id) & timeEntries.deletedAt.isNull())
        : const <String>[];
    await (update(timeEntries)
          ..where((e) => e.taskId.equals(id) & e.deletedAt.isNull()))
        .write(TimeEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)));
    await (update(tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await markDirtyForSync(timeEntries.actualTableName, entryIds);
    await markDirtyForSync(tasks.actualTableName, [id]);
  });

  // ── Archive (reversible hide-from-UI) (#246) ─────────────────────────────
  // Sets/clears archivedAt (+ bumps updatedAt for sync). Orthogonal to delete:
  // archived rows stay live and fully resolvable for invoices/history; the
  // active lists and pickers just filter them out (see watchClients/Projects).

  Future<void> archiveClient(String id) => _setClientArchived(id, DateTime.now());
  Future<void> unarchiveClient(String id) => _setClientArchived(id, null);
  Future<void> _setClientArchived(String id, DateTime? at) => transaction(() async {
    await (update(clients)..where((c) => c.id.equals(id))).write(
      ClientsCompanion(archivedAt: Value(at), updatedAt: Value(DateTime.now())),
    );
    await markDirtyForSync(clients.actualTableName, [id]);
  });

  Future<void> archiveProject(String id) =>
      _setProjectArchived(id, DateTime.now());
  Future<void> unarchiveProject(String id) => _setProjectArchived(id, null);
  Future<void> _setProjectArchived(String id, DateTime? at) => transaction(() async {
    await (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(archivedAt: Value(at), updatedAt: Value(DateTime.now())),
    );
    await markDirtyForSync(projects.actualTableName, [id]);
  });

  // ── Invoice branding: seed + DAOs (PRD #79) ──────────────────────────────

  /// Seed a timedart Template (visual style) and an example Profile pointed at
  /// it on first run. Idempotent — a no-op once any Template exists — so it's
  /// safe to call at every startup (mirrors [ensureDefaultProject]). Colours are
  /// the brand tokens as ARGB ints; the user edits them in the template editor.
  Future<void> ensureInvoiceDefaults() async {
    final existing = await (select(templates)..limit(1)).getSingleOrNull();
    if (existing != null) return;
    final templateId = idGen.newId();
    await into(templates).insert(
      TemplatesCompanion.insert(
        id: Value(templateId),
        name: 'timedart',
        colorBackground: 0xFF11140E, // brand dark surface
        colorSurface: 0xFF23241F, // neutral dark card (was green-tinted)
        colorPrimary: 0xFF69E228, // brand green
        colorText: 0xFFE2E3D8, // logo off-white (AppTokens.colorOffWhite)
        colorAccent: 0xFF2E6C0F, // brand secondary
        fontFamily: const Value('Outfit'),
        isDefault: const Value(true),
      ),
    );
    await into(profiles).insert(
      ProfilesCompanion.insert(
        name: 'Default',
        businessName: const Value('Your Business'),
        currency: const Value('USD'),
        templateId: Value(templateId),
        isDefault: const Value(true),
      ),
    );
  }

  // Templates (the visual style: colours, font)
  Stream<List<InvoiceTemplate>> watchTemplates() =>
      (select(templates)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();
  // Unfiltered by design: a since-deleted template must still resolve for any
  // profile/invoice still pointing at it.
  Future<InvoiceTemplate> templateById(String id) =>
      (select(templates)..where((t) => t.id.equals(id))).getSingle();
  Future<InvoiceTemplate?> defaultTemplate() => (select(templates)..where(
    (t) => t.isDefault.equals(true) & t.deletedAt.isNull(),
  )).getSingleOrNull();
  // Generates the uuid PK and returns it: insert() yields the int rowid, not the
  // text id, so callers that need the new row's id get it from here.
  Future<String> insertTemplate(TemplatesCompanion t) {
    final id = idGen.newId();
    return into(templates).insert(t.copyWith(id: Value(id))).then((_) => id);
  }

  Future<void> updateTemplateById(String id, TemplatesCompanion t) =>
      (update(templates)..where((x) => x.id.equals(id))).write(
        t.copyWith(updatedAt: Value(DateTime.now())),
      );
  // Soft-delete: hide from [watchTemplates] but keep the row so any invoice/
  // profile still pointing at it resolves via [templateById] (left unfiltered).
  Future<void> deleteTemplate(String id) {
    final now = DateTime.now();
    return (update(templates)..where((x) => x.id.equals(id))).write(
      TemplatesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
  Future<void> setDefaultTemplate(String id) => transaction(() async {
    final now = DateTime.now();
    await update(templates).write(
      TemplatesCompanion(isDefault: const Value(false), updatedAt: Value(now)),
    );
    await (update(templates)..where((x) => x.id.equals(id))).write(
      TemplatesCompanion(isDefault: const Value(true), updatedAt: Value(now)),
    );
  });

  // Profiles (business identity + payment; each points at a Template)
  Stream<List<InvoiceProfile>> watchProfiles() =>
      (select(profiles)
            ..where((p) => p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .watch();
  // Unfiltered by design: a past invoice must still resolve a since-deleted
  // profile.
  Future<InvoiceProfile> profileById(String id) =>
      (select(profiles)..where((p) => p.id.equals(id))).getSingle();
  Future<InvoiceProfile?> defaultProfile() => (select(profiles)..where(
    (p) => p.isDefault.equals(true) & p.deletedAt.isNull(),
  )).getSingleOrNull();
  Future<String> insertProfile(ProfilesCompanion p) {
    final id = idGen.newId();
    return into(profiles).insert(p.copyWith(id: Value(id))).then((_) => id);
  }

  Future<void> updateProfileById(String id, ProfilesCompanion p) =>
      (update(profiles)..where((x) => x.id.equals(id))).write(
        p.copyWith(updatedAt: Value(DateTime.now())),
      );
  // Soft-delete: hide from [watchProfiles] but keep the row so a past invoice
  // still resolves it via [profileById] (left unfiltered).
  Future<void> deleteProfile(String id) {
    final now = DateTime.now();
    return (update(profiles)..where((x) => x.id.equals(id))).write(
      ProfilesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
  Future<void> setDefaultProfile(String id) => transaction(() async {
    final now = DateTime.now();
    await update(profiles).write(
      ProfilesCompanion(isDefault: const Value(false), updatedAt: Value(now)),
    );
    await (update(profiles)..where((x) => x.id.equals(id))).write(
      ProfilesCompanion(isDefault: const Value(true), updatedAt: Value(now)),
    );
  });

  // ── App settings (key-value; PRD #133) ─────────────────────────────────────
  // A deep module: the string key/value encoding stays private; callers use the
  // typed helpers below.
  static const _onboardingCompleteKey = 'onboarding_complete';
  static const _installIdKey = 'install_id';

  Future<String?> _getSetting(String key) async {
    final row = await (select(
      appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setSetting(String key, String value) =>
      into(appSettings).insertOnConflictUpdate(
        AppSettingsCompanion(
          key: Value(key),
          value: Value(value),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<bool> _getFlag(String key) async => (await _getSetting(key)) == 'true';
  Future<void> _setFlag(String key, bool value) =>
      _setSetting(key, value ? 'true' : 'false');

  /// Whether the first-run onboarding flow has been completed (or skipped).
  /// A fresh install has no row → false, so onboarding shows once.
  Future<bool> isOnboardingComplete() => _getFlag(_onboardingCompleteKey);

  /// Mark onboarding complete (default) — or clear it (`false`) to replay the
  /// flow, which the Settings "Re-run setup" action and tests rely on.
  Future<void> setOnboardingComplete([bool value = true]) =>
      _setFlag(_onboardingCompleteKey, value);

  /// A stable, per-install identifier: minted once (UUIDv7) on first read and
  /// persisted thereafter, so every subsequent call returns the same value.
  /// Groundwork for the optional sync layer (PRD #189, Phase 4): it gives the
  /// eventual account subject / `org_id` a stable source that predates sync, so
  /// existing local data can be attributed at enable-time without inventing an
  /// identity right when we also seed and connect. Called at startup so current
  /// installs acquire one now, while the base is small. Device-local: it lives
  /// in [AppSettings] (never synced) and is not surfaced in the UI.
  Future<String> installId() => transaction(() async {
    final existing = await _getSetting(_installIdKey);
    if (existing != null) return existing;
    final id = idGen.newId();
    await _setSetting(_installIdKey, id);
    return id;
  });

  // Row getters for assembling an InvoiceDocument (the pure builder lives in
  // features/invoices — the data layer only hands back rows).
  Future<Project> getProject(String id) => (select(
    projects,
  )..where((p) => p.id.equals(id) & p.deletedAt.isNull())).getSingle();
  Future<Client> getClient(String id) => (select(
    clients,
  )..where((c) => c.id.equals(id) & c.deletedAt.isNull())).getSingle();
  Future<List<Task>> tasksForProject(String projectId) => (select(tasks)..where(
    (t) => t.projectId.equals(projectId) & t.deletedAt.isNull(),
  )).get();
  Future<List<TimeEntry>> entriesForProjectInPeriod(
    String projectId,
    DateTime from,
    DateTime to,
  ) =>
      (select(timeEntries)
            ..where(
              (t) =>
                  t.projectId.equals(projectId) &
                  t.deletedAt.isNull() &
                  t.startedAt.isBiggerOrEqualValue(from) &
                  t.startedAt.isSmallerOrEqualValue(to),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
          .get();

  // ── Active timer (DB-backed timer; PRD #189, Phase 3) ─────────────────────
  // Raw accessors for the single live active-timer row. Transition/recovery
  // logic lives in the TimerStore deep module (features/tracker/timer_store).
  // `limit(1)` guards against ever seeing >1 live row (shouldn't happen before
  // sync; watchSingleOrNull would otherwise throw).
  Stream<ActiveTimer?> watchActiveTimer() =>
      (select(activeTimers)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(1))
          .watchSingleOrNull();

  Future<ActiveTimer?> activeTimer() =>
      (select(activeTimers)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(1))
          .getSingleOrNull();

  // ── External-change detection (live GUI refresh; PRD #270, slice #274) ─────
  // SQLite bumps `data_version` on this connection whenever ANOTHER connection
  // commits (the companion CLI, or a delta-sync apply); it is unchanged by this
  // connection's own writes. The ExternalChangeWatcher polls [dataVersion] and,
  // on a detected external commit, calls [refreshAllStreams] so every open
  // `watch()` re-emits — no per-screen wiring.
  Future<int> dataVersion() async {
    final row = await customSelect('PRAGMA data_version').getSingle();
    return row.data.values.first as int;
  }

  /// Notify drift that every content table may have changed, so all live
  /// `watch()` streams re-emit. Used only to reflect *external* writes — drift
  /// already refreshes streams for this connection's own writes.
  void refreshAllStreams() => markTablesUpdated(allTables);

  // Insert-or-update the active-timer row by id, re-stamping updatedAt at the
  // choke-point (like every other write).
  Future<void> saveActiveTimer(ActiveTimersCompanion row) => into(
    activeTimers,
  ).insertOnConflictUpdate(row.copyWith(updatedAt: Value(DateTime.now())));

  // Soft-delete (tombstone) the active-timer row on finish, so the "stopped"
  // propagates across devices once sync lands.
  Future<void> tombstoneActiveTimer(String id) {
    final now = DateTime.now();
    return (update(activeTimers)..where((t) => t.id.equals(id))).write(
      ActiveTimersCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
