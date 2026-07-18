import 'dart:io';

import 'package:args/command_runner.dart';

import '../data/database.dart';
import '../features/tracker/timer_store.dart';
import 'crud_result.dart';
import 'db_open.dart';
import 'duration_parser.dart';
import 'entity_resolver.dart';
import 'exit_codes.dart';
import 'list_query.dart';
import 'log_result.dart';
import 'output_formatter.dart';
import 'timer_status.dart';
import 'timer_stop_result.dart';
import 'version.dart';
import '../util/parse_rate.dart';

// ── Verb dispatch (args-based) ─────────────────────────────────────────────
// The CLI spine: a CommandRunner that owns the global flags (`--json`, `--db`),
// dispatches verbs, and maps every outcome to the documented exit-code
// contract (see exit_codes.dart). All writes go through AppDatabase/TimerStore
// (never raw tables) so business rules — and later PowerSync CRUD capture —
// come for free.

/// Run the CLI for [args]; returns the process exit code. Never calls
/// `exit()` itself — `bin/timedart.dart` owns that.
Future<int> runTimedartCli(List<String> args) async {
  final runner =
      CommandRunner<int>(
          'timedart',
          'timedart companion CLI — a DB peer of the app.\n\n'
              '${versionLine()}',
        )
        ..argParser.addFlag(
          'version',
          negatable: false,
          help: 'Print the CLI version, DB schema version and sync-awareness.',
        )
        ..argParser.addFlag(
          'json',
          negatable: false,
          help: 'Emit machine-readable JSON instead of human text.',
        )
        ..argParser.addOption(
          'db',
          help:
              'Path to the timedart database (overrides TIMEDART_DB and the '
              'default per-platform location). May be a file or a directory.',
        )
        ..addCommand(TimerCommand())
        ..addCommand(ListCommand())
        ..addCommand(LogCommand())
        ..addCommand(ClientCommand())
        ..addCommand(ProjectCommand())
        ..addCommand(TaskCommand());

  try {
    // `--version` is handled before dispatch so it works with no sub-command.
    // A parse failure here is ignored — runner.run reports it as a UsageException.
    try {
      final top = runner.argParser.parse(args);
      if (top['version'] as bool) {
        stdout.writeln(versionLine());
        return CliExit.success;
      }
    } on FormatException {
      // fall through to runner.run for a proper usage message
    }
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
    addSubcommand(TimerStartCommand());
    addSubcommand(TimerStopCommand());
    addSubcommand(TimerPauseCommand());
    addSubcommand(TimerResumeCommand());
  }
}

/// Shared plumbing for the timer verbs: reads the global flags and opens the
/// app's DB through the seam.
abstract class _CliVerb extends Command<int> {
  bool get json => globalResults!['json'] as bool;
  String? get dbOverride => globalResults!['db'] as String?;

  /// Open the DB the seam resolves (honouring `--db`/`TIMEDART_DB`). Throws
  /// [CliException] on the guard failures (schema mismatch / not found).
  AppDatabase openDb() => openTimedartDb(resolveActiveDbPath(override: dbOverride));

  /// Print [text] to stdout and return success.
  int emit(String text) {
    stdout.writeln(text);
    return CliExit.success;
  }

  /// The single positional `<id|name>` selector a mutate verb targets. Throws
  /// [CliExit.usage] when absent or when more than one bare argument is given
  /// (a name with spaces must be quoted).
  String selector(String verb) {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      throw CliException(
        '$verb requires a <id|name> argument.',
        CliExit.usage,
      );
    }
    if (rest.length > 1) {
      throw CliException(
        '$verb takes a single <id|name> argument (got ${rest.length}) — quote '
        'names that contain spaces.',
        CliExit.usage,
      );
    }
    return rest.single;
  }

  /// Read a required non-empty option, else fail with a usage error naming it.
  String required(String option, String verb) {
    final v = argResults![option] as String?;
    if (v == null || v.trim().isEmpty) {
      throw CliException(
        '$verb requires --$option.',
        CliExit.usage,
      );
    }
    return v.trim();
  }
}

// ── Mutate-verb helpers ────────────────────────────────────────────────────

/// Trim [raw]; an empty string becomes null (clears an optional text field).
String? _clean(String? raw) =>
    (raw == null || raw.trim().isEmpty) ? null : raw.trim();

