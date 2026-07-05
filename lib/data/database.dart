import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart'; // generated — doesn't exist until you run build_runner

class Clients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)(); // organisation
  TextColumn get contactName => text().nullable()(); // the person (invoice TO)
  TextColumn get email => text().nullable()(); // nullable column
  TextColumn get phone => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get abn => text().nullable()();
  RealColumn get defaultRate => real()(); // $/hr fallback — required
  DateTimeColumn get archivedAt => dateTime().nullable()();
}

class Jobs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get clientId => integer().references(Clients, #id)(); // FK
  TextColumn get code => text().unique()(); // human job number
  TextColumn get title => text()();
  RealColumn get rate => real().nullable()(); // overrides client default
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// A unit of work under a job. Owns many time-entry segments, so multiple
// sessions accumulate against one task. `rate` overrides the job's rate (used
// by a later invoicing pass); status leaves room for open/done/archived.
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get jobId => integer().references(Jobs, #id)();
  TextColumn get title => text()();
  RealColumn get rate => real().nullable()(); // overrides job.rate
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class TimeEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get jobId => integer().references(Jobs, #id)();
  // An entry belongs to a task; [description] is an optional per-segment note
  // (e.g. "fixed the login bug"). Nullable — most entries just inherit the
  // task's title in the UI.
  IntColumn get taskId => integer().nullable().references(Tasks, #id)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get seconds =>
      integer()(); // TRACKED time (excludes pauses) — see below
}

// ── Invoice branding (see PRD #79) ────────────────────────────────────────
// Three data-only tables. Colours are stored as ARGB ints (0xAARRGGBB) so the
// data layer stays UI-free — the UI/PDF convert to Color/PdfColor. A logo is
// raw PNG/JPG bytes so it travels with the DB (no orphaned files).

/// The *look* of an invoice: logo + colour scheme + font. Reusable across
/// templates. Exactly one row is the default (see [AppDatabase.setDefaultTheme]).
@DataClassName('InvoiceTheme') // 'Theme' would clash with Flutter's Theme
class Themes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  BlobColumn get logo => blob().nullable()(); // PNG/JPG bytes; null = no logo
  TextColumn get logoMime => text().nullable()(); // e.g. image/png
  IntColumn get colorBackground => integer()();
  IntColumn get colorSurface => integer()();
  IntColumn get colorPrimary => integer()();
  IntColumn get colorText => integer()();
  IntColumn get colorAccent => integer()();
  TextColumn get fontFamily => text().withDefault(const Constant('Urbanist'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

/// The *details* of an invoice: sender identity + payment + currency + optional
/// tax. Tax is null-by-default and international-neutral (a [taxLabel] + percent
/// [taxRate], or nothing). Reusable across templates; one row is the default.
@DataClassName('InvoiceProfile')
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)(); // internal label
  TextColumn get businessName => text().withDefault(const Constant(''))();
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
  TextColumn get taxLabel => text().nullable()(); // e.g. GST, VAT; null = no tax
  RealColumn get taxRate => real().nullable()(); // percent, e.g. 10.0
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

/// A named pairing of one [Themes] + one [Profiles] — the single thing chosen in
/// the invoicing flow. One row is the default.
@DataClassName('InvoiceTemplate')
class Templates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get themeId => integer().references(Themes, #id)();
  IntColumn get profileId => integer().references(Profiles, #id)();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

/// One itemised line of a [JobInvoice]: an entry with its hours and amount.
/// `amount` is null when the invoice has no effective rate (un-billable).
class InvoiceLine {
  final TimeEntry entry;
  final String label; // task title, plus the entry's own name when set
  final double hours;
  final double? amount;
  InvoiceLine({
    required this.entry,
    required this.label,
    required this.hours,
    required this.amount,
  });
}

/// An invoice for a single job over a period: the job, its client, the
/// effective rate (`null` = un-billable), and the itemised time entries.
///
/// Owns all invoice arithmetic — hours, per-line amounts, totals — so the
/// preview and the PDF read numbers rather than recomputing them.
class JobInvoice {
  final Job job;
  final Client client;
  final double? rate; // effective: job.rate ?? client.defaultRate
  final List<TimeEntry> entries;
  final Map<int, String> taskTitles; // taskId → title, for line labels
  JobInvoice({
    required this.job,
    required this.client,
    required this.rate,
    required this.entries,
    required this.taskTitles,
  });

  /// The itemised lines: hours and (rate-permitting) amount per entry.
  List<InvoiceLine> get lines => [
    for (final e in entries)
      InvoiceLine(
        entry: e,
        label: _labelFor(e),
        hours: e.seconds / 3600,
        amount: rate == null ? null : (e.seconds / 3600) * rate!,
      ),
  ];

  String _labelFor(TimeEntry e) {
    final task = e.taskId == null ? null : taskTitles[e.taskId];
    final desc = e.description?.trim();
    if (task == null) return desc == null || desc.isEmpty ? '—' : desc;
    return desc == null || desc.isEmpty ? task : '$task · $desc';
  }

  int get totalSeconds => entries.fold(0, (sum, e) => sum + e.seconds);
  double get totalHours => totalSeconds / 3600;
  double? get total => rate == null ? null : totalHours * rate!;
}

@DriftDatabase(
  tables: [Clients, Jobs, Tasks, TimeEntries, Themes, Profiles, Templates],
)
class AppDatabase extends _$AppDatabase {
  // _$AppDatabase is generated
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 5;

  // drift doesn't enforce foreign keys unless we turn the pragma on per
  // connection. With it on, deleting a job that has time entries (or a client
  // that has jobs) fails loudly instead of silently orphaning rows.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // v1 → v2: introduce Tasks between Job and TimeEntry. Create the table,
      // add the (nullable) taskId column, then fold each distinct
      // (job, task-string) into one Task and repoint its entries. The old
      // `task` string column is left in place (dropped later in #57). FK
      // enforcement is off during migration (beforeOpen runs afterwards), so
      // the ALTER + backfill are safe.
      if (from < 2) {
        await m.createTable(tasks);
        await m.addColumn(timeEntries, timeEntries.taskId);
        await customStatement(
          'INSERT INTO tasks (job_id, title) '
          'SELECT DISTINCT job_id, task FROM time_entries',
        );
        await customStatement(
          'UPDATE time_entries SET task_id = ('
          'SELECT t.id FROM tasks t '
          'WHERE t.job_id = time_entries.job_id AND t.title = time_entries.task)',
        );
      }
      // v2 → v3: the free-text `task` string is now redundant with taskId.
      // Rebuild time_entries to drop it and add an optional per-entry `name`
      // (starts null — names are set explicitly, not inherited from the task).
      if (from < 3) {
        // `description` is nullable, so it needs no transformer — the rebuild
        // adds it as NULL and drops the old `task` column (gone from v3).
        await m.alterTable(
          TableMigration(timeEntries, newColumns: [timeEntries.description]),
        );
      }
      // v3 → v4: a client's default rate is now required (every job resolves to
      // at least the client default). Rebuild clients with the non-null column,
      // backfilling any pre-existing null rate to 0 so the copy can't violate.
      if (from < 4) {
        // TableMigration rebuilds `clients` to the CURRENT schema, which now
        // also carries contactName/phone (added in v5). Declare them here as
        // new nullable columns so this rebuild is self-consistent; the v4→v5
        // step below then only adds them for a DB coming straight from v4.
        await m.alterTable(
          TableMigration(
            clients,
            newColumns: [clients.contactName, clients.phone],
            columnTransformer: {
              clients.defaultRate: coalesce([
                clients.defaultRate,
                const Constant(0.0),
              ]),
            },
          ),
        );
      }
      // v4 → v5: invoice branding. Add the three branding tables and the two
      // new Client columns (person + phone, for the invoice TO/PHONE split).
      // Seeding the timedart default happens idempotently at startup via
      // ensureInvoiceDefaults(), so it covers fresh installs too.
      if (from < 5) {
        await m.createTable(themes);
        await m.createTable(profiles);
        await m.createTable(templates);
        // Only for a DB coming straight from v4: a from<4 upgrade already got
        // these columns via the v3→v4 clients rebuild above (current schema).
        if (from >= 4) {
          await m.addColumn(clients, clients.contactName);
          await m.addColumn(clients, clients.phone);
        }
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _open() => driftDatabase(
    name: 'time_tracker',
    native: const DriftNativeOptions(
      databaseDirectory:
          getApplicationSupportDirectory, // ~/.local/share, not ~/Documents
    ),
  );

  Future<int> ensureDefaultJob() async {
    final existing = await (select(
      jobs,
    )..where((j) => j.code.equals('GENERAL'))).getSingleOrNull();
    if (existing != null) return existing.id;
    final clientId = await _defaultClientId();
    return into(jobs).insert(
      JobsCompanion.insert(
        clientId: clientId,
        code: 'GENERAL',
        title: 'Uncategorised',
      ),
    );
  }

  Future<void> addEntry({
    required int jobId,
    required int taskId,
    String? description,
    required DateTime startedAt,
    required DateTime endedAt,
    required int seconds,
  }) => into(timeEntries).insert(
    TimeEntriesCompanion.insert(
      jobId: jobId,
      taskId: Value(taskId),
      description: Value(description),
      startedAt: startedAt,
      endedAt: endedAt,
      seconds: seconds,
    ),
  );

  Future<void> updateEntry({
    required int id,
    required int taskId,
    String? description,
    required DateTime startedAt,
    required DateTime endedAt,
    required int seconds,
  }) => (update(timeEntries)..where((t) => t.id.equals(id))).write(
    TimeEntriesCompanion(
      taskId: Value(taskId),
      description: Value(description),
      startedAt: Value(startedAt),
      endedAt: Value(endedAt),
      seconds: Value(seconds),
    ),
  );

  Future<void> deleteEntry(int id) =>
      (delete(timeEntries)..where((t) => t.id.equals(id))).go();

  Future<int> _defaultClientId() async {
    final c = await (select(clients)..limit(1)).getSingleOrNull();
    return c?.id ??
        await into(
          clients,
        ).insert(ClientsCompanion.insert(name: 'Personal', defaultRate: 0.0));
  }

  Future<int> addJob({
    required int clientId,
    required String code,
    required String title,
    double? rate,
  }) => into(jobs).insert(
    JobsCompanion.insert(
      clientId: clientId,
      code: code,
      title: title,
      rate: rate == null ? const Value.absent() : Value(rate),
    ),
  );

  Future<void> updateJob({
    required int id,
    required int clientId,
    required String code,
    required String title,
    double? rate,
  }) => (update(jobs)..where((j) => j.id.equals(id))).write(
    JobsCompanion(
      clientId: Value(clientId),
      code: Value(code),
      title: Value(title),
      rate: Value(rate),
    ),
  );

  Future<void> deleteJob(int id) =>
      (delete(jobs)..where((j) => j.id.equals(id))).go();

  Stream<List<Job>> watchJobs() =>
      (select(jobs)..orderBy([(j) => OrderingTerm.asc(j.title)])).watch();

  Stream<(Job, Client)?> watchJobWithClient(int id) {
    final q = select(jobs).join([
      innerJoin(clients, clients.id.equalsExp(jobs.clientId)),
    ])..where(jobs.id.equals(id));
    return q.watchSingleOrNull().map(
      (row) =>
          row == null ? null : (row.readTable(jobs), row.readTable(clients)),
    );
  }

  Stream<List<TimeEntry>> watchEntriesForJob(int jobId) =>
      (select(timeEntries)
            ..where((t) => t.jobId.equals(jobId))
            ..orderBy([(t) => OrderingTerm.desc(t.endedAt)]))
          .watch();

  // --- Tasks ---

  Stream<List<Task>> watchTasksForJob(int jobId) =>
      (select(tasks)
            ..where((t) => t.jobId.equals(jobId))
            ..orderBy([(t) => OrderingTerm.asc(t.title)]))
          .watch();

  Stream<List<TimeEntry>> watchEntriesForTask(int taskId) =>
      (select(timeEntries)
            ..where((t) => t.taskId.equals(taskId))
            ..orderBy([(t) => OrderingTerm.desc(t.endedAt)]))
          .watch();

  Future<int> addTask({
    required int jobId,
    required String title,
    double? rate,
  }) => into(tasks).insert(
    TasksCompanion.insert(
      jobId: jobId,
      title: title,
      rate: rate == null ? const Value.absent() : Value(rate),
    ),
  );

  Future<void> updateTask({
    required int id,
    required String title,
    double? rate,
  }) => (update(tasks)..where((t) => t.id.equals(id))).write(
    TasksCompanion(title: Value(title), rate: Value(rate)),
  );

  // Entries FK-reference the task (pragma on), so this throws if the task still
  // has time entries — matching how jobs/clients guard their children. The
  // caller surfaces that as "delete its entries first".
  Future<void> deleteTask(int id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  Stream<List<Client>> watchClients() =>
      (select(clients)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Stream<Job?> watchJob(int id) =>
      (select(jobs)..where((j) => j.id.equals(id))).watchSingleOrNull();

  Future<int> addClient({
    required String name,
    String? contactName,
    String? email,
    String? phone,
    required double defaultRate,
  }) => into(clients).insert(
    ClientsCompanion.insert(
      name: name,
      contactName: Value(contactName),
      email: email == null ? const Value.absent() : Value(email),
      phone: Value(phone),
      defaultRate: defaultRate,
    ),
  );

  Future<void> updateClient({
    required int id,
    required String name,
    String? contactName,
    String? email,
    String? phone,
    required double defaultRate,
  }) => (update(clients)..where((c) => c.id.equals(id))).write(
    ClientsCompanion(
      name: Value(name),
      contactName: Value(contactName),
      email: Value(email),
      phone: Value(phone),
      defaultRate: Value(defaultRate),
    ),
  );

  Future<void> deleteClient(int id) =>
      (delete(clients)..where((c) => c.id.equals(id))).go();

  // ── Invoice branding: seed + DAOs (PRD #79) ──────────────────────────────

  /// Seed a timedart Theme, an example Profile, and a default Template on first
  /// run. Idempotent — a no-op once any Template exists — so it's safe to call
  /// at every startup (mirrors [ensureDefaultJob]). Colours are the brand tokens
  /// as ARGB ints; the user edits them in the theme editor.
  Future<void> ensureInvoiceDefaults() async {
    final existing = await (select(templates)..limit(1)).getSingleOrNull();
    if (existing != null) return;
    final themeId = await into(themes).insert(
      ThemesCompanion.insert(
        name: 'timedart',
        colorBackground: 0xFF11140E, // brand dark surface
        colorSurface: 0xFF1C2113,
        colorPrimary: 0xFF69E228, // brand green
        colorText: 0xFFE8F5E0,
        colorAccent: 0xFF2E6C0F, // brand secondary
        isDefault: const Value(true),
      ),
    );
    final profileId = await into(profiles).insert(
      ProfilesCompanion.insert(
        name: 'Default',
        businessName: const Value('Your Business'),
        currency: const Value('USD'),
        isDefault: const Value(true),
      ),
    );
    await into(templates).insert(
      TemplatesCompanion.insert(
        name: 'timedart',
        themeId: themeId,
        profileId: profileId,
        isDefault: const Value(true),
      ),
    );
  }

  // Themes
  Stream<List<InvoiceTheme>> watchThemes() =>
      (select(themes)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  Future<InvoiceTheme> themeById(int id) =>
      (select(themes)..where((t) => t.id.equals(id))).getSingle();
  Future<int> insertTheme(ThemesCompanion t) => into(themes).insert(t);
  Future<void> updateThemeById(int id, ThemesCompanion t) =>
      (update(themes)..where((x) => x.id.equals(id))).write(t);
  // FK pragma is on, so this throws if a template still references the theme.
  Future<void> deleteTheme(int id) =>
      (delete(themes)..where((x) => x.id.equals(id))).go();
  Future<void> setDefaultTheme(int id) => transaction(() async {
    await update(themes).write(const ThemesCompanion(isDefault: Value(false)));
    await (update(themes)..where((x) => x.id.equals(id))).write(
      const ThemesCompanion(isDefault: Value(true)),
    );
  });

  // Profiles
  Stream<List<InvoiceProfile>> watchProfiles() =>
      (select(profiles)..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
  Future<InvoiceProfile> profileById(int id) =>
      (select(profiles)..where((p) => p.id.equals(id))).getSingle();
  Future<int> insertProfile(ProfilesCompanion p) => into(profiles).insert(p);
  Future<void> updateProfileById(int id, ProfilesCompanion p) =>
      (update(profiles)..where((x) => x.id.equals(id))).write(p);
  Future<void> deleteProfile(int id) =>
      (delete(profiles)..where((x) => x.id.equals(id))).go();
  Future<void> setDefaultProfile(int id) => transaction(() async {
    await update(
      profiles,
    ).write(const ProfilesCompanion(isDefault: Value(false)));
    await (update(profiles)..where((x) => x.id.equals(id))).write(
      const ProfilesCompanion(isDefault: Value(true)),
    );
  });

  // Templates
  Stream<List<InvoiceTemplate>> watchTemplates() =>
      (select(templates)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  Future<InvoiceTemplate?> defaultTemplate() =>
      (select(templates)..where((t) => t.isDefault.equals(true)))
          .getSingleOrNull();
  Future<int> insertTemplate(TemplatesCompanion t) =>
      into(templates).insert(t);
  Future<void> updateTemplateById(int id, TemplatesCompanion t) =>
      (update(templates)..where((x) => x.id.equals(id))).write(t);
  Future<void> deleteTemplate(int id) =>
      (delete(templates)..where((x) => x.id.equals(id))).go();
  Future<void> setDefaultTemplate(int id) => transaction(() async {
    await update(
      templates,
    ).write(const TemplatesCompanion(isDefault: Value(false)));
    await (update(templates)..where((x) => x.id.equals(id))).write(
      const TemplatesCompanion(isDefault: Value(true)),
    );
  });

  /// Build an on-demand invoice for a single job over [from]..[to] (inclusive):
  /// the job, its client, effective rate, and the itemised entries. Read-only —
  /// stores nothing.
  Future<JobInvoice> jobInvoice({
    required int jobId,
    required DateTime from,
    required DateTime to,
  }) async {
    final job = await (select(
      jobs,
    )..where((j) => j.id.equals(jobId))).getSingle();
    final client = await (select(
      clients,
    )..where((c) => c.id.equals(job.clientId))).getSingle();
    final entries =
        await (select(timeEntries)
              ..where(
                (t) =>
                    t.jobId.equals(jobId) &
                    t.startedAt.isBiggerOrEqualValue(from) &
                    t.startedAt.isSmallerOrEqualValue(to),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
            .get();
    final taskRows =
        await (select(tasks)..where((t) => t.jobId.equals(jobId))).get();
    return JobInvoice(
      job: job,
      client: client,
      rate: job.rate ?? client.defaultRate,
      entries: entries,
      taskTitles: {for (final t in taskRows) t.id: t.title},
    );
  }
}
