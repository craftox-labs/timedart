import 'dart:async';
import 'package:flutter/material.dart';
import 'package:time_tracker/models/time_entry.dart';
import 'package:time_tracker/widgets/timer_controls.dart';
import 'package:time_tracker/widgets/entry_list.dart';
import 'package:time_tracker/tokens.dart';

class TimeScreen extends StatefulWidget {
  const TimeScreen({super.key, required this.title});

  final String title;

  @override
  State<TimeScreen> createState() => _TimeScreenState();
}

class _TimeScreenState extends State<TimeScreen> {
  int _counter = 0;
  bool _running = false;
  Timer? _timer;
  final List<TimeEntry> _entries = [];
  final _taskController = TextEditingController();

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
    final text = _taskController.text.trim(); // read BEFORE resetting
    setState(() {
      if (_counter > 0) {
        _entries.add(
          TimeEntry(
            task: text.isEmpty ? 'Untitled session' : text,
            elapsed: Duration(seconds: _counter),
            endedAt: DateTime.now(),
          ),
        );
      }
      _counter = 0;
      _running = false;
    });
    _taskController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final counterSize = (width * 0.12).clamp(90.0, 140.0);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kRowInset),
            child: Column(
              children: [
                SizedBox(
                  height: 400,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Seconds tracked:'),
                      Text(
                        '$_counter',
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontSize: counterSize,
                              fontWeight: FontWeight.w300,
                              color: Theme.of(context).colorScheme.primary,
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
                      const SizedBox(height: 40),
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
                Expanded(child: EntryList(entries: _entries)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