/// Parse a required rate (client default rate) — a plain number. Throws a usage
/// error rather than silently dropping a typo to null.
double _requiredRate(String raw) {
  final parsed = parseRate(raw);
  if (parsed.error != null || parsed.value == null) {
    throw CliException(
      'Invalid --rate "$raw": enter a number.',
      CliExit.usage,
    );
  }
  return parsed.value!;
}

/// Parse an optional rate (project/task) that may *clear* to inherit. An empty
/// value or the literal `inherit` yields null (inherit the parent's rate); any
/// other value must be a number.
double? _optionalRate(String raw) {
  final t = raw.trim();
  if (t.isEmpty || t.toLowerCase() == 'inherit') return null;
  final parsed = parseRate(t);
  if (parsed.error != null) {
    throw CliException(
      'Invalid --rate "$raw": enter a number, or "inherit" to clear it.',
      CliExit.usage,
    );
  }
  return parsed.value;
}

/// Maps a caught database write failure to the clean, user-facing message for
/// [CliExit.constraintViolation] — never the raw driver exception or SQL
/// statement/parameters — or returns null if [error] isn't a constraint
/// failure at all.
///
/// [projectCode], when given, names the code being written so a duplicate
/// `projects.code` failure can point at it specifically; other constraint
/// failures fall back to a terse generic message. Exposed (not private) so
/// tests can pin the exact wording without spawning the CLI.
String? constraintViolationMessage(Object error, {String? projectCode}) {
  final msg = error.toString();
  if (!msg.contains('UNIQUE') && !msg.contains('constraint')) return null;
  if (projectCode != null && msg.contains('projects.code')) {
    return 'A project with code "$projectCode" already exists. Choose a '
        'different code.';
  }
  return 'The write violates a database constraint.';
}

/// Run a write, mapping a database constraint failure to
/// [CliExit.constraintViolation] via [constraintViolationMessage]. Other
/// errors pass through unchanged.
Future<T> _guardConstraints<T>(
  Future<T> Function() write, {
  String? projectCode,
}) async {
  try {
    return await write();
  } catch (e) {
    final message = constraintViolationMessage(e, projectCode: projectCode);
    if (message != null) {
      throw CliException(message, CliExit.constraintViolation);
    }
    rethrow;
  }
}

/// `timedart timer status` — print the currently running timer (read-only).
class TimerStatusCommand extends _CliVerb {
  @override
  final String name = 'status';
  @override
  final String description =
      'Show the currently running timer and its live elapsed time.';

