import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/invoices/editor_session.dart';

void main() {
  group('EditorSession', () {
    test('starts clean, goes dirty on a change, clears on revert', () {
      var value = 'a';
      final session = EditorSession<String>(
        snapshot: () => value,
        persist: () async => true,
      );
      expect(session.isDirty, isFalse);

      value = 'b';
      session.recompute();
      expect(session.isDirty, isTrue);

      // Reverting to the original value clears dirty (real diff, not a flag).
      value = 'a';
      session.recompute();
      expect(session.isDirty, isFalse);
    });

    test('dirty listenable notifies on transitions', () {
      var value = 0;
      final session = EditorSession<int>(
        snapshot: () => value,
        persist: () async => true,
      );
      final seen = <bool>[];
      session.dirty.addListener(() => seen.add(session.isDirty));

      value = 1;
      session.recompute(); // false -> true
      value = 0;
      session.recompute(); // true -> false
      expect(seen, [true, false]);
    });

    test('save persists, rebaselines to the saved value, and clears dirty', () {
      var value = 'x';
      var persistCalls = 0;
      final session = EditorSession<String>(
        snapshot: () => value,
        persist: () async {
          persistCalls++;
          return true;
        },
      );
      value = 'y';
      session.recompute();
      expect(session.isDirty, isTrue);

      return session.save().then((ok) {
        expect(ok, isTrue);
        expect(persistCalls, 1);
        expect(session.isDirty, isFalse);
        expect(session.baseline, 'y'); // the just-saved value is the baseline
      });
    });

    test('failed save leaves dirty set and baseline untouched', () async {
      var value = 'x';
      final session = EditorSession<String>(
        snapshot: () => value,
        persist: () async => false,
      );
      value = 'y';
      session.recompute();

      final ok = await session.save();
      expect(ok, isFalse);
      expect(session.isDirty, isTrue);
      expect(session.baseline, 'x'); // unchanged
    });

    test('rebaseline adopts the current snapshot without persisting', () {
      var value = 1;
      final session = EditorSession<int>(
        snapshot: () => value,
        persist: () async => true,
      );
      // An async default-fill lands a new on-screen value.
      value = 2;
      session.rebaseline();
      expect(session.isDirty, isFalse);
      expect(session.baseline, 2);

      // Now the baseline is 2, so 2 is clean and 3 is dirty.
      session.recompute();
      expect(session.isDirty, isFalse);
      value = 3;
      session.recompute();
      expect(session.isDirty, isTrue);
    });
  });

  group('LogoValue', () {
    Uint8List bytes(List<int> b) => Uint8List.fromList(b);

    test('equal by content across distinct instances', () {
      expect(
        LogoValue(bytes([1, 2, 3]), 'image/png'),
        equals(LogoValue(bytes([1, 2, 3]), 'image/png')),
      );
    });

    test('differs on bytes or mime', () {
      expect(
        LogoValue(bytes([1, 2, 3]), 'image/png'),
        isNot(equals(LogoValue(bytes([1, 2, 4]), 'image/png'))),
      );
      expect(
        LogoValue(bytes([1, 2, 3]), 'image/png'),
        isNot(equals(LogoValue(bytes([1, 2, 3]), 'image/jpeg'))),
      );
    });

    test('null bytes handled and distinct from non-null', () {
      expect(const LogoValue(null, null), equals(const LogoValue(null, null)));
      expect(
        const LogoValue(null, null),
        isNot(equals(LogoValue(bytes([1]), 'image/png'))),
      );
    });

    test('equal content produces equal hashCodes', () {
      expect(
        LogoValue(bytes([9, 8, 7]), 'image/png').hashCode,
        LogoValue(bytes([9, 8, 7]), 'image/png').hashCode,
      );
    });
  });
}
