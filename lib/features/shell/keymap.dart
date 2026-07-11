import 'package:flutter/services.dart';

/// The single source of the app's keyboard model: which keys mean what
/// ([KeyIntent]), where each binding is live ([KeyScope]), and the human labels
/// the help dialog renders. The four raw-`onKeyEvent` handlers (shell, side
/// panel, settings panel, tracker) each ask the [Keymap] to resolve an event to
/// an intent, then map that intent to their own local action; the help dialog
/// iterates the registry, so it can't drift from the handlers.
///
/// Flutter's `Shortcuts`/`Actions` can't express the vim multi-key sequences
/// (`gg`, `G`, `Ctrl-w` then `h`/`l`), so this is a lightweight custom registry
/// that fits the existing raw-key architecture. Chord state is owned by a
/// [ChordDetector] instance per handler (one implementation, no more hand-rolled
/// `_pendingG` / `_pendingCtrlW` copies).

/// Where a binding is active. A handler resolves against its own scope(s); most
/// list panes take `list` + their own scope + `global`.
enum KeyScope {
  /// App-wide: pane switching, help, search, settings, the timer toggle.
  global,

  /// Shared cursor navigation of a flat list (side panel, tracker, settings).
  list,

  /// The client/project side panel only.
  panel,

  /// The tracker (task/entry list) only.
  tracker,

  /// The settings panel only.
  settings,

  /// Documentation-only: the entity/branding edit modals bind these through
  /// their own `CallbackShortcuts`, not this keymap. Present so the help dialog
  /// documents them from one registry; never passed to [Keymap.resolve].
  editor,
}

/// What a key means, decoupled from the physical keys. A pane maps an intent to
/// its local action; the same intent (e.g. [collapseOrParent]) drives different
/// code in each pane.
enum KeyIntent {
  // global
  showHelp,
  search,
  openTracker,
  toggleTimer,
  openSettings,
  focusTracker,
  focusPanel,
  switchPane,
  // list (shared cursor nav)
  moveDown,
  moveUp,
  top,
  bottom,
  openOrExpand,
  collapseOrParent,
  activate,
  editItem,
  // panel
  addProject,
  addClient,
  nextMatch,
  prevMatch,
  // tracker
  addTask,
  addEntry,
  finishSession,
  focusDescription,
  // settings
  addEntity,
  back,
}

/// A single physical trigger: a logical key plus required modifier state, or —
/// for `?`, whose shifted `/` reports no slash logical key — a printable
/// [character] match. [shift] is `null` when shift is a don't-care (movement),
/// and `true`/`false` where it distinguishes bindings (`g` vs `G`, `a` vs `A`).
class KeyStroke {
  const KeyStroke(this.key, {this.ctrl = false, this.shift, this.character});
  final LogicalKeyboardKey? key;
  final bool ctrl;
  final bool? shift;
  final String? character;

  bool matches(KeyEvent event, bool ctrlDown, bool shiftDown) {
    if (character != null) return !ctrlDown && event.character == character;
    if (event.logicalKey != key) return false;
    if (ctrl != ctrlDown) return false;
    if (shift != null && shift != shiftDown) return false;
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is KeyStroke &&
      other.key == key &&
      other.ctrl == ctrl &&
      other.shift == shift &&
      other.character == character;

  @override
  int get hashCode => Object.hash(key, ctrl, shift, character);
}

/// One entry in the registry. Either a set of single-press [strokes]
/// (alternatives that fire [intent]), or — when [prefix] is set — a two-press
/// chord: [prefix] arms, then any of [strokes] completes.
///
/// [caps]/[description]/[helpGroup] are the help metadata; set [showInHelp]
/// false on a binding whose help row is represented by a sibling (e.g. `moveUp`
/// is shown alongside `moveDown`).
class Binding {
  const Binding({
    required this.intent,
    required this.scope,
    this.strokes = const [],
    this.prefix,
    this.caps = const [],
    this.description = '',
    this.helpGroup = '',
    this.showInHelp = false,
    this.blockedWhileTyping = false,
  });

  final KeyIntent intent;
  final KeyScope scope;
  final List<KeyStroke> strokes;
  final KeyStroke? prefix;
  final List<String> caps;
  final String description;
  final String helpGroup;
  final bool showInHelp;
  // Stands down while a text field is focused, so a printable global (`?`, `/`,
  // Space, `t`, Tab) types/traverses normally instead of firing.
  final bool blockedWhileTyping;

