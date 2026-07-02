import 'dart:async';
import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/tracker/timer_controls.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/tracker/time_entry_list.dart';

class TimerView extends StatefulWidget {
  const TimerView({super.key, required this.db, required this.jobId});
  final AppDatabase db;
  final int? jobId;

  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  int _counter = 0;
  bool _running = false;
  Timer? _timer;
  DateTime? _sessionStart;
  int? _sessionJobId; // the job this session belongs to, fixed at start
  final _taskController = TextEditingController();
  Stream<List<TimeEntry>>? _entriesStream; // entries for the selected job
  Stream<Job?>? _jobStream;

  @override
  void initState() {
    super.initState();
    _updateJobStream();
  }

  @override
  void didUpdateWidget(TimerView old) {
    super.didUpdateWidget(old);
    if (old.jobId != widget.jobId) _updateJobStream();
  }

  @override
  void dispose() {
    _taskController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  bool get _hasSession => _running || _counter > 0;

  void _updateJobStream() {
    final id = widget.jobId;
    _jobStream = id == null ? null : widget.db.watchJob(id);
    _entriesStream = id == null ? null : widget.db.watchEntriesForJob(id);
  }

  void _startOrResume() {
    if (_running) return;
    _sessionStart ??= DateTime.now();
    // Bind the session to the job selected at start, so switching (or losing)
    // the selection mid-session can't misattribute or silently discard it.
    _sessionJobId ??= widget.jobId;
    setState(() {
      _running = true;
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _counter++);
      });
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(() => _running = false);
  }

  Future<void> _finish() async {
    _timer?.cancel();
    setState(() => _running = false);

    final jobId = _sessionJobId; // the job at session start, not live selection
    // Nothing to record (empty session, or somehow no job) — just reset.
    if (_counter == 0 || jobId == null) {
      _resetSession();
      return;
    }

    final text = _taskController.text.trim();
    try {
      // Await the write so a failure is caught rather than silently lost.
      await widget.db.addEntry(
        jobId: jobId,
        task: text.isEmpty ? 'Untitled session' : text,
        startedAt: _sessionStart ?? DateTime.now(),
        endedAt: DateTime.now(),
        seconds: _counter,
      );
      _resetSession();
    } catch (e) {
      // Keep the session intact so the user can retry instead of losing time.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save entry: $e')),
        );
      }
    }
  }

  void _resetSession() {
    if (!mounted) return;
    setState(() {
      _counter = 0;
      _running = false;
    });
    _sessionStart = null;
    _sessionJobId = null;
    _taskController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final counterSize = (MediaQuery.sizeOf(context).width * 0.12).clamp(
      90.0,
      140.0,
    );

    return Column(
      children: [
        SizedBox(
          height: 440,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. Extracted Job Stream Element
              JobHeader(jobStream: _jobStream),
              const SizedBox(height: AppTokens.spaceXl),
              const Text('Time tracked:'),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  Duration(seconds: _counter).hms,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontSize: counterSize,
                    fontWeight: FontWeight.w300,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceXl),
              TimerControls(
                running: _running,
                hasSession: _hasSession,
                counter: _counter,
                // No job selected → disable start so time can't be tracked
                // against nothing (and later silently discarded).
                onPrimary: widget.jobId == null
                    ? null
                    : (_running ? _pause : _startOrResume),
                onFinish: _hasSession ? _finish : null,
              ),
              if (widget.jobId == null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  'Select a job to start tracking',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: AppTokens.spaceXl),
              TextField(
                controller: _taskController,
                decoration: const InputDecoration(
                  hintText: 'What are you working on?',
                  labelText: 'Task',
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _running ? null : _startOrResume(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 2. Extracted Historical Stream List
        Expanded(child: EntryHistoryList(entriesStream: _entriesStream)),
      ],
    );
  }
}

// --- Component 1: Job Meta Header ---
class JobHeader extends StatelessWidget {
  final Stream<Job?>? jobStream;

  const JobHeader({super.key, required this.jobStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Job?>(
      stream: jobStream,
      builder: (context, snap) {
        final job = snap.data;
        if (job == null) return const SizedBox.shrink();

        return Column(
          children: [
            Text(job.code, style: Theme.of(context).textTheme.bodySmall),
            Text(job.title, style: Theme.of(context).textTheme.titleLarge),
          ],
        );
      },
    );
  }
}

// --- Component 2: Isolated Entries List ---
class EntryHistoryList extends StatelessWidget {
  final Stream<List<TimeEntry>>? entriesStream; // null when no job selected

  const EntryHistoryList({super.key, required this.entriesStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TimeEntry>>(
      stream: entriesStream,
      builder: (context, snapshot) {
        return TimeEntryList(entries: snapshot.data ?? []);
      },
    );
  }
}
