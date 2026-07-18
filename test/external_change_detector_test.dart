import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/data/database.dart';
import 'package:timedart/data/external_change_detector.dart';

// Coverage for the live-refresh core (issue #274): the pure version-change
// decision, plus a light two-connection integration check that an external
// commit is observed as a data_version change.

void main() {
  group('ExternalChangeDetector (pure)', () {
    test('first observation sets the baseline and does not fire', () {
      final d = ExternalChangeDetector();
      expect(d.hasBaseline, isFalse);
      expect(d.observe(5), isFalse);
      expect(d.hasBaseline, isTrue);
      expect(d.lastSeen, 5);
    });

    test('repeated unchanged polls never fire', () {
      final d = ExternalChangeDetector()..observe(5);
      expect(d.observe(5), isFalse);
      expect(d.observe(5), isFalse);
    });

    test('fires exactly once per new value', () {
      final d = ExternalChangeDetector()..observe(1);
      expect(d.observe(2), isTrue); // external commit
      expect(d.observe(2), isFalse); // no further change
      expect(d.observe(3), isTrue); // next external commit
      expect(d.observe(3), isFalse);
    });

    test('reset re-baselines without firing', () {
      final d = ExternalChangeDetector()..observe(7);
      d.reset();
      expect(d.hasBaseline, isFalse);
      expect(d.observe(9), isFalse); // first read after reset = baseline
      expect(d.observe(10), isTrue);
    });
  });

  group('two-connection integration', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('timedart_watch_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('an external commit is seen as a data_version change', () async {
      final file = File('${tmp.path}/timedart.sqlite');
      final reader = AppDatabase(NativeDatabase(file));
      final writer = AppDatabase(NativeDatabase(file));
      addTearDown(reader.close);
      addTearDown(writer.close);

      final detector = ExternalChangeDetector();

      // Baseline from the reader connection.
      expect(detector.observe(await reader.dataVersion()), isFalse);

      // The reader's OWN write must not look like an external change.
      await reader.addClient(name: 'Self', defaultRate: 10);
      expect(
        detector.observe(await reader.dataVersion()),
        isFalse,
        reason: 'own writes leave data_version unchanged',
      );

      // A DIFFERENT connection commits → the reader observes a new version.
      await writer.addClient(name: 'External', defaultRate: 20);
      expect(
        detector.observe(await reader.dataVersion()),
        isTrue,
        reason: 'external commit bumps data_version',
      );

      // Polling again with no further external write does not fire.
      expect(detector.observe(await reader.dataVersion()), isFalse);
    });
  });
}
