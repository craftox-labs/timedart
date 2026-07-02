import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/features/tracker/timer_session.dart';

final _now = DateTime(2026, 1, 1, 9);
final _later = DateTime(2026, 1, 1, 10);

void main() {
  group('TimerSession', () {
    test('start binds the job and runs', () {
      final s = TimerSession();
      s.start(7, now: _now);
      expect(s.isRunning, isTrue);
      expect(s.boundJobId, 7);
      expect(s.hasSession, isTrue);
    });

    test('tick accrues seconds', () {
      final s = TimerSession()..start(1, now: _now);
      s.tick();
      s.tick();
      expect(s.elapsed, 2);
    });

    test('resume keeps the job bound at first start', () {
      final s = TimerSession()..start(7, now: _now);
      s.tick();
      s.pause();
      s.start(99, now: _later); // selection changed while paused
      expect(s.boundJobId, 7); // still the original job
      expect(s.isRunning, isTrue);
    });

    test('start while running is a no-op', () {
      final s = TimerSession()..start(7, now: _now);
      s.start(99, now: _later);
      expect(s.boundJobId, 7);
    });

    test('finish returns the tracked session', () {
      final s = TimerSession()..start(7, now: _now);
      s.tick();
      s.tick();
      s.tick();
      final r = s.finish(now: _later);
      expect(r, isNotNull);
      expect(r!.jobId, 7);
      expect(r.startedAt, _now);
      expect(r.endedAt, _later);
      expect(r.seconds, 3);
      expect(s.isRunning, isFalse);
    });

    test('finish does not clear — a failed write can be retried', () {
      final s = TimerSession()..start(7, now: _now);
      s.tick();
      s.finish(now: _later);
      expect(s.elapsed, 1); // still there
      expect(s.hasSession, isTrue);
    });

    test('finish with no elapsed time records nothing', () {
      final s = TimerSession()..start(7, now: _now);
      expect(s.finish(now: _later), isNull);
    });

    test('finish with no job bound records nothing', () {
      final s = TimerSession()..start(null, now: _now);
      s.tick();
      expect(s.finish(now: _later), isNull);
    });

    test('reset clears everything', () {
      final s = TimerSession()..start(7, now: _now);
      s.tick();
      s.reset();
      expect(s.elapsed, 0);
      expect(s.isRunning, isFalse);
      expect(s.boundJobId, isNull);
      expect(s.hasSession, isFalse);
    });
  });
}
