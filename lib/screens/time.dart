import 'dart:async';
import 'package:flutter/material.dart';
import 'package:time_tracker/data/database.dart';
import 'package:time_tracker/widgets/timer_controls.dart';
import 'package:time_tracker/widgets/entry_list.dart';
import 'package:time_tracker/widgets/content_app_bar.dart';
import 'package:time_tracker/widgets/content_body.dart';
import 'package:time_tracker/format.dart';
import 'package:time_tracker/screens/clients.dart';
import 'package:time_tracker/screens/jobs.dart';

class TimeScreen extends StatefulWidget {
  const TimeScreen({super.key, required this.title, required this.db});
  final String title;
  final AppDatabase db;

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  int _counter = 0;
  bool _running = false;
  Timer? _timer;
  DateTime? _sessionStart; // ← when the current session began
  int? _jobId; // ← seeded default job
  final _taskController = TextEditingController();
  late final Stream<List<TimeEntry>> _entriesStream = widget.db.watchEntries();
  late final Stream<List<Job>> _jobsStream = widget.db.watchJobs();

  @override
  void initState() {
    super.initState();
    widget.db.ensureDefaultJob().then((id) => setState(() => _jobId = id));
  }

  @override
  void dispose() {
    _taskController.dispose();
    _timer?.cancel(); // kill the timer before the State dies
    super.dispose(); // ALWAYS call super.dispose() last
  }

  bool get _hasSession =>
      _running || _counter > 0; // an uncommitted session exists

  void _startOrResume() {
    if (_running) return;
    _sessionStart ??= DateTime.now(); // ← stamp the start once
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
    setState(() => _running = false); // counter kept — that
  }

  void _finish() {
    _timer?.cancel();
    final text = _taskController.text.trim();
    if (_counter > 0 && _jobId != null) {
      widget.db.addEntry(
        // ← write to the DB, not a list
        jobId: _jobId!,
        task: text.isEmpty ? 'Untitled session' : text,
        startedAt: _sessionStart ?? DateTime.now(),
        endedAt: DateTime.now(),
        seconds: _counter,
      );
    }
    setState(() {
      _counter = 0;
      _running = false;
    });
    _sessionStart = null;
    _taskController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final counterSize = (width * 0.12).clamp(90.0, 140.0);

    return Scaffold(
      appBar: ContentAppBar(
        title: 'Time Tracker',
        actions: [
          IconButton(
            icon: const Icon(Icons.people),
            tooltip: 'Clients',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ClientsScreen(db: widget.db)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.work),
            tooltip: 'Jobs',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => JobsScreen(db: widget.db)),
            ),
          ),
        ],
      ),
      body: ContentBody(
        child: Column(
          children: [
            SizedBox(
              height: 440,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StreamBuilder<List<Job>>(
                    stream: _jobsStream,
                    builder: (context, snap) {
                      final jobs = snap.data ?? [];
                      final value = jobs.any((j) => j.id == _jobId)
                          ? _jobId
                          : null; // keep the guard
                      return InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Job',
                        ), // ← inherits inputDecorationTheme
                        isEmpty:
                            value == null, // lets the label float correctly
                        child: DropdownButtonHideUnderline(
                          // hide the dropdown's own underline
                          child: DropdownButton<int>(
                            value: value,
                            isDense: true,
                            isExpanded: true,
                            items: [
                              for (final j in jobs)
                                DropdownMenuItem(
                                  value: j.id,
                                  child: Text(j.title),
                                ),
                            ],
                            onChanged: (id) => setState(() => _jobId = id),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text('Time tracked:'),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      Duration(seconds: _counter).hms,
                      style: Theme.of(context).textTheme.headlineLarge
                          ?.copyWith(
                            fontSize: counterSize,
                            fontWeight: FontWeight.w300,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TimerControls(
                    running: _running,
                    hasSession: _hasSession,
                    counter: _counter,
                    onPrimary: _running ? _pause : _startOrResume,
                    onFinish: _hasSession ? _finish : null,
                  ),
                  const SizedBox(height: 24),
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
            Expanded(
              child: StreamBuilder<List<TimeEntry>>(
                stream: _entriesStream,
                builder: (context, snapshot) =>
                    EntryList(entries: snapshot.data ?? []),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
