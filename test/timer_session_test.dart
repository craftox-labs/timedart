import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/tracker/timer_session.dart';

final _now = DateTime(2026, 1, 1, 9);
final _later = DateTime(2026, 1, 1, 10);

void main() {
  group('TimerSession', () {
    test('start binds the project and task and runs', () {
      final s = TimerSession();
      s.start(7, 3, now: _now);
      expect(s.isRunning, isTrue);
      expect(s.boundProjectId, 7);
      expect(s.boundTaskId, 3);
      expect(s.hasSession, isTrue);
    });

    test('tick accrues seconds', () {
      final s = TimerSession()..start(1, 1, now: _now);
      s.tick();
      s.tick();
      expect(s.elapsed, 2);
    });

    test('resume keeps the project/task bound at first start', () {
      final s = TimerSession()..start(7, 3, now: _now);
      s.tick();
      s.pause();
      s.start(99, 88, now: _later); // selection changed while paused
      expect(s.boundProjectId, 7); // still the original
      expect(s.boundTaskId, 3);
      expect(s.isRunning, isTrue);
    });

    test('start while running is a no-op', () {
      final s = TimerSession()..start(7, 3, now: _now);
      s.start(99, 88, now: _later);
      expect(s.boundProjectId, 7);
      expect(s.boundTaskId, 3);
    });

    test('finish returns the tracked session', () {
      final s = TimerSession()..start(7, 3, now: _now);
      s.tick();
      s.tick();
      s.tick();
      final r = s.finish(now: _later);
      expect(r, isNotNull);
      expect(r!.projectId, 7);
      expect(r.taskId, 3);
      expect(r.startedAt, _now);
      expect(r.endedAt, _later);
      expect(r.seconds, 3);
      expect(s.isRunning, isFalse);
    });

    test('finish does not clear — a failed write can be retried', () {
      final s = TimerSession()..start(7, 3, now: _now);
      s.tick();
      s.finish(now: _later);
      expect(s.elapsed, 1); // still there
      expect(s.hasSession, isTrue);
    });

    test('finish with no elapsed time records nothing', () {
      final s = TimerSession()..start(7, 3, now: _now);
      expect(s.finish(now: _later), isNull);
    });

    test('finish with no project or task bound records nothing', () {
      final s = TimerSession()..start(null, null, now: _now);
      s.tick();
      expect(s.finish(now: _later), isNull);
      final s2 = TimerSession()..start(7, null, now: _now);
      s2.tick();
      expect(s2.finish(now: _later), isNull);
    });

    test('reset clears everything', () {
      final s = TimerSession()..start(7, 3, now: _now);
      s.tick();
      s.reset();
      expect(s.elapsed, 0);
      expect(s.isRunning, isFalse);
      expect(s.boundProjectId, isNull);
      expect(s.boundTaskId, isNull);
      expect(s.hasSession, isFalse);
    });
  });
}
