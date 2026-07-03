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

class TimeEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get jobId => integer().references(Jobs, #id)();
  TextColumn get task => text()();
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

@DriftDatabase(tables: [Clients, Jobs, TimeEntries])
class AppDatabase extends _$AppDatabase {
  // _$AppDatabase is generated
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  // drift doesn't enforce foreign keys unless we turn the pragma on per
  // connection. With it on, deleting a job that has time entries (or a client
  // that has jobs) fails loudly instead of silently orphaning rows.
  @override
  MigrationStrategy get migration => MigrationStrategy(
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
    required String task,
    required DateTime startedAt,
    required DateTime endedAt,
    required int seconds,
  }) => into(timeEntries).insert(
    TimeEntriesCompanion.insert(
      jobId: jobId,
      task: task,
      startedAt: startedAt,
      endedAt: endedAt,
      seconds: seconds,
    ),
  );

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
