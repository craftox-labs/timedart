import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/features/tracker/task_rows.dart';

Task _task(String id, String title) => Task(
  id: id,
  projectId: 'p1',
  title: title,
  rate: null,
  status: 'active',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

TimeEntry _entry(String id, String taskId, int seconds) => TimeEntry(
  id: id,
  projectId: 'p1',
  taskId: taskId,
  startedAt: DateTime(2026),
  endedAt: DateTime(2026),
  seconds: seconds,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  final tasks = [_task('t1', 'Alpha'), _task('t2', 'Beta')];
  final entries = [
    _entry('e1', 't1', 100),
    _entry('e2', 't1', 200),
    _entry('e3', 't2', 50),
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
      isExpanded: (id) => id == 't1',
    );
    // header(t1) + 2 entries + header(t2)
    expect(rows.length, 4);
    expect(rows[0], isA<TaskHeaderRow>());
    expect(rows[1], isA<TaskEntryRow>());
    expect(rows[2], isA<TaskEntryRow>());
    expect(rows[3], isA<TaskHeaderRow>());
    expect((rows[3] as TaskHeaderRow).task.id, 't2');
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
      tasks: [_task('t3', 'Gamma')],
      entries: const [],
      isExpanded: (_) => true,
    );
    expect(rows.length, 1);
    expect((rows.single as TaskHeaderRow).entryCount, 0);
  });
}
