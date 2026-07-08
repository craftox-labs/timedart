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

class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get clientId => integer().references(Clients, #id)(); // FK
  TextColumn get code => text().unique()(); // human project number
  TextColumn get title => text()();
  RealColumn get rate => real().nullable()(); // overrides client default
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// A unit of work under a project. Owns many time-entry segments, so multiple
// sessions accumulate against one task. `rate` overrides the project's rate (used
// by a later invoicing pass); status leaves room for open/done/archived.
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer().references(Projects, #id)();
  TextColumn get title => text()();
  RealColumn get rate => real().nullable()(); // overrides project.rate
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class TimeEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get projectId => integer().references(Projects, #id)();
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

/// An invoice *template*: colour scheme + font — the visual style a profile is
/// rendered with. Named "template" (not "theme") to leave "theme" free for
/// future app-wide UI theming. The logo lives on the [Profiles] (business
/// identity), not here — a template is pure look, reusable across profiles.
/// Exactly one row is the default (see [AppDatabase.setDefaultTemplate]).
@DataClassName('InvoiceTemplate')
class Templates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get colorBackground => integer()();
  IntColumn get colorSurface => integer()();
  IntColumn get colorPrimary => integer()();
  IntColumn get colorText => integer()();
  IntColumn get colorAccent => integer()();
  TextColumn get fontFamily => text().withDefault(const Constant('Mona'))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
}

/// The *details* of an invoice: sender identity + logo + payment + currency +
/// optional tax. Tax is null-by-default and international-neutral (a [taxLabel]
/// + percent [taxRate], or nothing). The logo lives here (business identity),
/// set once with the other business details, so it survives a change of visual
/// [Templates]. Reusable across templates; one row is the default.
@DataClassName('InvoiceProfile')
class Profiles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)(); // internal label
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
  TextColumn get taxLabel => text().nullable()(); // e.g. GST, VAT; null = no tax
  RealColumn get taxRate => real().nullable()(); // percent, e.g. 10.0
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  // The template (visual style) this profile is rendered with. Null → the
  // default template. Replaces the old Theme+Profile pairing table.
  IntColumn get templateId =>
      integer().nullable().references(Templates, #id)();
}

/// One itemised line of a [ProjectInvoice]: an entry with its hours and amount.
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

/// An invoice for a single project over a period: the project, its client, the
/// effective rate (`null` = un-billable), and the itemised time entries.
///
/// Owns all invoice arithmetic — hours, per-line amounts, totals — so the
/// preview and the PDF read numbers rather than recomputing them.
class ProjectInvoice {
  final Project project;
  final Client client;
  final double? rate; // effective: project.rate ?? client.defaultRate
  final List<TimeEntry> entries;
  final Map<int, String> taskTitles; // taskId → title, for line labels
  ProjectInvoice({
    required this.project,
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
  tables: [Clients, Projects, Tasks, TimeEntries, Templates, Profiles],
)
class AppDatabase extends _$AppDatabase {
  // _$AppDatabase is generated
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 8;

  // drift doesn't enforce foreign keys unless we turn the pragma on per
  // connection. With it on, deleting a project that has time entries (or a
  // client that has projects) fails loudly instead of silently orphaning rows.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
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
        // tasks is created with the current schema (project_id); time_entries
        // at v1 still uses job_id, so the SELECT reads job_id from the old rows.
        await customStatement(
          'INSERT INTO tasks (project_id, title) '
          'SELECT DISTINCT job_id, task FROM time_entries',
        );
        await customStatement(
          'UPDATE time_entries SET task_id = ('
          'SELECT t.id FROM tasks t '
          'WHERE t.project_id = time_entries.job_id AND t.title = time_entries.task)',
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
            newColumns: [timeEntries.description],
            columnTransformer: {
              timeEntries.projectId: const CustomExpression('job_id'),
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
      // Every pre-v7 database has a `jobs` table, so the table rename is
      // unconditional. Column renames are guarded:
      //   - tasks.job_id: from<2 creates tasks fresh (project_id already); from≥2
      //     databases have job_id from a prior migration run.
      //   - time_entries.job_id: from<3 TableMigration already maps job_id→project_id
      //     via columnTransformer; from≥3 databases still have job_id.
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
      // v7 → v8: the logo moves from the template (visual style) to the profile
      // (business identity). Add logo/logo_mime to profiles, backfill each from
      // its resolved template (its templateId, else the default template), then
      // drop logo/logo_mime from templates via a rebuild to the current shape.
      // Guarded to from>=5: a from<5 upgrade built the current tables directly
      // above (logo already on profiles, absent from templates), so it must not
      // re-run these column ops. from∈{5,6,7} all reach here with the logo still
      // on templates (v5's themes had it; the v5→v6 rename kept it).
      if (from >= 5) {
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
        await m.alterTable(TableMigration(templates));
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

  Future<int> ensureDefaultProject() async {
    final existing = await (select(
      projects,
    )..where((p) => p.code.equals('GENERAL'))).getSingleOrNull();
    if (existing != null) return existing.id;
    final clientId = await _defaultClientId();
    return into(projects).insert(
      ProjectsCompanion.insert(
        clientId: clientId,
        code: 'GENERAL',
        title: 'Uncategorised',
      ),
    );
  }

  Future<void> addEntry({
    required int projectId,
    required int taskId,
    String? description,
    required DateTime startedAt,
    required DateTime endedAt,
    required int seconds,
  }) => into(timeEntries).insert(
    TimeEntriesCompanion.insert(
      projectId: projectId,
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

  Future<int> addProject({
    required int clientId,
    required String code,
    required String title,
    double? rate,
  }) => into(projects).insert(
    ProjectsCompanion.insert(
      clientId: clientId,
      code: code,
      title: title,
      rate: rate == null ? const Value.absent() : Value(rate),
    ),
  );

  Future<void> updateProject({
    required int id,
    required int clientId,
    required String code,
    required String title,
    double? rate,
  }) => (update(projects)..where((p) => p.id.equals(id))).write(
    ProjectsCompanion(
      clientId: Value(clientId),
      code: Value(code),
      title: Value(title),
      rate: Value(rate),
    ),
  );

  Future<void> deleteProject(int id) =>
      (delete(projects)..where((p) => p.id.equals(id))).go();

  Stream<List<Project>> watchProjects() =>
      (select(projects)..orderBy([(p) => OrderingTerm.asc(p.title)])).watch();

  Stream<(Project, Client)?> watchProjectWithClient(int id) {
    final q = select(projects).join([
      innerJoin(clients, clients.id.equalsExp(projects.clientId)),
    ])..where(projects.id.equals(id));
    return q.watchSingleOrNull().map(
      (row) =>
          row == null
              ? null
              : (row.readTable(projects), row.readTable(clients)),
    );
  }

  Stream<List<TimeEntry>> watchEntriesForProject(int projectId) =>
      (select(timeEntries)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.desc(t.endedAt)]))
          .watch();

  // --- Tasks ---

  Stream<List<Task>> watchTasksForProject(int projectId) =>
      (select(tasks)
            ..where((t) => t.projectId.equals(projectId))
            ..orderBy([(t) => OrderingTerm.asc(t.title)]))
          .watch();

  Stream<List<TimeEntry>> watchEntriesForTask(int taskId) =>
      (select(timeEntries)
            ..where((t) => t.taskId.equals(taskId))
            ..orderBy([(t) => OrderingTerm.desc(t.endedAt)]))
          .watch();

  Future<int> addTask({
    required int projectId,
    required String title,
    double? rate,
  }) => into(tasks).insert(
    TasksCompanion.insert(
      projectId: projectId,
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
  // has time entries — matching how projects/clients guard their children. The
  // caller surfaces that as "delete its entries first".
  Future<void> deleteTask(int id) =>
      (delete(tasks)..where((t) => t.id.equals(id))).go();

  Stream<List<Client>> watchClients() =>
      (select(clients)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Stream<Project?> watchProject(int id) =>
      (select(projects)..where((p) => p.id.equals(id))).watchSingleOrNull();

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

  /// Seed a timedart Template (visual style) and an example Profile pointed at
  /// it on first run. Idempotent — a no-op once any Template exists — so it's
  /// safe to call at every startup (mirrors [ensureDefaultProject]). Colours are
  /// the brand tokens as ARGB ints; the user edits them in the template editor.
  Future<void> ensureInvoiceDefaults() async {
    final existing = await (select(templates)..limit(1)).getSingleOrNull();
    if (existing != null) return;
    final templateId = await into(templates).insert(
      TemplatesCompanion.insert(
        name: 'timedart',
        colorBackground: 0xFF11140E, // brand dark surface
        colorSurface: 0xFF23241F, // neutral dark card (was green-tinted)
        colorPrimary: 0xFF69E228, // brand green
        colorText: 0xFFE8F5E0,
        colorAccent: 0xFF2E6C0F, // brand secondary
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
      (select(templates)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
  Future<InvoiceTemplate> templateById(int id) =>
      (select(templates)..where((t) => t.id.equals(id))).getSingle();
  Future<InvoiceTemplate?> defaultTemplate() =>
      (select(templates)..where((t) => t.isDefault.equals(true)))
          .getSingleOrNull();
  Future<int> insertTemplate(TemplatesCompanion t) =>
      into(templates).insert(t);
  Future<void> updateTemplateById(int id, TemplatesCompanion t) =>
      (update(templates)..where((x) => x.id.equals(id))).write(t);
  // FK pragma is on, so this throws if a profile still references the template.
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

  // Profiles (business identity + payment; each points at a Template)
  Stream<List<InvoiceProfile>> watchProfiles() =>
      (select(profiles)..orderBy([(p) => OrderingTerm.asc(p.name)])).watch();
  Future<InvoiceProfile> profileById(int id) =>
      (select(profiles)..where((p) => p.id.equals(id))).getSingle();
  Future<InvoiceProfile?> defaultProfile() =>
      (select(profiles)..where((p) => p.isDefault.equals(true)))
          .getSingleOrNull();
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

  // Row getters for assembling an InvoiceDocument (the pure builder lives in
  // features/invoices — the data layer only hands back rows).
  Future<Project> getProject(int id) =>
      (select(projects)..where((p) => p.id.equals(id))).getSingle();
  Future<Client> getClient(int id) =>
      (select(clients)..where((c) => c.id.equals(id))).getSingle();
  Future<List<Task>> tasksForProject(int projectId) =>
      (select(tasks)..where((t) => t.projectId.equals(projectId))).get();
  Future<List<TimeEntry>> entriesForProjectInPeriod(
    int projectId,
    DateTime from,
    DateTime to,
  ) =>
      (select(timeEntries)
            ..where(
              (t) =>
                  t.projectId.equals(projectId) &
                  t.startedAt.isBiggerOrEqualValue(from) &
                  t.startedAt.isSmallerOrEqualValue(to),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
          .get();

  /// Build an on-demand invoice for a single project over [from]..[to]
  /// (inclusive): the project, its client, effective rate, and the itemised
  /// entries. Read-only — stores nothing.
  Future<ProjectInvoice> projectInvoice({
    required int projectId,
    required DateTime from,
    required DateTime to,
  }) async {
    final project = await (select(
      projects,
    )..where((p) => p.id.equals(projectId))).getSingle();
    final client = await (select(
      clients,
    )..where((c) => c.id.equals(project.clientId))).getSingle();
    final entries =
        await (select(timeEntries)
              ..where(
                (t) =>
                    t.projectId.equals(projectId) &
                    t.startedAt.isBiggerOrEqualValue(from) &
                    t.startedAt.isSmallerOrEqualValue(to),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.startedAt)]))
            .get();
    final taskRows =
        await (select(tasks)..where((t) => t.projectId.equals(projectId))).get();
    return ProjectInvoice(
      project: project,
      client: client,
      rate: project.rate ?? client.defaultRate,
      entries: entries,
      taskTitles: {for (final t in taskRows) t.id: t.title},
    );
  }
}
