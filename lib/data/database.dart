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

class JobWithRate {
  final Job job;
  final double? effectiveRate;
  JobWithRate(this.job, this.effectiveRate);
}

/// One aggregated line of an invoice: a job's total tracked time over a period,
/// at its effective rate. `rate == null` means the job is un-billable (no rate
/// set on the job or its client).
class InvoiceLine {
  final String jobCode;
  final String jobTitle;
  final int seconds;
  final double? rate;
  InvoiceLine({
    required this.jobCode,
    required this.jobTitle,
    required this.seconds,
    required this.rate,
  });
  double get hours => seconds / 3600;
  double? get amount => rate == null ? null : hours * rate!;
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

  Stream<List<TimeEntry>> watchEntries() => (select(
    timeEntries,
  )..orderBy([(t) => OrderingTerm.desc(t.endedAt)])).watch();

  Stream<List<TimeEntry>> watchEntriesForJob(int jobId) =>
      (select(timeEntries)
            ..where((t) => t.jobId.equals(jobId))
            ..orderBy([(t) => OrderingTerm.desc(t.endedAt)]))
          .watch();

  Stream<List<Client>> watchClients() =>
      (select(clients)..orderBy([(c) => OrderingTerm.asc(c.name)])).watch();

  Stream<List<JobWithRate>> watchJobsWithRate() {
    final q = select(jobs).join([
      innerJoin(clients, clients.id.equalsExp(jobs.clientId)),
    ])..orderBy([OrderingTerm.asc(jobs.title)]);
    return q.watch().map(
      (rows) => [
        for (final r in rows)
          JobWithRate(
            r.readTable(jobs),
            r.readTable(jobs).rate ?? r.readTable(clients).defaultRate,
          ),
      ],
    );
  }

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

  /// Aggregate a client's tracked time between [from] and [to] (inclusive),
  /// grouped by job, at each job's effective rate. Read-only — the invoice
  /// feature is generated on demand from this, storing nothing.
  Future<List<InvoiceLine>> invoiceLines({
    required int clientId,
    required DateTime from,
    required DateTime to,
  }) async {
    final rows =
        await (select(timeEntries).join([
          innerJoin(jobs, jobs.id.equalsExp(timeEntries.jobId)),
          innerJoin(clients, clients.id.equalsExp(jobs.clientId)),
        ])..where(
          jobs.clientId.equals(clientId) &
              timeEntries.startedAt.isBiggerOrEqualValue(from) &
              timeEntries.startedAt.isSmallerOrEqualValue(to),
        )).get();

    // Sum seconds per job (keeping each job's effective rate).
    final byJob = <int, ({Job job, double? rate, int seconds})>{};
    for (final r in rows) {
      final job = r.readTable(jobs);
      final client = r.readTable(clients);
      final entry = r.readTable(timeEntries);
      final prev = byJob[job.id];
      byJob[job.id] = (
        job: job,
        rate: job.rate ?? client.defaultRate,
        seconds: (prev?.seconds ?? 0) + entry.seconds,
      );
    }

    final lines = [
      for (final a in byJob.values)
        InvoiceLine(
          jobCode: a.job.code,
          jobTitle: a.job.title,
          seconds: a.seconds,
          rate: a.rate,
        ),
    ];
    lines.sort((x, y) => x.jobCode.compareTo(y.jobCode));
    return lines;
  }
}
