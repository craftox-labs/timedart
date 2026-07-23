/// The pure decision at the heart of the GUI's live-refresh (PRD #270, slice
/// #274): *given the latest SQLite `data_version`, has another connection
/// committed since we last looked — should we refresh?*
///
/// SQLite's `PRAGMA data_version` is bumped on a connection whenever ANY OTHER
/// connection commits, and is stable across the connection's own writes — so it
/// is a writer-agnostic "someone else changed the file" signal (the CLI now, a
/// second CLI, or a delta-sync apply). This class owns only
/// the last-seen bookkeeping; the timer/lifecycle/drift wiring is a thin shell
/// around it (see the ExternalChangeWatcher widget), keeping the decision
/// Flutter-free and exhaustively testable.
class ExternalChangeDetector {
  int? _lastSeen;

  /// Whether the detector has taken its first reading yet.
  bool get hasBaseline => _lastSeen != null;

  /// The most recent `data_version` observed (null before the first reading).
  int? get lastSeen => _lastSeen;

  /// Record a freshly-read [dataVersion] and report whether it represents an
  /// external commit that warrants a refresh.
  ///
  /// The first observation only establishes the baseline and returns `false`
  /// (no spurious refresh on startup). Every later observation returns `true`
  /// exactly once per NEW value — a repeated (unchanged) value returns `false`,
  /// so idle polls and the app's own writes never trigger a refresh.
  bool observe(int dataVersion) {
    if (_lastSeen == null) {
      _lastSeen = dataVersion;
      return false;
    }
    if (dataVersion == _lastSeen) return false;
    _lastSeen = dataVersion;
    return true;
  }

  /// Forget the baseline, so the next [observe] re-establishes it without
  /// firing (used when polling restarts after a background gap).
  void reset() => _lastSeen = null;
}
