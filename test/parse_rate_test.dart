import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/util/parse_rate.dart';

void main() {
  group('parseRate', () {
    test('empty is valid and means no rate', () {
      final r = parseRate('');
      expect(r.value, isNull);
      expect(r.error, isNull);
    });

    test('whitespace-only is treated as empty', () {
      final r = parseRate('   ');
      expect(r.value, isNull);
      expect(r.error, isNull);
    });

    test('a number parses', () {
      final r = parseRate('42.5');
      expect(r.value, 42.5);
      expect(r.error, isNull);
    });

    test('surrounding whitespace is trimmed', () {
      expect(parseRate('  90 ').value, 90);
    });

    test('non-numeric is an error, not a silent null', () {
      final r = parseRate('5o');
      expect(r.value, isNull);
      expect(r.error, isNotNull);
    });
  });
}
