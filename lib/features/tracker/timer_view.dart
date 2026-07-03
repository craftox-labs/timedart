import 'dart:async';
import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/features/tracker/timer_controls.dart';
import 'package:time_tracker/features/tracker/timer_session.dart';
import 'package:time_tracker/constants/format.dart';
import 'package:time_tracker/constants/tokens.dart';
import 'package:time_tracker/features/tracker/time_entry_list.dart';

class TimerView extends StatefulWidget {
  const TimerView({
    super.key,
    required this.db,
    required this.jobId,
    required this.onInvoice,
  });
  final AppDatabase db;
  final int? jobId;
  final void Function(Job) onInvoice; // open the invoice view for this job

  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  final _session = TimerSession();
  Timer? _timer;
  final _taskController = TextEditingController();
  Stream<List<TimeEntry>>? _entriesStream; // entries for the selected job
  Stream<(Job, Client)?>? _jobStream;

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

  void _updateJobStream() {
    final id = widget.jobId;
    _jobStream = id == null ? null : widget.db.watchJobWithClient(id);
    _entriesStream = id == null ? null : widget.db.watchEntriesForJob(id);
  }

  void _startOrResume() {
    if (_session.isRunning) return;
    setState(() {
      _session.start(widget.jobId, now: DateTime.now());
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(_session.tick);
      });
    });
  }

  void _pause() {
    _timer?.cancel();
    setState(_session.pause);
  }

  Future<void> _finish() async {
    _timer?.cancel();
    final result = _session.finish(now: DateTime.now());
    setState(() {}); // reflect the stopped state

    // Nothing to record (empty session, or no job was ever bound).
    if (result == null) {
      _resetSession();
      return;
    }

    final text = _taskController.text.trim();
    try {
      // Await the write so a failure is caught rather than silently lost.
      await widget.db.addEntry(
        jobId: result.jobId,
        task: text.isEmpty ? 'Untitled session' : text,
        startedAt: result.startedAt,
        endedAt: result.endedAt,
        seconds: result.seconds,
      );
      _resetSession();
    } catch (e) {
      // Keep the session intact so the user can retry instead of losing time.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save entry: $e')));
      }
    }
  }

  void _resetSession() {
    if (!mounted) return;
    setState(_session.reset);
    _taskController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Size the counter to the content area (not the whole window), so it
        // isn't oversized next to the side panel.
        final counterSize = (constraints.maxWidth * 0.16).clamp(72.0, 128.0);
        return _body(context, counterSize);
      },
    );
  }

  Widget _body(BuildContext context, double counterSize) {
    return Column(
      children: [
        Column(
          children: [
            // 1. Extracted Job Stream Element
            JobHeader(jobStream: _jobStream),
            const SizedBox(height: AppTokens.spaceSm),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                Duration(seconds: _session.elapsed).hms,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: counterSize,
                  fontWeight: FontWeight.w300,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceMd),
            TimerControls(
              running: _session.isRunning,
              hasSession: _session.hasSession,
              counter: _session.elapsed,
              // No job selected → disable start so time can't be tracked
              // against nothing (and later silently discarded).
              onPrimary: widget.jobId == null
                  ? null
                  : (_session.isRunning ? _pause : _startOrResume),
              onFinish: _session.hasSession ? _finish : null,
            ),
            const SizedBox(height: AppTokens.space2xl), // match input→history
            if (widget.jobId == null) ...[
              Text(
                'Select a job to start tracking',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            TextField(
              controller: _taskController,
              decoration: const InputDecoration(
                hintText: 'What are you working on?',
                labelText: 'Task',
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _session.isRunning ? null : _startOrResume(),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.space2xl),
        // 2. Entries section: header (with the per-job Invoice action) + list
        if (widget.jobId != null) ...[
          _EntriesHeader(jobStream: _jobStream, onInvoice: widget.onInvoice),
          const Divider(),
        ],
        Expanded(
          child: EntryHistoryList(
            entriesStream: _entriesStream,
            jobStream: _jobStream,
          ),
        ),
      ],
    );
  }
}

// --- Component 1: Job Meta Header ---
class JobHeader extends StatelessWidget {
  final Stream<(Job, Client)?>? jobStream;

  const JobHeader({super.key, required this.jobStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<(Job, Client)?>(
      stream: jobStream,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final (job, client) = data;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 4,
          children: [
            Text(
              '${client.name} : ${job.code}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Text(
              job.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w300,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        );
      },
    );
  }
}

// --- Entries section header: label + per-job Invoice action ---
class _EntriesHeader extends StatelessWidget {
  final Stream<(Job, Client)?>? jobStream;
  final void Function(Job) onInvoice;

  const _EntriesHeader({required this.jobStream, required this.onInvoice});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<(Job, Client)?>(
      stream: jobStream,
      builder: (context, snap) {
        final job = snap.data?.$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
          child: Row(
            children: [
              Text('Entries', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                // Disabled until the job has loaded.
                onPressed: job == null ? null : () => onInvoice(job),
                icon: const Icon(Icons.receipt_long, size: AppTokens.iconSm),
                label: const Text('Invoice'),
                // Strip padding so the label sits flush to the right edge.
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Component 2: Isolated Entries List ---
class EntryHistoryList extends StatelessWidget {
  final Stream<List<TimeEntry>>? entriesStream; // null when no job selected
  final Stream<(Job, Client)?>? jobStream; // for the effective rate

  const EntryHistoryList({
    super.key,
    required this.entriesStream,
    required this.jobStream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<(Job, Client)?>(
      stream: jobStream,
      builder: (context, jobSnap) {
        final data = jobSnap.data;
        // Effective rate: the job's own rate, else the client default.
        final rate = data == null ? null : (data.$1.rate ?? data.$2.defaultRate);
        return StreamBuilder<List<TimeEntry>>(
          stream: entriesStream,
          builder: (context, snapshot) {
            return TimeEntryList(entries: snapshot.data ?? [], rate: rate);
          },
        );
      },
    );
  }
}
