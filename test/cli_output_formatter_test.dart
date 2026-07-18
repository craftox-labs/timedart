import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/cli/output_formatter.dart';
import 'package:timedart/cli/timer_status_result.dart';

// Coverage for the pure output formatter (issue #271): deterministic human +
// JSON shapes for both "timer running" and "no timer".

void main() {
  final running = TimerStatusResult(
    hasTimer: true,
    running: true,
    elapsedSeconds: 3600 + 23 * 60 + 45, // 1h 23m 45s
    projectId: 'p1',
    projectCode: 'ACME',
    projectTitle: 'Acme Website',
    taskId: 't1',
    taskTitle: 'Design',
    description: 'hero section',
    startedAt: DateTime.utc(2026, 7, 18, 9, 30),
  );

  group('formatElapsed', () {
    test('sub-minute shows seconds only', () => expect(formatElapsed(45), '45s'));
    test('minutes and seconds', () => expect(formatElapsed(125), '2m 5s'));
    test('hours minutes seconds', () => expect(formatElapsed(5025), '1h 23m 45s'));
    test('negative clamps to zero', () => expect(formatElapsed(-5), '0s'));
  });

  group('human output', () {
    test('no timer', () {
      expect(
        formatTimerStatusHuman(TimerStatusResult.idle),
        'No timer running.',
      );
    });

    test('running timer includes project, task, elapsed, note', () {
      final text = formatTimerStatusHuman(running);
      expect(text, contains('Running'));
      expect(text, contains('ACME Acme Website'));
      expect(text, contains('Design'));
      expect(text, contains('hero section'));
      expect(text, contains('Elapsed: 1h 23m 45s'));
      expect(text, contains('Started: 2026-07-18T09:30:00.000Z'));
    });

    test('paused timer reads Paused', () {
      final text = formatTimerStatusHuman(
        TimerStatusResult(hasTimer: true, running: false, elapsedSeconds: 60),
      );
      expect(text, startsWith('Paused'));
      expect(text, contains('Elapsed: 1m 0s'));
    });
  });

  group('JSON output', () {
    test('idle shape is stable and fully-keyed', () {
      final json = jsonDecode(formatTimerStatusJson(TimerStatusResult.idle));
      expect(json, {
        'status': 'idle',
        'running': false,
        'elapsedSeconds': 0,
        'project': null,
        'task': null,
        'description': null,
        'startedAt': null,
      });
    });

    test('running shape carries nested project/task', () {
      final json =
          jsonDecode(formatTimerStatusJson(running)) as Map<String, Object?>;
      expect(json['status'], 'running');
      expect(json['running'], true);
      expect(json['elapsedSeconds'], 5025);
      expect(json['project'], {
        'id': 'p1',
        'code': 'ACME',
        'title': 'Acme Website',
      });
      expect(json['task'], {'id': 't1', 'title': 'Design'});
      expect(json['description'], 'hero section');
      expect(json['startedAt'], '2026-07-18T09:30:00.000Z');
    });

    test('formatTimerStatus routes on the json flag', () {
      expect(
        formatTimerStatus(TimerStatusResult.idle, json: false),
        'No timer running.',
      );
      expect(
        formatTimerStatus(TimerStatusResult.idle, json: true),
        contains('"status": "idle"'),
      );
    });
  });
}
