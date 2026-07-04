import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/tracker/task_rows.dart';

Task _task(int id, String title) => Task(
  id: id,
  jobId: 1,
  title: title,
  rate: null,
  status: 'active',
  createdAt: DateTime(2026),
);

TimeEntry _entry(int id, int taskId, int seconds) => TimeEntry(
  id: id,
  jobId: 1,
  task: 'x',
  taskId: taskId,
  startedAt: DateTime(2026),
  endedAt: DateTime(2026),
  seconds: seconds,
);

void main() {
  final tasks = [_task(1, 'Alpha'), _task(2, 'Beta')];
  final entries = [
    _entry(10, 1, 100),
    _entry(11, 1, 200),
    _entry(12, 2, 50),
  ];

  test('collapsed tasks contribute only their headers', () {
    final rows = buildTaskRows(
      tasks: tasks,
      entries: entries,
      isExpanded: (_) => false,
    );
    expect(rows.length, 2);
    expect(rows.every((r) => r is TaskHeaderRow), isTrue);
  });

  test('an expanded task is followed by its entry rows', () {
    final rows = buildTaskRows(
      tasks: tasks,
      entries: entries,
      isExpanded: (id) => id == 1,
    );
    // header(1) + 2 entries + header(2)
    expect(rows.length, 4);
    expect(rows[0], isA<TaskHeaderRow>());
    expect(rows[1], isA<TaskEntryRow>());
    expect(rows[2], isA<TaskEntryRow>());
    expect(rows[3], isA<TaskHeaderRow>());
    expect((rows[3] as TaskHeaderRow).task.id, 2);
  });

  test('header rolls up total seconds and entry count regardless of expansion', () {
    final rows = buildTaskRows(
      tasks: tasks,
      entries: entries,
      isExpanded: (_) => false,
    );
    final alpha = rows[0] as TaskHeaderRow;
    expect(alpha.totalSeconds, 300);
    expect(alpha.entryCount, 2);
    final beta = rows[1] as TaskHeaderRow;
    expect(beta.totalSeconds, 50);
    expect(beta.entryCount, 1);
  });

  test('a task with no entries still shows, empty', () {
    final rows = buildTaskRows(
      tasks: [_task(3, 'Gamma')],
      entries: const [],
      isExpanded: (_) => true,
    );
    expect(rows.length, 1);
    expect((rows.single as TaskHeaderRow).entryCount, 0);
  });
}