  @override
  Future<int> run() async {
    final db = openDb();
    try {
      final result = await queryTimerStatus(db, now: DateTime.now());
      return emit(formatTimerStatus(result, json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart timer start --project <id|name> [--task <id|name>] [--description]`
class TimerStartCommand extends _CliVerb {
  @override
  final String name = 'start';
  @override
  final String description = 'Start a timer against a project and task.';

  TimerStartCommand() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        help: 'Project to track — a UUID or an exact project code/title.',
      )
      ..addOption(
        'task',
        abbr: 't',
        help: 'Task to track — a UUID or exact title within the project '
            '(required).',
      )
      ..addOption(
        'description',
        abbr: 'd',
        help: 'Session note, saved as the recorded entry\'s description.',
      );
  }

  @override
  Future<int> run() async {
    final projectSel = argResults!['project'] as String?;
    if (projectSel == null || projectSel.isEmpty) {
      throw const CliException(
        'timer start requires --project <id|name>.',
        CliExit.usage,
      );
    }
    final taskSel = argResults!['task'] as String?;
    // All time in timedart is task-level (matches the GUI and `log`): without a
    // task the elapsed time would be silently discarded on stop.
    if (taskSel == null || taskSel.isEmpty) {
      throw const CliException(
        'timer start requires --task <id|name> (every entry belongs to a '
        'task).',
        CliExit.usage,
      );
    }
    final description = argResults!['description'] as String?;

    final db = openDb();
    try {
      final now = DateTime.now();
      final store = TimerStore(db);
      await store.recover(now: now);
      if (store.session.hasSession) {
        throw const CliException(
          'A timer is already active — stop it before starting a new one.',
          CliExit.timerAlreadyRunning,
        );
      }

      final project = await resolveProject(db, projectSel);
      final task = await resolveTask(db, project.id, taskSel);

      await store.start(
        project.id,
        task.id,
        now: now,
        description: description,
      );

      final result = await queryTimerStatus(db, now: now);
      return emit(formatTimerStatus(result, json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart timer stop` — finish the running timer, recording a TimeEntry.
class TimerStopCommand extends _CliVerb {
  @override
  final String name = 'stop';
  @override
  final String description =
      'Stop the running timer and record the elapsed time as an entry.';

  @override
  Future<int> run() async {
    final db = openDb();
    try {
      final now = DateTime.now();
      final store = TimerStore(db);
      await store.recover(now: now);
      if (!store.session.hasSession) {
        throw const CliException(
          'No timer is running.',
          CliExit.noTimerRunning,
        );
      }

      final finished = await store.finish(
        now: now,
        description: store.recoveredDescription,
      );

      final TimerStopResult result;
      if (finished == null) {
        result = TimerStopResult.nothingRecorded;
      } else {
        // Best-effort labels for the recorded entry.
        String? code, title;
        try {
          final p = await db.getProject(finished.projectId);
          code = p.code;
          title = p.title;
        } catch (_) {}
        final tasks = await db.tasksForProject(finished.projectId);
        final taskMatches = tasks
            .where((t) => t.id == finished.taskId)
            .toList();
        final taskTitle = taskMatches.isEmpty ? null : taskMatches.first.title;
        result = TimerStopResult(
          recorded: true,
          seconds: finished.seconds,
          projectId: finished.projectId,
          projectCode: code,
          projectTitle: title,
          taskId: finished.taskId,
          taskTitle: taskTitle,
          description: store.recoveredDescription,
          startedAt: finished.startedAt,
          endedAt: finished.endedAt,
        );
      }
      return emit(formatTimerStop(result, json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart timer pause` — pause the running timer (elapsed frozen).
class TimerPauseCommand extends _CliVerb {
  @override
  final String name = 'pause';
  @override
  final String description = 'Pause the running timer.';

  @override
  Future<int> run() async {
    final db = openDb();
    try {
      final now = DateTime.now();
      final store = TimerStore(db);
      await store.recover(now: now);
      if (!store.session.hasSession) {
        throw const CliException('No timer is running.', CliExit.noTimerRunning);
      }
      if (!store.session.isRunning) {
        throw const CliException(
          'Timer is already paused.',
          CliExit.timerAlreadyPaused,
        );
      }
      await store.pause(now: now, description: store.recoveredDescription);
      final result = await queryTimerStatus(db, now: now);
      return emit(formatTimerStatus(result, json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart timer resume` — resume a paused timer.
class TimerResumeCommand extends _CliVerb {
  @override
  final String name = 'resume';
  @override
  final String description = 'Resume a paused timer.';

  @override
  Future<int> run() async {
    final db = openDb();
    try {
      final now = DateTime.now();
      final store = TimerStore(db);
      await store.recover(now: now);
      if (!store.session.hasSession) {
        throw const CliException('No timer is paused.', CliExit.noTimerRunning);
      }
      if (store.session.isRunning) {
        throw const CliException(
          'Timer is already running.',
          CliExit.timerAlreadyRunning,
        );
      }
      // start() resumes a paused session, keeping its existing project/task
      // binding (TimerSession binds only at first start).
      await store.start(
        null,
        null,
        now: now,
        description: store.recoveredDescription,
      );
      final result = await queryTimerStatus(db, now: now);
      return emit(formatTimerStatus(result, json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart list …` — discovery of the ids/names to target work against.
class ListCommand extends Command<int> {
  @override
  final String name = 'list';
  @override
  final String description = 'List live projects or tasks.';

  ListCommand() {
    addSubcommand(ListClientsCommand());
    addSubcommand(ListProjectsCommand());
    addSubcommand(ListTasksCommand());
  }
}

/// `timedart list clients` — live clients with UUID, name and default rate.
class ListClientsCommand extends _CliVerb {
  @override
  final String name = 'clients';
  @override
  final String description = 'List live clients.';

  @override
  Future<int> run() async {
    final db = openDb();
    try {
      final items = await queryClients(db);
      return emit(formatClients(items, json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart list projects` — live projects with UUID, code, title and client.
class ListProjectsCommand extends _CliVerb {
  @override
  final String name = 'projects';
  @override
  final String description = 'List live projects.';

  @override
  Future<int> run() async {
    final db = openDb();
    try {
      final items = await queryProjects(db);
      return emit(formatProjects(items, json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart list tasks [--project <id|name>]` — live tasks, optionally scoped.
class ListTasksCommand extends _CliVerb {
  @override
  final String name = 'tasks';
  @override
  final String description = 'List live tasks, optionally scoped to a project.';

  ListTasksCommand() {
    argParser.addOption(
      'project',
      abbr: 'p',
      help: 'Only tasks under this project — a UUID or exact code/title.',
    );
  }

  @override
  Future<int> run() async {
    final projectSel = argResults!['project'] as String?;
    final db = openDb();
    try {
      String? projectId;
      if (projectSel != null && projectSel.isNotEmpty) {
        projectId = (await resolveProject(db, projectSel)).id;
      }
      final items = await queryTasks(db, projectId: projectId);
      return emit(formatTasks(items, json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart log` — record a completed TimeEntry directly (`--project` +
/// `--task` + `--duration`, optional `--description` / `--at`).
///
/// `--task` is REQUIRED: the shared [AppDatabase.addEntry] (the only sanctioned
/// write path — no raw tables) records every entry against a task, matching how
/// the GUI stores time. `--duration` accepts `90m` / `1h30m` / `1.5h` / `45s` /
/// bare seconds. `--at` is an ISO-8601 START time; omitted, the entry ends now
/// and starts `duration` earlier.
class LogCommand extends _CliVerb {
  @override
  final String name = 'log';
  @override
  final String description = 'Record a completed time entry directly.';

  LogCommand() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        help: 'Project — a UUID or exact project code/title.',
      )
      ..addOption(
        'task',
        abbr: 't',
        help: 'Task — a UUID or exact title within the project (required).',
      )
      ..addOption(
        'duration',
        abbr: 'D',
        help: 'Tracked duration: 90m, 1h30m, 1.5h, 45s, or bare seconds.',
      )
      ..addOption('description', abbr: 'd', help: 'Entry description/note.')
      ..addOption(
        'at',
        help:
            'ISO-8601 start time (e.g. 2026-07-18T09:30). Default: now minus '
            'duration.',
      );
  }

  @override
  Future<int> run() async {
    final projectSel = argResults!['project'] as String?;
    final taskSel = argResults!['task'] as String?;
    final durationSel = argResults!['duration'] as String?;
    final description = argResults!['description'] as String?;
    final atSel = argResults!['at'] as String?;

    if (projectSel == null || projectSel.isEmpty) {
      throw const CliException(
        'log requires --project <id|name>.',
        CliExit.usage,
      );
    }
    if (taskSel == null || taskSel.isEmpty) {
      throw const CliException(
        'log requires --task <id|name> (every entry belongs to a task).',
        CliExit.usage,
      );
    }
    if (durationSel == null || durationSel.isEmpty) {
      throw const CliException(
        'log requires --duration <e.g. 90m>.',
        CliExit.usage,
      );
    }
    final seconds = parseDurationSeconds(durationSel); // throws usage on bad

    final db = openDb();
    try {
      final project = await resolveProject(db, projectSel);
      final task = await resolveTask(db, project.id, taskSel);

      final DateTime startedAt;
      final DateTime endedAt;
      if (atSel != null && atSel.isNotEmpty) {
        startedAt = parseAt(atSel);
        endedAt = startedAt.add(Duration(seconds: seconds));
      } else {
        endedAt = DateTime.now();
        startedAt = endedAt.subtract(Duration(seconds: seconds));
      }

      await db.addEntry(
        projectId: project.id,
        taskId: task.id,
        description: description,
        startedAt: startedAt,
        endedAt: endedAt,
        seconds: seconds,
      );

      final result = LogResult(
        seconds: seconds,
        projectId: project.id,
        projectCode: project.code,
        projectTitle: project.title,
        taskId: task.id,
        taskTitle: task.title,
        description: description,
        startedAt: startedAt,
        endedAt: endedAt,
      );
      return emit(formatLog(result, json: json));
    } finally {
      await db.close();
    }
  }
}

// ── Entity CRUD (issue #280) ───────────────────────────────────────────────
// Manage the client → project → task graph, reusing the same lib/data write
// methods the GUI calls (addClient/updateProject/deleteTaskCascade/…) so every
// business rule — rate inheritance, unique codes, cascade soft-delete, sync
// tombstones — matches the app exactly. Conventions carried from the shipped
// slices: `--json` everywhere, id-or-name selectors, documented exit codes.
//
// Parity note: only clients and projects are archivable (they carry an
// `archivedAt`); tasks are not archived in the app either, so `task` has no
// archive verb — delete (with --force) is its removal path.

/// `timedart client …` — manage clients.
class ClientCommand extends Command<int> {
  @override
  final String name = 'client';
  @override
  final String description = 'Create, edit, archive or delete a client.';

  ClientCommand() {
    addSubcommand(ClientAddCommand());
    addSubcommand(ClientEditCommand());
    addSubcommand(ClientArchiveCommand(archive: true));
    addSubcommand(ClientArchiveCommand(archive: false));
    addSubcommand(ClientDeleteCommand());
  }
}

/// `timedart client add --name <n> --rate <r> [--contact …]`
class ClientAddCommand extends _CliVerb {
  @override
  final String name = 'add';
  @override
  final String description = 'Create a client.';

  ClientAddCommand() {
    argParser
      ..addOption('name', help: 'Client name (required).')
      ..addOption(
        'rate',
        help: 'Default hourly rate its projects inherit (required, a number).',
      )
      ..addOption('contact', help: 'Contact person.')
      ..addOption('email', help: 'Email.')
      ..addOption('phone', help: 'Phone.')
      ..addOption('address', help: 'Postal address.')
      ..addOption('abn', help: 'ABN / tax number.');
  }

  @override
  Future<int> run() async {
    final clientName = required('name', 'client add');
    final rate = _requiredRate(required('rate', 'client add'));
    final db = openDb();
    try {
      final id = await _guardConstraints(
        () => db.addClient(
          name: clientName,
          contactName: _clean(argResults!['contact'] as String?),
          email: _clean(argResults!['email'] as String?),
          phone: _clean(argResults!['phone'] as String?),
          address: _clean(argResults!['address'] as String?),
          abn: _clean(argResults!['abn'] as String?),
          defaultRate: rate,
        ),
      );
      final item = clientListItem(await db.getClient(id));
      return emit(formatClient(item, action: 'Created', json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart client edit <id|name> [--name --rate --contact …]` — only the
/// options you pass change; pass an empty value to clear an optional text field.
class ClientEditCommand extends _CliVerb {
  @override
  final String name = 'edit';
  @override
  final String description = 'Edit a client (only the fields you pass change).';

  ClientEditCommand() {
    argParser
      ..addOption('name', help: 'New name.')
      ..addOption('rate', help: 'New default rate (a number).')
      ..addOption('contact', help: 'Contact person ("" clears).')
      ..addOption('email', help: 'Email ("" clears).')
      ..addOption('phone', help: 'Phone ("" clears).')
      ..addOption('address', help: 'Address ("" clears).')
      ..addOption('abn', help: 'ABN / tax number ("" clears).');
  }

  @override
  Future<int> run() async {
    final sel = selector('client edit');
    final db = openDb();
    try {
      final c = await resolveClient(db, sel);
      final wants = argResults!;
      await _guardConstraints(
        () => db.updateClient(
          id: c.id,
          name: wants.wasParsed('name')
              ? required('name', 'client edit')
              : c.name,
          defaultRate: wants.wasParsed('rate')
              ? _requiredRate(wants['rate'] as String)
              : c.defaultRate,
          contactName: wants.wasParsed('contact')
              ? _clean(wants['contact'] as String?)
              : c.contactName,
          email: wants.wasParsed('email')
              ? _clean(wants['email'] as String?)
              : c.email,
          phone: wants.wasParsed('phone')
              ? _clean(wants['phone'] as String?)
              : c.phone,
          address: wants.wasParsed('address')
              ? _clean(wants['address'] as String?)
              : c.address,
          abn: wants.wasParsed('abn') ? _clean(wants['abn'] as String?) : c.abn,
        ),
      );
      final item = clientListItem(await db.getClient(c.id));
      return emit(formatClient(item, action: 'Updated', json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart client archive|unarchive <id|name>` — reversible hide-from-UI,
/// distinct from delete (the client stays live and invoiceable).
class ClientArchiveCommand extends _CliVerb {
  ClientArchiveCommand({required this.archive});
  final bool archive;
  @override
  String get name => archive ? 'archive' : 'unarchive';
  @override
  String get description =>
      archive ? 'Archive a client (hide from the active list).'
              : 'Unarchive a client.';

  @override
  Future<int> run() async {
    final sel = selector('client $name');
    final db = openDb();
    try {
      final c = await resolveClient(db, sel);
      if (archive) {
        await db.archiveClient(c.id);
      } else {
        await db.unarchiveClient(c.id);
      }
      final item = clientListItem(await db.getClient(c.id));
      return emit(
        formatClient(
          item,
          action: archive ? 'Archived' : 'Unarchived',
          json: json,
        ),
      );
    } finally {
      await db.close();
    }
  }
}

/// `timedart client delete <id|name> [--force]` — destructive + cascading.
/// Without `--force` it prints the cascade-impact count and exits
/// [CliExit.confirmationRequired] without touching data.
class ClientDeleteCommand extends _CliVerb {
  @override
  final String name = 'delete';
  @override
  final String description =
      'Delete a client and everything under it (needs --force).';

  ClientDeleteCommand() {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Actually delete (and cascade). Without it, only the impact is '
          'shown.',
    );
  }

  @override
  Future<int> run() async {
    final sel = selector('client delete');
    final db = openDb();
    try {
      final c = await resolveClient(db, sel);
      if (await db.isTimerBoundToClient(c.id)) {
        throw CliException(
          'A timer is running under "${c.name}". Stop it before deleting this '
          'client.',
          CliExit.timerAlreadyRunning,
        );
      }
      final impact = await db.clientDeleteImpact(c.id);
      final force = argResults!['force'] as bool;
      if (!force) {
        stdout.writeln(
          formatDelete(
            DeleteOutcome(
              kind: 'client',
              id: c.id,
              label: c.name,
              impact: impact,
              deleted: false,
            ),
            json: json,
          ),
        );
        return CliExit.confirmationRequired;
      }
      await db.deleteClientCascade(c.id);
      return emit(
        formatDelete(
          DeleteOutcome(
            kind: 'client',
            id: c.id,
            label: c.name,
            impact: impact,
            deleted: true,
          ),
          json: json,
        ),
      );
    } finally {
      await db.close();
    }
  }
}

/// `timedart project …` — manage projects.
class ProjectCommand extends Command<int> {
  @override
  final String name = 'project';
  @override
  final String description = 'Create, edit, archive or delete a project.';

  ProjectCommand() {
    addSubcommand(ProjectAddCommand());
    addSubcommand(ProjectEditCommand());
    addSubcommand(ProjectArchiveCommand(archive: true));
    addSubcommand(ProjectArchiveCommand(archive: false));
    addSubcommand(ProjectDeleteCommand());
  }
}

/// `timedart project add --client <id|name> --code <c> --title <t> [--rate]`
class ProjectAddCommand extends _CliVerb {
  @override
  final String name = 'add';
  @override
  final String description = 'Create a project under a client.';

  ProjectAddCommand() {
    argParser
      ..addOption(
        'client',
        abbr: 'c',
        help: 'Owning client — a UUID or exact name (required).',
      )
      ..addOption('code', help: 'Unique project code (required).')
      ..addOption('title', help: 'Project title (required).')
      ..addOption(
        'rate',
        help: 'Project rate (a number). Omit to inherit the client default.',
      );
  }

  @override
  Future<int> run() async {
    final clientSel = required('client', 'project add');
    final code = required('code', 'project add');
    final title = required('title', 'project add');
    final rateRaw = argResults!['rate'] as String?;
    final rate = rateRaw == null ? null : _optionalRate(rateRaw);
    final db = openDb();
    try {
      final client = await resolveClient(db, clientSel);
      final id = await _guardConstraints(
        () => db.addProject(
          clientId: client.id,
          code: code,
          title: title,
          rate: rate,
        ),
        projectCode: code,
      );
      final item = projectListItem(
        await db.getProject(id),
        clientName: client.name,
      );
      return emit(formatProject(item, action: 'Created', json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart project edit <id|name> [--client --code --title --rate]`.
/// `--rate inherit` (or an empty value) clears the project rate to inherit.
class ProjectEditCommand extends _CliVerb {
  @override
  final String name = 'edit';
  @override
  final String description = 'Edit a project (only the fields you pass change).';

  ProjectEditCommand() {
    argParser
      ..addOption('client', abbr: 'c', help: 'Reassign to this client.')
      ..addOption('code', help: 'New code.')
      ..addOption('title', help: 'New title.')
      ..addOption('rate', help: 'New rate (a number, or "inherit" to clear).');
  }

  @override
  Future<int> run() async {
    final sel = selector('project edit');
    final db = openDb();
    try {
      final p = await resolveProject(db, sel);
      final wants = argResults!;
      var clientId = p.clientId;
      if (wants.wasParsed('client')) {
        clientId = (await resolveClient(db, wants['client'] as String)).id;
      }
      final newCode = wants.wasParsed('code')
          ? required('code', 'project edit')
          : p.code;
      await _guardConstraints(
        () => db.updateProject(
          id: p.id,
          clientId: clientId,
          code: newCode,
          title: wants.wasParsed('title')
              ? required('title', 'project edit')
              : p.title,
          rate: wants.wasParsed('rate')
              ? _optionalRate(wants['rate'] as String)
              : p.rate,
        ),
        projectCode: newCode,
      );
      final updated = await db.getProject(p.id);
      final item = projectListItem(
        updated,
        clientName: (await db.getClient(updated.clientId)).name,
      );
      return emit(formatProject(item, action: 'Updated', json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart project archive|unarchive <id|name>`.
class ProjectArchiveCommand extends _CliVerb {
  ProjectArchiveCommand({required this.archive});
  final bool archive;
  @override
  String get name => archive ? 'archive' : 'unarchive';
  @override
  String get description => archive
      ? 'Archive a project (hide from the active list).'
      : 'Unarchive a project.';

  @override
  Future<int> run() async {
    final sel = selector('project $name');
    final db = openDb();
    try {
      final p = await resolveProject(db, sel);
      if (archive) {
        await db.archiveProject(p.id);
      } else {
        await db.unarchiveProject(p.id);
      }
      final updated = await db.getProject(p.id);
      final item = projectListItem(
        updated,
        clientName: (await db.getClient(updated.clientId)).name,
      );
      return emit(
        formatProject(
          item,
          action: archive ? 'Archived' : 'Unarchived',
          json: json,
        ),
      );
    } finally {
      await db.close();
    }
  }
}

/// `timedart project delete <id|name> [--force]` — destructive + cascading.
class ProjectDeleteCommand extends _CliVerb {
  @override
  final String name = 'delete';
  @override
  final String description =
      'Delete a project and its tasks/entries (needs --force).';

  ProjectDeleteCommand() {
    argParser.addFlag(
      'force',
      negatable: false,
      help: 'Actually delete (and cascade). Without it, only the impact is '
          'shown.',
    );
  }

  @override
  Future<int> run() async {
    final sel = selector('project delete');
    final db = openDb();
    try {
      final p = await resolveProject(db, sel);
      if (await db.isTimerBoundToProject(p.id)) {
        throw CliException(
          'A timer is running on "${p.title}". Stop it before deleting this '
          'project.',
          CliExit.timerAlreadyRunning,
        );
      }
      final impact = await db.projectDeleteImpact(p.id);
      final label = '${p.code} ${p.title}';
      final force = argResults!['force'] as bool;
      if (!force) {
        stdout.writeln(
          formatDelete(
            DeleteOutcome(
              kind: 'project',
              id: p.id,
              label: label,
              impact: impact,
              deleted: false,
            ),
            json: json,
          ),
        );
        return CliExit.confirmationRequired;
      }
      await db.deleteProjectCascade(p.id);
      return emit(
        formatDelete(
          DeleteOutcome(
            kind: 'project',
            id: p.id,
            label: label,
            impact: impact,
            deleted: true,
          ),
          json: json,
        ),
      );
    } finally {
      await db.close();
    }
  }
}

/// `timedart task …` — manage tasks. (No archive: tasks aren't archivable in
/// the app; use delete for removal.)
class TaskCommand extends Command<int> {
  @override
  final String name = 'task';
  @override
  final String description = 'Create, edit or delete a task.';

  TaskCommand() {
    addSubcommand(TaskAddCommand());
    addSubcommand(TaskEditCommand());
    addSubcommand(TaskDeleteCommand());
  }
}

/// `timedart task add --project <id|name> --title <t> [--rate]`
class TaskAddCommand extends _CliVerb {
  @override
  final String name = 'add';
  @override
  final String description = 'Create a task under a project.';

  TaskAddCommand() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        help: 'Owning project — a UUID or exact code/title (required).',
      )
      ..addOption('title', help: 'Task title (required).')
      ..addOption(
        'rate',
        help: 'Task rate (a number). Omit to inherit the project rate.',
      );
  }

  @override
  Future<int> run() async {
    final projectSel = required('project', 'task add');
    final title = required('title', 'task add');
    final rateRaw = argResults!['rate'] as String?;
    final rate = rateRaw == null ? null : _optionalRate(rateRaw);
    final db = openDb();
    try {
      final project = await resolveProject(db, projectSel);
      final id = await _guardConstraints(
        () => db.addTask(projectId: project.id, title: title, rate: rate),
      );
      final task = await _taskById(db, id);
      final item = taskListItem(
        task,
        projectCode: project.code,
        projectTitle: project.title,
      );
      return emit(formatTask(item, action: 'Created', json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart task edit <id|name> [--project <scope>] [--title --rate]`. Give
/// `--project` to disambiguate a task named the same across projects (not
/// needed when the selector is a UUID). `--rate inherit`/empty clears the rate.
class TaskEditCommand extends _CliVerb {
  @override
  final String name = 'edit';
  @override
  final String description = 'Edit a task (only the fields you pass change).';

  TaskEditCommand() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        help: 'Scope the <id|name> lookup to this project.',
      )
      ..addOption('title', help: 'New title.')
      ..addOption('rate', help: 'New rate (a number, or "inherit" to clear).');
  }

  @override
  Future<int> run() async {
    final sel = selector('task edit');
    final db = openDb();
    try {
      final scope = await _resolveScope(db, argResults!['project'] as String?);
      final t = await resolveTaskAnywhere(db, sel, projectId: scope);
      final wants = argResults!;
      await _guardConstraints(
        () => db.updateTask(
          id: t.id,
          title: wants.wasParsed('title')
              ? required('title', 'task edit')
              : t.title,
          rate: wants.wasParsed('rate')
              ? _optionalRate(wants['rate'] as String)
              : t.rate,
        ),
      );
      final updated = await _taskById(db, t.id);
      final project = await db.getProject(updated.projectId);
      final item = taskListItem(
        updated,
        projectCode: project.code,
        projectTitle: project.title,
      );
      return emit(formatTask(item, action: 'Updated', json: json));
    } finally {
      await db.close();
    }
  }
}

/// `timedart task delete <id|name> [--project <scope>] [--force]` — destructive
/// + cascading (its time entries).
class TaskDeleteCommand extends _CliVerb {
  @override
  final String name = 'delete';
  @override
  final String description = 'Delete a task and its time entries (needs --force).';

  TaskDeleteCommand() {
    argParser
      ..addOption(
        'project',
        abbr: 'p',
        help: 'Scope the <id|name> lookup to this project.',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Actually delete (and cascade). Without it, only the impact is '
            'shown.',
      );
  }

  @override
  Future<int> run() async {
    final sel = selector('task delete');
    final db = openDb();
    try {
      final scope = await _resolveScope(db, argResults!['project'] as String?);
      final t = await resolveTaskAnywhere(db, sel, projectId: scope);
      if (await db.isTimerBoundToTask(t.id)) {
        throw CliException(
          'A timer is running on "${t.title}". Stop it before deleting this '
          'task.',
          CliExit.timerAlreadyRunning,
        );
      }
      final impact = await db.taskDeleteImpact(t.id);
      final force = argResults!['force'] as bool;
      if (!force) {
        stdout.writeln(
          formatDelete(
            DeleteOutcome(
              kind: 'task',
              id: t.id,
              label: t.title,
              impact: impact,
              deleted: false,
            ),
            json: json,
          ),
        );
        return CliExit.confirmationRequired;
      }
      await db.deleteTaskCascade(t.id);
      return emit(
        formatDelete(
          DeleteOutcome(
            kind: 'task',
            id: t.id,
            label: t.title,
            impact: impact,
            deleted: true,
          ),
          json: json,
        ),
      );
    } finally {
      await db.close();
    }
  }
}

/// Resolve an optional `--project` scope selector to a project id (or null when
/// unset) for the task verbs.
Future<String?> _resolveScope(AppDatabase db, String? projectSel) async {
  if (projectSel == null || projectSel.isEmpty) return null;
  return (await resolveProject(db, projectSel)).id;
}

/// Fetch a single live task by its id (there's no `getTask` on the data layer).
Future<Task> _taskById(AppDatabase db, String id) => (db.select(db.tasks)
      ..where((t) => t.id.equals(id))
      ..where((t) => t.deletedAt.isNull()))
    .getSingle();
