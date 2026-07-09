import 'package:flutter_test/flutter_test.dart';
import 'package:time_tracker/features/invoices/bank_validators.dart';

// Real vectors as fixtures — the tests are the guard for the format rules, so a
// mistyped IBAN/routing/BSB/sort code is caught without anyone memorising them.
// Empty is always acceptable (the fields are optional, hints are non-blocking).

void main() {
  group('IBAN (MOD-97)', () {
    test('accepts valid IBANs (with and without spacing)', () {
      expect(ibanError('GB33BUKB20201555555555'), isNull);
      expect(ibanError('DE89 3704 0044 0532 0130 00'), isNull);
      expect(ibanError('FR14 2004 1010 0505 0001 3M02 606'), isNull);
    });

    test('rejects a bad checksum and malformed input', () {
      expect(ibanError('GB94BARC20201530093459'), isNotNull); // wrong check
      expect(ibanError('GB00BUKB20201555555555'), isNotNull);
      expect(ibanError('nonsense'), isNotNull);
    });

    test('empty is acceptable', () {
      expect(ibanError(''), isNull);
      expect(ibanError('   '), isNull);
    });
  });

  group('ABA routing (9-digit 3-7-1 checksum)', () {
    test('accepts valid routing numbers', () {
      expect(abaError('021000021'), isNull); // JPMorgan Chase (NY)
      expect(abaError('011401533'), isNull); // valid check
    });

    test('rejects bad length and bad checksum', () {
      expect(abaError('02100002'), isNotNull); // 8 digits
      expect(abaError('021000022'), isNotNull); // checksum off by one
    });

    test('empty is acceptable', () => expect(abaError(''), isNull));
  });

  group('BSB (6 digits)', () {
    test('accepts 6 digits with or without the hyphen', () {
      expect(bsbError('062-000'), isNull);
      expect(bsbError('083006'), isNull);
    });

    test('rejects the wrong length', () {
      expect(bsbError('06200'), isNotNull);
      expect(bsbError('0620000'), isNotNull);
    });

    test('empty is acceptable', () => expect(bsbError(''), isNull));
  });

  group('UK sort code (6 digits)', () {
    test('accepts 6 digits with or without hyphens', () {
      expect(sortCodeError('20-30-40'), isNull);
      expect(sortCodeError('203040'), isNull);
    });

    test('rejects the wrong length', () {
      expect(sortCodeError('2030'), isNotNull);
    });

    test('empty is acceptable', () => expect(sortCodeError(''), isNull));
  });
}
