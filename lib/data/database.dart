import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart'; // generated — doesn't exist until you run build_runner

class Clients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get email => text().nullable()(); // nullable column
  TextColumn get address => text().nullable()();
  TextColumn get abn => text().nullable()();
  RealColumn get defaultRate => real().nullable()(); // $/hr fallback
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
  TextColumn get task => text()(); // DEAD once #57 lands — taskId is the source
  // Nullable only to allow the ALTER TABLE add during the v1→v2 migration; the
  // add/update bridge always sets it, so in practice every row has a task.
  IntColumn get taskId => integer().nullable().references(Tasks, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get seconds =>
      integer()(); // TRACKED time (excludes pauses) — see below
}

/// One itemised line of a [JobInvoice]: an entry with its hours and amount.
/// `amount` is null when the invoice has no effective rate (un-billable).
class InvoiceLine {
  final TimeEntry entry;
  final double hours;
  final double? amount;
  InvoiceLine({required this.entry, required this.hours, required this.amount});
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
  JobInvoice({
    required this.job,
    required this.client,
    required this.rate,
    required this.entries,
  });

  /// The itemised lines: hours and (rate-permitting) amount per entry.
  List<InvoiceLine> get lines => [
    for (final e in entries)
      InvoiceLine(
        entry: e,
        hours: e.seconds / 3600,
        amount: rate == null ? null : (e.seconds / 3600) * rate!,
      ),
  ];

  int get totalSeconds => entries.fold(0, (sum, e) => sum + e.seconds);
  double get totalHours => totalSeconds / 3600;
  double? get total => rate == null ? null : totalHours * rate!;
}

@DriftDatabase(tables: [Clients, Jobs, Tasks, TimeEntries])
class AppDatabase extends _$AppDatabase {
  // _$AppDatabase is generated
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 2;

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

  // Bridge until #56 passes a real taskId: resolve the free-text task to a Task
  // row (creating it once per job+title), so every entry links to a task while
  // callers still speak in strings.
  Future<int> _getOrCreateTask(int jobId, String title) async {
    final existing =
        await (select(tasks)
              ..where((t) => t.jobId.equals(jobId) & t.title.equals(title)))
            .getSingleOrNull();
    if (existing != null) return existing.id;
    return into(tasks).insert(TasksCompanion.insert(jobId: jobId, title: title));
  }

  Future<void> addEntry({
    required int jobId,
    required String task,
    required DateTime startedAt,
    required DateTime endedAt,
    required int seconds,
  }) async {
    final taskId = await _getOrCreateTask(jobId, task);
    await into(timeEntries).insert(
      TimeEntriesCompanion.insert(
        jobId: jobId,
        task: task,
        taskId: Value(taskId),
        startedAt: startedAt,
        endedAt: endedAt,
        seconds: seconds,
      ),
    );
  }

  Future<void> updateEntry({
    required int id,
    required String task,
    required DateTime startedAt,
    required DateTime endedAt,
    required int seconds,
  }) async {
    // Editing the label may re-point the entry to a different task under the
    // same job — keep task_id consistent with the string.
    final row =
        await (select(timeEntries)..where((t) => t.id.equals(id))).getSingle();
    final taskId = await _getOrCreateTask(row.jobId, task);
    await (update(timeEntries)..where((t) => t.id.equals(id))).write(
      TimeEntriesCompanion(
        task: Value(task),
        taskId: Value(taskId),
        startedAt: Value(startedAt),
        endedAt: Value(endedAt),
        seconds: Value(seconds),
      ),
    );
  }

  Future<void> deleteEntry(int id) =>
      (delete(timeEntries)..where((t) => t.id.equals(id))).go();

  Future<int> _defaultClientId() async {
    final c = await (select(clients)..limit(1)).getSingleOrNull();
    return c?.id ??
        await into(clients).insert(ClientsCompanion.insert(name: 'Personal'));
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

  // Entries FK-reference the task (pragma on), so remove them first. Matches
  // the editor's "task and its time entries will be removed" confirmation.
  Future<void> deleteTask(int id) => transaction(() async {
    await (delete(timeEntries)..where((t) => t.taskId.equals(id))).go();
    await (delete(tasks)..where((t) => t.id.equals(id))).go();
  });

  Stream<List<Client>> watchClients() =>
      (select(clients)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Stream<Job?> watchJob(int id) =>
      (select(jobs)..where((j) => j.id.equals(id))).watchSingleOrNull();

  Future<int> addClient({
    required String name,
    String? email,
    double? defaultRate,
  }) => into(clients).insert(
    ClientsCompanion.insert(
      name: name,
      email: email == null ? const Value.absent() : Value(email),
      defaultRate: defaultRate == null
          ? const Value.absent()
          : Value(defaultRate),
    ),
  );

  Future<void> updateClient({
    required int id,
    required String name,
    String? email,
    double? defaultRate,
  }) => (update(clients)..where((c) => c.id.equals(id))).write(
    ClientsCompanion(
      name: Value(name),
      email: Value(email),
      defaultRate: Value(defaultRate),
    ),
  );

  Future<void> deleteClient(int id) =>
      (delete(clients)..where((c) => c.id.equals(id))).go();

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
    return JobInvoice(
      job: job,
      client: client,
      rate: job.rate ?? client.defaultRate,
      entries: entries,
    );
  }
}
