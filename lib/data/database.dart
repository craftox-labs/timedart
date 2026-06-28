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

@DriftDatabase(tables: [Clients, Jobs, TimeEntries])
class AppDatabase extends _$AppDatabase {
  // _$AppDatabase is generated
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _open() => driftDatabase(
    name: 'time_tracker',
    native: const DriftNativeOptions(
      databaseDirectory:
          getApplicationSupportDirectory, // ~/.local/share, not ~/Documents
    ),
  );
  // Seed one client + job so every entry has a valid jobId before the picker exists (Session 6).
  Future<int> ensureDefaultJob() async {
    final existing = await (select(jobs)..limit(1)).getSingleOrNull();
    if (existing != null) return existing.id;
    final clientId = await into(
      clients,
    ).insert(ClientsCompanion.insert(name: 'Personal'));
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

  Stream<List<TimeEntry>> watchEntries() => (select(
    timeEntries,
  )..orderBy([(t) => OrderingTerm.desc(t.endedAt)])).watch();
}
