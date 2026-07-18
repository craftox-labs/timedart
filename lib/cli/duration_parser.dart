import 'exit_codes.dart';

// ── --duration / --at parsing (pure) ───────────────────────────────────────
// A small, dependency-free parser for the `log` verb's human-friendly duration
// and start-time inputs. Kept pure so it's exhaustively unit-testable.

/// Parse a human duration into whole seconds.
///
/// Accepted forms (case-insensitive, whitespace ignored):
///   • unit tokens combined in any order: `1h30m`, `90m`, `45s`, `2h`, `1h 30m`
///   • a single decimal-with-unit: `1.5h`, `0.5m`, `2.5s`
///   • a bare number = seconds: `5400`
///
/// Throws [CliException] ([CliExit.usage]) on anything it can't parse. Rounds to
/// the nearest second.
int parseDurationSeconds(String input) {
  final s = input.trim().toLowerCase().replaceAll(' ', '');
  if (s.isEmpty) _bad(input);

  // Bare number → seconds.
  final bare = num.tryParse(s);
  if (bare != null) {
    if (bare < 0) _bad(input);
    return bare.round();
  }

  final token = RegExp(r'(\d+(?:\.\d+)?)([hms])');
  var consumed = 0;
  double total = 0;
  for (final m in token.allMatches(s)) {
    consumed += m.group(0)!.length;
    final value = double.parse(m.group(1)!);
    switch (m.group(2)) {
      case 'h':
        total += value * 3600;
      case 'm':
        total += value * 60;
      case 's':
        total += value;
    }
  }
  // Every character must belong to a token, and there must be at least one.
  if (consumed != s.length || consumed == 0) _bad(input);
  if (total <= 0) _bad(input);
  return total.round();
}

/// Parse an ISO-8601-ish date/time (`2026-07-18`, `2026-07-18T09:30`,
/// `2026-07-18T09:30:00`) with [DateTime.parse]. [label] names the option in
/// the error message — defaults to `--at` (its original/primary caller), but
/// `--since`/`--until`/`--end` pass their own so the error points at the right
/// flag. Throws [CliException] on a bad value.
DateTime parseAt(String input, {String label = '--at'}) {
  final v = DateTime.tryParse(input.trim());
  if (v == null) {
    throw CliException(
      'Invalid $label "$input": expected an ISO-8601 date/time '
      '(e.g. 2026-07-18 or 2026-07-18T09:30).',
      CliExit.usage,
    );
  }
  return v;
}

Never _bad(String input) => throw CliException(
  'Invalid --duration "$input": use e.g. 90m, 1h30m, 1.5h, 45s, or a number '
  'of seconds.',
  CliExit.usage,
);
