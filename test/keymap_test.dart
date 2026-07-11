import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedart/features/shell/keymap.dart';

// Synthesise a key-down (or key-repeat) for a logical key, optionally with a
// printable character (for the `?` binding). Physical key is arbitrary — the
// keymap matches on the logical key / character only.
KeyEvent _down(LogicalKeyboardKey key, {String? character}) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  character: character,
  timeStamp: Duration.zero,
);

KeyEvent _repeat(LogicalKeyboardKey key) => KeyRepeatEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: key,
  timeStamp: Duration.zero,
);

KeyIntent? _intent(KeyResolution r) => r is KeyMatch ? r.intent : null;

void main() {
  const listScopes = {KeyScope.list, KeyScope.panel, KeyScope.global};

  group('single-stroke matching', () {
    test('j / arrow-down → moveDown, repeats too', () {
      final d = ChordDetector();
      expect(
        _intent(Keymap.resolve(_down(LogicalKeyboardKey.keyJ), d, listScopes)),
        KeyIntent.moveDown,
      );
      expect(
        _intent(
          Keymap.resolve(_repeat(LogicalKeyboardKey.keyJ), d, listScopes),
        ),
        KeyIntent.moveDown,
      );
    });

    test('shift distinguishes a (addProject) from A (addClient)', () {
      final d = ChordDetector();
      expect(
        _intent(Keymap.resolve(_down(LogicalKeyboardKey.keyA), d, listScopes)),
        KeyIntent.addProject,
      );
      expect(
        _intent(
          Keymap.resolve(
            _down(LogicalKeyboardKey.keyA),
            d,
            listScopes,
            shiftDown: true,
          ),
        ),
        KeyIntent.addClient,
      );
    });

    test('? matched by character', () {
      final d = ChordDetector();
      expect(
        _intent(
          Keymap.resolve(
            _down(LogicalKeyboardKey.slash, character: '?'),
            d,
            {KeyScope.global},
            shiftDown: true,
          ),
        ),
        KeyIntent.showHelp,
      );
    });
  });

  group('gg / G chord', () {
    test('gg → top (first g pending, second g completes)', () {
      final d = ChordDetector();
      expect(
        Keymap.resolve(_down(LogicalKeyboardKey.keyG), d, listScopes),
        isA<KeyPending>(),
      );
      expect(d.isArmed, isTrue);
      expect(
        _intent(Keymap.resolve(_down(LogicalKeyboardKey.keyG), d, listScopes)),
        KeyIntent.top,
      );
      expect(d.isArmed, isFalse);
    });

    test('G (shift+g) → bottom directly, no chord', () {
      final d = ChordDetector();
      expect(
        _intent(
          Keymap.resolve(
            _down(LogicalKeyboardKey.keyG),
            d,
            listScopes,
            shiftDown: true,
          ),
        ),
        KeyIntent.bottom,
      );
      expect(d.isArmed, isFalse);
    });

    test('g then a non-g key abandons the chord and matches fresh', () {
      final d = ChordDetector();
      Keymap.resolve(_down(LogicalKeyboardKey.keyG), d, listScopes); // arm
      final r = Keymap.resolve(_down(LogicalKeyboardKey.keyJ), d, listScopes);
      expect(_intent(r), KeyIntent.moveDown);
      expect(d.isArmed, isFalse);
    });

    test('G after a pending g abandons then jumps bottom', () {
      final d = ChordDetector();
      Keymap.resolve(_down(LogicalKeyboardKey.keyG), d, listScopes); // arm
      final r = Keymap.resolve(
        _down(LogicalKeyboardKey.keyG),
        d,
        listScopes,
        shiftDown: true,
      );
      expect(_intent(r), KeyIntent.bottom);
      expect(d.isArmed, isFalse);
    });
  });

  group('Ctrl-w window chord', () {
    test('Ctrl-w then h → focusTracker', () {
      final d = ChordDetector();
      expect(
        Keymap.resolve(
          _down(LogicalKeyboardKey.keyW),
          d,
          {KeyScope.global},
          ctrlDown: true,
        ),
        isA<KeyPending>(),
      );
      expect(
        _intent(
          Keymap.resolve(_down(LogicalKeyboardKey.keyH), d, {KeyScope.global}),
        ),
        KeyIntent.focusTracker,
      );
    });

    test('Ctrl-w then l → focusPanel', () {
      final d = ChordDetector();
      Keymap.resolve(
        _down(LogicalKeyboardKey.keyW),
        d,
        {KeyScope.global},
        ctrlDown: true,
      );
      expect(
        _intent(
          Keymap.resolve(_down(LogicalKeyboardKey.keyL), d, {KeyScope.global}),
        ),
        KeyIntent.focusPanel,
      );
    });

    test('Ctrl-w then an unrelated key abandons the chord', () {
      final d = ChordDetector();
      Keymap.resolve(
        _down(LogicalKeyboardKey.keyW),
        d,
        {KeyScope.global},
        ctrlDown: true,
      );
      final r = Keymap.resolve(
        _down(LogicalKeyboardKey.keyX),
        d,
        {KeyScope.global},
      );
      expect(r, isA<KeyNone>());
      expect(d.isArmed, isFalse);
    });

    test('bare Ctrl-h → focusTracker (single, no chord)', () {
      final d = ChordDetector();
      expect(
        _intent(
          Keymap.resolve(
            _down(LogicalKeyboardKey.keyH),
            d,
            {KeyScope.global},
            ctrlDown: true,
          ),
        ),
        KeyIntent.focusTracker,
      );
    });
  });

  group('scope + typing filters', () {
    test('tracker intents are invisible to the panel scope set', () {
      final d = ChordDetector();
      // `f` (finishSession) is tracker-scope; not resolvable under panel scopes.
      expect(
        Keymap.resolve(_down(LogicalKeyboardKey.keyF), d, listScopes),
        isA<KeyNone>(),
      );
      // …but resolvable with the tracker scope.
      expect(
        _intent(
          Keymap.resolve(_down(LogicalKeyboardKey.keyF), d, {
            KeyScope.list,
            KeyScope.tracker,
            KeyScope.global,
          }),
        ),
        KeyIntent.finishSession,
      );
    });

    test('blockedWhileTyping bindings stand down while typing', () {
      final d = ChordDetector();
      // `/` (search) is blocked while typing; Ctrl-, (settings) is not.
      expect(
        Keymap.resolve(
          _down(LogicalKeyboardKey.slash),
          d,
          {KeyScope.global},
          typing: true,
        ),
        isA<KeyNone>(),
      );
      expect(
        _intent(
          Keymap.resolve(
            _down(LogicalKeyboardKey.comma),
            d,
            {KeyScope.global},
            ctrlDown: true,
            typing: true,
          ),
        ),
        KeyIntent.openSettings,
      );
    });
  });

  test('Ctrl-w chord silently fixed for settings scope', () {
    // The DoD: Ctrl-w h/l resolves in the settings pane (was a silent gap).
    final d = ChordDetector();
    const settingsScopes = {KeyScope.list, KeyScope.settings, KeyScope.global};
    Keymap.resolve(
      _down(LogicalKeyboardKey.keyW),
      d,
      settingsScopes,
      ctrlDown: true,
    );
    expect(
      _intent(
        Keymap.resolve(_down(LogicalKeyboardKey.keyH), d, settingsScopes),
      ),
      KeyIntent.focusTracker,
    );
  });
}
