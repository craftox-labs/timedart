import 'package:flutter/material.dart';

class TimerControls extends StatelessWidget {
  final bool running;
  final bool hasSession;
  final int counter;
  final VoidCallback onPrimary; // start / pause / resume
  final VoidCallback? onFinish; // nullable → disables the button when null

  const TimerControls({
    super.key,
    required this.running,
    required this.hasSession,
    required this.counter,
    required this.onPrimary,
    this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilledButton.icon(
          onPressed: onPrimary,
          icon: Icon(running ? Icons.pause : Icons.play_arrow),
          label: Text(running ? 'Pause' : (counter > 0 ? 'Resume' : 'Start')),
          style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
        ),
        const SizedBox(width: 16),
        OutlinedButton.icon(
          onPressed: onFinish,
          icon: const Icon(Icons.stop),
          label: const Text('Finish'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
        ),
      ],
    );
  }
}