  bool get isChord => prefix != null;
}

/// The outcome of resolving a key event against the keymap.
sealed class KeyResolution {
  const KeyResolution();
}

/// The event completed (or singly matched) a binding for [intent].
class KeyMatch extends KeyResolution {
  const KeyMatch(this.intent);
  final KeyIntent intent;
}

/// The event armed a chord prefix and was consumed; await the completion.
class KeyPending extends KeyResolution {
  const KeyPending();
}

/// Nothing matched — the handler should let the event bubble.
class KeyNone extends KeyResolution {
  const KeyNone();
}

// Some shared strokes used across scopes.
const _left = [
  KeyStroke(LogicalKeyboardKey.keyH),
  KeyStroke(LogicalKeyboardKey.arrowLeft),
];
const _right = [
  KeyStroke(LogicalKeyboardKey.keyL),
  KeyStroke(LogicalKeyboardKey.arrowRight),
];
const _ctrlLeft = [
  KeyStroke(LogicalKeyboardKey.keyH, ctrl: true),
  KeyStroke(LogicalKeyboardKey.arrowLeft, ctrl: true),
];
const _ctrlRight = [
  KeyStroke(LogicalKeyboardKey.keyL, ctrl: true),
  KeyStroke(LogicalKeyboardKey.arrowRight, ctrl: true),
];
const _ctrlW = KeyStroke(LogicalKeyboardKey.keyW, ctrl: true);

/// The registry. Ordered so the help dialog renders groups top-to-bottom.
const List<Binding> _bindings = [
  // --- Navigation (shared list scope) ---
  Binding(
    intent: KeyIntent.moveDown,
    scope: KeyScope.list,
    strokes: [
      KeyStroke(LogicalKeyboardKey.keyJ),
      KeyStroke(LogicalKeyboardKey.arrowDown),
    ],
    caps: ['J', 'K', '↓', '↑'],
    description: 'Move',
    helpGroup: 'Navigation',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.moveUp,
    scope: KeyScope.list,
    strokes: [
      KeyStroke(LogicalKeyboardKey.keyK),
      KeyStroke(LogicalKeyboardKey.arrowUp),
    ],
  ),
  Binding(
    intent: KeyIntent.top,
    scope: KeyScope.list,
    prefix: KeyStroke(LogicalKeyboardKey.keyG, shift: false),
    strokes: [KeyStroke(LogicalKeyboardKey.keyG, shift: false)],
    caps: ['g', 'g', 'G'],
    description: 'Top / bottom',
    helpGroup: 'Navigation',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.bottom,
    scope: KeyScope.list,
    strokes: [KeyStroke(LogicalKeyboardKey.keyG, shift: true)],
  ),
  Binding(
    intent: KeyIntent.openOrExpand,
    scope: KeyScope.list,
    strokes: _right,
    caps: ['L', '→'],
    description: 'Open / expand',
    helpGroup: 'Navigation',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.collapseOrParent,
    scope: KeyScope.list,
    strokes: _left,
    caps: ['H', '←'],
    description: 'Collapse / parent',
    helpGroup: 'Navigation',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.activate,
    scope: KeyScope.list,
    strokes: [
      KeyStroke(LogicalKeyboardKey.enter),
      KeyStroke(LogicalKeyboardKey.numpadEnter),
    ],
    caps: ['Enter'],
    description: 'Select / activate',
    helpGroup: 'Navigation',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.editItem,
    scope: KeyScope.list,
    strokes: [KeyStroke(LogicalKeyboardKey.keyE)],
    caps: ['e'],
    description: 'Edit focused item',
    helpGroup: 'Navigation',
    showInHelp: true,
  ),
  // Esc-to-back is bound by the panes' own field CallbackShortcuts (blur) and
  // the settings `back` below; documented here in one place.
  Binding(
    intent: KeyIntent.back,
    scope: KeyScope.editor,
    caps: ['Esc'],
    description: 'Back to list',
    helpGroup: 'Navigation',
    showInHelp: true,
  ),

  // --- Panes (global scope) ---
  Binding(
    intent: KeyIntent.switchPane,
    scope: KeyScope.global,
    strokes: [KeyStroke(LogicalKeyboardKey.tab)],
    caps: ['Tab'],
    description: 'Switch pane',
    helpGroup: 'Panes',
    showInHelp: true,
    blockedWhileTyping: true,
  ),
  Binding(
    intent: KeyIntent.focusTracker,
    scope: KeyScope.global,
    strokes: _ctrlLeft,
    caps: ['Ctrl+←', 'Ctrl+→'],
    description: 'Focus tracker / panel',
    helpGroup: 'Panes',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.focusPanel,
    scope: KeyScope.global,
    strokes: _ctrlRight,
  ),
  Binding(
    intent: KeyIntent.focusTracker,
    scope: KeyScope.global,
    prefix: _ctrlW,
    strokes: _left,
    caps: ['Ctrl+W', 'H', 'L'],
    description: 'Switch pane (vim)',
    helpGroup: 'Panes',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.focusPanel,
    scope: KeyScope.global,
    prefix: _ctrlW,
    strokes: _right,
  ),
  Binding(
    intent: KeyIntent.search,
    scope: KeyScope.global,
    // shift:false so a shifted slash (`?`, matched by character below) can't
    // also read as search on platforms that report it as the slash key.
    strokes: [KeyStroke(LogicalKeyboardKey.slash, shift: false)],
    caps: ['/'],
    description: 'Search',
    helpGroup: 'Panes',
    showInHelp: true,
    blockedWhileTyping: true,
  ),
  Binding(
    intent: KeyIntent.openSettings,
    scope: KeyScope.global,
    strokes: [KeyStroke(LogicalKeyboardKey.comma, ctrl: true)],
    caps: ['Ctrl+,'],
    description: 'Settings',
    helpGroup: 'Panes',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.showHelp,
    scope: KeyScope.global,
    strokes: [KeyStroke(null, character: '?')],
    caps: ['?'],
    description: 'This help',
    helpGroup: 'Panes',
    showInHelp: true,
    blockedWhileTyping: true,
  ),

  // --- Side panel ---
  Binding(
    intent: KeyIntent.addClient,
    scope: KeyScope.panel,
    strokes: [KeyStroke(LogicalKeyboardKey.keyA, shift: true)],
    caps: ['A'],
    description: 'Add client',
    helpGroup: 'Side panel',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.addProject,
    scope: KeyScope.panel,
    strokes: [KeyStroke(LogicalKeyboardKey.keyA, shift: false)],
    caps: ['a'],
    description: 'Add project',
    helpGroup: 'Side panel',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.nextMatch,
    scope: KeyScope.panel,
    strokes: [KeyStroke(LogicalKeyboardKey.keyN, shift: false)],
    caps: ['n', 'N'],
    description: 'Next / previous project',
    helpGroup: 'Side panel',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.prevMatch,
    scope: KeyScope.panel,
    strokes: [KeyStroke(LogicalKeyboardKey.keyN, shift: true)],
  ),

  // --- Tracker ---
  Binding(
    intent: KeyIntent.openTracker,
    scope: KeyScope.global,
    strokes: [KeyStroke(LogicalKeyboardKey.keyT)],
    caps: ['t'],
    description: 'Open tracker',
    helpGroup: 'Tracker',
    showInHelp: true,
    blockedWhileTyping: true,
  ),
  Binding(
    intent: KeyIntent.toggleTimer,
    scope: KeyScope.global,
    strokes: [KeyStroke(LogicalKeyboardKey.space)],
    caps: ['Space'],
    description: 'Start / pause / resume',
    helpGroup: 'Tracker',
    showInHelp: true,
    blockedWhileTyping: true,
  ),
  Binding(
    intent: KeyIntent.finishSession,
    scope: KeyScope.tracker,
    strokes: [KeyStroke(LogicalKeyboardKey.keyF)],
    caps: ['f'],
    description: 'Finish session',
    helpGroup: 'Tracker',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.addTask,
    scope: KeyScope.tracker,
    strokes: [KeyStroke(LogicalKeyboardKey.keyA, shift: false)],
    caps: ['a'],
    description: 'Add task',
    helpGroup: 'Tracker',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.addEntry,
    scope: KeyScope.tracker,
    strokes: [KeyStroke(LogicalKeyboardKey.keyA, shift: true)],
    caps: ['A'],
    description: 'Add entry',
    helpGroup: 'Tracker',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.focusDescription,
    scope: KeyScope.tracker,
    strokes: [KeyStroke(LogicalKeyboardKey.keyI)],
    caps: ['i'],
    description: 'Focus description',
    helpGroup: 'Tracker',
    showInHelp: true,
  ),

  // --- Settings panel (nav mirrors the side panel; not re-listed in help) ---
  Binding(
    intent: KeyIntent.addEntity,
    scope: KeyScope.settings,
    strokes: [KeyStroke(LogicalKeyboardKey.keyA, shift: false)],
  ),
  Binding(
    intent: KeyIntent.back,
    scope: KeyScope.settings,
    strokes: [KeyStroke(LogicalKeyboardKey.escape)],
  ),

  // --- Editors (documentation-only; bound in each editor's CallbackShortcuts) ---
  Binding(
    intent: KeyIntent.activate,
    scope: KeyScope.editor,
    caps: ['Enter', 'Ctrl+S'],
    description: 'Save',
    helpGroup: 'Editors',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.editItem,
    scope: KeyScope.editor,
    caps: ['d'],
    description: 'Delete (in an edit modal)',
    helpGroup: 'Editors',
    showInHelp: true,
  ),
  Binding(
    intent: KeyIntent.back,
    scope: KeyScope.editor,
    caps: ['Esc'],
    description: 'Cancel / close',
    helpGroup: 'Editors',
    showInHelp: true,
  ),
];

/// The keymap registry + matching. All matching state (the armed chord prefix)
/// lives in the caller's [ChordDetector]; this class is otherwise stateless.
abstract final class Keymap {
  static const List<Binding> bindings = _bindings;

