import 'dart:io';

import 'package:args/command_runner.dart';

import 'db_open.dart';
import 'exit_codes.dart';
import 'output_formatter.dart';
import 'timer_status.dart';

// ── Verb dispatch (args-based) ─────────────────────────────────────────────
// The CLI spine: a CommandRunner that owns the global flags (`--json`, `--db`),
// dispatches verbs, and maps every outcome to the documented exit-code
// contract (see exit_codes.dart). Slice 1 ships one verb — `timer status` —
// but the command tree is the scaffold future verbs (start/stop/log/list) slot
// into.

/// Run the CLI for [args]; returns the process exit code. Never calls
/// `exit()` itself — `bin/timedart.dart` owns that.
Future<int> runTimedartCli(List<String> args) async {
  final runner =
      CommandRunner<int>('timedart', 'timedart companion CLI — a DB peer of the app.')
        ..argParser.addFlag(
          'json',
          negatable: false,
          help: 'Emit machine-readable JSON instead of human text.',
        )
        ..argParser.addOption(
          'db',
          help: 'Path to the timedart database (overrides TIMEDART_DB and the '
              'default per-platform location). May be a file or a directory.',
        )
        ..addCommand(TimerCommand());

  try {
    final code = await runner.run(args);
    return code ?? CliExit.success;
  } on CliException catch (e) {
    stderr.writeln('error: ${e.message}');
    return e.exitCode;
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln();
    stderr.writeln(e.usage);
    return CliExit.usage;
  }
}

/// `timedart timer …` — the running-timer verb group.
class TimerCommand extends Command<int> {
  @override
  final String name = 'timer';
  @override
  final String description = 'Inspect and control the running timer.';

  TimerCommand() {
    addSubcommand(TimerStatusCommand());
  }
}

/// `timedart timer status` — print the currently running timer (read-only).
class TimerStatusCommand extends Command<int> {
  @override
  final String name = 'status';
  @override
  final String description =
      'Show the currently running timer and its live elapsed time.';

  @override
  Future<int> run() async {
    final global = globalResults!;
    final json = global['json'] as bool;
    final dbOverride = global['db'] as String?;

    final path = resolveActiveDbPath(override: dbOverride);
    final db = openTimedartDb(path); // throws CliException on guard failures
    try {
      final result = await queryTimerStatus(db, now: DateTime.now());
      stdout.writeln(formatTimerStatus(result, json: json));
      return CliExit.success;
    } finally {
      await db.close();
    }
  }
}
