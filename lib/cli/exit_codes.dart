/// The CLI's process exit-code contract (PRD #270, slice #271).
///
/// Deterministic, documented codes so a shell script or agent can branch on the
/// outcome of a `timedart` invocation. The set is deliberately small and stable
/// — new error classes get new codes; existing ones never change meaning.
class CliExit {
  CliExit._();

  /// The command completed successfully.
  static const int success = 0;

  /// A generic/unexpected failure with no more specific code.
  static const int failure = 1;

  /// The command line could not be parsed (unknown verb, bad flag, missing
  /// argument). Mirrors the conventional "usage error" code.
  static const int usage = 2;

  /// The on-disk database's schema version differs from the one this CLI ships
  /// with. The CLI refuses to open it and NEVER migrates — a stale binary must
  /// not silently upgrade (or corrupt) the user's data.
  static const int schemaMismatch = 3;

  /// No database file was found at the resolved (or overridden) path.
  static const int dbNotFound = 4;
}

/// A failure a command can raise to abort with a specific [exitCode] and a
/// human-readable [message] (printed to stderr by the dispatcher).
class CliException implements Exception {
  final String message;
  final int exitCode;
  const CliException(this.message, this.exitCode);

  @override
  String toString() => message;
}