  /// Movement is the only hold-repeatable intent; everything else fires once
  /// per press.
  static bool isRepeatable(KeyIntent intent) =>
      intent == KeyIntent.moveDown || intent == KeyIntent.moveUp;

  /// Resolve [event] against the bindings in [scopes], using [detector] for
  /// chord state. [ctrlDown]/[shiftDown] are the live modifier state (handlers
  /// pass `HardwareKeyboard.instance.is…Pressed`). When [typing] a text field is
  /// focused, bindings marked [Binding.blockedWhileTyping] stand down so the key
  /// types normally.
  ///
  /// Chords only arm/complete on a key-down (held keys don't auto-complete a
  /// chord); single strokes also match on key-repeat so movement can be held.
  static KeyResolution resolve(
    KeyEvent event,
    ChordDetector detector,
    Set<KeyScope> scopes, {
    bool ctrlDown = false,
    bool shiftDown = false,
    bool typing = false,
  }) {
    final down = event is KeyDownEvent;

    bool active(Binding b) =>
        scopes.contains(b.scope) && !(typing && b.blockedWhileTyping);

    // Complete a pending chord (down events only).
    final armed = detector._armed;
    if (armed != null && down) {
      detector._armed = null;
      for (final b in _bindings) {
        if (!active(b) || !b.isChord || b.prefix != armed) continue;
        for (final s in b.strokes) {
          if (s.matches(event, ctrlDown, shiftDown)) return KeyMatch(b.intent);
        }
      }
      // Not a completion — fall through and match this event fresh.
    }

    // Single-press bindings.
    for (final b in _bindings) {
      if (!active(b) || b.isChord) continue;
      for (final s in b.strokes) {
        if (s.matches(event, ctrlDown, shiftDown)) return KeyMatch(b.intent);
      }
    }

    // Arm a chord prefix (down events only).
    if (down) {
      for (final b in _bindings) {
        if (!active(b) || !b.isChord) continue;
        if (b.prefix!.matches(event, ctrlDown, shiftDown)) {
          detector._armed = b.prefix;
          return const KeyPending();
        }
      }
    }

    return const KeyNone();
  }
}

/// Per-handler chord state — the armed prefix of an in-progress `gg` / `G` /
/// `Ctrl-w h/l` sequence. One instance per raw-key handler; [reset] on a focus
/// excursion so a half-typed sequence can't mis-fire on the next keypress.
class ChordDetector {
  KeyStroke? _armed;

  bool get isArmed => _armed != null;

  void reset() => _armed = null;
}
