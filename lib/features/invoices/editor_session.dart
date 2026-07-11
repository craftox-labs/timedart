import 'package:flutter/foundation.dart';

/// The dirty / save / rebaseline lifecycle for a content-pane editor, extracted
/// out of the individual editors so the field-by-field diff (the bug-prone part)
/// lives in one place and can be unit-tested with no widget tree.
///
/// The session holds a baseline **snapshot** of type [S] — a small immutable
/// value class capturing every edited field with an explicit `==`. On each edit
/// the editor calls [recompute]; dirty is simply `snapshot() != baseline`, so
/// reverting a field back to its original value clears dirty for free.
///
/// Pure by design — it never touches a `BuildContext`. The unsaved-changes
/// confirm dialog stays in the UI layer (the shell / the editor's Cancel);
/// [save] just reports success as a `Future<bool>`.
class EditorSession<S> {
  EditorSession({required this.snapshot, required this.persist})
    : _baseline = snapshot();

  /// Reads the editor's current edited state as a comparable value.
  final S Function() snapshot;

  /// Writes the edited state, returning whether the write succeeded.
  final Future<bool> Function() persist;

  S _baseline;

  final ValueNotifier<bool> _dirty = ValueNotifier(false);

  /// Whether the live snapshot differs from the baseline. The shell listens to
  /// gate navigation; the editor listens to drive its Save/Cancel state.
  ValueListenable<bool> get dirty => _dirty;
  bool get isDirty => _dirty.value;

  /// The snapshot the editor diffs against — also what a Cancel reverts the
  /// on-screen fields to.
  S get baseline => _baseline;

  /// Recompute dirty from the current snapshot against the baseline. Call after
  /// any change to an edited field.
  void recompute() => _dirty.value = snapshot() != _baseline;

  /// Persist via the supplied callback; on success adopt the just-saved values
  /// as the new baseline (so dirty clears without the widget re-mounting) and
  /// return true. On failure the baseline is untouched and dirty stands.
  Future<bool> save() async {
    final ok = await persist();
    if (ok) rebaseline();
    return ok;
  }

  /// Adopt the current snapshot as the baseline (dirty → false) without
  /// persisting. Used after an async default-fill lands on-screen values that
  /// shouldn't read as user edits (e.g. the profile editor's auto-picked
  /// default template once templates finish loading).
  void rebaseline() {
    _baseline = snapshot();
    _dirty.value = false;
  }

  void dispose() => _dirty.dispose();
}

/// A logo (image bytes + MIME) compared by **content**, not identity, so an
/// unchanged logo never reads as a dirty edit when it lands in an editor
/// snapshot. Two [LogoValue]s are equal when their bytes and MIME match.
@immutable
class LogoValue {
  const LogoValue(this.bytes, this.mime);
  final Uint8List? bytes;
  final String? mime;

  @override
  bool operator ==(Object other) =>
      other is LogoValue &&
      other.mime == mime &&
      listEquals(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(
    mime,
    // Content hash so equal bytes hash alike; length is a cheap, stable proxy
    // that keeps a large logo off the hot path (equality still compares bytes).
    bytes == null ? null : Object.hash(bytes!.length, bytes!.isEmpty ? 0 : bytes!.first),
  );
}
