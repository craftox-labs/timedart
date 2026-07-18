import 'dart:convert';

import 'timer_status_result.dart';

// ── Output formatter (pure) ────────────────────────────────────────────────
// Result object → deterministic human-readable text OR JSON. No I/O, no clock:
// given the same result it always renders the same bytes, so both shapes are
// trivially testable and an agent can rely on the JSON contract.

/// Format elapsed [seconds] as a compact `Hh Mm Ss` string (e.g. `1h 23m 45s`).
/// Always shows seconds; hides higher units only when zero and nothing above
/// them is present, so a sub-minute timer reads `45s` and an exact hour reads
/// `1h 0m 0s`.
String formatElapsed(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  final parts = <String>[];
  if (h > 0) parts.add('${h}h');
  if (h > 0 || m > 0) parts.add('${m}m');
  parts.add('${sec}s');
  return parts.join(' ');
}

/// Render a `timer status` [result] as human-readable text.
String formatTimerStatusHuman(TimerStatusResult result) {
  if (!result.hasTimer) return 'No timer running.';

  final buffer = StringBuffer();
  final state = result.running ? 'Running' : 'Paused';
  final project = _projectLabel(result);
  final task = result.taskTitle;
  final where = <String>[?project, ?task].join(' / ');

  buffer.writeln(where.isEmpty ? state : '$state — $where');
  if (result.description != null && result.description!.isNotEmpty) {
    buffer.writeln('  ${result.description}');
  }
  buffer.writeln('  Elapsed: ${formatElapsed(result.elapsedSeconds)}');
  if (result.startedAt != null) {
    buffer.write('  Started: ${result.startedAt!.toIso8601String()}');
  } else {
    // Drop the trailing newline from the last writeln for a clean single block.
    final text = buffer.toString();
    return text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  }
  return buffer.toString();
}

String? _projectLabel(TimerStatusResult r) {
  final code = r.projectCode;
  final title = r.projectTitle;
  if (code != null && title != null) return '$code $title';
  return title ?? code;
}

/// The stable JSON contract for `timer status` (agent-facing).
///
/// Idle: `{"status":"idle","running":false,"elapsedSeconds":0,
///          "project":null,"task":null,"description":null,"startedAt":null}`
/// Active: `status` is `"running"` or `"paused"`, `elapsedSeconds` is the
/// live-derived tracked time, and `project`/`task` are `{id,code?,title}` /
/// `{id,title}` objects (or null), `startedAt` an ISO-8601 string.
Map<String, Object?> timerStatusJson(TimerStatusResult result) {
  if (!result.hasTimer) {
    return {
      'status': 'idle',
      'running': false,
      'elapsedSeconds': 0,
      'project': null,
      'task': null,
      'description': null,
      'startedAt': null,
    };
  }
  return {
    'status': result.running ? 'running' : 'paused',
    'running': result.running,
    'elapsedSeconds': result.elapsedSeconds,
    'project': result.projectId == null
        ? null
        : {
            'id': result.projectId,
            'code': result.projectCode,
            'title': result.projectTitle,
          },
    'task': result.taskId == null
        ? null
        : {'id': result.taskId, 'title': result.taskTitle},
    'description': result.description,
    'startedAt': result.startedAt?.toIso8601String(),
  };
}

/// Render a `timer status` [result] as a JSON string (pretty-printed, stable
/// key order).
String formatTimerStatusJson(TimerStatusResult result) =>
    const JsonEncoder.withIndent('  ').convert(timerStatusJson(result));

/// Render [result] as JSON when [json] is true, else as human text.
String formatTimerStatus(TimerStatusResult result, {required bool json}) =>
    json ? formatTimerStatusJson(result) : formatTimerStatusHuman(result);
